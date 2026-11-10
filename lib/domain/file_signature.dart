/// Supported file categories.
enum FileCategory {
  image,
  video,
  audio,
  document,
  archive,

  /// Databases, contacts, calendars: app data an investigator usually wants.
  data,
  other,
}

/// A concrete file type the detector can report.
class FileType {
  const FileType({
    required this.id,
    required this.category,
    required this.extension,
    required this.mimeType,
    required this.displayName,
  });

  /// Unique id, e.g. 'jpeg'.
  final String id;

  /// Broad category for filtering in the results screen.
  final FileCategory category;

  /// Canonical extension without the leading dot, e.g. 'jpg'.
  final String extension;

  /// IANA mime type.
  final String mimeType;

  /// Human readable name, e.g. 'JPEG Image'.
  final String displayName;

  @override
  bool operator ==(Object other) => other is FileType && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FileType($id)';

  /// True when a file named with [ext] (no dot, any case) is not disguised:
  /// the canonical extension or a common alias of the same format family.
  bool acceptsExtension(String ext) {
    final e = ext.toLowerCase();
    if (e == extension) return true;
    return _aliases[id]?.contains(e) ?? false;
  }

  static const _isoVideo = {'mp4', 'm4v', 'm4a', 'm4b', 'mov', '3gp', '3gpp', '3ga', '3g2', 'mp4v', 'qt'};
  static const _ole = {'doc', 'dot', 'xls', 'xlt', 'ppt', 'pps', 'pot', 'msg', 'ole', 'wps', 'vsd', 'pub'};

  static const Map<String, Set<String>> _aliases = {
    'jpeg': {'jpeg', 'jpe', 'jfif', 'jif'},
    'tiff': {'tiff'},
    'heic': {'heif', 'hif'},
    'heif': {'heic', 'hif'},
    'mp4': _isoVideo,
    'm4v': _isoVideo,
    'mov': _isoVideo,
    '3gp': _isoVideo,
    '3g2': _isoVideo,
    'm4a': _isoVideo,
    'mkv': {'mka', 'mk3d', 'webm'},
    'webm': {'mkv'},
    'asf': {'wma', 'asf'},
    'mpeg': {'mpeg', 'mpe', 'vob', 'm2p'},
    'ts': {'mts', 'm2ts', 'tsv'},
    'mp3': {'mpga', 'mp2'},
    'aac': {'adts'},
    'ogg': {'oga', 'ogv', 'opus'},
    'opus': {'ogg', 'oga'},
    'midi': {'midi', 'kar', 'rmi'},
    'aiff': {'aif', 'aifc'},
    'doc': _ole,
    'xls': _ole,
    'ppt': _ole,
    'msg': _ole,
    'ole': _ole,
    'docx': {'docm', 'dotx', 'dotm'},
    'xlsx': {'xlsm', 'xltx', 'xltm'},
    'pptx': {'pptm', 'ppsx', 'potx'},
    'apk': {'apks', 'xapk', 'apkm'},
    'gzip': {'tgz', 'gzip'},
    'sqlite': {'sqlite', 'sqlite3', 'db3', 'sqlitedb'},
    'vcf': {'vcard'},
    'ics': {'ical', 'ifb'},
  };
}

/// A plain magic-number signature that maps straight to a [FileType].
///
/// Container formats (ISO-BMFF, RIFF, EBML, ZIP, OLE, Ogg, TIFF) need more
/// than a prefix to tell their sub-types apart; the detector handles those in
/// code. Everything else is a [FileSignature] in `SignatureDatabase`.
class FileSignature {
  const FileSignature({
    required this.type,
    required this.pattern,
    this.offset = 0,
  });

  final FileType type;

  /// Magic bytes. `null` entries are wildcards.
  final List<int?> pattern;

  /// Byte offset where [pattern] starts.
  final int offset;

  /// Number of fixed (non-wildcard) bytes; longer patterns win ties.
  int get strength => pattern.where((b) => b != null).length;

  /// Bytes a reader needs to test this signature.
  int get headerBytes => offset + pattern.length;

  /// Tests [header] against [pattern] starting at [offset].
  bool matchesHeader(List<int> header) {
    if (header.length < offset + pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      final expected = pattern[i];
      if (expected == null) continue;
      if (header[offset + i] != expected) return false;
    }
    return true;
  }
}
