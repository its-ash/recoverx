import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recoverx/core/analysis/byte_source.dart';
import 'package:recoverx/core/analysis/carver.dart';
import 'package:recoverx/core/analysis/file_analyzer.dart';
import 'package:recoverx/core/analysis/file_type_detector.dart';
import 'package:recoverx/core/analysis/metadata_extractor.dart';
import 'package:recoverx/core/recovery/recovery_service.dart';
import 'package:recoverx/core/scanner/location_classifier.dart';
import 'package:recoverx/domain/file_item.dart';
import 'package:recoverx/domain/file_metadata.dart';
import 'package:recoverx/domain/signature_database.dart';

import 'fixtures.dart';

String? detect(List<int> bytes) =>
    const FileTypeDetector().detect(MemoryByteSource(bytes))?.type.id;

void main() {
  group('FileTypeDetector', () {
    test('images', () {
      expect(detect(jpeg()), 'jpeg');
      expect(detect(png()), 'png');
      expect(detect([...ascii('GIF89a'), ...List.filled(20, 0)]), 'gif');
      expect(detect(riff('WEBP')), 'webp');
    });

    test('ISO-BMFF brands and tracks', () {
      expect(detect(isoBmff('isom')), 'mp4');
      expect(detect(isoBmff('mp42', handler: 'soun')), 'm4a');
      expect(detect(isoBmff('M4A ', handler: 'soun')), 'm4a');
      expect(detect(isoBmff('qt  ')), 'mov');
      expect(detect(isoBmff('3gp4')), '3gp');
      expect(detect(isoBmff('heic', withMoov: false)), 'heic');
      expect(detect(isoBmff('mif1', compat: ['mif1', 'heic'], withMoov: false)), 'heic');
      expect(detect(isoBmff('avif', withMoov: false)), 'avif');
    });

    test('RIFF and EBML sub-types', () {
      expect(detect(riff('AVI ')), 'avi');
      expect(detect(riff('WAVE')), 'wav');
      final ebml = [0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82];
      expect(detect([...ebml, 0x84, ...ascii('webm'), ...List.filled(20, 0)]), 'webm');
      expect(detect([...ebml, 0x88, ...ascii('matroska'), ...List.filled(20, 0)]), 'mkv');
    });

    test('ZIP family', () {
      expect(detect(zip('[Content_Types].xml', names: ['word/document.xml'])), 'docx');
      expect(detect(zip('[Content_Types].xml', names: ['xl/workbook.xml'])), 'xlsx');
      expect(detect(zip('[Content_Types].xml', names: ['ppt/presentation.xml'])), 'pptx');
      expect(detect(zip('AndroidManifest.xml', names: ['classes.dex'])), 'apk');
      expect(detect(zip('mimetype', storedContent: 'application/epub+zip')), 'epub');
      expect(detect(zip('notes.txt')), 'zip');
    });

    test('OLE2 sub-types', () {
      expect(detect(ole('WordDocument')), 'doc');
      expect(detect(ole('Workbook')), 'xls');
      expect(detect(ole('PowerPoint Document')), 'ppt');
      expect(detect(ole('Something')), 'ole');
    });

    test('Ogg / Opus', () {
      List<int> page(String id) => [...ascii('OggS'), 0, 2, ...List.filled(20, 0), 1, 19, ...ascii(id), ...List.filled(30, 0)];
      expect(detect(page('OpusHead')), 'opus');
      expect(detect(page('\x01vorbis')), 'ogg');
    });

    test('MP3 by ID3 and by frame chain; AAC ADTS', () {
      expect(detect([...ascii('ID3'), 4, 0, 0, 0, 0, 0, 0, ...List.filled(40, 0)]), 'mp3');
      // MPEG-1 Layer III, 128 kbps, 44.1 kHz: frame length 417.
      final frame = [0xFF, 0xFB, 0x90, 0x00, ...List.filled(413, 0)];
      expect(detect([...frame, ...frame, ...frame]), 'mp3');
      // ADTS frames of 100 bytes each.
      final adts = [0xFF, 0xF1, 0x50, 0x80, (100 >> 3) & 0xFF, (100 & 7) << 5, 0xFC, ...List.filled(93, 0)];
      expect(detect([...adts, ...adts]), 'aac');
    });

    test('BMP requires a sane header; random bytes are rejected', () {
      final bmp = [...ascii('BM'), ...le32(70), 0, 0, 0, 0, ...le32(54), ...le32(40), ...List.filled(52, 0)];
      expect(detect(bmp), 'bmp');
      expect(detect([...ascii('BM'), ...List.filled(60, 0x41)]), isNull);
      final rnd = Random(1);
      var hits = 0;
      for (var i = 0; i < 500; i++) {
        if (detect(List.generate(2048, (_) => rnd.nextInt(256))) != null) hits++;
      }
      expect(hits, lessThan(3));
    });

    test('TIFF variants', () {
      expect(detect([...ascii('II'), 0x2A, 0, ...le32(8), ...ascii('CR'), ...List.filled(30, 0)]), 'cr2');
      final dng = [...ascii('II'), 0x2A, 0, ...le32(8), ...le16(1), ...le16(0xC612), ...le16(1), ...le32(4), 1, 4, 0, 0, ...le32(0)];
      expect(detect(dng), 'dng');
    });

    test('plain signatures', () {
      expect(detect([...ascii('%PDF-1.7'), ...List.filled(20, 0)]), 'pdf');
      expect(detect([...ascii('SQLite format 3'), 0, ...List.filled(100, 0)]), 'sqlite');
      expect(detect([...ascii('#!AMR\n'), ...List.filled(20, 0)]), 'amr');
      expect(detect([...ascii('BEGIN:VCARD\r\nFN:A'), ...List.filled(20, 0)]), 'vcf');
    });
  });

  group('Metadata', () {
    test('JPEG EXIF: camera, capture time, GPS, size', () {
      final m = const MetadataExtractor()
          .extract(MemoryByteSource(jpeg(exifTiff: exifTiff(), width: 640, height: 480)), FileTypes.jpeg)!;
      expect(m.cameraMake, 'Google');
      expect(m.cameraModel, 'Pixel 8');
      expect(m.takenAt, DateTime(2024, 5, 17, 14, 3, 22));
      expect(m.latitude, closeTo(28.6139, 1e-4));
      expect(m.longitude, closeTo(-77.2090, 1e-4));
      expect(m.width, 640);
      expect(m.height, 480);
    });

    test('PNG size and MP4 duration', () {
      final p = const MetadataExtractor().extract(MemoryByteSource(png(width: 9, height: 7)), FileTypes.png)!;
      expect((p.width, p.height), (9, 7));
      final v = const MetadataExtractor().extract(MemoryByteSource(isoBmff('isom')), FileTypes.mp4)!;
      expect(v.duration, const Duration(seconds: 5));
      expect(v.takenAt, isNotNull);
    });
  });

  group('Integrity', () {
    const check = IntegrityChecker();
    test('detects cut-short files', () {
      final j = jpeg();
      expect(check.check(MemoryByteSource(j), FileTypes.jpeg), Integrity.intact);
      expect(check.check(MemoryByteSource(j.sublist(0, j.length - 50)), FileTypes.jpeg), Integrity.truncated);
      final mp4 = isoBmff('isom');
      expect(check.check(MemoryByteSource(mp4), FileTypes.mp4), Integrity.intact);
      expect(check.check(MemoryByteSource(mp4.sublist(0, mp4.length - 10)), FileTypes.mp4), Integrity.truncated);
      expect(check.check(MemoryByteSource(isoBmff('isom', withMoov: false)), FileTypes.mp4), Integrity.truncated);
    });
  });

  group('Carver', () {
    test('finds exact files inside junk and rejects fake headers', () {
      final j = jpeg();
      final p = png();
      final junk = List.filled(333, 0x00);
      final fake = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x99, 0x99];
      final blob = Uint8List.fromList([...junk, ...fake, ...junk, ...j, ...junk, ...p, ...junk]);
      final regions = const Carver().carve(MemoryByteSource(blob));
      expect(regions.map((r) => r.type.id), ['jpeg', 'png']);
      final jStart = junk.length * 2 + fake.length;
      expect(regions[0].offset, jStart);
      expect(regions[0].length, j.length);
      expect(regions[1].offset, jStart + j.length + junk.length);
      expect(regions[1].length, p.length);
    });

    test('carves MP4 appended to a JPEG (motion photo)', () {
      final blob = Uint8List.fromList([...jpeg(), ...isoBmff('mp42')]);
      final items = const FileAnalyzer()
          .analyzeSource(MemoryByteSource(blob), path: '/storage/emulated/0/DCIM/Camera/PXL_1.MP.jpg', deep: true);
      expect(items.map((i) => i.type.id), ['jpeg', 'mp4']);
      expect(items[1].isCarved, isTrue);
      expect(items[1].sourceOffset, jpeg().length);
    });

    test('gallery thumbnail cache is carved even in a standard scan', () {
      final blob = Uint8List.fromList([...List.filled(64, 1), ...jpeg(), ...List.filled(64, 2), ...jpeg(width: 32)]);
      final items = const FileAnalyzer().analyzeSource(MemoryByteSource(blob),
          path: '/storage/emulated/0/DCIM/.thumbnails/.thumbdata4--1967290299');
      expect(items.length, 2);
      expect(items.every((i) => i.reasons.contains(DiscoveryReason.carved)), isTrue);
      expect(items.every((i) => i.reasons.contains(DiscoveryReason.cache)), isTrue);
      expect(items[1].metadata?.width, 32);
    });
  });

  group('LocationClassifier', () {
    const c = LocationClassifier();
    test('Android trash file', () {
      final i = c.classify(path: '/storage/emulated/0/DCIM/Camera/.trashed-1735689600-IMG_2024.jpg', type: FileTypes.jpeg);
      expect(i.reasons, {DiscoveryReason.trashed});
      expect(i.originalName, 'IMG_2024.jpg');
      expect(i.notes['Trash expires'], isNotNull);
      expect(i.sourceApp, 'Camera');
    });

    test('renamed / disguised file', () {
      final i = c.classify(path: '/storage/emulated/0/Documents/budget.xlsx', type: FileTypes.mp4);
      expect(i.reasons, contains(DiscoveryReason.renamed));
      final ok = c.classify(path: '/storage/emulated/0/Movies/clip.MOV', type: FileTypes.mp4);
      expect(ok.reasons, isEmpty);
    });

    test('hidden folder, nomedia, WhatsApp', () {
      final i = c.classify(
          path: '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses/abc.jpg',
          type: FileTypes.jpeg);
      expect(i.reasons, contains(DiscoveryReason.hidden));
      expect(i.sourceApp, 'WhatsApp Status');
      final n = c.classify(path: '/storage/emulated/0/Secret/a.jpg', type: FileTypes.jpeg, underNoMedia: true);
      expect(n.reasons, contains(DiscoveryReason.hidden));
    });

    test('cache blobs without extension are cache, not renamed', () {
      final i = c.classify(
          path: '/storage/emulated/0/Android/data/x/cache/image_manager_disk_cache/3f2a.0',
          type: FileTypes.jpeg);
      expect(i.reasons, {DiscoveryReason.cache});
    });
  });

  group('FileItem.suggestedName', () {
    FileItem item(String path, {String? original, int? offset}) => FileItem(
        path: path, size: 1, type: FileTypes.jpeg, matchConfidence: MatchConfidence.high,
        originalName: original, sourceOffset: offset);

    test('restores real extension and original name', () {
      expect(item('/a/holiday.txt').suggestedName, 'holiday.jpg');
      expect(item('/a/holiday').suggestedName, 'holiday.jpg');
      expect(item('/a/holiday.jpeg').suggestedName, 'holiday.jpeg');
      expect(item('/a/.secret').suggestedName, 'secret.jpg');
      expect(item('/a/.trashed-1-IMG.jpg', original: 'IMG.jpg').suggestedName, 'IMG.jpg');
      expect(item('/a/.thumbdata4--1', offset: 4096).suggestedName, 'thumbdata4--1_at_0x1000.jpg');
    });
  });

  test('export copies, hashes, verifies and writes reports', () async {
    final dir = await Directory.systemTemp.createTemp('recoverx_test');
    try {
      final j = jpeg();
      final src = File('${dir.path}/evidence.bin')..writeAsBytesSync([...List.filled(10, 0), ...j]);
      final whole = File('${dir.path}/photo.dat')..writeAsBytesSync(j);
      final when = DateTime(2023, 1, 2, 3, 4, 5);
      whole.setLastModifiedSync(when);
      final items = [
        FileItem(path: whole.path, size: j.length, type: FileTypes.jpeg, matchConfidence: MatchConfidence.high,
            reasons: {DiscoveryReason.renamed}, lastModified: when),
        FileItem(path: src.path, size: j.length, type: FileTypes.jpeg, matchConfidence: MatchConfidence.high,
            reasons: {DiscoveryReason.carved}, sourceOffset: 10),
      ];
      final events = await RecoveryService.export(items: items, volumeRoot: '${dir.path}/out').toList();
      final result = events.whereType<ExportResult>().single;
      expect(result.failedCount, 0);
      final expected = sha256.convert(j).toString();
      expect(result.records.map((r) => r.sha256), [expected, expected]);
      final first = File(result.records[0].exportedPath!);
      expect(first.path, endsWith('/image/photo.jpg'));
      expect(first.lastModifiedSync(), when);
      expect(File(result.records[1].exportedPath!).readAsBytesSync(), j);
      final report = jsonDecode(File('${result.folder}/report.json').readAsStringSync()) as Map;
      expect((report['files'] as List).length, 2);
      expect(File('${result.folder}/manifest.csv').readAsLinesSync().length, 3);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
