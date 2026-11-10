import 'file_metadata.dart';
import 'file_signature.dart';
import 'sensitive_rating.dart';
import 'signature_database.dart';

/// Why the scanner flagged a file. A file can have several reasons.
enum DiscoveryReason {
  /// Extension is missing or does not match the real (signature) type.
  renamed,

  /// The file, or a folder above it, starts with `.` or sits under `.nomedia`.
  hidden,

  /// In a trash / recycle bin: Android 11+ `.trashed-*` files, gallery and
  /// file-manager recycle bins.
  trashed,

  /// In an app cache or thumbnail cache.
  cache,

  /// Not a file on disk: carved out of a larger file (thumbnail databases,
  /// caches, unknown blobs) by scanning its bytes for embedded signatures.
  carved,
}

/// Confidence of the type detection.
enum MatchConfidence {
  /// Signature plus structural checks agree.
  high,

  /// Signature matched; structure only partly checked.
  medium,

  /// Weak signature (short magic / frame sync heuristics).
  low,
}

/// A recoverable file detected by the scanner.
class FileItem {
  FileItem({
    required this.path,
    required this.size,
    required this.type,
    required this.matchConfidence,
    this.reasons = const {},
    this.lastModified,
    this.originalName,
    this.sourceOffset,
    this.sourceApp,
    this.metadata,
    this.integrity = Integrity.unknown,
    this.isRecovered = false,
    this.sensitive,
  });

  /// Absolute path of the file on the device. For carved items, the path of
  /// the container they were carved from.
  final String path;

  /// Size in bytes (for carved items: the carved length).
  final int size;

  /// Real type detected from the bytes.
  final FileType type;

  final MatchConfidence matchConfidence;

  /// Why the file was flagged. Empty = a normal, visible, correctly named file.
  final Set<DiscoveryReason> reasons;

  /// Filesystem last-modified time of [path].
  final DateTime? lastModified;

  /// Name before it was trashed (Android `.trashed-<expiry>-<name>`).
  final String? originalName;

  /// Byte offset inside [path] for carved items; null for whole files.
  final int? sourceOffset;

  /// App or folder the file belongs to (WhatsApp, Camera, Screenshots...).
  final String? sourceApp;

  final FileMetadata? metadata;
  final Integrity integrity;

  bool isRecovered;

  /// Result of the sensitive-content check; null until checked.
  SensitiveRating? sensitive;

  /// Unique id: the path, plus the offset for carved items.
  String get id => sourceOffset == null ? path : '$path#$sourceOffset';

  bool get isCarved => sourceOffset != null;

  FileCategory get category => type.category;
  String get detectedExtension => type.extension;
  String get detectedMimeType => type.mimeType;
  String get displayName => type.displayName;

  /// Name on disk.
  String get fileName => path.substring(path.lastIndexOf('/') + 1);

  /// True when the name on disk does not end with the detected extension.
  bool get hasWrongExtension => reasons.contains(DiscoveryReason.renamed);

  /// Name to use when recovering: original (pre-trash) name, leading dots
  /// removed so the copy is visible, and the correct extension.
  String get suggestedName {
    var name = originalName ?? fileName;
    if (isCarved) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      name = '${base}_at_0x${sourceOffset!.toRadixString(16)}';
    }
    name = name.replaceFirst(RegExp(r'^\.+'), '');
    if (name.isEmpty) name = 'recovered';
    final dot = name.lastIndexOf('.');
    if (dot > 0 && type.acceptsExtension(name.substring(dot + 1))) return name;
    // Keep the old suffix if it is not a real extension (e.g. "IMG.1"),
    // replace it if it looks like one.
    final base = dot > 0 && name.length - dot <= 5 && !isCarved ? name.substring(0, dot) : name;
    return '$base.$detectedExtension';
  }

  FileItem copyWith({bool? isRecovered}) => FileItem(
        path: path,
        size: size,
        type: type,
        matchConfidence: matchConfidence,
        reasons: reasons,
        lastModified: lastModified,
        originalName: originalName,
        sourceOffset: sourceOffset,
        sourceApp: sourceApp,
        metadata: metadata,
        integrity: integrity,
        isRecovered: isRecovered ?? this.isRecovered,
        sensitive: sensitive,
      );

  /// Plain map used to pass items between isolates and into reports.
  Map<String, Object?> toMap() => {
        'path': path,
        'size': size,
        'type': type.id,
        'confidence': matchConfidence.name,
        'reasons': reasons.map((r) => r.name).join(','),
        'lastModified': lastModified?.millisecondsSinceEpoch,
        'originalName': originalName,
        'sourceOffset': sourceOffset,
        'sourceApp': sourceApp,
        'metadata': metadata?.encode(),
        'integrity': integrity.name,
        'isRecovered': isRecovered,
        'sensitive': sensitive?.encode(),
      };

  static FileItem? fromMap(Map<String, Object?> m) {
    final type = FileTypes.byId(m['type'] as String);
    if (type == null) return null;
    final lm = m['lastModified'] as int?;
    return FileItem(
      path: m['path'] as String,
      size: m['size'] as int,
      type: type,
      matchConfidence: MatchConfidence.values.byName(m['confidence'] as String),
      reasons: decodeReasons(m['reasons'] as String?),
      lastModified: lm == null ? null : DateTime.fromMillisecondsSinceEpoch(lm),
      originalName: m['originalName'] as String?,
      sourceOffset: m['sourceOffset'] as int?,
      sourceApp: m['sourceApp'] as String?,
      metadata: FileMetadata.decode(m['metadata'] as String?),
      integrity: Integrity.values.byName(m['integrity'] as String),
      isRecovered: m['isRecovered'] as bool? ?? false,
      sensitive: SensitiveRating.decode(m['sensitive'] as String?),
    );
  }

  static Set<DiscoveryReason> decodeReasons(String? s) {
    if (s == null || s.isEmpty) return const {};
    final out = <DiscoveryReason>{};
    for (final part in s.split(',')) {
      for (final r in DiscoveryReason.values) {
        if (r.name == part) out.add(r);
      }
    }
    return out;
  }
}
