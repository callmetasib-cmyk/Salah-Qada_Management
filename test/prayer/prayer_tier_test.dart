import 'package:flutter_test/flutter_test.dart';

import 'package:salah_qada_tracker/prayer/prayer_tier.dart';

void main() {
  final prayerStart = DateTime(2026, 11, 7, 12);
  final prayerEnd = DateTime(2026, 11, 7, 15);

  group('classifyPrayerTier', () {
    test('returns green during the first third of the prayer window', () {
      expect(
        classifyPrayerTier(
          now: DateTime(2026, 11, 7, 12, 30),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.green,
      );
    });

    test('returns yellow during the second third of the prayer window', () {
      expect(
        classifyPrayerTier(
          now: DateTime(2026, 11, 7, 13, 30),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.yellow,
      );
    });

    test('returns red during the final third of the prayer window', () {
      expect(
        classifyPrayerTier(
          now: DateTime(2026, 11, 7, 14, 30),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.red,
      );
    });

    test('assigns exact third boundaries to the later tier', () {
      expect(
        classifyPrayerTier(
          now: DateTime(2026, 11, 7, 13),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.yellow,
      );
      expect(
        classifyPrayerTier(
          now: DateTime(2026, 11, 7, 14),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        PrayerTier.red,
      );
    });

    test('throws when the current time is outside the prayer window', () {
      expect(
        () => classifyPrayerTier(
          now: DateTime(2026, 11, 7, 11, 59),
          prayerStart: prayerStart,
          prayerEnd: prayerEnd,
        ),
        throwsArgumentError,
      );
    });

    test('throws when the prayer window is invalid', () {
      expect(
        () => classifyPrayerTier(
          now: prayerStart,
          prayerStart: prayerStart,
          prayerEnd: prayerStart,
        ),
        throwsArgumentError,
      );
    });
  });
}
