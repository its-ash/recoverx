import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../domain/file_item.dart';
import '../analysis/file_analyzer.dart';
import 'scan_models.dart';

/// Runs a full scan in a background isolate so the UI never blocks.
///
/// Two phases:
///  1. **Indexing**: walks every folder under the roots (hidden folders,
///     `.nomedia` folders, trash and cache folders included) without
///     following symlinks.
///  2. **Analyzing**: reads each file's bytes to find its real type,
///     metadata and integrity, and carves embedded files out of caches.
///
/// The scanner only reads. It never writes to the device, so it cannot
/// overwrite deleted data.
class ScannerService {
  Isolate? _isolate;
  SendPort? _control;
  ReceivePort? _port;
  StreamController<ScanUpdate>? _out;

  bool get isRunning => _out != null;

  Stream<ScanUpdate> scan(ScanOptions options) {
    _dispose();
    final out = StreamController<ScanUpdate>();
    final port = ReceivePort();
    _out = out;
    _port = port;
    var last = ScanProgress.idle;
    var finished = false;

    void finish({bool cancelled = false}) {
      if (finished) return;
      finished = true;
      last = last.copyWith(
          phase: ScanPhase.done, isPaused: false, isCancelled: cancelled);
      out.add(ScanUpdate(last));
      out.close();
      _dispose();
    }

    port.listen((msg) {
      if (msg is SendPort) {
        _control = msg;
        return;
      }
      if (msg == null) {
        // Isolate exited without a "done" message (crash or kill).
        finish(cancelled: true);
        return;
      }
      if (msg is List) {
        // Uncaught error from the isolate: [error, stack].
        out.addError(StateError('Scanner failed: ${msg.first}'));
        finish(cancelled: true);
        return;
      }
      final m = msg as Map;
      switch (m['t']) {
        case 'p':
          last = ScanProgress(
            phase: ScanPhase.values[m['ph'] as int],
            scannedCount: m['s'] as int,
            totalCount: m['n'] as int,
            foundCount: m['f'] as int,
            currentPath: m['c'] as String,
            elapsed: Duration(milliseconds: m['e'] as int),
            isPaused: m['z'] as bool,
          );
          out.add(ScanUpdate(last));
        case 'i':
          final items = <FileItem>[];
          for (final raw in m['items'] as List) {
            final item = FileItem.fromMap((raw as Map).cast<String, Object?>());
            if (item != null) items.add(item);
          }
          out.add(ScanUpdate(last, items));
        case 'd':
          finish(cancelled: m['c'] as bool);
      }
    });

    Isolate.spawn(
      _scanEntry,
      [port.sendPort, options.toMap()],
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'recoverx-scan',
    ).then((iso) {
      if (finished) {
        iso.kill(priority: Isolate.immediate);
      } else {
        _isolate = iso;
      }
    }, onError: (Object e) {
      out.addError(e);
      finish(cancelled: true);
    });

    return out.stream;
  }

  void pause() => _control?.send('pause');
  void resume() => _control?.send('resume');

  /// Asks the isolate to stop; it sends a final "done (cancelled)" update.
  void cancel() {
    final c = _control;
    if (c == null) {
      _isolate?.kill(priority: Isolate.immediate);
      return;
    }
    c.send('cancel');
    // Long carving of one huge file cannot be interrupted cooperatively;
    // kill the isolate if it has not stopped shortly.
    final iso = _isolate;
    Timer(const Duration(seconds: 3), () {
      if (identical(_isolate, iso) && iso != null) {
        iso.kill(priority: Isolate.immediate);
      }
    });
  }

  void _dispose() {
    _isolate = null;
    _control = null;
    _port?.close();
    _port = null;
    _out = null;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _dispose();
  }
}

// ───────────────────────── Isolate side ─────────────────────────

@pragma('vm:entry-point')
Future<void> _scanEntry(List<Object?> args) async {
  final main = args[0] as SendPort;
  final options = ScanOptions.fromMap(args[1] as Map);
  final control = ReceivePort();
  main.send(control.sendPort);

  var paused = false;
  var cancelled = false;
  control.listen((m) {
    switch (m) {
      case 'pause':
        paused = true;
      case 'resume':
        paused = false;
      case 'cancel':
        cancelled = true;
        paused = false;
    }
  });

  final clock = Stopwatch()..start();
  var lastProgress = -1000;
  var phase = ScanPhase.indexing;
  var scanned = 0, total = 0, found = 0;
  var current = '';

  void progress({bool force = false}) {
    final now = clock.elapsedMilliseconds;
    if (!force && now - lastProgress < 120) return;
    lastProgress = now;
    main.send({
      't': 'p',
      'ph': phase.index,
      's': scanned,
      'n': total,
      'f': found,
      'c': current,
      'e': now,
      'z': paused,
    });
  }

  /// Lets control messages in and blocks while paused.
  Future<void> breathe() async {
    await Future<void>.delayed(Duration.zero);
    if (paused) progress(force: true);
    while (paused && !cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!paused) progress();
  }

  // ── Phase 1: index ──
  final files = <String>[];
  final noMedia = <bool>[];
  final exclude = options.exclude.map(_strip).toSet();
  final roots = _dedupeRoots(options.roots);
  final stack = <(String, bool)>[for (final r in roots.reversed) (r, false)];
  var dirs = 0;

  while (stack.isNotEmpty && !cancelled) {
    final (dir, inherited) = stack.removeLast();
    if (exclude.contains(_strip(dir))) continue;
    List<FileSystemEntity> children;
    try {
      children = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue; // No permission (e.g. Android/data on 11+): skip.
    }
    final hasNoMedia = inherited ||
        children.any((c) => c is File && c.path.endsWith('/.nomedia'));
    final subdirs = <String>[];
    for (final c in children) {
      if (c is File) {
        files.add(c.path);
        noMedia.add(hasNoMedia);
      } else if (c is Directory) {
        subdirs.add(c.path);
      }
    }
    subdirs.sort();
    for (final d in subdirs.reversed) {
      stack.add((d, hasNoMedia));
    }
    scanned = files.length;
    current = dir;
    if (++dirs % 40 == 0) {
      progress();
      await breathe();
    }
  }

  // ── Phase 2: analyze ──
  phase = ScanPhase.analyzing;
  total = files.length;
  scanned = 0;
  progress(force: true);

  const analyzer = FileAnalyzer();
  final batch = <Map<String, Object?>>[];
  var lastFlush = clock.elapsedMilliseconds;

  void flush() {
    if (batch.isEmpty) return;
    main.send({'t': 'i', 'items': List.of(batch)});
    batch.clear();
    lastFlush = clock.elapsedMilliseconds;
  }

  for (var i = 0; i < files.length; i++) {
    if (i % 16 == 0) await breathe();
    if (cancelled) break;
    current = files[i];
    List<FileItem> items;
    try {
      items = analyzer.analyze(files[i],
          underNoMedia: noMedia[i],
          deep: options.deep,
          isCancelled: () => cancelled);
    } catch (_) {
      items = const [];
    }
    scanned = i + 1;
    if (items.isNotEmpty) {
      found += items.length;
      batch.addAll(items.map((e) => e.toMap()));
    }
    if (batch.length >= 200 || clock.elapsedMilliseconds - lastFlush > 300) {
      flush();
    }
    progress();
  }

  flush();
  progress(force: true);
  main.send({'t': 'd', 'c': cancelled});
  control.close();
}

String _strip(String p) =>
    p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

/// Drops roots that are missing, duplicates (same real path), or nested
/// inside another root, so no file is scanned twice.
List<String> _dedupeRoots(List<String> roots) {
  final real = <String>[];
  for (final r in roots) {
    try {
      final d = Directory(r);
      if (!d.existsSync()) continue;
      real.add(_strip(d.resolveSymbolicLinksSync()));
    } catch (_) {}
  }
  real.sort((a, b) => a.length.compareTo(b.length));
  final out = <String>[];
  for (final r in real) {
    if (out.any((o) => r == o || r.startsWith('$o/'))) continue;
    out.add(r);
  }
  return out;
}
