import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:salah_qada_tracker/storage/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores and updates a local prayer record', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.closeDatabase);

    final id = await database.insertRecord(
      prayer: 'Fajr',
      prayerDay: 'unknown',
      source: 'manual',
      createdAt: DateTime.utc(2026, 11, 13),
    );

    final record = await database.findRecord(
      prayer: 'Fajr',
      prayerDay: 'unknown',
      source: 'manual',
    );
    expect(record?.id, id);
    expect(record?.completed, isFalse);

    await database.setCompleted(id, true, DateTime.utc(2026, 11, 14));
    final completed = await database.getAllRecords();
    expect(completed.single.completed, isTrue);
    expect(
      completed.single.completedAt?.toUtc(),
      DateTime.utc(2026, 11, 14),
    );
  });
}
