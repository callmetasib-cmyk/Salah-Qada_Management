import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salah_qada_tracker/prayer/prayer_schedule.dart';
import 'package:salah_qada_tracker/prayer/qada_state.dart';
import 'package:salah_qada_tracker/storage/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase database;
  late PrayerTrackerState state;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    state = PrayerTrackerState.forTesting(database);
    await state.initialize();
  });

  tearDown(() async {
    await database.closeDatabase();
  });

  group('PrayerTrackerState Core Logic', () {
    test('initial state has empty pending qada and no completions', () {
      expect(state.totalPendingQada, 0);
      expect(state.qadaList, isEmpty);
      expect(state.targetCompletionDate, isNull);
    });

    test('manual Qada creation and removal works accurately', () async {
      await state.addManualQada('Fajr', count: 3);
      expect(state.totalPendingQada, 3);
      expect(state.getPendingCountFor('Fajr'), 3);
      expect(state.getPendingCountFor('Dhuhr'), 0);

      final item = state.qadaList.first;
      expect(item.prayer, 'Fajr');
      expect(item.isManual, isTrue);
      expect(item.isMadeUp, isFalse);

      await state.removeManualQada(item);
      expect(state.totalPendingQada, 2);
      expect(state.getPendingCountFor('Fajr'), 2);
    });

    test('daily quota calculation with target dates and boundaries', () async {
      await state.addManualQada('Fajr', count: 20);
      expect(state.getPendingCountFor('Fajr'), 20);

      // Default without target completion date is 1 per day
      expect(state.getDailyQuotaFor('Fajr'), 1);

      // Target 10 calendar days in future -> 20 / 10 = 2 per day
      final now = DateTime.now();
      final tenDaysFuture = DateTime(now.year, now.month, now.day).add(const Duration(days: 9)); // today + 9 days = 10 days
      await state.setTargetCompletionDate(tenDaysFuture);
      expect(state.getDailyQuotaFor('Fajr'), 2);

      // Target today (1 day total) -> all 20 needed
      final todayDate = DateTime(now.year, now.month, now.day);
      await state.setTargetCompletionDate(todayDate);
      expect(state.getDailyQuotaFor('Fajr'), 20);

      // Target in the past -> clamped to total pending
      final pastDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 5));
      await state.setTargetCompletionDate(pastDate);
      expect(state.getDailyQuotaFor('Fajr'), 20);

      // 0 pending prayer quota is always 0
      expect(state.getDailyQuotaFor('Dhuhr'), 0);
    });

    test('habit stacking and custom prayer pairing', () async {
      expect(state.getAssignedCurrentPrayer('Fajr'), 'Fajr');

      // Pair Qada Fajr with Maghrib
      await state.setPrayerPairing('Fajr', 'Maghrib');
      expect(state.getAssignedCurrentPrayer('Fajr'), 'Maghrib');

      // Reset pairing back to self
      await state.setPrayerPairing('Fajr', 'Fajr');
      expect(state.getAssignedCurrentPrayer('Fajr'), 'Fajr');
    });

    test('partial completion of daily quota', () async {
      await state.addManualQada('Fajr', count: 10);
      final now = DateTime.now();
      // Target 2 calendar days -> quota is ceil(10/2) = 5
      final twoDays = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      await state.setTargetCompletionDate(twoDays);
      expect(state.getDailyQuotaFor('Fajr'), 5);

      expect(state.getTodayCompletedPlanQadaCount('Fajr', 'Fajr'), 0);
      expect(state.isPlanQadaDoneForToday('Fajr', 'Fajr'), isFalse);

      // Complete 2 out of 5
      await state.completePlanQada('Fajr', 'Fajr', count: 2);
      expect(state.getTodayCompletedPlanQadaCount('Fajr', 'Fajr'), 2);
      expect(state.getPendingCountFor('Fajr'), 8);
      expect(state.isPlanQadaDoneForToday('Fajr', 'Fajr'), isFalse);

      // Complete the remaining 3
      await state.completePlanQada('Fajr', 'Fajr', count: 3);
      expect(state.getTodayCompletedPlanQadaCount('Fajr', 'Fajr'), 5);
      expect(state.getPendingCountFor('Fajr'), 5);
      expect(state.isPlanQadaDoneForToday('Fajr', 'Fajr'), isTrue);
    });

    test('direct completion of Qada item updates daily plan completion', () async {
      await state.addManualQada('Dhuhr', count: 5);
      expect(state.getTodayCompletedPlanQadaCount('Dhuhr', 'Dhuhr'), 0);

      final item = state.qadaList.first;
      await state.completeQadaItem(item);

      expect(state.getTodayCompletedPlanQadaCount('Dhuhr', 'Dhuhr'), 1);
      expect(state.getPendingCountFor('Dhuhr'), 4);
    });

    test('syncWithLiveStatus respects onboarding and logs missed past prayers without duplication', () async {
      final city = starterCities.first;
      final today = DateTime.utc(2026, 11, 26);
      final fajrWindow = PrayerWindow(
        prayer: 'Fajr',
        start: DateTime.utc(2026, 11, 26, 5, 0),
        end: DateTime.utc(2026, 11, 26, 6, 30),
        prayerDay: today,
        islamicMidnight: null,
        city: city,
      );

      // Before first launch is completed, syncing should NOT auto-create Qada
      await state.syncWithLiveStatus([fajrWindow], {fajrWindow: PrayerStatus.past});
      expect(state.totalPendingQada, 0);

      // Mark first launch completed
      await state.setFirstLaunchCompleted();

      // Now sync past prayer
      await state.syncWithLiveStatus([fajrWindow], {fajrWindow: PrayerStatus.past});
      expect(state.totalPendingQada, 1);
      expect(state.qadaList.single.prayer, 'Fajr');

      // Sync again with same window - should not create duplicate
      await state.syncWithLiveStatus([fajrWindow], {fajrWindow: PrayerStatus.past});
      expect(state.totalPendingQada, 1);
    });

    test('markMissedPrayerDone marks as on-time and removes pending automatic Qada', () async {
      final city = starterCities.first;
      final today = DateTime.utc(2026, 11, 26);
      final dhuhrWindow = PrayerWindow(
        prayer: 'Dhuhr',
        start: DateTime.utc(2026, 11, 26, 12, 0),
        end: DateTime.utc(2026, 11, 26, 15, 0),
        prayerDay: today,
        islamicMidnight: null,
        city: city,
      );

      await state.setFirstLaunchCompleted();
      await state.syncWithLiveStatus([dhuhrWindow], {dhuhrWindow: PrayerStatus.past});
      expect(state.totalPendingQada, 1);

      // User says: I prayed on time!
      await state.markMissedPrayerDone('Dhuhr', today);
      expect(state.isPrayerDone('Dhuhr', today), isTrue);
      expect(state.totalPendingQada, 0);

      final history = await state.completedHistory();
      expect(history.length, 1);
      expect(history.single.isQada, isFalse);
    });

    test('markMissedPrayerLate records made up Qada and does not claim on-time completion', () async {
      final city = starterCities.first;
      final today = DateTime.utc(2026, 11, 26);
      final asrWindow = PrayerWindow(
        prayer: 'Asr',
        start: DateTime.utc(2026, 11, 26, 15, 0),
        end: DateTime.utc(2026, 11, 26, 17, 0),
        prayerDay: today,
        islamicMidnight: null,
        city: city,
      );

      await state.setFirstLaunchCompleted();
      await state.syncWithLiveStatus([asrWindow], {asrWindow: PrayerStatus.past});
      expect(state.totalPendingQada, 1);

      // User says: I prayed late (made up)
      await state.markMissedPrayerLate('Asr', today);
      expect(state.isPrayerDone('Asr', today), isTrue);
      expect(state.totalPendingQada, 0);

      final history = await state.completedHistory();
      expect(history.length, 1);
      expect(history.single.isQada, isTrue); // Correctly logged as Qada made up!
    });
  });
}
