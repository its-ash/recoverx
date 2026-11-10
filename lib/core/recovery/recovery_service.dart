import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/file_item.dart';
import '../../domain/sensitive_rating.dart';

/// Case details written into the report.
class CaseInfo {
  const CaseInfo({this.deviceModel, this.deviceMaker, this.androidVersion, this.scanStarted, this.examiner});

  final String? deviceModel;
  final String? deviceMaker;
  final String? androidVersion;
  final DateTime? scanStarted;
  final String? examiner;

  Map<String, Object?> toJson() => {
        'deviceMaker': deviceMaker,
        'deviceModel': deviceModel,
        'androidVersion': androidVersion,
        'scanStarted': scanStarted?.toIso8601String(),
        'examiner': examiner,
      };
}

/// One exported file.
class ExportRecord {
  const ExportRecord({
    required this.item,
    this.exportedPath,
    this.sha256,
    this.error,
  });

  final FileItem item;
  final String? exportedPath;
  final String? sha256;
  final String? error;

  bool get ok => error == null;
}

class ExportProgress {
  const ExportProgress(this.done, this.total, this.bytesDone, this.bytesTotal, this.current);

  final int done;
  final int total;
  final int bytesDone;
  final int bytesTotal;
  final String current;

  double get fraction => bytesTotal == 0 ? 0 : (bytesDone / bytesTotal).clamp(0, 1);
}

class ExportResult {
  const ExportResult(this.folder, this.records);

  final String folder;
  final List<ExportRecord> records;

  int get okCount => records.where((r) => r.ok).length;
  int get failedCount => records.length - okCount;
}

/// Copies recovered files out of the device, verifying every copy.
///
/// For each item:
///  * streams the bytes (whole file, or the carved byte range) to the
///    destination while computing SHA-256 of the source,
///  * re-reads the written copy and checks its SHA-256 matches,
///  * restores the original modification time,
///  * names the copy with its real extension.
///
/// It also writes `manifest.csv` and `report.json` (original path, offset,
/// type, reasons, metadata, hash) next to the files for chain of custody.
///
/// The scan itself never writes. Export to a different volume (SD card or
/// USB-OTG) when possible: writing to internal storage can overwrite
/// deleted data that has not been recovered yet.
class RecoveryService {
  RecoveryService._();

  static String exportFolderFor(String volumeRoot, DateTime when) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${when.year}-${two(when.month)}-${two(when.day)}_'
        '${two(when.hour)}-${two(when.minute)}-${two(when.second)}';
    return p.join(volumeRoot, 'RecoverX', 'Recovered', stamp);
  }

  /// Exports [items] into a new time-stamped folder under [volumeRoot].
  static Stream<Object> export({
    required List<FileItem> items,
    required String volumeRoot,
    CaseInfo caseInfo = const CaseInfo(),
  }) {
    final out = StreamController<Object>();
    final port = ReceivePort();
    final folder = exportFolderFor(volumeRoot, DateTime.now());
    var finished = false;

    port.listen((msg) {
      if (msg is Map && msg['t'] == 'p') {
        out.add(ExportProgress(msg['d'] as int, msg['n'] as int, msg['b'] as int,
            msg['bt'] as int, msg['c'] as String));
      } else if (msg is Map && msg['t'] == 'r') {
        final records = <ExportRecord>[];
        final raw = msg['records'] as List;
        for (var i = 0; i < raw.length; i++) {
          final r = raw[i] as Map;
          records.add(ExportRecord(
            item: items[i],
            exportedPath: r['path'] as String?,
            sha256: r['sha'] as String?,
            error: r['err'] as String?,
          ));
        }
        finished = true;
        out.add(ExportResult(folder, records));
        out.close();
        port.close();
      } else if (msg is List) {
        out.addError(StateError('Export failed: ${msg.first}'));
        finished = true;
        out.close();
        port.close();
      } else if (msg == null && !finished) {
        out.addError(StateError('Export stopped unexpectedly'));
        out.close();
        port.close();
      }
    });

    Isolate.spawn(
      _exportEntry,
      [
        port.sendPort,
        folder,
        [for (final i in items) i.toMap()],
        caseInfo.toJson(),
        // Static state does not cross isolates: send the content-check limits.
        [SensitiveThresholds.current.explicit, SensitiveThresholds.current.suggestive],
      ],
      onError: port.sendPort,
      onExit: port.sendPort,
      debugName: 'recoverx-export',
    ).catchError((Object e) {
      finished = true;
      out.addError(e);
      out.close();
      port.close();
      return Isolate.current;
    });
    return out.stream;
  }
}

// ───────────────────────── Isolate side ─────────────────────────

@pragma('vm:entry-point')
Future<void> _exportEntry(List<Object?> args) async {
  final main = args[0] as SendPort;
  final folder = args[1] as String;
  final items = [
    for (final m in args[2] as List)
      FileItem.fromMap((m as Map).cast<String, Object?>())!,
  ];
  final caseInfo = (args[3] as Map).cast<String, Object?>();
  final limits = (args[4] as List).cast<double>();
  SensitiveThresholds.current = SensitiveThresholds(explicit: limits[0], suggestive: limits[1]);

  Directory(folder).createSync(recursive: true);
  final bytesTotal = items.fold<int>(0, (s, i) => s + i.size);
  var bytesDone = 0;
  var lastSend = 0;
  final clock = Stopwatch()..start();

  void progress(int done, String current, {bool force = false}) {
    final now = clock.elapsedMilliseconds;
    if (!force && now - lastSend < 150) return;
    lastSend = now;
    main.send({'t': 'p', 'd': done, 'n': items.length, 'b': bytesDone, 'bt': bytesTotal, 'c': current});
  }

  final records = <Map<String, Object?>>[];
  final usedNames = <String>{};

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    progress(i, item.suggestedName, force: true);
    try {
      final dir = p.join(folder, item.category.name);
      Directory(dir).createSync(recursive: true);
      final target = _uniquePath(dir, item.suggestedName, usedNames);
      final sha = _copyHashed(item, target, (n) {
        bytesDone += n;
        progress(i, item.suggestedName);
      });
      final check = _hashFile(target);
      if (check != sha) {
        throw StateError('Hash mismatch after copy (source $sha, copy $check)');
      }
      if (!item.isCarved && item.lastModified != null) {
        try {
          File(target).setLastModifiedSync(item.lastModified!);
        } catch (_) {}
      }
      records.add({'path': target, 'sha': sha});
    } catch (e) {
      records.add({'err': '$e'});
    }
    await Future<void>.delayed(Duration.zero);
  }

  _writeReports(folder, items, records, caseInfo);
  progress(items.length, '', force: true);
  main.send({'t': 'r', 'records': records});
}

String _uniquePath(String dir, String name, Set<String> used) {
  final base = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var candidate = p.join(dir, name);
  var n = 1;
  while (used.contains(candidate) || File(candidate).existsSync()) {
    candidate = p.join(dir, '$base ($n)$ext');
    n++;
  }
  used.add(candidate);
  return candidate;
}

/// Copies the item's bytes to [target]; returns SHA-256 of what was read.
String _copyHashed(FileItem item, String target, void Function(int) onBytes) {
  final src = File(item.path).openSync();
  final dst = File(target).openSync(mode: FileMode.writeOnly);
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  try {
    final start = item.sourceOffset ?? 0;
    final length = item.isCarved ? item.size : src.lengthSync();
    src.setPositionSync(start);
    var left = length;
    const chunk = 1 << 20;
    while (left > 0) {
      final buf = src.readSync(math.min(chunk, left));
      if (buf.isEmpty) throw StateError('Source ended early (file changed?)');
      dst.writeFromSync(buf);
      hasher.add(buf);
      left -= buf.length;
      onBytes(buf.length);
    }
    dst.flushSync();
  } finally {
    src.closeSync();
    dst.closeSync();
  }
  hasher.close();
  return sink.value.toString();
}

String _hashFile(String path) {
  final f = File(path).openSync();
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  try {
    while (true) {
      final buf = f.readSync(1 << 20);
      if (buf.isEmpty) break;
      hasher.add(buf);
    }
  } finally {
    f.closeSync();
  }
  hasher.close();
  return sink.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

void _writeReports(String folder, List<FileItem> items,
    List<Map<String, Object?>> records, Map<String, Object?> caseInfo) {
  String csv(Object? v) {
    final s = v?.toString() ?? '';
    return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final rows = StringBuffer()
    ..writeln([
      'status', 'exported_file', 'sha256', 'type', 'mime', 'size_bytes',
      'original_path', 'carved_offset', 'original_name', 'reasons',
      'source_app', 'integrity', 'confidence', 'fs_modified', 'captured',
      'gps', 'camera', 'error', 'sensitive_level', 'sensitive_explicit', 'sensitive_suggestive',
    ].join(','));

  final entries = <Map<String, Object?>>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final r = records[i];
    final meta = it.metadata;
    final exported = r['path'] as String?;
    final row = {
      'status': r['err'] == null ? 'ok' : 'failed',
      'exportedFile': exported == null ? null : p.relative(exported, from: folder),
      'sha256': r['sha'],
      'type': it.type.id,
      'mime': it.detectedMimeType,
      'sizeBytes': it.size,
      'originalPath': it.path,
      'carvedOffset': it.sourceOffset,
      'originalName': it.originalName,
      'reasons': it.reasons.map((e) => e.name).toList(),
      'sourceApp': it.sourceApp,
      'integrity': it.integrity.name,
      'confidence': it.matchConfidence.name,
      'fsModified': it.lastModified?.toIso8601String(),
      'metadata': meta?.toJson(),
      'sensitiveCheck': it.sensitive?.toJson(),
      'error': r['err'],
    };
    entries.add(row);
    rows.writeln([
      row['status'],
      row['exportedFile'],
      row['sha256'],
      row['type'],
      row['mime'],
      row['sizeBytes'],
      row['originalPath'],
      row['carvedOffset'],
      row['originalName'],
      it.reasons.map((e) => e.name).join(' '),
      row['sourceApp'],
      row['integrity'],
      row['confidence'],
      row['fsModified'],
      meta?.takenAt?.toIso8601String(),
      meta != null && meta.hasLocation ? '${meta.latitude},${meta.longitude}' : null,
      [meta?.cameraMake, meta?.cameraModel].whereType<String>().join(' '),
      row['error'],
      it.sensitive?.level.name,
      it.sensitive?.explicit,
      it.sensitive?.suggestive,
    ].map(csv).join(','));
  }

  File(p.join(folder, 'manifest.csv')).writeAsStringSync(rows.toString());
  File(p.join(folder, 'report.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'tool': 'RecoverX',
      'exportedAt': DateTime.now().toIso8601String(),
      'case': caseInfo,
      'hashAlgorithm': 'SHA-256',
      'note': 'Each sha256 is computed from the source bytes during copy and '
          're-verified against the written copy. sensitiveCheck is an automatic '
          'on-device model score for review, not a finding.',
      'files': entries,
    }),
  );
}
