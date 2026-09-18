import 'dart:io';

import 'file_signature.dart';

/// How a file was discovered during a scan.
enum DiscoveryReason {
  /// Extension matches the detected type — a normal visible file.
  normal,

  /// File extension differs from the detected type or is missing entirely.
  renamed,

  /// File is hidden (starts with `.` or is listed in a `.nomedia` context).
  hidden,

  /// Located in a system / cache directory not normally browsed.
  system,
}

/// Confidence of the signature match.
enum MatchConfidence { high, medium, low }

/// A recoverable file detected by the scanner.
class FileItem {
  FileItem({
    required this.id,
    required this.path,
    required this.size,
    required this.detectedExtension,
    required this.detectedMimeType,
    required this.category,
    required this.displayName,
    required this.discoveryReason,
    required this.matchConfidence,
    this.lastModified,
    this.isRecovered = false,
  });

  /// Unique id (uuid v4).
  final String id;

  /// Absolute path on device.
  final String path;

  /// File size in bytes.
  final int size;

  /// Detected extension (without dot) based on magic numbers.
  final String detectedExtension;

  /// Detected mime type based on magic numbers.
  final String detectedMimeType;

  /// Category derived from the detected signature.
  final FileCategory category;

  /// Display name of the matched signature (e.g. 'PNG Image').
  final String displayName;

  /// Why the scanner flagged this file.
  final DiscoveryReason discoveryReason;

  /// How confident the signature match is.
  final MatchConfidence matchConfidence;

  /// Filesystem last-modified stamp (nullable on some paths).
  final DateTime? lastModified;

  /// Whether the user has already recovered this file.
  bool isRecovered;

  /// Original file name on disk.
  String get fileName => path.split(Platform.pathSeparator).last;

  /// Whether the on-disk extension differs from the detected one.
  bool get hasWrongExtension {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return detectedExtension.isNotEmpty;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return ext != detectedExtension.toLowerCase();
  }

  /// Suggested recovery name with the correct extension.
  String get suggestedName {
    final dot = fileName.lastIndexOf('.');
    final base = dot == -1 ? fileName : fileName.substring(0, dot);
    return '$base.$detectedExtension';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'path': path,
        'size': size,
        'detectedExtension': detectedExtension,
        'detectedMimeType': detectedMimeType,
        'category': category.name,
        'displayName': displayName,
        'discoveryReason': discoveryReason.name,
        'matchConfidence': matchConfidence.name,
        'lastModified': lastModified?.millisecondsSinceEpoch,
        'isRecovered': isRecovered ? 1 : 0,
      };

  factory FileItem.fromMap(Map<String, dynamic> m) => FileItem(
        id: m['id'] as String,
        path: m['path'] as String,
        size: m['size'] as int,
        detectedExtension: m['detectedExtension'] as String,
        detectedMimeType: m['detectedMimeType'] as String,
        category: FileCategory.values.byName(m['category'] as String),
        displayName: m['displayName'] as String,
        discoveryReason:
            DiscoveryReason.values.byName(m['discoveryReason'] as String),
        matchConfidence:
            MatchConfidence.values.byName(m['matchConfidence'] as String),
        lastModified: m['lastModified'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['lastModified'] as int),
        isRecovered: (m['isRecovered'] as int) == 1,
      );
}