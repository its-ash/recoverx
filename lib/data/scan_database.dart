import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/file_item.dart';
import '../domain/file_metadata.dart';
import '../domain/sensitive_rating.dart';
import '../domain/signature_database.dart';

part 'scan_database.g.dart';

/// Drift row for a scanned file. Lives in the app's private storage.
class ScannedFileRows extends Table {
  /// Path, plus `#offset` for carved items.
  TextColumn get id => text()();
  TextColumn get path => text()();
  IntColumn get size => integer()();
  TextColumn get typeId => text()();
  TextColumn get confidence => text()();

  /// Comma-separated [DiscoveryReason] names.
  TextColumn get reasons => text().withDefault(const Constant(''))();
  DateTimeColumn get lastModified => dateTime().nullable()();
  TextColumn get originalName => text().nullable()();
  IntColumn get sourceOffset => integer().nullable()();
  TextColumn get sourceApp => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
  TextColumn get integrity => text().withDefault(const Constant('unknown'))();
  BoolColumn get isRecovered => boolean().withDefault(const Constant(false))();

  /// [SensitiveRating.encode]; null until the sensitive-content check ran.
  TextColumn get sensitiveJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ScannedFileRows])
class ScanDatabase extends _$ScanDatabase {
  ScanDatabase() : super(_openConnection());

  ScanDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v1 rows lack type ids and metadata; the table is only a cache of
          // the last scan, so rebuild it.
          if (from < 2) {
            await m.deleteTable(scannedFileRows.actualTableName);
            await m.createTable(scannedFileRows);
          } else if (from < 3) {
            await m.addColumn(scannedFileRows, scannedFileRows.sensitiveJson);
          }
        },
      );

  Future<List<FileItem>> getAllFiles() async {
    final rows = await select(scannedFileRows).get();
    return rows.map(FileItemMapper.fromRow).whereType<FileItem>().toList();
  }

  Future<void> insertFiles(List<FileItem> items) => batch((b) {
        b.insertAll(
          scannedFileRows,
          items.map(FileItemMapper.toRow),
          mode: InsertMode.insertOrReplace,
        );
      });

  Future<void> markRecovered(Iterable<String> ids) =>
      (update(scannedFileRows)..where((r) => r.id.isIn(ids)))
          .write(const ScannedFileRowsCompanion(isRecovered: Value(true)));

  /// Stores sensitive-content results by item id.
  Future<void> saveSensitive(Map<String, SensitiveRating> ratings) => batch((b) {
        for (final e in ratings.entries) {
          b.update(
            scannedFileRows,
            ScannedFileRowsCompanion(sensitiveJson: Value(e.value.encode())),
            where: (r) => r.id.equals(e.key),
          );
        }
      });

  Future<void> clearSensitive() =>
      update(scannedFileRows).write(const ScannedFileRowsCompanion(sensitiveJson: Value(null)));

  Future<void> clearAll() => delete(scannedFileRows).go();
}

class FileItemMapper {
  FileItemMapper._();

  static FileItem? fromRow(ScannedFileRow row) {
    final type = FileTypes.byId(row.typeId);
    if (type == null) return null;
    return FileItem(
      path: row.path,
      size: row.size,
      type: type,
      matchConfidence: MatchConfidence.values
              .where((c) => c.name == row.confidence)
              .firstOrNull ??
          MatchConfidence.medium,
      reasons: FileItem.decodeReasons(row.reasons),
      lastModified: row.lastModified,
      originalName: row.originalName,
      sourceOffset: row.sourceOffset,
      sourceApp: row.sourceApp,
      metadata: FileMetadata.decode(row.metadataJson),
      integrity:
          Integrity.values.where((i) => i.name == row.integrity).firstOrNull ??
              Integrity.unknown,
      isRecovered: row.isRecovered,
      sensitive: SensitiveRating.decode(row.sensitiveJson),
    );
  }

  static ScannedFileRowsCompanion toRow(FileItem item) =>
      ScannedFileRowsCompanion(
        id: Value(item.id),
        path: Value(item.path),
        size: Value(item.size),
        typeId: Value(item.type.id),
        confidence: Value(item.matchConfidence.name),
        reasons: Value(item.reasons.map((r) => r.name).join(',')),
        lastModified: Value(item.lastModified),
        originalName: Value(item.originalName),
        sourceOffset: Value(item.sourceOffset),
        sourceApp: Value(item.sourceApp),
        metadataJson: Value(item.metadata?.encode()),
        integrity: Value(item.integrity.name),
        isRecovered: Value(item.isRecovered),
        sensitiveJson: Value(item.sensitive?.encode()),
      );
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'recoverx_scan.db'));
      return NativeDatabase.createInBackground(file);
    });
