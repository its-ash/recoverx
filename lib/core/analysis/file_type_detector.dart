import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';
import '../../domain/signature_database.dart';
import 'byte_source.dart';

/// Result of type detection.
class Detection {
  const Detection(this.type, this.confidence);

  final FileType type;
  final MatchConfidence confidence;

  @override
  String toString() => 'Detection(${type.id}, ${confidence.name})';
}

/// Identifies a file's real type from its bytes. The name and extension are
/// never used.
///
/// Plain magic numbers come from [SignatureDatabase]. Container formats that
/// share a prefix (ISO-BMFF, RIFF, EBML, ZIP, OLE2, Ogg, TIFF) and weak
/// signatures (BMP, MP3/AAC frames, MPEG-TS) are checked structurally here.
class FileTypeDetector {
  const FileTypeDetector();

  static const _headerLen = 1024;

  Detection? detect(ByteSource s) {
    if (s.length < 4) return null;
    final h = s.read(0, _headerLen);

    return _jpeg(h) ??
        _isoBmff(s, h) ??
        _riff(h) ??
        _ebml(h) ??
        _zip(s, h) ??
        _ole(s, h) ??
        _ogg(h) ??
        _tiff(s, h) ??
        _table(h) ??
        _bmp(s, h) ??
        _mpegAudio(s, h) ??
        _mpegTs(h);
  }

  // ───────────────────────── JPEG ─────────────────────────

  Detection? _jpeg(Uint8List h) {
    if (h.length < 4 || h[0] != 0xFF || h[1] != 0xD8 || h[2] != 0xFF) {
      return null;
    }
    final m = h[3];
    if (m < 0xC0 || m == 0xFF) return null;
    const common = {0xE0, 0xE1, 0xE2, 0xDB, 0xC0, 0xC2, 0xC4, 0xEE, 0xFE, 0xED};
    return Detection(FileTypes.jpeg,
        common.contains(m) ? MatchConfidence.high : MatchConfidence.medium);
  }

  // ─────────────────── ISO-BMFF (MP4/MOV/HEIC/3GP/M4A) ───────────────────

  static const _heicBrands = {
    'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'hevm', 'hevs', //
  };

  Detection? _isoBmff(ByteSource s, Uint8List h) {
    if (h.length < 12) return null;
    final box = String.fromCharCodes(h.sublist(4, 8));
    if (box == 'ftyp') {
      final size = _be32(h, 0);
      if (size < 8 || size > 4096) return null;
      final major = String.fromCharCodes(h.sublist(8, 12));
      final brands = <String>{major};
      for (var i = 16; i + 4 <= math.min(size, h.length); i += 4) {
        brands.add(String.fromCharCodes(h.sublist(i, i + 4)));
      }
      return Detection(_brandType(s, major, brands), MatchConfidence.high);
    }
    // QuickTime files from old devices may start without `ftyp`.
    const qtFirst = {'moov', 'mdat', 'wide', 'free', 'skip', 'pnot'};
    if (qtFirst.contains(box)) {
      final size = _be32(h, 0);
      if (size < 8 && size != 1) return null;
      if (size >= 8 && size < s.length) {
        final next = s.ascii(size + 4, 4);
        if (!_isFourCC(next)) return null;
      }
      return const Detection(FileTypes.mov, MatchConfidence.medium);
    }
    return null;
  }

  FileType _brandType(ByteSource s, String major, Set<String> brands) {
    if (major == 'avif' || major == 'avis') return FileTypes.avif;
    if (_heicBrands.contains(major)) return FileTypes.heic;
    if (major == 'mif1' || major == 'msf1') {
      if (brands.any(_heicBrands.contains)) return FileTypes.heic;
      if (brands.contains('avif')) return FileTypes.avif;
      return FileTypes.heif;
    }
    if (major == 'qt  ') return FileTypes.mov;
    if (major.startsWith('3g2')) return FileTypes.threeG2;
    if (major.startsWith('3g')) return FileTypes.threeGp;
    if (const {'M4A ', 'M4B ', 'M4P ', 'F4A ', 'F4B '}.contains(major)) {
      return FileTypes.m4a;
    }
    if (major.startsWith('M4V')) return FileTypes.m4v;
    // Generic brands (isom, mp41, mp42, avc1, dash, ...): check the tracks.
    return _hasVideoTrack(s) == false ? FileTypes.m4a : FileTypes.mp4;
  }

  /// Looks at `hdlr` boxes inside `moov`. Returns null if `moov` is missing.
  bool? _hasVideoTrack(ByteSource s) {
    final moov = findTopLevelBox(s, 'moov');
    if (moov == null) return null;
    final len = math.min(moov.$2, 4 * 1024 * 1024);
    final body = s.read(moov.$1, len);
    var sawAudio = false;
    var i = 0;
    const hdlr = [0x68, 0x64, 0x6C, 0x72];
    while ((i = indexOfBytes(body, hdlr, i)) >= 0) {
      if (i + 16 <= body.length) {
        final handler = String.fromCharCodes(body.sublist(i + 12, i + 16));
        if (handler == 'vide') return true;
        if (handler == 'soun') sawAudio = true;
      }
      i += 4;
    }
    return sawAudio ? false : null;
  }

  /// Walks top-level ISO-BMFF boxes. Returns (offset, size) of [type].
  static (int, int)? findTopLevelBox(ByteSource s, String type) {
    var off = 0;
    for (var n = 0; n < 4096 && off + 8 <= s.length; n++) {
      var size = s.u32(off)!;
      final t = s.ascii(off + 4, 4);
      if (size == 1) {
        size = s.u64(off + 8) ?? 0;
      } else if (size == 0) {
        size = s.length - off;
      }
      if (size < 8 || !_isFourCC(t)) return null;
      if (t == type) return (off, size);
      off += size;
    }
    return null;
  }

  static bool _isFourCC(String t) =>
      t.length == 4 &&
      t.codeUnits.every((c) => c == 0xA9 || (c >= 0x20 && c < 0x7F));

  // ───────────────────────── RIFF ─────────────────────────

  Detection? _riff(Uint8List h) {
    if (h.length < 12) return null;
    final tag = String.fromCharCodes(h.sublist(0, 4));
    if (tag != 'RIFF' && tag != 'RF64') return null;
    final form = String.fromCharCodes(h.sublist(8, 12));
    final type = switch (form) {
      'WEBP' => FileTypes.webp,
      'AVI ' => FileTypes.avi,
      'WAVE' => FileTypes.wav,
      'RMID' => FileTypes.midi,
      _ => null,
    };
    return type == null ? null : Detection(type, MatchConfidence.high);
  }

  // ───────────────────────── EBML (MKV / WebM) ─────────────────────────

  Detection? _ebml(Uint8List h) {
    if (h.length < 8 ||
        h[0] != 0x1A ||
        h[1] != 0x45 ||
        h[2] != 0xDF ||
        h[3] != 0xA3) {
      return null;
    }
    final i = indexOfBytes(h.sublist(0, math.min(h.length, 128)), [0x42, 0x82]);
    if (i >= 0 && i + 3 < h.length) {
      final lenByte = h[i + 2];
      if (lenByte & 0x80 != 0) {
        final n = lenByte & 0x7F;
        final docType =
            String.fromCharCodes(h.sublist(i + 3, math.min(h.length, i + 3 + n)));
        if (docType.startsWith('webm')) {
          return const Detection(FileTypes.webm, MatchConfidence.high);
        }
      }
    }
    return const Detection(FileTypes.mkv, MatchConfidence.high);
  }

  // ───────────────────────── ZIP family ─────────────────────────

  Detection? _zip(ByteSource s, Uint8List h) {
    if (h.length < 30 ||
        h[0] != 0x50 ||
        h[1] != 0x4B ||
        h[2] != 0x03 ||
        h[3] != 0x04) {
      return null;
    }
    // OpenDocument / EPUB: first entry is a stored "mimetype" file.
    final nameLen = h[26] | (h[27] << 8);
    final extraLen = h[28] | (h[29] << 8);
    if (nameLen == 8 && String.fromCharCodes(h.sublist(30, 38)) == 'mimetype') {
      final cSize = h[18] | (h[19] << 8) | (h[20] << 16) | (h[21] << 24);
      final mime = s.ascii(30 + nameLen + extraLen, math.min(cSize, 100));
      final t = switch (mime) {
        'application/epub+zip' => FileTypes.epub,
        'application/vnd.oasis.opendocument.text' => FileTypes.odt,
        'application/vnd.oasis.opendocument.spreadsheet' => FileTypes.ods,
        'application/vnd.oasis.opendocument.presentation' => FileTypes.odp,
        _ => null,
      };
      if (t != null) return Detection(t, MatchConfidence.high);
    }

    // Entry names live in the local headers (start) and the central
    // directory (end). Read both and look for marker paths.
    final head = s.read(0, 256 * 1024);
    final tail = s.length > head.length
        ? s.read(math.max(head.length, s.length - 256 * 1024), 256 * 1024)
        : Uint8List(0);
    final names = latin1.decode(head) + latin1.decode(tail);

    bool has(String n) => names.contains(n);
    FileType type;
    if (has('AndroidManifest.xml') &&
        (has('classes.dex') || has('resources.arsc'))) {
      type = FileTypes.apk;
    } else if (has('word/document.xml') || has('word/_rels')) {
      type = FileTypes.docx;
    } else if (has('xl/workbook.xml') || has('xl/_rels')) {
      type = FileTypes.xlsx;
    } else if (has('ppt/presentation.xml') || has('ppt/_rels')) {
      type = FileTypes.pptx;
    } else if (has('META-INF/MANIFEST.MF') && has('.class')) {
      type = FileTypes.jar;
    } else {
      type = FileTypes.zip;
    }
    return Detection(type, MatchConfidence.high);
  }

  // ───────────────────────── OLE2 (doc/xls/ppt/msg) ─────────────────────────

  Detection? _ole(ByteSource s, Uint8List h) {
    const sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    if (h.length < 512) return null;
    for (var i = 0; i < 8; i++) {
      if (h[i] != sig[i]) return null;
    }
    final shift = h[30] | (h[31] << 8);
    final sector = (shift == 9 || shift == 12) ? 1 << shift : 512;
    final dirStart = _le32(h, 48);
    // Directory entries hold UTF-16LE stream names. Read the first directory
    // run plus the start of the file as a fallback.
    final dir = s.read((dirStart + 1) * sector, sector * 4);
    final text = _utf16Ascii(dir) + _utf16Ascii(s.read(0, 128 * 1024));

    FileType type;
    if (text.contains('WordDocument')) {
      type = FileTypes.doc;
    } else if (text.contains('Workbook') || text.contains('Book\u0000')) {
      type = FileTypes.xls;
    } else if (text.contains('PowerPoint Document')) {
      type = FileTypes.ppt;
    } else if (text.contains('__substg1.0_')) {
      type = FileTypes.msg;
    } else {
      return const Detection(FileTypes.ole, MatchConfidence.medium);
    }
    return Detection(type, MatchConfidence.high);
  }

  /// Keeps the low byte of each UTF-16LE unit whose high byte is zero.
  static String _utf16Ascii(Uint8List b) {
    final out = StringBuffer();
    for (var i = 0; i + 1 < b.length; i += 2) {
      out.writeCharCode(b[i + 1] == 0 ? b[i] : 0x20);
    }
    return out.toString();
  }

  // ───────────────────────── Ogg ─────────────────────────

  Detection? _ogg(Uint8List h) {
    if (h.length < 36 || String.fromCharCodes(h.sublist(0, 4)) != 'OggS') {
      return null;
    }
    final segs = h[26];
    final data = 27 + segs;
    if (data + 8 <= h.length) {
      final id = String.fromCharCodes(h.sublist(data, data + 8));
      if (id.startsWith('OpusHead')) {
        return const Detection(FileTypes.opus, MatchConfidence.high);
      }
    }
    return const Detection(FileTypes.ogg, MatchConfidence.high);
  }

  // ───────────────────────── TIFF & RAW ─────────────────────────

  Detection? _tiff(ByteSource s, Uint8List h) {
    if (h.length < 16) return null;
    final little = h[0] == 0x49 && h[1] == 0x49 && h[2] == 0x2A && h[3] == 0;
    final big = h[0] == 0x4D && h[1] == 0x4D && h[2] == 0 && h[3] == 0x2A;
    if (!little && !big) return null;
    if (little && h[8] == 0x43 && h[9] == 0x52) {
      return const Detection(FileTypes.cr2, MatchConfidence.high);
    }
    final ifd = s.u32(4, little: little) ?? 0;
    final count = s.u16(ifd, little: little) ?? 0;
    if (count == 0 || count > 500) {
      return const Detection(FileTypes.tiff, MatchConfidence.medium);
    }
    String? make;
    for (var i = 0; i < count; i++) {
      final e = ifd + 2 + i * 12;
      final tag = s.u16(e, little: little);
      if (tag == 0xC612) {
        return const Detection(FileTypes.dng, MatchConfidence.high);
      }
      if (tag == 0x010F) {
        final n = s.u32(e + 4, little: little) ?? 0;
        final off = n <= 4 ? e + 8 : (s.u32(e + 8, little: little) ?? 0);
        make = s.ascii(off, math.min(n, 64)).toUpperCase();
      }
    }
    if (make != null) {
      if (make.startsWith('NIKON')) {
        return const Detection(FileTypes.nef, MatchConfidence.high);
      }
      if (make.startsWith('SONY')) {
        return const Detection(FileTypes.arw, MatchConfidence.high);
      }
    }
    return const Detection(FileTypes.tiff, MatchConfidence.high);
  }

  // ───────────────────────── Plain table ─────────────────────────

  Detection? _table(Uint8List h) {
    FileSignature? best;
    for (final sig in SignatureDatabase.all) {
      if (!sig.matchesHeader(h)) continue;
      if (best == null || sig.strength > best.strength) best = sig;
    }
    if (best == null) return null;
    return Detection(best.type,
        best.strength >= 4 ? MatchConfidence.high : MatchConfidence.medium);
  }

  // ───────────────────────── BMP ─────────────────────────

  Detection? _bmp(ByteSource s, Uint8List h) {
    if (h.length < 26 || h[0] != 0x42 || h[1] != 0x4D) return null;
    final declared = _le32(h, 2);
    final reserved = _le32(h, 6);
    final pixelOffset = _le32(h, 10);
    final dib = _le32(h, 14);
    const dibSizes = {12, 40, 52, 56, 64, 108, 124};
    if (reserved != 0 || !dibSizes.contains(dib)) return null;
    if (pixelOffset < 14 + dib || declared < pixelOffset) return null;
    return Detection(
        FileTypes.bmp,
        declared == s.length ? MatchConfidence.high : MatchConfidence.medium);
  }

  // ───────────────────────── MP3 / AAC ─────────────────────────

  Detection? _mpegAudio(ByteSource s, Uint8List h) {
    if (h.length >= 10 &&
        h[0] == 0x49 &&
        h[1] == 0x44 &&
        h[2] == 0x33 &&
        h[3] >= 2 &&
        h[3] <= 4) {
      // ID3v2 tag: skip it and check what follows.
      final tagSize = ((h[6] & 0x7F) << 21) |
          ((h[7] & 0x7F) << 14) |
          ((h[8] & 0x7F) << 7) |
          (h[9] & 0x7F);
      final after = 10 + tagSize + ((h[5] & 0x10) != 0 ? 10 : 0);
      final hdr = s.read(after, 8);
      if (hdr.length >= 4 && _adtsLen(hdr) != null) {
        return const Detection(FileTypes.aac, MatchConfidence.high);
      }
      return const Detection(FileTypes.mp3, MatchConfidence.high);
    }
    final adts = _adtsLen(h);
    if (adts != null) {
      final next = s.read(adts, 8);
      if (next.length >= 7 && _adtsLen(next) != null) {
        return const Detection(FileTypes.aac, MatchConfidence.medium);
      }
      return null;
    }
    final mp3 = mp3FrameLength(h);
    if (mp3 != null) {
      final next = s.read(mp3, 4);
      if (next.length == 4 && mp3FrameLength(next) != null) {
        final third = s.read(mp3 + mp3FrameLength(next)!, 4);
        return Detection(
            FileTypes.mp3,
            third.length == 4 && mp3FrameLength(third) != null
                ? MatchConfidence.medium
                : MatchConfidence.low);
      }
    }
    return null;
  }

  /// ADTS frame length if [b] starts with a valid ADTS header.
  static int? _adtsLen(List<int> b) {
    if (b.length < 7 || b[0] != 0xFF || (b[1] & 0xF6) != 0xF0) return null;
    final sfIndex = (b[2] >> 2) & 0x0F;
    if (sfIndex > 12) return null;
    final len = ((b[3] & 0x03) << 11) | (b[4] << 3) | (b[5] >> 5);
    return len >= 7 ? len : null;
  }

  static const _mp3Bitrates = {
    // (version, layer) -> kbps table, index 1..14
    'v1l1': [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
    'v1l2': [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
    'v1l3': [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
    'v2l1': [32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
    'v2l23': [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  };

  /// MPEG audio frame length if [b] starts with a valid frame header.
  static int? mp3FrameLength(List<int> b) {
    if (b.length < 4 || b[0] != 0xFF || (b[1] & 0xE0) != 0xE0) return null;
    final version = (b[1] >> 3) & 0x03; // 0=2.5, 2=2, 3=1
    final layer = (b[1] >> 1) & 0x03; // 1=III, 2=II, 3=I
    final brIndex = (b[2] >> 4) & 0x0F;
    final srIndex = (b[2] >> 2) & 0x03;
    final padding = (b[2] >> 1) & 0x01;
    if (version == 1 || layer == 0 || brIndex == 0 || brIndex == 15) {
      return null;
    }
    if (srIndex == 3) return null;
    const rates = [44100, 48000, 32000];
    var sampleRate = rates[srIndex];
    if (version == 2) sampleRate ~/= 2;
    if (version == 0) sampleRate ~/= 4;
    final v1 = version == 3;
    final key = v1
        ? (layer == 3 ? 'v1l1' : layer == 2 ? 'v1l2' : 'v1l3')
        : (layer == 3 ? 'v2l1' : 'v2l23');
    final bitrate = _mp3Bitrates[key]![brIndex - 1] * 1000;
    if (layer == 3) return (12 * bitrate ~/ sampleRate + padding) * 4;
    final coef = (layer == 1 && !v1) ? 72 : 144;
    final len = coef * bitrate ~/ sampleRate + padding;
    return len >= 4 ? len : null;
  }

  // ───────────────────────── MPEG-TS ─────────────────────────

  Detection? _mpegTs(Uint8List h) {
    bool stride(int start, int step) {
      for (var i = 0; i < 4; i++) {
        final p = start + i * step;
        if (p >= h.length || h[p] != 0x47) return false;
      }
      return true;
    }

    if (stride(0, 188) || stride(4, 192)) {
      return const Detection(FileTypes.mpegTs, MatchConfidence.medium);
    }
    return null;
  }

  static int _be32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _le32(List<int> b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}
