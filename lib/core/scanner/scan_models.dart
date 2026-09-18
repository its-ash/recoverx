/// Real-time scan progress emitted by [ScannerService].
class ScanProgress {
  const ScanProgress({
    required this.scannedCount,
    required this.foundCount,
    required this.currentPath,
    required this.percentage,
    this.isPaused = false,
    this.isCancelled = false,
  });

  final int scannedCount;
  final int foundCount;
  final String currentPath;
  final double percentage; // 0..1
  final bool isPaused;
  final bool isCancelled;

  ScanProgress copyWith({
    int? scannedCount,
    int? foundCount,
    String? currentPath,
    double? percentage,
    bool? isPaused,
    bool? isCancelled,
  }) =>
      ScanProgress(
        scannedCount: scannedCount ?? this.scannedCount,
        foundCount: foundCount ?? this.foundCount,
        currentPath: currentPath ?? this.currentPath,
        percentage: percentage ?? this.percentage,
        isPaused: isPaused ?? this.isPaused,
        isCancelled: isCancelled ?? this.isCancelled,
      );
}