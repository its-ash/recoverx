import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/file_item.dart';
import '../../domain/file_signature.dart';

part 'scan_database.g.dart';

/// Drift row for a recovered/scanned file.
class ScannedFileRows extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();
  IntColumn get size => integer()();
  TextColumn get detectedExtension => text()();
  TextColumn get detectedMimeType => text()();
  TextColumn get category => text()();
  TextColumn get displayName => text()();
  TextColumn get discoveryReason => text()();
  TextColumn get matchConfidence => text()();
  DateTimeColumn get lastModified => dateTime().nullable()();
  BoolColumn get isRecovered => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ScannedFileRows])
class ScanDatabase extends _$ScanDatabase {
  ScanDatabase() : super(_openConnection());

  ScanDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  // ── Queries ───────────────────────────────────────────────────

  Future<List<FileItem>> getAllFiles() =>
      select(scannedFileRows).map(FileItemMapper.fromRow).get();

  Future<List<FileItem>> getByCategory(FileCategory category) =>
      (select(scannedFileRows)
            ..where((r) => r.category.equals(category.name)))
          .map(FileItemMapper.fromRow)
          .get();

  Future<List<FileItem>> getByReason(DiscoveryReason reason) =>
      (select(scannedFileRows)
            ..where((r) => r.discoveryReason.equals(reason.name)))
          .map(FileItemMapper.fromRow)
          .get();

  Future<void> insertFile(FileItem item) =>
      into(scannedFileRows).insertOnConflictUpdate(FileItemMapper.toRow(item));

  Future<void> insertFiles(List<FileItem> items) => batch((b) {
        b.insertAll(
          scannedFileRows,
          items.map(FileItemMapper.toRow),
          mode: InsertMode.insertOrReplace,
        );
      });

  Future<void> markRecovered(String id) =>
      (update(scannedFileRows)..where((r) => r.id.equals(id)))
          .write(const ScannedFileRowsCompanion(isRecovered: Value(true)));

  Future<void> clearAll() => delete(scannedFileRows).go();
}

class FileItemMapper {
  FileItemMapper._();

  static FileItem fromRow(ScannedFileRow row) => FileItem(
        id: row.id,
        path: row.path,
        size: row.size,
        detectedExtension: row.detectedExtension,
        detectedMimeType: row.detectedMimeType,
        category: FileCategory.values.byName(row.category),
        displayName: row.displayName,
        discoveryReason: DiscoveryReason.values.byName(row.discoveryReason),
        matchConfidence: MatchConfidence.values.byName(row.matchConfidence),
        lastModified: row.lastModified,
        isRecovered: row.isRecovered,
      );

  static ScannedFileRowsCompanion toRow(FileItem item) =>
      ScannedFileRowsCompanion(
        id: Value(item.id),
        path: Value(item.path),
        size: Value(item.size),
        detectedExtension: Value(item.detectedExtension),
        detectedMimeType: Value(item.detectedMimeType),
        category: Value(item.category.name),
        displayName: Value(item.displayName),
        discoveryReason: Value(item.discoveryReason.name),
        matchConfidence: Value(item.matchConfidence.name),
        lastModified: Value(item.lastModified),
        isRecovered: Value(item.isRecovered),
      );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'recoverx_scan.db'));
      return NativeDatabase.createInBackground(file);
    });