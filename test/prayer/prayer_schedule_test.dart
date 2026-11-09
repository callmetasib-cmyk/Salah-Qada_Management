import 'package:flutter_test/flutter_test.dart';

import 'package:salah_qada_tracker/prayer/prayer_schedule.dart';

void main() {
  test('prayer starts round up after the safety margin', () {
    final raw = DateTime.utc(2026, 11, 8, 12, 0, 1);

    expect(roundPrayerStart(raw), DateTime.utc(2026, 11, 8, 12, 2));
  });

  test('prayer ends round down without adding seconds', () {
    final raw = DateTime.utc(2026, 11, 8, 12, 0, 59, 999);

    expect(roundPrayerEnd(raw), DateTime.utc(2026, 11, 8, 12));
  });

  test('the safety margin consistently moves starts and keeps ends safe', () {
    final rawStart = DateTime.utc(2026, 11, 8, 12, 0, 1);
    final rawEnd = DateTime.utc(2026, 11, 8, 13, 0, 59);

    expect(
      roundPrayerStart(rawStart).difference(rawStart),
      const Duration(minutes: 1, seconds: 59),
    );
    expect(roundPrayerEnd(rawEnd).isBefore(rawEnd), isTrue);
    expect(
      roundPrayerStart(rawStart).isAfter(roundPrayerEnd(rawStart)),
      isTrue,
    );
  });

  test('adjacent prayer windows share displayed boundaries', () {
    final city = starterCities.first;
    final date = DateTime(2026, 11, 8);
    final schedule = calculatePrayerSchedule(
      city: city,
      date: date,
      now: date.add(const Duration(hours: 12)),
    );
    final nextDay = calculatePrayerSchedule(
      city: city,
      date: date.add(const Duration(days: 1)),
      now: date.add(const Duration(hours: 12)),
    );

    expect(schedule[1].end, schedule[2].start);
    expect(schedule[2].end, schedule[3].start);
    expect(schedule[3].end, schedule[4].start);
    expect(schedule[4].end, nextDay.first.start);
  });

  test('the schedule margin shifts each start and dependent window end', () {
    final city = starterCities.first;
    final date = DateTime(2026, 11, 8);
    final withoutMargin = calculatePrayerSchedule(
      city: city,
      date: date,
      now: date.add(const Duration(hours: 12)),
      includeStartSafetyMargin: false,
    );
    final withMargin = calculatePrayerSchedule(
      city: city,
      date: date,
      now: date.add(const Duration(hours: 12)),
    );

    expect(withMargin[2].start.isAfter(withoutMargin[2].start), isTrue);
    expect(withMargin[1].end, withMargin[2].start);
    expect(withMargin[1].end.isAfter(withoutMargin[1].end), isTrue);
    expect(withMargin[4].end.isAfter(withoutMargin[4].end), isTrue);
  });

  test(
    'raw prayer times preserve seconds independently of display rounding',
    () {
      final rawTimes = calculateRawPrayerTimes(
        city: starterCities.first,
        date: DateTime(2026, 11, 8),
        calculationMethod: starterCities.first.automaticProfile.method,
        madhab: starterCities.first.automaticProfile.madhab,
      );

      expect(rawTimes['Fajr']!.second, greaterThan(0));
      expect(
        roundPrayerStart(rawTimes['Fajr']!, includeSafetyMargin: false).second,
        0,
      );
    },
  );

  test('pre-Fajr local schedules show the previous Isha as current', () {
    final now = DateTime.utc(2026, 11, 8, 16, 43);
    for (final cityName in ['Osaka', 'Kuala Lumpur']) {
      final city = starterCities.firstWhere((city) => city.name == cityName);
      final profile = city.automaticProfile;
      final schedule = calculatePrayerSchedule(
        city: city,
        now: now,
        calculationMethod: profile.method,
        madhab: profile.madhab,
      );

      expect(schedule.first.name, 'Isha', reason: cityName);
      expect(schedule.first.status, PrayerStatus.current, reason: cityName);
      expect(
        schedule
            .skip(1)
            .every((prayer) => prayer.status == PrayerStatus.upcoming),
        isTrue,
        reason: cityName,
      );
    }
  });
}
