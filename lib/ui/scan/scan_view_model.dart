import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permission_handler.dart';
import '../../core/recovery/recovery_service.dart';
import '../../core/scanner/scan_models.dart';
import '../../core/scanner/scanner_service.dart';
import '../../data/scan_database.dart';
import '../../domain/file_item.dart';

final scanDatabaseProvider = Provider<ScanDatabase>(
  (ref) => ScanDatabase(),
);

final scannerServiceProvider = Provider<ScannerService>(
  (ref) {
    final s = ScannerService();
    ref.onDispose(s.dispose);
    return s;
  },
);

/// Current live progress stream (null = idle, not scanning).
final scanProgressProvider =
    StateNotifierProvider<ScanProgressNotifier, ScanProgress?>(
        (ref) => ScanProgressNotifier(ref));

/// Live list of found files during/after a scan.
final foundFilesProvider =
    StateNotifierProvider<FoundFilesNotifier, List<FileItem>>(
        (ref) => FoundFilesNotifier());

/// Selected file ids for export.
final selectedIdsProvider = StateNotifierProvider<SelectedIdsNotifier, Set<String>>(
    (ref) => SelectedIdsNotifier());

/// Last export path (shown to user after export).
final exportPathProvider = StateProvider<String?>((ref) => null);

class SelectedIdsNotifier extends StateNotifier<Set<String>> {
  SelectedIdsNotifier() : super({});
  void toggle(String id) =>
      state = state.contains(id) ? (state..remove(id)) : ({...state, id});
  void clear() => state = {};
  void selectAll(List<FileItem> items) => state = items.map((i) => i.id).toSet();
}

class FoundFilesNotifier extends StateNotifier<List<FileItem>> {
  FoundFilesNotifier() : super([]);
  void add(FileItem item) => state = [...state, item];
  void clear() => state = [];
}

class ScanProgressNotifier extends StateNotifier<ScanProgress?> {
  ScanProgressNotifier(this._ref) : super(null);

  final Ref _ref;
  StreamSubscription<ScanProgress>? _sub;

  bool get isScanning => state != null && !state!.isCancelled;

  Future<void> startScan() async {
    state = const ScanProgress(
        scannedCount: 0, foundCount: 0, currentPath: '', percentage: 0);
    _ref.read(foundFilesProvider.notifier).clear();
    _ref.read(selectedIdsProvider.notifier).clear();

    // Clear temp from any previous run.
    await RecoveryService.clearTemp();

    List<Directory> roots;
    try {
      roots = await PermissionService.accessibleRoots();
    } catch (_) {
      roots = [];
    }
    if (roots.isEmpty) {
      state = const ScanProgress(
        scannedCount: 0,
        foundCount: 0,
        currentPath: '',
        percentage: 1.0,
      );
      return;
    }
    final service = _ref.read(scannerServiceProvider);
    final db = _ref.read(scanDatabaseProvider);
    final foundNotifier = _ref.read(foundFilesProvider.notifier);

    _sub = service
        .scan(
          roots: roots,
          onFound: (item) async {
            foundNotifier.add(item);
            db.insertFile(item);
            // Immediately copy to temp folder, categorized.
            RecoveryService.copyToTemp(item);
          },
        )
        .listen((p) => state = p, onDone: () => state = state?.copyWith());
  }

  void pause() => _ref.read(scannerServiceProvider).pause();
  void resume() => _ref.read(scannerServiceProvider).resume();
  void cancel() {
    _ref.read(scannerServiceProvider).cancel();
    _sub?.cancel();
  }

  /// Exports selected files from temp to date-stamped folder.
  /// Sets [exportPathProvider] with the result path.
  Future<void> exportSelected() async {
    final selected = _ref.read(selectedIdsProvider);
    final allFound = _ref.read(foundFilesProvider);
    final items = allFound.where((i) => selected.contains(i.id)).toList();
    if (items.isEmpty) return;
    final path = await RecoveryService.exportSelected(items);
    _ref.read(exportPathProvider.notifier).state = path;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}