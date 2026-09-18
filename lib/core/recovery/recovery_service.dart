import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';

/// Manages the two-stage recovery pipeline:
///   1. [copyToTemp] — called during scan, copies each found file to a
///      category-organized temp folder immediately.
///   2. [exportSelected] — called when the user taps Export; copies from
///      temp into a date-stamped final folder and returns its path.
class RecoveryService {
  RecoveryService._();

  /// Returns the temp directory: <app-files>/RecoverX/Temp/<category>/
  static Future<Directory> tempDirForCategory(FileCategory category) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'RecoverX', 'Temp',
        category.name));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a found file to the temp folder immediately during scan.
  /// Returns the temp path, or null on failure.
  static Future<String?> copyToTemp(FileItem item) async {
    try {
      final dir = await tempDirForCategory(item.category);
      final targetName = item.suggestedName;
      var targetPath = p.join(dir.path, targetName);
      if (!File(targetPath).existsSync()) {
        await File(item.path).copy(targetPath);
      }
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  /// Exports selected items from temp into a date-stamped final folder:
  ///   <storage>/RecoverX/Exported/<yyyy-MM-dd_HH-mm-ss> RecoverX/
  /// Returns the export folder path.
  static Future<String> exportSelected(List<FileItem> items) async {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-'
        '${now.minute.toString().padLeft(2, '0')}-'
        '${now.second.toString().padLeft(2, '0')}';

    final appDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final exportDir = Directory(
        p.join(appDir.path, 'RecoverX', 'Exported', '$stamp RecoverX'));
    if (!exportDir.existsSync()) await exportDir.create(recursive: true);

    for (final item in items) {
      try {
        // Copy from temp (or from original if temp copy failed).
        final tempDir = await tempDirForCategory(item.category);
        final tempPath = p.join(tempDir.path, item.suggestedName);
        final source = File(tempPath).existsSync()
            ? File(tempPath)
            : File(item.path);

        // Organize by category inside export folder.
        final catDir = Directory(p.join(exportDir.path, item.category.name));
        if (!catDir.existsSync()) await catDir.create(recursive: true);

        var targetPath = p.join(catDir.path, item.suggestedName);
        if (!File(targetPath).existsSync()) {
          final base = p.basenameWithoutExtension(item.suggestedName);
          final ext = p.extension(item.suggestedName);
          var n = 1;
          while (File(targetPath).existsSync()) {
            targetPath = p.join(catDir.path, '$base ($n)$ext');
            n++;
          }
        }
        await source.copy(targetPath);
      } catch (_) {
        // Continue on per-file errors.
      }
    }
    return exportDir.path;
  }

  /// Clears the temp folder.
  static Future<void> clearTemp() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempRoot = Directory(p.join(appDir.path, 'RecoverX', 'Temp'));
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  }
}