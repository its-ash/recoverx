/// Supported file categories.
enum FileCategory {
  image,
  video,
  audio,
  document,
  archive,
  other,
}

/// A single file-signature definition (magic number).
///
/// [offset] is the byte offset from the start of the file where [pattern]
/// begins. [footer] is an optional trailing signature verified against the
/// end of the file for extra confidence.
class FileSignature {
  const FileSignature({
    required this.id,
    required this.category,
    required this.extension,
    required this.mimeType,
    required this.displayName,
    required this.pattern,
    this.offset = 0,
    this.footer,
    this.maxHeaderBytes = 64,
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

  /// Magic number bytes. Wildcard bytes inside the pattern are represented by
  /// `null` — they match any value at that position (used for versioned
  /// headers like AVI / MKV).
  final List<int?> pattern;

  /// Byte offset where [pattern] starts.
  final int offset;

  /// Optional trailing signature verified against the end of the file.
  final List<int>? footer;

  /// Maximum header bytes a scanner needs to read for this signature.
  final int maxHeaderBytes;

  /// Tests [header] against [pattern] starting at [offset].
  bool matchesHeader(List<int> header) {
    if (header.length < offset + pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      final expected = pattern[i];
      if (expected == null) continue; // wildcard
      if (header[offset + i] != expected) return false;
    }
    return true;
  }

  /// Verifies the footer if one is defined. Returns `true` when no footer is
  /// set or when the footer matches the last bytes of [fileBytes].
  bool matchesFooter(List<int> fileBytes) {
    if (footer == null || footer!.isEmpty) return true;
    if (fileBytes.length < footer!.length) return false;
    final start = fileBytes.length - footer!.length;
    for (var i = 0; i < footer!.length; i++) {
      if (fileBytes[start + i] != footer![i]) return false;
    }
    return true;
  }
}