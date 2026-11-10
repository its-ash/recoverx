import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Random-access, read-only view of some bytes (a file or a memory buffer).
///
/// All analysis code reads through this so it never loads whole files and
/// stays unit-testable with in-memory buffers.
abstract class ByteSource {
  int get length;

  /// Reads up to [count] bytes at [offset]. Returns fewer at end of data and
  /// an empty list when [offset] is out of range.
  Uint8List read(int offset, int count);

  /// A view of [count] bytes starting at [offset].
  ByteSource slice(int offset, int count) => _SliceSource(this, offset, count);

  int u8(int offset) {
    final b = read(offset, 1);
    return b.isEmpty ? -1 : b[0];
  }

  int? u16(int offset, {bool little = false}) {
    final b = read(offset, 2);
    if (b.length < 2) return null;
    return little ? b[0] | (b[1] << 8) : (b[0] << 8) | b[1];
  }

  int? u32(int offset, {bool little = false}) {
    final b = read(offset, 4);
    if (b.length < 4) return null;
    return little
        ? b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)
        : (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  int? u64(int offset) {
    final hi = u32(offset);
    final lo = u32(offset + 4);
    if (hi == null || lo == null) return null;
    return hi * 0x100000000 + lo;
  }

  String ascii(int offset, int count) =>
      String.fromCharCodes(read(offset, count));

  bool startsWith(int offset, List<int> pattern) {
    final b = read(offset, pattern.length);
    if (b.length < pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (b[i] != pattern[i]) return false;
    }
    return true;
  }

  /// First index of [needle] in `[from, to)`, scanning in chunks.
  int indexOf(List<int> needle, {int from = 0, int? to}) {
    final end = math.min(to ?? length, length);
    const chunk = 1 << 16;
    var pos = from;
    while (pos < end) {
      final buf = read(pos, math.min(chunk + needle.length - 1, end - pos));
      final i = indexOfBytes(buf, needle);
      if (i >= 0) return pos + i;
      if (buf.length < needle.length) break;
      pos += buf.length - needle.length + 1;
    }
    return -1;
  }

  /// Last index of [needle] within the final [window] bytes.
  int lastIndexOf(List<int> needle, {int window = 4096}) {
    final start = math.max(0, length - window);
    final buf = read(start, length - start);
    for (var i = buf.length - needle.length; i >= 0; i--) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (buf[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return start + i;
    }
    return -1;
  }
}

/// Index of [needle] in [hay] starting at [from], or -1.
int indexOfBytes(List<int> hay, List<int> needle, [int from = 0]) {
  if (needle.isEmpty) return from;
  final first = needle[0];
  final last = hay.length - needle.length;
  outer:
  for (var i = from; i <= last; i++) {
    if (hay[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

class MemoryByteSource extends ByteSource {
  MemoryByteSource(List<int> bytes)
      : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || offset >= _bytes.length || count <= 0) {
      return Uint8List(0);
    }
    final end = math.min(_bytes.length, offset + count);
    return Uint8List.sublistView(_bytes, offset, end);
  }
}

/// Synchronous file reader with a small read-ahead cache. Meant for use
/// inside a background isolate; call [close] when done.
class FileByteSource extends ByteSource {
  FileByteSource._(this._raf, this.length);

  static FileByteSource open(String path) {
    final raf = File(path).openSync();
    return FileByteSource._(raf, raf.lengthSync());
  }

  final RandomAccessFile _raf;

  @override
  final int length;

  static const _cacheSize = 64 * 1024;
  int _cacheStart = -1;
  Uint8List _cache = Uint8List(0);

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || offset >= length || count <= 0) return Uint8List(0);
    count = math.min(count, length - offset);
    if (_cacheStart >= 0 &&
        offset >= _cacheStart &&
        offset + count <= _cacheStart + _cache.length) {
      return Uint8List.sublistView(
          _cache, offset - _cacheStart, offset - _cacheStart + count);
    }
    if (count > _cacheSize) {
      _raf.setPositionSync(offset);
      return _raf.readSync(count);
    }
    _raf.setPositionSync(offset);
    _cache = _raf.readSync(math.min(_cacheSize, length - offset));
    _cacheStart = offset;
    return Uint8List.sublistView(_cache, 0, math.min(count, _cache.length));
  }

  void close() {
    try {
      _raf.closeSync();
    } catch (_) {}
  }
}

class _SliceSource extends ByteSource {
  _SliceSource(this._parent, this._start, int count)
      : length = math.max(0, math.min(count, _parent.length - _start));

  final ByteSource _parent;
  final int _start;

  @override
  final int length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || offset >= length || count <= 0) return Uint8List(0);
    return _parent.read(_start + offset, math.min(count, length - offset));
  }
}
