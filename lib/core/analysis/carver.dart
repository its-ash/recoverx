import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/file_signature.dart';
import '../../domain/signature_database.dart';
import 'byte_source.dart';

/// A file found inside a larger blob.
class CarvedRegion {
  const CarvedRegion(this.offset, this.length, this.type);

  final int offset;
  final int length;
  final FileType type;

  @override
  String toString() => 'Carved(${type.id} @$offset +$length)';
}

/// Finds complete files embedded in a larger byte stream by locating each
/// format's header and walking its structure to the real end.
///
/// Typical sources: gallery thumbnail databases (`.thumbdata*`), app image
/// caches, SQLite blobs, WAL journals, motion photos, and unknown files.
/// Only structurally valid files are returned, so random byte matches are
/// rejected.
class Carver {
  const Carver({this.maxResults = 5000, this.maxCarveBytes = 512 * 1024 * 1024});

  final int maxResults;
  final int maxCarveBytes;

  static const _chunk = 1 << 20;

  /// Scans [s] from [from]. With [skipStart], a header at [from] itself is
  /// ignored (the container's own type).
  List<CarvedRegion> carve(ByteSource s, {int from = 0, bool skipStart = false, bool Function()? isCancelled}) {
    final out = <CarvedRegion>[];
    var pos = from;
    while (pos < s.length && out.length < maxResults) {
      if (isCancelled?.call() ?? false) break;
      final buf = s.read(pos, _chunk + 16);
      if (buf.length < 8) break;
      final limit = math.min(buf.length - 8, _chunk);
      var next = pos + limit;
      for (var i = 0; i < limit; i++) {
        final abs = pos + i;
        if (skipStart && abs == from) continue;
        final r = _tryAt(s, buf, i, abs);
        if (r != null) {
          out.add(r);
          next = r.offset + r.length;
          break;
        }
      }
      pos = math.max(next, pos + 1);
    }
    return out;
  }

  CarvedRegion? _tryAt(ByteSource s, Uint8List b, int i, int abs) {
    final c = b[i];
    switch (c) {
      case 0xFF:
        if (b[i + 1] == 0xD8 && b[i + 2] == 0xFF && b[i + 3] >= 0xC0 && b[i + 3] != 0xFF) {
          final len = jpegLength(s, abs);
          if (len != null) return CarvedRegion(abs, len, FileTypes.jpeg);
        }
      case 0x89:
        if (b[i + 1] == 0x50 && b[i + 2] == 0x4E && b[i + 3] == 0x47 &&
            b[i + 4] == 0x0D && b[i + 5] == 0x0A && b[i + 6] == 0x1A && b[i + 7] == 0x0A) {
          final len = _pngLength(s, abs);
          if (len != null) return CarvedRegion(abs, len, FileTypes.png);
        }
      case 0x47: // G
        if (b[i + 1] == 0x49 && b[i + 2] == 0x46 && b[i + 3] == 0x38 &&
            (b[i + 4] == 0x37 || b[i + 4] == 0x39) && b[i + 5] == 0x61) {
          final len = _gifLength(s, abs);
          if (len != null) return CarvedRegion(abs, len, FileTypes.gif);
        }
      case 0x52: // R
        if (b[i + 1] == 0x49 && b[i + 2] == 0x46 && b[i + 3] == 0x46) {
          return _riff(s, abs);
        }
      case 0x25: // %
        if (b[i + 1] == 0x50 && b[i + 2] == 0x44 && b[i + 3] == 0x46 && b[i + 4] == 0x2D) {
          final len = _pdfLength(s, abs);
          if (len != null) return CarvedRegion(abs, len, FileTypes.pdf);
        }
      case 0x66: // f — "ftyp" sits 4 bytes after the box start
        if (abs >= 4 && b[i + 1] == 0x74 && b[i + 2] == 0x79 && b[i + 3] == 0x70) {
          return _isoBmff(s, abs - 4);
        }
    }
    return null;
  }

  // ───────────────────────── JPEG ─────────────────────────

  /// Length of the JPEG starting at [start] (through its EOI), or null.
  int? jpegLength(ByteSource s, int start) {
    var pos = start + 2;
    var sawSof = false;
    var sawSos = false;
    final end = math.min(s.length, start + maxCarveBytes);
    while (pos + 2 <= end) {
      if (s.u8(pos) != 0xFF) return null;
      var m = s.u8(pos + 1);
      while (m == 0xFF && pos + 2 < end) {
        pos++;
        m = s.u8(pos + 1);
      }
      if (m == 0xD9) {
        if (!sawSof || !sawSos) return null;
        final len = pos + 2 - start;
        return len >= 256 ? len : null;
      }
      if ((m >= 0xD0 && m <= 0xD7) || m == 0x01) {
        pos += 2;
        continue;
      }
      if (m < 0xC0) return null;
      final segLen = s.u16(pos + 2);
      if (segLen == null || segLen < 2) return null;
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        sawSof = true;
      }
      pos += 2 + segLen;
      if (m == 0xDA) {
        sawSos = true;
        final next = _scanEntropy(s, pos, end);
        if (next == null) return null;
        pos = next;
      }
    }
    return null;
  }

  /// Skips entropy-coded data; returns the offset of the next real marker.
  int? _scanEntropy(ByteSource s, int pos, int end) {
    while (pos < end) {
      final buf = s.read(pos, math.min(64 * 1024, end - pos));
      if (buf.length < 2) return null;
      for (var i = 0; i + 1 < buf.length; i++) {
        if (buf[i] != 0xFF) continue;
        final n = buf[i + 1];
        if (n == 0x00 || n == 0xFF || (n >= 0xD0 && n <= 0xD7)) continue;
        return pos + i;
      }
      pos += buf.length - 1;
    }
    return null;
  }

  // ───────────────────────── PNG ─────────────────────────

  int? _pngLength(ByteSource s, int start) {
    var pos = start + 8;
    var first = true;
    final end = math.min(s.length, start + maxCarveBytes);
    while (pos + 12 <= end) {
      final len = s.u32(pos);
      final type = s.ascii(pos + 4, 4);
      if (len == null || len > maxCarveBytes) return null;
      if (!RegExp(r'^[A-Za-z]{4}$').hasMatch(type)) return null;
      if (first && type != 'IHDR') return null;
      first = false;
      pos += 12 + len;
      if (type == 'IEND') return pos <= end ? pos - start : null;
    }
    return null;
  }

  // ───────────────────────── GIF ─────────────────────────

  int? _gifLength(ByteSource s, int start) {
    final flags = s.u8(start + 10);
    if (flags < 0) return null;
    var pos = start + 13;
    if (flags & 0x80 != 0) pos += 3 * (1 << ((flags & 0x07) + 1));
    final end = math.min(s.length, start + maxCarveBytes);
    var frames = 0;
    while (pos < end) {
      final block = s.u8(pos);
      if (block == 0x3B) {
        return frames > 0 ? pos + 1 - start : null;
      } else if (block == 0x21) {
        pos = _skipSubBlocks(s, pos + 2, end) ?? end;
      } else if (block == 0x2C) {
        final f = s.u8(pos + 9);
        pos += 10;
        if (f & 0x80 != 0) pos += 3 * (1 << ((f & 0x07) + 1));
        pos += 1; // LZW minimum code size
        final n = _skipSubBlocks(s, pos, end);
        if (n == null) return null;
        pos = n;
        frames++;
      } else {
        return null;
      }
    }
    return null;
  }

  int? _skipSubBlocks(ByteSource s, int pos, int end) {
    while (pos < end) {
      final n = s.u8(pos);
      if (n < 0) return null;
      pos += 1 + n;
      if (n == 0) return pos;
    }
    return null;
  }

  // ───────────────────────── RIFF ─────────────────────────

  CarvedRegion? _riff(ByteSource s, int start) {
    final size = s.u32(start + 4, little: true);
    final form = s.ascii(start + 8, 4);
    if (size == null || size < 16) return null;
    final type = switch (form) {
      'WEBP' => FileTypes.webp,
      'WAVE' => FileTypes.wav,
      'AVI ' => FileTypes.avi,
      _ => null,
    };
    if (type == null) return null;
    final len = size + 8;
    if (start + len > s.length || len > maxCarveBytes) return null;
    final chunk = s.ascii(start + 12, 4);
    if (!RegExp(r'^[\x20-\x7E]{4}$').hasMatch(chunk)) return null;
    return CarvedRegion(start, len, type);
  }

  // ───────────────────────── PDF ─────────────────────────

  int? _pdfLength(ByteSource s, int start) {
    final nextPdf = s.indexOf('%PDF-'.codeUnits, from: start + 5);
    final limit = math.min(nextPdf < 0 ? s.length : nextPdf, start + maxCarveBytes);
    var last = -1;
    var from = start;
    while (true) {
      final i = s.indexOf('%%EOF'.codeUnits, from: from, to: limit);
      if (i < 0) break;
      last = i;
      from = i + 5;
    }
    if (last < 0) return null;
    var end = last + 5;
    final tail = s.read(end, 2);
    for (final b in tail) {
      if (b == 0x0D || b == 0x0A) {
        end++;
      } else {
        break;
      }
    }
    return end - start;
  }

  // ───────────────────────── MP4 / MOV / HEIC ─────────────────────────

  static const _topBoxes = {
    'ftyp', 'moov', 'mdat', 'free', 'skip', 'wide', 'uuid', 'meta', 'pdin', //
    'moof', 'mfra', 'sidx', 'styp', 'emsg', 'prft', 'udta', 'mfro', 'iloc', 'idat',
  };

  CarvedRegion? _isoBmff(ByteSource s, int start) {
    final ftypSize = s.u32(start);
    if (ftypSize == null || ftypSize < 12 || ftypSize > 512) return null;
    final major = s.ascii(start + 8, 4);
    var pos = start;
    var sawMoov = false, sawMdat = false, sawMeta = false;
    while (pos + 8 <= s.length && pos - start < maxCarveBytes) {
      var size = s.u32(pos)!;
      final t = s.ascii(pos + 4, 4);
      if (!_topBoxes.contains(t)) break;
      if (size == 1) size = s.u64(pos + 8) ?? 0;
      if (size < 8) break;
      if (pos + size > s.length) break;
      if (t == 'moov') sawMoov = true;
      if (t == 'mdat') sawMdat = true;
      if (t == 'meta') sawMeta = true;
      pos += size;
    }
    final len = pos - start;
    final FileType type;
    if (const {'heic', 'heix', 'mif1', 'msf1', 'hevc'}.contains(major)) {
      if (!sawMeta || !sawMdat) return null;
      type = FileTypes.heic;
    } else {
      if (!sawMoov || !sawMdat) return null;
      type = major == 'qt  '
          ? FileTypes.mov
          : major.startsWith('3g')
              ? FileTypes.threeGp
              : major.startsWith('M4A')
                  ? FileTypes.m4a
                  : FileTypes.mp4;
    }
    return CarvedRegion(start, len, type);
  }
}
