import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:salah_qada_tracker/prayer/prayer_schedule.dart';

void main() {
  tzdata.initializeTimeZones();

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
    final date = DateTime.utc(2026, 11, 8, 12);
    final schedule = buildPrayerWindowSchedule(
      city: city,
      now: date,
      calculationMethod: city.automaticProfile.method,
      madhab: city.automaticProfile.madhab,
    );
    final todayWindows = schedule.windows
        .where((w) => w.prayerDay == DateTime.utc(2026, 11, 8))
        .toList();
    final tomorrowWindows = schedule.windows
        .where((w) => w.prayerDay == DateTime.utc(2026, 11, 9))
        .toList();

    expect(todayWindows[1].end, todayWindows[2].start);
    expect(todayWindows[2].end, todayWindows[3].start);
    expect(todayWindows[3].end, todayWindows[4].start);
    expect(todayWindows[4].end, tomorrowWindows.first.start);
  });

  test('the schedule margin shifts each start and dependent window end', () {
    final city = starterCities.first;
    final date = DateTime.utc(2026, 11, 8, 12);
    final withoutMargin = buildPrayerWindowSchedule(
      city: city,
      now: date,
      calculationMethod: city.automaticProfile.method,
      madhab: city.automaticProfile.madhab,
      includeStartSafetyMargin: false,
    );
    final withMargin = buildPrayerWindowSchedule(
      city: city,
      now: date,
      calculationMethod: city.automaticProfile.method,
      madhab: city.automaticProfile.madhab,
      includeStartSafetyMargin: true,
    );

    final withoutToday = withoutMargin.windows
        .where((w) => w.prayerDay == DateTime.utc(2026, 11, 8))
        .toList();
    final withToday = withMargin.windows
        .where((w) => w.prayerDay == DateTime.utc(2026, 11, 8))
        .toList();

    expect(withToday[2].start.isAfter(withoutToday[2].start), isTrue);
    expect(withToday[1].end, withToday[2].start);
    expect(withToday[1].end.isAfter(withoutToday[1].end), isTrue);
    expect(withToday[4].end.isAfter(withoutToday[4].end), isTrue);
  });

  test(
    'raw prayer times preserve seconds independently of display rounding',
    () {
      final rawTimes = calculateRawPrayerTimes(
        city: starterCities.first,
        date: DateTime.utc(2026, 11, 8),
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
      final schedule = buildPrayerWindowSchedule(
        city: city,
        now: now,
        calculationMethod: profile.method,
        madhab: profile.madhab,
      );

      final current = schedule.currentWindow(now);
      expect(current?.prayer, 'Isha', reason: cityName);
    }
  });
}
