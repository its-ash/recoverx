import 'dart:convert';
import 'dart:math' as math;

import '../../domain/file_metadata.dart';
import 'byte_source.dart';

/// Minimal TIFF/EXIF reader: camera, capture time, size, GPS, orientation.
///
/// [tiff] must start at the TIFF header (`II*\0` or `MM\0*`).
class ExifReader {
  ExifReader._(this._s, this._le);

  final ByteSource _s;
  final bool _le;

  static FileMetadata? read(ByteSource tiff) {
    final b = tiff.read(0, 4);
    if (b.length < 4) return null;
    final bool le;
    if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0) {
      le = true;
    } else if (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && b[3] == 0x2A) {
      le = false;
    } else {
      return null;
    }
    try {
      return ExifReader._(tiff, le)._parse();
    } catch (_) {
      return null;
    }
  }

  FileMetadata _parse() {
    final ifd0 = _ifd(_s.u32(4, little: _le) ?? 0);
    final exif = ifd0.containsKey(0x8769) ? _ifd(_int(ifd0[0x8769]!)) : const <int, _Entry>{};
    final gps = ifd0.containsKey(0x8825) ? _ifd(_int(ifd0[0x8825]!)) : const <int, _Entry>{};

    final taken = _date(exif[0x9003]) ?? _date(exif[0x9004]) ?? _date(ifd0[0x0132]);
    final w = _intOrNull(exif[0xA002]) ?? _intOrNull(ifd0[0x0100]);
    final h = _intOrNull(exif[0xA003]) ?? _intOrNull(ifd0[0x0101]);

    double? lat, lon;
    if (gps.isNotEmpty) {
      lat = _dms(gps[0x0002]);
      lon = _dms(gps[0x0004]);
      if (lat != null && _str(gps[0x0001])?.toUpperCase() == 'S') lat = -lat;
      if (lon != null && _str(gps[0x0003])?.toUpperCase() == 'W') lon = -lon;
      if (lat != null && (lat.abs() > 90 || (lat == 0 && lon == 0))) {
        lat = lon = null;
      }
    }

    final extra = <String, String>{};
    final orientation = _intOrNull(ifd0[0x0112]);
    if (orientation != null && orientation > 1 && orientation <= 8) {
      extra['Orientation'] = '$orientation';
    }
    final lens = _str(exif[0xA434]);
    if (lens != null) extra['Lens'] = lens;
    final owner = _str(exif[0xA430]);
    if (owner != null) extra['Camera owner'] = owner;
    final serial = _str(exif[0xA431]);
    if (serial != null) extra['Body serial'] = serial;
    final uid = _str(exif[0xA420]);
    if (uid != null) extra['Image unique ID'] = uid;

    return FileMetadata(
      width: w,
      height: h,
      takenAt: taken,
      cameraMake: _str(ifd0[0x010F]),
      cameraModel: _str(ifd0[0x0110]),
      software: _str(ifd0[0x0131]),
      latitude: lat,
      longitude: lon,
      extra: extra,
    );
  }

  static const _typeSize = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8};

  Map<int, _Entry> _ifd(int offset) {
    final out = <int, _Entry>{};
    final count = _s.u16(offset, little: _le);
    if (count == null || count == 0 || count > 512) return out;
    for (var i = 0; i < count; i++) {
      final e = offset + 2 + i * 12;
      final tag = _s.u16(e, little: _le);
      final type = _s.u16(e + 2, little: _le);
      final n = _s.u32(e + 4, little: _le);
      if (tag == null || type == null || n == null) break;
      final size = (_typeSize[type] ?? 1) * n;
      final dataOff = size <= 4 ? e + 8 : (_s.u32(e + 8, little: _le) ?? 0);
      out[tag] = _Entry(type, n, dataOff);
    }
    return out;
  }

  int _int(_Entry e) => _intOrNull(e) ?? 0;

  int? _intOrNull(_Entry? e) {
    if (e == null) return null;
    return switch (e.type) {
      3 => _s.u16(e.offset, little: _le),
      4 || 9 => _s.u32(e.offset, little: _le),
      1 || 7 => _s.u8(e.offset),
      _ => null,
    };
  }

  String? _str(_Entry? e) {
    if (e == null || e.type != 2 || e.count == 0) return null;
    final raw = _s.read(e.offset, math.min(e.count, 256));
    final end = raw.indexOf(0);
    final text = latin1
        .decode(end >= 0 ? raw.sublist(0, end) : raw)
        .trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _date(_Entry? e) {
    final s = _str(e);
    if (s == null) return null;
    final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m[1]!);
    if (y < 1970) return null;
    return DateTime(y, int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!),
        int.parse(m[5]!), int.parse(m[6]!));
  }

  double? _rational(int off) {
    final n = _s.u32(off, little: _le);
    final d = _s.u32(off + 4, little: _le);
    if (n == null || d == null || d == 0) return null;
    return n / d;
  }

  double? _dms(_Entry? e) {
    if (e == null || e.type != 5 || e.count < 3) return null;
    final d = _rational(e.offset);
    final m = _rational(e.offset + 8);
    final s = _rational(e.offset + 16);
    if (d == null || m == null || s == null) return null;
    return d + m / 60 + s / 3600;
  }
}

class _Entry {
  const _Entry(this.type, this.count, this.offset);
  final int type;
  final int count;
  final int offset;
}
