import 'dart:typed_data';

/// Builders for small, structurally valid sample files.
List<int> ascii(String s) => s.codeUnits;

List<int> be16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> box(String type, List<int> body) => [...be32(8 + body.length), ...ascii(type), ...body];

/// Minimal baseline JPEG with optional APP1 EXIF segment.
Uint8List jpeg({List<int>? exifTiff, int width = 16, int height = 16, int scanBytes = 400}) {
  final out = <int>[0xFF, 0xD8];
  out.addAll([0xFF, 0xE0, ...be16(16), ...ascii('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
  if (exifTiff != null) {
    final body = [...ascii('Exif'), 0, 0, ...exifTiff];
    out.addAll([0xFF, 0xE1, ...be16(body.length + 2), ...body]);
  }
  out.addAll([0xFF, 0xDB, ...be16(67), 0, ...List.filled(64, 1)]);
  out.addAll([0xFF, 0xC0, ...be16(17), 8, ...be16(height), ...be16(width), 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]);
  out.addAll([0xFF, 0xDA, ...be16(12), 3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3F, 0]);
  for (var i = 0; i < scanBytes; i++) {
    out.add(i == 100 ? 0xFF : 0x12);
    if (i == 100) out.add(0x00); // stuffed byte, not a marker
  }
  out.addAll([0xFF, 0xD9]);
  return Uint8List.fromList(out);
}

Uint8List png({int width = 4, int height = 3}) {
  List<int> chunk(String t, List<int> d) => [...be32(d.length), ...ascii(t), ...d, 0, 0, 0, 0];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', [...be32(width), ...be32(height), 8, 6, 0, 0, 0]),
    ...chunk('IDAT', List.filled(20, 7)),
    ...chunk('IEND', []),
  ]);
}

/// ISO-BMFF file: ftyp + moov (with a handler) + mdat.
Uint8List isoBmff(String major, {String handler = 'vide', List<String> compat = const [], bool withMoov = true}) {
  final ftyp = box('ftyp', [...ascii(major), 0, 0, 0, 0, for (final c in compat) ...ascii(c)]);
  final mvhd = box('mvhd', [0, 0, 0, 0, ...be32(3786000000), ...be32(3786000000), ...be32(1000), ...be32(5000), ...List.filled(80, 0)]);
  final hdlr = box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...ascii(handler), ...List.filled(13, 0)]);
  final moov = box('moov', [...mvhd, ...box('trak', box('mdia', hdlr))]);
  final mdat = box('mdat', List.filled(64, 0x55));
  return Uint8List.fromList([...ftyp, if (withMoov) ...moov, ...mdat]);
}

Uint8List riff(String form, {int extra = 16}) {
  final body = [...ascii(form), ...ascii('fmt '), ...le32(extra - 8 > 0 ? extra - 8 : 0), ...List.filled(extra - 8 > 0 ? extra - 8 : 0, 1)];
  return Uint8List.fromList([...ascii('RIFF'), ...le32(body.length), ...body]);
}

/// ZIP with one local header naming [firstEntry], and [names] in the tail.
Uint8List zip(String firstEntry, {List<String> names = const [], String? storedContent}) {
  final content = ascii(storedContent ?? 'x');
  final local = [
    0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, ...le32(content.length), ...le32(content.length),
    ...le16(firstEntry.length), 0, 0, ...ascii(firstEntry), ...content,
  ];
  final central = [for (final n in [firstEntry, ...names]) ...[0x50, 0x4B, 0x01, 0x02, ...List.filled(42, 0), ...ascii(n)]];
  final eocd = [0x50, 0x4B, 0x05, 0x06, ...List.filled(18, 0)];
  return Uint8List.fromList([...local, ...central, ...eocd]);
}

/// OLE2 compound file whose first directory sector names [stream].
Uint8List ole(String stream) {
  final header = List<int>.filled(512, 0);
  header.setAll(0, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
  header.setAll(30, le16(9));
  header.setAll(48, le32(0)); // directory starts at sector 0 → offset 512
  final dir = List<int>.filled(512, 0);
  final name = [for (final c in 'Root Entry'.codeUnits) ...le16(c)];
  dir.setAll(0, name);
  final s = [for (final c in stream.codeUnits) ...le16(c)];
  dir.setAll(128, s);
  return Uint8List.fromList([...header, ...dir]);
}

/// Big-endian TIFF/EXIF block with make, model, date and GPS.
List<int> exifTiff({
  String make = 'Google',
  String model = 'Pixel 8',
  String date = '2024:05:17 14:03:22',
  double lat = 28.6139,
  double lon = -77.2090,
}) {
  // Layout: header(8) | IFD0 | ExifIFD | GPSIFD | data
  final data = <int>[];
  int dataBase = 0;
  int addData(List<int> bytes) {
    final off = dataBase + data.length;
    data.addAll(bytes);
    if (data.length.isOdd) data.add(0);
    return off;
  }

  List<int> entry(int tag, int type, int count, List<int> valueOrOffset) =>
      [...be16(tag), ...be16(type), ...be32(count), ...valueOrOffset];

  List<int> rational3(double v) {
    final d = v.abs().floor();
    final mFull = (v.abs() - d) * 60;
    final m = mFull.floor();
    final s = ((mFull - m) * 60 * 1000).round();
    return [...be32(d), ...be32(1), ...be32(m), ...be32(1), ...be32(s), ...be32(1000)];
  }

  const ifd0Count = 4, exifCount = 1, gpsCount = 4;
  final ifd0Off = 8;
  final exifOff = ifd0Off + 2 + ifd0Count * 12 + 4;
  final gpsOff = exifOff + 2 + exifCount * 12 + 4;
  dataBase = gpsOff + 2 + gpsCount * 12 + 4;

  final makeOff = addData([...ascii(make), 0]);
  final modelOff = addData([...ascii(model), 0]);
  final dateOff = addData([...ascii(date), 0]);
  final latOff = addData(rational3(lat));
  final lonOff = addData(rational3(lon));

  final ifd0 = [
    ...be16(ifd0Count),
    ...entry(0x010F, 2, make.length + 1, be32(makeOff)),
    ...entry(0x0110, 2, model.length + 1, be32(modelOff)),
    ...entry(0x8769, 4, 1, be32(exifOff)),
    ...entry(0x8825, 4, 1, be32(gpsOff)),
    ...be32(0),
  ];
  final exif = [...be16(exifCount), ...entry(0x9003, 2, date.length + 1, be32(dateOff)), ...be32(0)];
  final gps = [
    ...be16(gpsCount),
    ...entry(0x0001, 2, 2, [lat >= 0 ? 0x4E : 0x53, 0, 0, 0]),
    ...entry(0x0002, 5, 3, be32(latOff)),
    ...entry(0x0003, 2, 2, [lon >= 0 ? 0x45 : 0x57, 0, 0, 0]),
    ...entry(0x0004, 5, 3, be32(lonOff)),
    ...be32(0),
  ];
  return [...ascii('MM'), 0, 0x2A, ...be32(8), ...ifd0, ...exif, ...gps, ...data];
}
