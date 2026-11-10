import 'dart:io';

import '../../domain/file_item.dart';
import '../../domain/file_metadata.dart';
import '../../domain/file_signature.dart';
import '../scanner/location_classifier.dart';
import 'byte_source.dart';
import 'carver.dart';
import 'file_type_detector.dart';
import 'metadata_extractor.dart';

/// Turns one path on disk into zero or more [FileItem]s: the file itself (if
/// its bytes match a known type) plus anything carved out of it.
class FileAnalyzer {
  const FileAnalyzer({
    this.detector = const FileTypeDetector(),
    this.extractor = const MetadataExtractor(),
    this.integrity = const IntegrityChecker(),
    this.classifier = const LocationClassifier(),
    this.carver = const Carver(),
  });

  final FileTypeDetector detector;
  final MetadataExtractor extractor;
  final IntegrityChecker integrity;
  final LocationClassifier classifier;
  final Carver carver;

  /// Smallest unknown file worth carving in deep mode.
  static const minCarveSize = 4 * 1024;

  List<FileItem> analyze(
    String path, {
    bool underNoMedia = false,
    bool deep = false,
    bool Function()? isCancelled,
  }) {
    final FileByteSource src;
    try {
      src = FileByteSource.open(path);
    } catch (_) {
      return const [];
    }
    try {
      if (src.length < 16) return const [];
      DateTime? modified;
      try {
        modified = File(path).lastModifiedSync();
      } catch (_) {}
      return analyzeSource(src,
          path: path,
          modified: modified,
          underNoMedia: underNoMedia,
          deep: deep,
          isCancelled: isCancelled);
    } finally {
      src.close();
    }
  }

  /// Same as [analyze] for an already-open source (used by tests).
  List<FileItem> analyzeSource(
    ByteSource src, {
    required String path,
    DateTime? modified,
    bool underNoMedia = false,
    bool deep = false,
    bool Function()? isCancelled,
  }) {
    final out = <FileItem>[];
    final det = detector.detect(src);
    LocationInfo? loc;

    if (det != null) {
      loc = classifier.classify(
          path: path, type: det.type, underNoMedia: underNoMedia);
      out.add(FileItem(
        path: path,
        size: src.length,
        type: det.type,
        matchConfidence: det.confidence,
        reasons: loc.reasons,
        lastModified: modified,
        originalName: loc.originalName,
        sourceApp: loc.sourceApp,
        metadata: _withNotes(extractor.extract(src, det.type), loc.notes),
        integrity: integrity.check(src, det.type),
      ));
    }

    final carveFrom = _carveStart(src, det?.type, path, deep);
    if (carveFrom != null) {
      final regions = carver.carve(src,
          from: carveFrom.$1, skipStart: carveFrom.$2, isCancelled: isCancelled);
      if (regions.isNotEmpty) {
        // Classify the container's location once; carved files inherit it.
        final where = classifier.classify(
            path: path, type: regions.first.type, underNoMedia: underNoMedia);
        final inherited = where.reasons
            .where((r) => r != DiscoveryReason.renamed)
            .toSet();
        for (final r in regions) {
          final slice = src.slice(r.offset, r.length);
          out.add(FileItem(
            path: path,
            size: r.length,
            type: r.type,
            matchConfidence: MatchConfidence.high,
            reasons: {...inherited, DiscoveryReason.carved},
            lastModified: modified,
            sourceOffset: r.offset,
            sourceApp: where.sourceApp,
            metadata: extractor.extract(slice, r.type),
            integrity: Integrity.intact,
          ));
        }
      }
    }
    return out;
  }

  /// Where to start carving inside this file, and whether to skip a header
  /// at that exact offset. Null = do not carve.
  (int, bool)? _carveStart(ByteSource s, FileType? type, String path, bool deep) {
    final name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
    final thumbCache = name.startsWith('.thumbdata') ||
        name.startsWith('thumbdata') ||
        name.startsWith('imgcache') ||
        path.toLowerCase().contains('/.thumbnails/');

    if (type == null) {
      if (thumbCache) return (0, false);
      if (deep && s.length >= minCarveSize) return (0, false);
      return null;
    }
    if (!deep) return null;
    switch (type.id) {
      case 'sqlite':
        // Image blobs stored in app databases (chat thumbnails, contacts).
        return (0, true);
      case 'jpeg':
        // Data appended after the image's end marker: motion-photo videos,
        // or files deliberately hidden behind a picture.
        final end = carver.jpegLength(s, 0);
        if (end != null && s.length - end >= 64) return (end, false);
        return null;
      default:
        return null;
    }
  }

  static FileMetadata? _withNotes(FileMetadata? m, Map<String, String> notes) {
    if (notes.isEmpty) return m;
    final base = m ?? const FileMetadata();
    return base.copyWith(extra: {...base.extra, ...notes});
  }
}
