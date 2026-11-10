import '../../domain/file_item.dart';

enum ScanPhase { indexing, analyzing, done }

/// What to scan.
class ScanOptions {
  const ScanOptions({required this.roots, this.deep = false, this.exclude = const []});

  /// Folders to walk (storage volumes).
  final List<String> roots;

  /// Deep scan: also carve unknown files, app databases and data appended
  /// after images. Slower.
  final bool deep;

  /// Folders to skip (e.g. RecoverX's own export folder).
  final List<String> exclude;

  Map<String, Object> toMap() => {'roots': roots, 'deep': deep, 'exclude': exclude};

  factory ScanOptions.fromMap(Map<Object?, Object?> m) => ScanOptions(
        roots: (m['roots'] as List).cast<String>(),
        deep: m['deep'] as bool,
        exclude: (m['exclude'] as List).cast<String>(),
      );
}

/// Real-time scan progress emitted by `ScannerService`.
class ScanProgress {
  const ScanProgress({
    required this.phase,
    required this.scannedCount,
    required this.totalCount,
    required this.foundCount,
    required this.currentPath,
    this.elapsed = Duration.zero,
    this.isPaused = false,
    this.isCancelled = false,
  });

  static const idle = ScanProgress(
    phase: ScanPhase.indexing,
    scannedCount: 0,
    totalCount: 0,
    foundCount: 0,
    currentPath: '',
  );

  final ScanPhase phase;

  /// Files analyzed so far (indexing: files listed so far).
  final int scannedCount;

  /// Files to analyze; known once indexing finishes.
  final int totalCount;
  final int foundCount;
  final String currentPath;
  final Duration elapsed;
  final bool isPaused;
  final bool isCancelled;

  bool get isDone => phase == ScanPhase.done;

  /// 0..1 during analysis; null while indexing (unknown total).
  double? get percentage {
    if (phase == ScanPhase.done) return 1;
    if (phase == ScanPhase.indexing || totalCount == 0) return null;
    return (scannedCount / totalCount).clamp(0.0, 1.0);
  }

  ScanProgress copyWith({
    ScanPhase? phase,
    int? scannedCount,
    int? totalCount,
    int? foundCount,
    String? currentPath,
    Duration? elapsed,
    bool? isPaused,
    bool? isCancelled,
  }) =>
      ScanProgress(
        phase: phase ?? this.phase,
        scannedCount: scannedCount ?? this.scannedCount,
        totalCount: totalCount ?? this.totalCount,
        foundCount: foundCount ?? this.foundCount,
        currentPath: currentPath ?? this.currentPath,
        elapsed: elapsed ?? this.elapsed,
        isPaused: isPaused ?? this.isPaused,
        isCancelled: isCancelled ?? this.isCancelled,
      );
}

/// One message from the scanner: progress plus any newly found items.
class ScanUpdate {
  const ScanUpdate(this.progress, [this.items = const []]);

  final ScanProgress progress;
  final List<FileItem> items;
}
