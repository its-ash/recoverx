import 'dart:convert';
import 'dart:math' as math;

import '../../domain/file_metadata.dart';
import '../../domain/file_signature.dart';
import 'byte_source.dart';
import 'exif_reader.dart';
import 'file_type_detector.dart';

/// Reads metadata embedded inside a file. Never throws; returns null when
/// nothing useful was found.
class MetadataExtractor {
  const MetadataExtractor();

  FileMetadata? extract(ByteSource s, FileType type) {
    try {
      final m = switch (type.id) {
        'jpeg' => _jpeg(s),
        'png' => _png(s),
        'gif' => _gif(s),
        'webp' => _webp(s),
        'bmp' => _bmp(s),
        'tiff' || 'dng' || 'cr2' || 'nef' || 'arw' => ExifReader.read(s),
        'heic' || 'heif' || 'avif' => _heif(s),
        'mp4' || 'm4v' || 'mov' || '3gp' || '3g2' || 'm4a' => _isoBmff(s),
        'mp3' || 'aac' => _id3(s),
        'wav' => _wav(s),
        'flac' => _flac(s),
        'pdf' => _pdf(s),
        'sqlite' => _sqlite(s),
        'vcf' => _vcf(s),
        _ => null,
      };
      return (m == null || m.isEmpty) ? null : m;
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── Images ─────────────────────────

  FileMetadata? _jpeg(ByteSource s) {
    FileMetadata? exif;
    int? w, h;
    var off = 2;
    final extra = <String, String>{};
    for (var n = 0; n < 200 && off + 4 <= s.length; n++) {
      if (s.u8(off) != 0xFF) break;
      final marker = s.u8(off + 1);
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        off += 2;
        continue;
      }
      if (marker == 0xFF) {
        off += 1;
        continue;
      }
      final len = s.u16(off + 2) ?? 0;
      if (len < 2) break;
      final seg = off + 4;
      if (marker == 0xE1 && exif == null && s.ascii(seg, 6) == 'Exif\u0000\u0000') {
        exif = ExifReader.read(s.slice(seg + 6, len - 8));
      } else if (marker == 0xE1 && s.ascii(seg, 28) == 'http://ns.adobe.com/xap/1.0/') {
        final xmp = latin1.decode(s.read(seg, math.min(len, 64 * 1024)));
        if (xmp.contains('MotionPhoto') || xmp.contains('MicroVideo')) {
          extra['Motion photo'] = 'Yes (embedded video)';
        }
      } else if (_isSof(marker)) {
        h = s.u16(seg + 1);
        w = s.u16(seg + 3);
      } else if (marker == 0xDA) {
        break;
      }
      off = seg + len - 2;
    }
    final base = exif ?? const FileMetadata();
    return base.copyWith(
      width: w ?? base.width,
      height: h ?? base.height,
      extra: {...base.extra, ...extra},
    );
  }

  static bool _isSof(int m) =>
      m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;

  FileMetadata? _png(ByteSource s) {
    final w = s.u32(16);
    final h = s.u32(20);
    FileMetadata? exif;
    final extra = <String, String>{};
    var off = 8;
    for (var n = 0; n < 64 && off + 12 <= s.length; n++) {
      final len = s.u32(off) ?? 0;
      final type = s.ascii(off + 4, 4);
      if (type == 'eXIf') exif = ExifReader.read(s.slice(off + 8, len));
      if (type == 'tEXt' || type == 'iTXt') {
        final body = latin1.decode(s.read(off + 8, math.min(len, 512)));
        final key = body.split('\u0000').first;
        final value = body.substring(math.min(body.length, key.length + 1))
            .replaceAll('\u0000', ' ')
            .trim();
        if (key.isNotEmpty && value.isNotEmpty && extra.length < 6) {
          extra[key] = value.length > 120 ? '${value.substring(0, 120)}…' : value;
        }
      }
      if (type == 'IDAT' || type == 'IEND') break;
      off += 12 + len;
    }
    final base = exif ?? const FileMetadata();
    return base.copyWith(width: w, height: h, extra: {...base.extra, ...extra});
  }

  FileMetadata? _gif(ByteSource s) => FileMetadata(
        width: s.u16(6, little: true),
        height: s.u16(8, little: true),
      );

  FileMetadata? _webp(ByteSource s) {
    int? w, h;
    FileMetadata? exif;
    var off = 12;
    for (var n = 0; n < 32 && off + 8 <= s.length; n++) {
      final type = s.ascii(off, 4);
      final len = s.u32(off + 4, little: true) ?? 0;
      final body = off + 8;
      final b = s.read(body, 10);
      if (type == 'VP8X' && b.length >= 10) {
        w = 1 + (b[4] | (b[5] << 8) | (b[6] << 16));
        h = 1 + (b[7] | (b[8] << 8) | (b[9] << 16));
      } else if (type == 'VP8L' && w == null && b.length >= 5) {
        final bits = b[1] | (b[2] << 8) | (b[3] << 16) | (b[4] << 24);
        w = (bits & 0x3FFF) + 1;
        h = ((bits >> 14) & 0x3FFF) + 1;
      } else if (type == 'VP8 ' && w == null && b.length >= 10) {
        w = (b[6] | (b[7] << 8)) & 0x3FFF;
        h = (b[8] | (b[9] << 8)) & 0x3FFF;
      } else if (type == 'EXIF') {
        var start = body;
        if (s.ascii(start, 6) == 'Exif\u0000\u0000') start += 6;
        exif = ExifReader.read(s.slice(start, len));
      }
      off = body + len + (len & 1);
    }
    final base = exif ?? const FileMetadata();
    return base.copyWith(width: w, height: h);
  }

  FileMetadata? _bmp(ByteSource s) {
    final w = s.u32(18, little: true);
    final hRaw = s.u32(22, little: true);
    if (w == null || hRaw == null) return null;
    final h = hRaw > 0x7FFFFFFF ? 0x100000000 - hRaw : hRaw;
    return FileMetadata(width: w, height: h);
  }

  FileMetadata? _heif(ByteSource s) {
    final head = s.read(0, math.min(s.length, 2 * 1024 * 1024));
    int? w, h;
    var i = 0;
    const ispe = [0x69, 0x73, 0x70, 0x65];
    while ((i = indexOfBytes(head, ispe, i)) >= 0 && i + 16 <= head.length) {
      final bw = _be32(head, i + 8);
      final bh = _be32(head, i + 12);
      if (bw * bh > (w ?? 0) * (h ?? 0)) {
        w = bw;
        h = bh;
      }
      i += 4;
    }
    FileMetadata? exif;
    final e = indexOfBytes(head, 'Exif\u0000\u0000'.codeUnits);
    if (e >= 0) exif = ExifReader.read(s.slice(e + 6, s.length - e - 6));
    final base = exif ?? const FileMetadata();
    return base.copyWith(width: w ?? base.width, height: h ?? base.height);
  }

  // ───────────────────────── Video / audio ─────────────────────────

  FileMetadata? _isoBmff(ByteSource s) {
    final moov = FileTypeDetector.findTopLevelBox(s, 'moov');
    if (moov == null) return null;
    final body = s.read(moov.$1, math.min(moov.$2, 8 * 1024 * 1024));
    final src = MemoryByteSource(body);

    DateTime? created;
    Duration? duration;
    final mvhd = indexOfBytes(body, 'mvhd'.codeUnits);
    if (mvhd >= 0) {
      final v = src.u8(mvhd + 4);
      final p = mvhd + 8;
      final int? ctime, scale, dur;
      if (v == 1) {
        ctime = src.u64(p);
        scale = src.u32(p + 16);
        dur = src.u64(p + 20);
      } else {
        ctime = src.u32(p);
        scale = src.u32(p + 8);
        dur = src.u32(p + 12);
      }
      created = _mp4Time(ctime);
      if (scale != null && scale > 0 && dur != null && dur > 0) {
        duration = Duration(milliseconds: dur * 1000 ~/ scale);
      }
    }

    int? w, h;
    var i = 0;
    while ((i = indexOfBytes(body, 'tkhd'.codeUnits, i)) >= 0) {
      final v = src.u8(i + 4);
      final p = i + 8 + (v == 1 ? 84 : 72);
      final tw = (src.u32(p) ?? 0) >> 16;
      final th = (src.u32(p + 4) ?? 0) >> 16;
      if (tw > 0 && th > 0 && tw * th > (w ?? 0) * (h ?? 0)) {
        w = tw;
        h = th;
      }
      i += 4;
    }

    double? lat, lon;
    final xyz = indexOfBytes(body, [0xA9, 0x78, 0x79, 0x7A]);
    if (xyz >= 0) {
      final text = latin1.decode(src.read(xyz + 8, 40));
      final m = RegExp(r'([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)').firstMatch(text);
      if (m != null) {
        lat = double.tryParse(m[1]!);
        lon = double.tryParse(m[2]!);
      }
    }

    String? make, model;
    final latin = latin1.decode(body);
    final mk = RegExp(r'com\.android\.manufacturer.{0,40}?data.{8}([\x20-\x7E]{2,40})')
        .firstMatch(latin);
    if (mk != null) make = mk[1];
    final md = RegExp(r'com\.android\.model.{0,40}?data.{8}([\x20-\x7E]{2,40})')
        .firstMatch(latin);
    if (md != null) model = md[1];

    return FileMetadata(
      width: w,
      height: h,
      takenAt: created,
      duration: duration,
      latitude: lat,
      longitude: lon,
      cameraMake: make,
      cameraModel: model,
    );
  }

  static DateTime? _mp4Time(int? secondsSince1904) {
    if (secondsSince1904 == null || secondsSince1904 == 0) return null;
    const offset = 2082844800; // 1904 → 1970
    final unix = secondsSince1904 - offset;
    if (unix < 0) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
    return t.year > 2100 ? null : t.toLocal();
  }

  FileMetadata? _id3(ByteSource s) {
    if (s.ascii(0, 3) != 'ID3') return null;
    final ver = s.u8(3);
    final hdr = s.read(6, 4);
    if (hdr.length < 4) return null;
    final size = ((hdr[0] & 0x7F) << 21) |
        ((hdr[1] & 0x7F) << 14) |
        ((hdr[2] & 0x7F) << 7) |
        (hdr[3] & 0x7F);
    final tag = s.read(10, math.min(size, 256 * 1024));
    String? title, artist, year, album;
    var off = 0;
    while (off + 10 <= tag.length && ver >= 3) {
      final id = String.fromCharCodes(tag.sublist(off, off + 4));
      if (id.codeUnits.first == 0) break;
      final len = ver == 4
          ? ((tag[off + 4] & 0x7F) << 21) |
              ((tag[off + 5] & 0x7F) << 14) |
              ((tag[off + 6] & 0x7F) << 7) |
              (tag[off + 7] & 0x7F)
          : _be32(tag, off + 4);
      if (len <= 0 || off + 10 + len > tag.length) break;
      if (id.startsWith('T')) {
        final text = _id3Text(tag.sublist(off + 10, off + 10 + len));
        switch (id) {
          case 'TIT2':
            title = text;
          case 'TPE1':
            artist = text;
          case 'TALB':
            album = text;
          case 'TDRC' || 'TYER':
            year = text;
        }
      }
      off += 10 + len;
    }
    return FileMetadata(
      title: title,
      artist: artist,
      extra: {
        if (album != null) 'Album': album,
        if (year != null) 'Year': year,
      },
    );
  }

  static String? _id3Text(List<int> b) {
    if (b.isEmpty) return null;
    final enc = b[0];
    final data = b.sublist(1);
    String text;
    try {
      text = switch (enc) {
        0 => latin1.decode(data),
        3 => utf8.decode(data, allowMalformed: true),
        _ => _utf16(data, bigEndian: enc == 2),
      };
    } catch (_) {
      return null;
    }
    text = text.replaceAll('\u0000', '').trim();
    return text.isEmpty ? null : text;
  }

  static String _utf16(List<int> b, {required bool bigEndian}) {
    var be = bigEndian;
    var i = 0;
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      be = false;
      i = 2;
    } else if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      be = true;
      i = 2;
    }
    final units = <int>[];
    for (; i + 1 < b.length; i += 2) {
      units.add(be ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  FileMetadata? _wav(ByteSource s) {
    var off = 12;
    int? byteRate, sampleRate, channels;
    int? dataSize;
    for (var n = 0; n < 32 && off + 8 <= s.length; n++) {
      final id = s.ascii(off, 4);
      final len = s.u32(off + 4, little: true) ?? 0;
      if (id == 'fmt ') {
        channels = s.u16(off + 10, little: true);
        sampleRate = s.u32(off + 12, little: true);
        byteRate = s.u32(off + 16, little: true);
      } else if (id == 'data') {
        dataSize = math.min(len, s.length - off - 8);
        break;
      }
      off += 8 + len + (len & 1);
    }
    return FileMetadata(
      duration: (byteRate != null && byteRate > 0 && dataSize != null)
          ? Duration(milliseconds: dataSize * 1000 ~/ byteRate)
          : null,
      extra: {
        if (sampleRate != null) 'Sample rate': '$sampleRate Hz',
        if (channels != null) 'Channels': '$channels',
      },
    );
  }

  FileMetadata? _flac(ByteSource s) {
    final b = s.read(18, 8);
    if (b.length < 8) return null;
    final sampleRate = (b[0] << 12) | (b[1] << 4) | (b[2] >> 4);
    final total = ((b[3] & 0x0F) * 0x100000000) + _be32(b, 4);
    return FileMetadata(
      duration: sampleRate > 0
          ? Duration(milliseconds: total * 1000 ~/ sampleRate)
          : null,
      extra: {if (sampleRate > 0) 'Sample rate': '$sampleRate Hz'},
    );
  }

  // ───────────────────────── Documents / data ─────────────────────────

  FileMetadata? _pdf(ByteSource s) {
    final version = s.ascii(5, 3);
    final text = latin1.decode(s.read(0, 64 * 1024)) +
        latin1.decode(s.read(math.max(0, s.length - 64 * 1024), 64 * 1024));
    String? field(String name) {
      final m = RegExp('/$name\\s*\\(([^)]{1,200})\\)').firstMatch(text);
      final v = m?[1]?.trim();
      return (v == null || v.isEmpty || v.startsWith('þÿ')) ? null : v;
    }

    DateTime? created;
    final d = RegExp(r'/CreationDate\s*\(D:(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?')
        .firstMatch(text);
    if (d != null) {
      created = DateTime(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!),
          int.parse(d[4] ?? '0'), int.parse(d[5] ?? '0'), int.parse(d[6] ?? '0'));
    }
    return FileMetadata(
      takenAt: created,
      title: field('Title'),
      artist: field('Author'),
      software: field('Producer') ?? field('Creator'),
      extra: {'PDF version': version},
    );
  }

  FileMetadata? _sqlite(ByteSource s) {
    final text = latin1.decode(s.read(0, 128 * 1024));
    final tables = RegExp(r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?["`\[]?(\w+)')
        .allMatches(text)
        .map((m) => m[1]!)
        .where((t) => !t.startsWith('sqlite_') && t != 'android_metadata')
        .toSet()
        .take(12)
        .toList();
    final pageSize = s.u16(16);
    final pages = s.u32(28);
    return FileMetadata(extra: {
      if (tables.isNotEmpty) 'Tables': tables.join(', '),
      if (pageSize != null && pages != null)
        'Pages': '$pages × ${pageSize == 1 ? 65536 : pageSize} B',
    });
  }

  FileMetadata? _vcf(ByteSource s) {
    final text = utf8.decode(s.read(0, 1024 * 1024), allowMalformed: true);
    final count = 'BEGIN:VCARD'.allMatches(text).length;
    final fn = RegExp(r'^FN[^:]*:(.+)$', multiLine: true).firstMatch(text)?[1];
    return FileMetadata(
      title: fn?.trim(),
      extra: {'Contacts': s.length > 1024 * 1024 ? '$count+ ' : '$count'},
    );
  }

  static int _be32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}

/// Checks whether a file's structure is complete.
class IntegrityChecker {
  const IntegrityChecker();

  Integrity check(ByteSource s, FileType type) {
    try {
      return switch (type.id) {
        'jpeg' => _jpeg(s),
        'png' => s.lastIndexOf('IEND'.codeUnits, window: 64) >= 0
            ? Integrity.intact
            : Integrity.truncated,
        'gif' => _trimmedEndsWith(s, const [0x3B]),
        'pdf' => s.lastIndexOf('%%EOF'.codeUnits, window: 2048) >= 0
            ? Integrity.intact
            : Integrity.truncated,
        'zip' || 'apk' || 'jar' || 'docx' || 'xlsx' || 'pptx' || 'odt' ||
        'ods' || 'odp' || 'epub' =>
          s.lastIndexOf(const [0x50, 0x4B, 0x05, 0x06], window: 66 * 1024) >= 0
              ? Integrity.intact
              : Integrity.truncated,
        'mp4' || 'm4v' || 'mov' || '3gp' || '3g2' || 'm4a' || 'heic' ||
        'heif' || 'avif' =>
          _isoBmff(s, needMoov: !const {'heic', 'heif', 'avif'}.contains(type.id)),
        'webp' || 'avi' || 'wav' => _riff(s),
        'bmp' => (s.u32(2, little: true) ?? 0) <= s.length
            ? Integrity.intact
            : Integrity.truncated,
        'sqlite' => _sqlite(s),
        _ => Integrity.unknown,
      };
    } catch (_) {
      return Integrity.unknown;
    }
  }

  Integrity _jpeg(ByteSource s) {
    final r = _trimmedEndsWith(s, const [0xFF, 0xD9]);
    if (r == Integrity.intact) return r;
    // Motion photos append an MP4 after the JPEG's EOI.
    final head = latin1.decode(s.read(0, 64 * 1024));
    if (head.contains('MotionPhoto') || head.contains('MicroVideo')) {
      return Integrity.intact;
    }
    return r;
  }

  /// Ends with [tail], ignoring zero / 0xFF padding at the very end.
  Integrity _trimmedEndsWith(ByteSource s, List<int> tail) {
    final win = s.read(math.max(0, s.length - 4096), 4096);
    var end = win.length;
    while (end > 0 && (win[end - 1] == 0x00 || (win[end - 1] == 0xFF && tail.last != 0xFF))) {
      end--;
    }
    if (end < tail.length) return Integrity.truncated;
    for (var i = 0; i < tail.length; i++) {
      if (win[end - tail.length + i] != tail[i]) return Integrity.truncated;
    }
    return Integrity.intact;
  }

  Integrity _isoBmff(ByteSource s, {required bool needMoov}) {
    var off = 0;
    var sawMoov = false;
    var sawMeta = false;
    for (var n = 0; n < 4096 && off < s.length; n++) {
      if (off + 8 > s.length) return Integrity.truncated;
      var size = s.u32(off)!;
      final t = s.ascii(off + 4, 4);
      if (size == 1) size = s.u64(off + 8) ?? 0;
      if (size == 0) size = s.length - off;
      if (size < 8) {
        // Zero-filled tail (pre-allocated but unwritten) counts as cut short.
        return Integrity.truncated;
      }
      if (t == 'moov') sawMoov = true;
      if (t == 'meta') sawMeta = true;
      if (off + size > s.length) return Integrity.truncated;
      off += size;
    }
    if (needMoov && !sawMoov) return Integrity.truncated;
    if (!needMoov && !sawMeta) return Integrity.truncated;
    return Integrity.intact;
  }

  Integrity _riff(ByteSource s) {
    final declared = s.u32(4, little: true);
    if (declared == null) return Integrity.truncated;
    return declared + 8 <= s.length ? Integrity.intact : Integrity.truncated;
  }

  Integrity _sqlite(ByteSource s) {
    var pageSize = s.u16(16) ?? 0;
    if (pageSize == 1) pageSize = 65536;
    final pages = s.u32(28) ?? 0;
    if (pageSize == 0 || pages == 0) return Integrity.unknown;
    return pageSize * pages <= s.length ? Integrity.intact : Integrity.truncated;
  }
}
