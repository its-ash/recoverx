import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permission_handler.dart';
import '../../core/recovery/recovery_service.dart';
import '../../core/scanner/scan_models.dart';
import '../../core/scanner/scanner_service.dart';
import '../../data/scan_database.dart';
import '../../domain/file_item.dart';
import '../../domain/file_metadata.dart';
import '../../domain/file_signature.dart';
import '../../domain/sensitive_rating.dart';
import '../settings/settings_controller.dart';

final scanDatabaseProvider = Provider<ScanDatabase>((ref) {
  final db = ScanDatabase();
  ref.onDispose(db.close);
  return db;
});

final scannerServiceProvider = Provider<ScannerService>((ref) {
  final s = ScannerService();
  ref.onDispose(s.dispose);
  return s;
});

// ───────────────────────── Scan ─────────────────────────

class ScanState {
  const ScanState({
    this.progress,
    this.items = const [],
    this.revision = 0,
    this.deep = false,
    this.startedAt,
    this.error,
    this.fromHistory = false,
  });

  /// Null when no scan has run in this session.
  final ScanProgress? progress;

  /// All found items. Grows in place during a scan; [revision] changes on
  /// every append so listeners rebuild.
  final List<FileItem> items;
  final int revision;
  final bool deep;
  final DateTime? startedAt;
  final String? error;

  /// Items were loaded from the previous session's scan.
  final bool fromHistory;

  bool get isScanning => progress != null && !progress!.isDone;

  ScanState copyWith({
    ScanProgress? progress,
    List<FileItem>? items,
    int? revision,
    bool? deep,
    DateTime? startedAt,
    String? error,
    bool clearError = false,
    bool? fromHistory,
  }) =>
      ScanState(
        progress: progress ?? this.progress,
        items: items ?? this.items,
        revision: revision ?? this.revision,
        deep: deep ?? this.deep,
        startedAt: startedAt ?? this.startedAt,
        error: clearError ? null : (error ?? this.error),
        fromHistory: fromHistory ?? this.fromHistory,
      );
}

final scanControllerProvider = StateNotifierProvider<ScanController, ScanState>((ref) => ScanController(ref));

class ScanController extends StateNotifier<ScanState> {
  ScanController(this._ref) : super(const ScanState()) {
    _loadHistory();
  }

  final Ref _ref;
  StreamSubscription<ScanUpdate>? _sub;

  Future<void> _loadHistory() async {
    try {
      final items = await _ref.read(scanDatabaseProvider).getAllFiles();
      if (items.isNotEmpty && !state.isScanning && mounted) {
        state = state.copyWith(items: items, revision: state.revision + 1, fromHistory: true);
      }
    } catch (_) {}
  }

  /// Deep scan is a saved setting (Settings and the start card share it).
  void setDeep(bool v) {
    final settings = _ref.read(settingsProvider.notifier);
    settings.update(settings.state.copyWith(deepScan: v));
  }

  /// Rebuilds listeners after items changed in place (e.g. new content-check
  /// limits re-label ratings).
  void touch() => state = state.copyWith(revision: state.revision + 1);

  /// Forgets all content-check results (UI + DB).
  Future<void> clearSensitive() async {
    for (final item in state.items) {
      item.sensitive = null;
    }
    touch();
    try {
      await _ref.read(scanDatabaseProvider).clearSensitive();
    } catch (_) {}
  }

  Future<void> start() async {
    if (state.isScanning) return;
    final roots = PermissionService.scanRoots();
    if (roots.isEmpty) {
      state = state.copyWith(error: 'No readable storage found. Check the storage permission.');
      return;
    }
    _ref.read(selectionProvider.notifier).clear();
    final items = <FileItem>[];
    final deep = _ref.read(settingsProvider).deepScan;
    state = ScanState(
      progress: ScanProgress.idle,
      items: items,
      revision: state.revision + 1,
      deep: deep,
      startedAt: DateTime.now(),
    );

    final options = ScanOptions(
      roots: roots,
      deep: deep,
      exclude: [for (final r in roots) '$r/RecoverX'],
    );
    await _sub?.cancel();
    _sub = _ref.read(scannerServiceProvider).scan(options).listen(
      (u) {
        if (u.items.isNotEmpty) items.addAll(u.items);
        state = state.copyWith(
          progress: u.progress,
          revision: u.items.isEmpty ? state.revision : state.revision + 1,
        );
        if (u.progress.isDone) _persist(items);
      },
      onError: (Object e) {
        state = state.copyWith(error: '$e');
      },
    );
  }

  Future<void> _persist(List<FileItem> items) async {
    final db = _ref.read(scanDatabaseProvider);
    try {
      await db.clearAll();
      for (var i = 0; i < items.length; i += 2000) {
        await db.insertFiles(items.sublist(i, (i + 2000).clamp(0, items.length)));
      }
    } catch (_) {}
  }

  void pause() => _ref.read(scannerServiceProvider).pause();
  void resume() => _ref.read(scannerServiceProvider).resume();
  void cancel() => _ref.read(scannerServiceProvider).cancel();

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> clearResults() async {
    if (state.isScanning) return;
    _ref.read(selectionProvider.notifier).clear();
    state = ScanState(deep: state.deep, revision: state.revision + 1);
    try {
      await _ref.read(scanDatabaseProvider).clearAll();
    } catch (_) {}
  }

  /// Marks exported items as recovered (UI badge + DB).
  void markRecovered(Iterable<String> ids) {
    final set = ids.toSet();
    for (final item in state.items) {
      if (set.contains(item.id)) item.isRecovered = true;
    }
    state = state.copyWith(revision: state.revision + 1);
    _ref.read(scanDatabaseProvider).markRecovered(set).ignore();
  }

  /// Stores sensitive-content results on the items (UI + DB).
  void applySensitive(Map<String, SensitiveRating> ratings) {
    if (ratings.isEmpty) return;
    for (final item in state.items) {
      final r = ratings[item.id];
      if (r != null) item.sensitive = r;
    }
    state = state.copyWith(revision: state.revision + 1);
    _ref.read(scanDatabaseProvider).saveSensitive(ratings).ignore();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ───────────────────────── Filters ─────────────────────────

/// Quick views over the results.
enum ResultView { all, flagged, trashed, hidden, renamed, carved, cache, truncated, sensitive }

enum ResultSort { newest, oldest, largest, smallest, name, type }

class ResultFilter {
  const ResultFilter({
    this.view = ResultView.all,
    this.categories = const {},
    this.query = '',
    this.sort = ResultSort.newest,
  });

  final ResultView view;

  /// Empty = every category.
  final Set<FileCategory> categories;
  final String query;
  final ResultSort sort;

  ResultFilter copyWith({
    ResultView? view,
    Set<FileCategory>? categories,
    String? query,
    ResultSort? sort,
  }) =>
      ResultFilter(
        view: view ?? this.view,
        categories: categories ?? this.categories,
        query: query ?? this.query,
        sort: sort ?? this.sort,
      );

  bool matchesView(FileItem i) => switch (view) {
        ResultView.all => true,
        ResultView.flagged => i.reasons.isNotEmpty,
        ResultView.trashed => i.reasons.contains(DiscoveryReason.trashed),
        ResultView.hidden => i.reasons.contains(DiscoveryReason.hidden),
        ResultView.renamed => i.reasons.contains(DiscoveryReason.renamed),
        ResultView.carved => i.reasons.contains(DiscoveryReason.carved),
        ResultView.cache => i.reasons.contains(DiscoveryReason.cache),
        ResultView.truncated => i.integrity == Integrity.truncated,
        ResultView.sensitive => i.sensitive?.flagged ?? false,
      };
}

final resultFilterProvider = StateProvider<ResultFilter>((_) => const ResultFilter());

/// Items after view, category, search and sort.
final filteredItemsProvider = Provider<List<FileItem>>((ref) {
  final scan = ref.watch(scanControllerProvider);
  final f = ref.watch(resultFilterProvider);
  final q = f.query.trim().toLowerCase();
  final out = scan.items.where((i) {
    if (!f.matchesView(i)) return false;
    if (f.categories.isNotEmpty && !f.categories.contains(i.category)) return false;
    if (q.isEmpty) return true;
    return i.path.toLowerCase().contains(q) ||
        (i.originalName?.toLowerCase().contains(q) ?? false) ||
        (i.sourceApp?.toLowerCase().contains(q) ?? false) ||
        i.displayName.toLowerCase().contains(q);
  }).toList();

  int byDate(FileItem a, FileItem b) {
    final da = a.metadata?.takenAt ?? a.lastModified;
    final db = b.metadata?.takenAt ?? b.lastModified;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  }

  out.sort(switch (f.sort) {
    ResultSort.newest => byDate,
    ResultSort.oldest => (a, b) => byDate(b, a),
    ResultSort.largest => (a, b) => b.size.compareTo(a.size),
    ResultSort.smallest => (a, b) => a.size.compareTo(b.size),
    ResultSort.name => (a, b) => a.suggestedName.toLowerCase().compareTo(b.suggestedName.toLowerCase()),
    ResultSort.type => (a, b) => a.type.id.compareTo(b.type.id),
  });
  return out;
});

/// Counts for filter chips.
class ResultCounts {
  ResultCounts(List<FileItem> items) {
    for (final i in items) {
      byCategory[i.category] = (byCategory[i.category] ?? 0) + 1;
      for (final v in ResultView.values) {
        if (ResultFilter(view: v).matchesView(i)) {
          byView[v] = (byView[v] ?? 0) + 1;
        }
      }
    }
  }

  final byCategory = <FileCategory, int>{};
  final byView = <ResultView, int>{};
}

final resultCountsProvider = Provider<ResultCounts>((ref) => ResultCounts(ref.watch(scanControllerProvider).items));

// ───────────────────────── Selection ─────────────────────────

final selectionProvider = StateNotifierProvider<SelectionNotifier, Set<String>>((ref) => SelectionNotifier());

class SelectionNotifier extends StateNotifier<Set<String>> {
  SelectionNotifier() : super(const {});

  void toggle(String id) => state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};

  void selectAll(Iterable<FileItem> items) => state = {...state, ...items.map((i) => i.id)};

  void clear() => state = const {};
}

// ───────────────────────── Export ─────────────────────────

class ExportState {
  const ExportState({this.progress, this.result, this.error, this.running = false});

  final ExportProgress? progress;
  final ExportResult? result;
  final String? error;
  final bool running;
}

final exportControllerProvider = StateNotifierProvider<ExportController, ExportState>((ref) => ExportController(ref));

class ExportController extends StateNotifier<ExportState> {
  ExportController(this._ref) : super(const ExportState());

  final Ref _ref;

  List<FileItem> selectedItems() {
    final ids = _ref.read(selectionProvider);
    return _ref.read(scanControllerProvider).items.where((i) => ids.contains(i.id)).toList();
  }

  Future<void> export(String volumeRoot) async {
    final items = selectedItems();
    if (items.isEmpty || state.running) return;
    state = const ExportState(running: true);

    CaseInfo info;
    try {
      final d = await DeviceInfoPlugin().androidInfo;
      info = CaseInfo(
        deviceMaker: d.manufacturer,
        deviceModel: d.model,
        androidVersion: '${d.version.release} (SDK ${d.version.sdkInt})',
        scanStarted: _ref.read(scanControllerProvider).startedAt,
      );
    } catch (_) {
      info = CaseInfo(scanStarted: _ref.read(scanControllerProvider).startedAt);
    }

    try {
      await for (final e in RecoveryService.export(items: items, volumeRoot: volumeRoot, caseInfo: info)) {
        if (!mounted) return;
        if (e is ExportProgress) {
          state = ExportState(running: true, progress: e);
        } else if (e is ExportResult) {
          state = ExportState(result: e, progress: state.progress);
          _ref.read(scanControllerProvider.notifier).markRecovered(e.records.where((r) => r.ok).map((r) => r.item.id));
        }
      }
    } catch (e) {
      if (mounted) state = ExportState(error: '$e');
    }
  }

  void reset() => state = const ExportState();
}
