import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

class PrayerRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get prayer => text()();
  TextColumn get prayerDay => text()();
  TextColumn get source => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [PrayerRecords, AppSettings])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'salah_qada',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 1;

  Future<List<PrayerRecord>> getAllRecords() => select(prayerRecords).get();

  Future<List<PrayerRecord>> getCompletedRecords() {
    return (select(prayerRecords)
          ..where((row) => row.completed.equals(true))
          ..orderBy([(row) => OrderingTerm.desc(row.completedAt)]))
        .get();
  }

  Future<String?> getSetting(String key) async {
    final setting = await (select(
      appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return setting?.value;
  }

  Future<void> setSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<PrayerRecord?> findRecord({
    required String prayer,
    required String prayerDay,
    required String source,
  }) {
    return (select(prayerRecords)..where(
          (row) =>
              row.prayer.equals(prayer) &
              row.prayerDay.equals(prayerDay) &
              row.source.equals(source),
        ))
        .getSingleOrNull();
  }

  Future<int> insertRecord({
    required String prayer,
    required String prayerDay,
    required String source,
    required DateTime createdAt,
  }) {
    return into(prayerRecords).insert(
      PrayerRecordsCompanion.insert(
        prayer: prayer,
        prayerDay: prayerDay,
        source: source,
        createdAt: createdAt,
      ),
    );
  }

  Future<void> setCompleted(int id, bool completed, DateTime? completedAt) {
    return (update(prayerRecords)..where((row) => row.id.equals(id))).write(
      PrayerRecordsCompanion(
        completed: Value(completed),
        completedAt: Value(completedAt),
      ),
    );
  }

  Future<void> deleteRecord(int id) {
    return (delete(prayerRecords)..where((row) => row.id.equals(id))).go();
  }

  Future<void> closeDatabase() => close();
}
