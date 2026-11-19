import 'package:flutter_test/flutter_test.dart';

import 'package:salah_qada_tracker/prayer/prayer_tier.dart';

void main() {
  final prayerStart = DateTime.utc(2026, 11, 7, 12);
  final prayerEnd = DateTime.utc(2026, 11, 7, 15);

  group('classifyPrayerTier standard window', () {
    test('returns green during early zone (first 30 minutes)', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 12, 15),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.green,
      );
    });

    test('returns yellow during middle normal zone', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 13),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.yellow,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 14, 29),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.yellow,
      );
    });

    test('returns red during final zone (last 30 minutes)', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 14, 30),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.red,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 14, 59),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.red,
      );
    });

    test('throws when now is outside the half-open window', () {
      expect(
        () => classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 11, 59),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        throwsArgumentError,
      );
      expect(
        () => classifyPrayerTier(
          now: prayerEnd,
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        throwsArgumentError,
      );
    });
  });

  group('classifyPrayerTier for Isha with Islamic midnight', () {
    final ishaStart = DateTime.utc(2026, 11, 7, 19, 30);
    final ishaEnd = DateTime.utc(2026, 11, 8, 4, 50);
    final islamicMidnight = DateTime.utc(2026, 11, 7, 23, 3);

    test('returns green in first 30 minutes', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 19, 45),
          prayerStart: ishaStart,
          prayerEnd: ishaEnd,
          prayer: 'Isha',
          islamicMidnight: islamicMidnight,
        ),
        PrayerTier.green,
      );
    });

    test('returns yellow between early zone and Islamic midnight', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 20, 15),
          prayerStart: ishaStart,
          prayerEnd: ishaEnd,
          prayer: 'Isha',
          islamicMidnight: islamicMidnight,
        ),
        PrayerTier.yellow,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 23, 2),
          prayerStart: ishaStart,
          prayerEnd: ishaEnd,
          prayer: 'Isha',
          islamicMidnight: islamicMidnight,
        ),
        PrayerTier.yellow,
      );
    });

    test('returns red (warning) at and after Islamic midnight', () {
      expect(
        classifyPrayerTier(
          now: islamicMidnight,
          prayerStart: ishaStart,
          prayerEnd: ishaEnd,
          prayer: 'Isha',
          islamicMidnight: islamicMidnight,
        ),
        PrayerTier.red,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 8, 1, 30),
          prayerStart: ishaStart,
          prayerEnd: ishaEnd,
          prayer: 'Isha',
          islamicMidnight: islamicMidnight,
        ),
        PrayerTier.red,
      );
    });
  });

  group('classifyPrayerTier for Maghrib', () {
    final maghribStart = DateTime.utc(2026, 11, 7, 17, 15);
    final maghribEnd = DateTime.utc(2026, 11, 7, 18, 25); // 70 min window

    test('allocates 15 min early, middle normal, and 15 min ending soon', () {
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 17, 25),
          prayerStart: maghribStart,
          prayerEnd: maghribEnd,
          prayer: 'Maghrib',
        ),
        PrayerTier.green,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 17, 45),
          prayerStart: maghribStart,
          prayerEnd: maghribEnd,
          prayer: 'Maghrib',
        ),
        PrayerTier.yellow,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 18, 15),
          prayerStart: maghribStart,
          prayerEnd: maghribEnd,
          prayer: 'Maghrib',
        ),
        PrayerTier.red,
      );
    });
  });

  group('classifyPrayerTier short windows', () {
    test('scales early and final zones for short prayer window', () {
      final shortStart = DateTime.utc(2026, 11, 7, 17);
      final shortEnd = DateTime.utc(2026, 11, 7, 17, 45); // 45 minutes

      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 17, 10),
          prayerStart: shortStart,
          prayerEnd: shortEnd,
        ),
        PrayerTier.green,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 17, 20),
          prayerStart: shortStart,
          prayerEnd: shortEnd,
        ),
        PrayerTier.yellow,
      );
      expect(
        classifyPrayerTier(
          now: DateTime.utc(2026, 11, 7, 17, 35),
          prayerStart: shortStart,
          prayerEnd: shortEnd,
        ),
        PrayerTier.red,
      );
    });
  });
}
