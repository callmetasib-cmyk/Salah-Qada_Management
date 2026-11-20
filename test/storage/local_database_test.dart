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

  test('insertRecord supports completed and completedAt directly', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.closeDatabase);

    final completedAt = DateTime.utc(2026, 11, 15, 12);
    final id = await database.insertRecord(
      prayer: 'Dhuhr',
      prayerDay: '2026-11-15',
      source: 'current',
      createdAt: completedAt,
      completed: true,
      completedAt: completedAt,
    );

    final record = await database.findRecord(
      prayer: 'Dhuhr',
      prayerDay: '2026-11-15',
      source: 'current',
    );
    expect(record?.id, id);
    expect(record?.completed, isTrue);
    expect(record?.completedAt?.toUtc(), completedAt);
  });

  test('findRecord does not throw when multiple matching rows exist', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.closeDatabase);

    await database.insertRecord(
      prayer: 'Asr',
      prayerDay: 'unknown',
      source: 'manual',
      createdAt: DateTime.utc(2026, 11, 16),
    );
    await database.insertRecord(
      prayer: 'Asr',
      prayerDay: 'unknown',
      source: 'manual',
      createdAt: DateTime.utc(2026, 11, 17),
    );

    // Should return the first matching record instead of throwing StateError
    final record = await database.findRecord(
      prayer: 'Asr',
      prayerDay: 'unknown',
      source: 'manual',
    );
    expect(record, isNotNull);
    expect(record?.prayer, 'Asr');
  });

  test('getSetting and setSetting save and retrieve configurations', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.closeDatabase);

    expect(await database.getSetting('settings_mode'), isNull);

    await database.setSetting('settings_mode', 'manual');
    expect(await database.getSetting('settings_mode'), 'manual');

    await database.setSetting('settings_mode', 'automatic');
    expect(await database.getSetting('settings_mode'), 'automatic');
  });
}
