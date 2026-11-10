import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sensitive/nsfw_model.dart';
import '../../core/sensitive/sensitive_checker.dart';
import '../../domain/sensitive_rating.dart';
import '../scan/scan_view_model.dart';
import '../settings/settings_controller.dart';

class SensitiveCheckState {
  const SensitiveCheckState({
    this.running = false,
    this.paused = false,
    this.finished = false,
    this.cancelled = false,
    this.total = 0,
    this.checked = 0,
    this.flagged = 0,
    this.skipped = 0,
    this.error,
  });

  final bool running;
  final bool paused;

  /// A run has ended (complete or stopped) and its summary is showing.
  final bool finished;
  final bool cancelled;
  final int total;
  final int checked;
  final int flagged;

  /// Could not be decoded (corrupt, unsupported codec).
  final int skipped;
  final String? error;

  double? get fraction => total == 0 ? null : checked / total;

  SensitiveCheckState copyWith({
    bool? running,
    bool? paused,
    bool? finished,
    bool? cancelled,
    int? total,
    int? checked,
    int? flagged,
    int? skipped,
  }) =>
      SensitiveCheckState(
        running: running ?? this.running,
        paused: paused ?? this.paused,
        finished: finished ?? this.finished,
        cancelled: cancelled ?? this.cancelled,
        total: total ?? this.total,
        checked: checked ?? this.checked,
        flagged: flagged ?? this.flagged,
        skipped: skipped ?? this.skipped,
      );
}

final sensitiveCheckProvider = StateNotifierProvider<SensitiveCheckController, SensitiveCheckState>((ref) {
  final controller = SensitiveCheckController(ref);
  // A new scan or cleared results replace the item list: stop checking the old one.
  ref.listen(scanControllerProvider.select((s) => s.items), (_, __) => controller.cancel());
  return controller;
});

/// Items whose blur the user removed in this session.
final revealedProvider = StateProvider<Set<String>>((_) => const {});

/// Runs the on-device sensitive-content check over the scan results that
/// have not been checked yet. Read-only: photos and video frames are decoded
/// in memory. Results are saved in the scan cache in batches.
class SensitiveCheckController extends StateNotifier<SensitiveCheckState> {
  SensitiveCheckController(this._ref) : super(const SensitiveCheckState());

  final Ref _ref;
  bool _cancel = false;
  Completer<void>? _resume;

  /// Items still to check in the current results.
  int pendingCount() =>
      _ref.read(scanControllerProvider).items.where((i) => i.sensitive == null && SensitiveChecker.eligible(i)).length;

  Future<void> start() async {
    final scan = _ref.read(scanControllerProvider);
    if (state.running || scan.isScanning) return;
    final todo = scan.items.where((i) => i.sensitive == null && SensitiveChecker.eligible(i)).toList();
    _cancel = false;
    _resume = null;
    if (todo.isEmpty) {
      state = const SensitiveCheckState(finished: true);
      return;
    }
    state = SensitiveCheckState(running: true, total: todo.length);

    final NsfwModel model;
    try {
      model = await NsfwModel.load();
    } catch (e) {
      if (mounted) state = SensitiveCheckState(finished: true, error: 'Could not load the model: $e');
      return;
    }

    final checker = SensitiveChecker(
      classify: model.classify,
      imagePixels: decodeImagePixels,
      videoFrames: (item) => sampleVideoFrames(item, count: _ref.read(settingsProvider).videoFrames),
    );
    final pending = <String, SensitiveRating>{};
    final sinceFlush = Stopwatch()..start();
    void flush() {
      if (pending.isEmpty) return;
      // Results belong to this item list; a new scan replaced it.
      if (!identical(_ref.read(scanControllerProvider).items, scan.items)) {
        pending.clear();
        return;
      }
      _ref.read(scanControllerProvider.notifier).applySensitive(Map.of(pending));
      pending.clear();
      sinceFlush.reset();
    }

    var flagged = 0, skipped = 0, checked = 0;
    try {
      for (final item in todo) {
        if (_cancel || !mounted) break;
        if (_resume != null) await _resume!.future;
        if (_cancel || !mounted) break;
        SensitiveRating? r;
        try {
          r = await checker.rate(item);
        } catch (_) {
          r = null;
        }
        checked++;
        if (r == null) {
          skipped++;
        } else {
          pending[item.id] = r;
          if (r.flagged) flagged++;
        }
        if (pending.length >= 25 || sinceFlush.elapsed > const Duration(seconds: 2)) flush();
        if (mounted) state = state.copyWith(checked: checked, flagged: flagged, skipped: skipped);
      }
    } finally {
      if (mounted) flush();
      await model.close();
    }
    if (mounted) {
      state = state.copyWith(running: false, paused: false, finished: true, cancelled: _cancel);
    }
  }

  void pause() {
    if (!state.running || state.paused) return;
    _resume = Completer<void>();
    state = state.copyWith(paused: true);
  }

  void resume() {
    final r = _resume;
    _resume = null;
    r?.complete();
    if (state.running) state = state.copyWith(paused: false);
  }

  void cancel() {
    if (!state.running) return;
    _cancel = true;
    resume();
  }

  /// Hides the summary card.
  void dismiss() {
    if (!state.running) state = const SensitiveCheckState();
  }
}
