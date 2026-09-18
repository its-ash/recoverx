import 'dart:async';
import 'dart:io';

import '../../domain/file_item.dart';
import '../../domain/signature_database.dart';
import 'scan_models.dart';
import 'signature_matcher.dart';

/// Coordinates a full directory walk + signature scan.
///
/// Scans **everything**: visible, hidden, dotfiles, system/cache dirs,
/// renamed/wrong-extension files, and uses binary signatures (magic numbers)
/// to identify the real type of every file — regardless of name or extension.
///
/// Designed to run inside a background isolate or WorkManager task. All
/// progress is emitted via a [Stream] so the UI can render live progress
/// without polling. Supports pause / resume / cancel through controllers.
class ScannerService {
  ScannerService({SignatureMatcher? matcher})
      : _matcher = matcher ?? SignatureMatcher();

  final SignatureMatcher _matcher;

  // Pause / cancel signals.
  final _pauseController = StreamController<void>.broadcast();

  bool _isPaused = false;
  bool _isCancelled = false;

  /// Starts a full scan of [roots]. Emits [ScanProgress] for every file
  /// processed and calls [onFound] for each recoverable file identified by
  /// its binary signature.
  ///
  /// All files are scanned: hidden, dotfiles, system dirs, wrong-extension
  /// files — everything. The signature matcher identifies the real type.
  Stream<ScanProgress> scan({
    required List<Directory> roots,
    required void Function(FileItem found) onFound,
  }) async* {
    _isPaused = false;
    _isCancelled = false;

    final maxHeader = SignatureDatabase.maxHeaderBytes;

    final queue = List<FileSystemEntity>.from(roots);
    var scanned = 0;
    var found = 0;
    var totalEstimate = _estimateTotal(roots);

    while (queue.isNotEmpty) {
      if (_isCancelled) {
        yield ScanProgress(
          scannedCount: scanned,
          foundCount: found,
          currentPath: '',
          percentage: scanned / (totalEstimate > 0 ? totalEstimate : 1),
          isCancelled: true,
        );
        return;
      }

      if (_isPaused) {
        await _pauseController.stream.first;
        _isPaused = false;
      }

      final entity = queue.removeAt(0);

      try {
        if (entity is Directory) {
          // Descend into every directory — including hidden dotdirs,
          // .nomedia dirs, system/cache dirs — scan everything.
          try {
            await for (final child in entity.list(followLinks: false)) {
              queue.add(child);
            }
          } catch (_) {
            // Permission denied — skip silently.
          }
          continue;
        }

        if (entity is File) {
          scanned++;
          final path = entity.path;
          final fileName = path.split(Platform.pathSeparator).last;

          final isHiddenFile = fileName.startsWith('.');

          // Read just the header bytes — never load whole files.
          FileItem? item;
          try {
            final raf = await entity.open();
            final header = raf.readSync(maxHeader);
            await raf.close();

            if (header.isNotEmpty) {
              // Always identify by signature — ignore the file's extension.
              final match = _matcher.identify(headerBytes: header);
              if (match != null) {
                final stat = await entity.stat();
                    DiscoveryReason reason;
                    if (isHiddenFile) {
                      reason = DiscoveryReason.hidden;
                    } else if (!_extensionMatches(
                        fileName, match.signature.extension)) {
                      reason = DiscoveryReason.renamed;
                    } else {
                      reason = DiscoveryReason.normal;
                    }

                    item = FileItem(
                      id: path,
                      path: path,
                      size: stat.size,
                      detectedExtension: match.signature.extension,
                      detectedMimeType: match.signature.mimeType,
                      category: match.signature.category,
                      displayName: match.signature.displayName,
                      discoveryReason: reason,
                      matchConfidence: match.confidence,
                      lastModified: stat.modified,
                    );
              }
            }
          } catch (_) {
            // Read error — skip.
          }

          if (item != null) {
            found++;
            onFound(item);
          }

          yield ScanProgress(
            scannedCount: scanned,
            foundCount: found,
            currentPath: path,
            percentage: scanned / (totalEstimate > 0 ? totalEstimate : 1),
          );
        }
      } catch (_) {
        // Defensive: never crash the whole scan on a single bad path.
      }
    }

    yield ScanProgress(
      scannedCount: scanned,
      foundCount: found,
      currentPath: '',
      percentage: 1.0,
    );
  }

  void pause() => _isPaused = true;
  void resume() => _pauseController.add(null);
  void cancel() => _isCancelled = true;

  void dispose() {
    _pauseController.close();
  }

  // ───────────────────────── helpers ─────────────────────────

  static bool _extensionMatches(String fileName, String detected) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return false;
    return fileName.substring(dot + 1).toLowerCase() == detected.toLowerCase();
  }

  static int _estimateTotal(List<Directory> roots) {
    var count = 0;
    for (final r in roots) {
      try {
        count += r.listSync(recursive: true, followLinks: false).length;
      } catch (_) {}
    }
    return count > 0 ? count : 1;
  }
}