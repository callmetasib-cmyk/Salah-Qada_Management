// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:salah_qada_tracker/prayer/prayer_schedule.dart';

void main() {
  tzdata.initializeTimeZones();
  final dhaka = starterCities.firstWhere((city) => city.name == 'Dhaka');
  final newYork = starterCities.firstWhere((city) => city.name == 'New York');

  DateTime localInstant(
    PrayerCity city,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    final location = tz.getLocation(city.timeZone);
    return tz.TZDateTime(
      location,
      year,
      month,
      day,
      hour,
      minute,
      second,
    ).toUtc();
  }

  PrayerWindowSchedule scheduleFor(
    PrayerCity city,
    DateTime now, {
    bool includeStartSafetyMargin = true,
  }) {
    return buildPrayerWindowSchedule(
      city: city,
      now: now,
      calculationMethod: city.automaticProfile.method,
      madhab: city.automaticProfile.madhab,
      includeStartSafetyMargin: includeStartSafetyMargin,
    );
  }

  test('00:30 returns yesterday Isha with the previous prayer day', () {
    final now = localInstant(dhaka, 2026, 11, 8, 0, 30, 0);
    final current = scheduleFor(dhaka, now).currentWindow(now);

    expect(current?.prayer, 'Isha');
    expect(current?.prayerDay, DateTime(2026, 11, 7));
  });

  test('04:49 returns yesterday Isha with the previous prayer day', () {
    final now = localInstant(dhaka, 2026, 11, 8, 4, 49, 0);
    final current = scheduleFor(dhaka, now).currentWindow(now);

    expect(current?.prayer, 'Isha');
    expect(current?.prayerDay, DateTime(2026, 11, 7));
  });

  test('exact Fajr start is current and the adjacent seconds are correct', () {
    final probe = localInstant(dhaka, 2026, 11, 8, 12, 0, 0);
    final schedule = scheduleFor(dhaka, probe);
    final fajr = schedule.windows.firstWhere(
      (window) => window.prayer == 'Fajr',
    );

    expect(
      schedule.currentWindow(fajr.start.subtract(const Duration(seconds: 1))),
      isNull,
    );
    expect(schedule.currentWindow(fajr.start)?.prayer, 'Fajr');
    expect(
      schedule
          .currentWindow(fajr.start.add(const Duration(seconds: 1)))
          ?.prayer,
      'Fajr',
    );
  });

  test('every window boundary is half-open', () {
    final now = localInstant(dhaka, 2026, 11, 8, 12, 0, 0);
    final schedule = scheduleFor(dhaka, now);

    for (final window in schedule.windows) {
      expect(
        schedule.currentWindow(window.start)?.prayer,
        window.prayer,
        reason: 'start of ${window.prayer} should be included',
      );
      expect(
        schedule
            .currentWindow(window.start.add(const Duration(seconds: 1)))
            ?.prayer,
        window.prayer,
      );
      final beforeEnd = schedule.currentWindow(
        window.end.subtract(const Duration(seconds: 1)),
      );
      expect(beforeEnd?.prayer, window.prayer);

      final atEnd = schedule.currentWindow(window.end);
      expect(atEnd?.prayer, isNot(window.prayer));
      expect(
        schedule
            .currentWindow(window.end.add(const Duration(seconds: 1)))
            ?.prayer,
        isNot(window.prayer),
      );
      final next = schedule.windows
          .where((candidate) => candidate.start == window.end)
          .firstOrNull;
      expect(atEnd?.prayer, next?.prayer);
    }
  });

  test('sunrise to Dhuhr has no current window and exposes Dhuhr next', () {
    final now = localInstant(dhaka, 2026, 11, 8, 12, 0, 0);
    final schedule = scheduleFor(dhaka, now);
    final fajr = schedule.windows.firstWhere(
      (window) => window.prayer == 'Fajr',
    );
    final dhuhr = schedule.windows.firstWhere(
      (window) => window.prayer == 'Dhuhr',
    );
    final between = fajr.end.add(dhuhr.start.difference(fajr.end) ~/ 2);

    expect(schedule.currentWindow(between), isNull);
    expect(schedule.nextWindow(between)?.prayer, 'Dhuhr');
    expect(schedule.nextWindow(between)?.start, dhuhr.start);
  });

  test('exact midnight still belongs to yesterday Isha', () {
    final now = localInstant(dhaka, 2026, 11, 8, 0, 0, 0);
    final current = scheduleFor(dhaka, now).currentWindow(now);

    expect(current?.prayer, 'Isha');
    expect(current?.prayerDay, DateTime(2026, 11, 7));
  });

  test('Islamic midnight is the instant midpoint of Maghrib and next Fajr', () {
    final now = localInstant(dhaka, 2026, 11, 8, 12, 0, 0);
    final schedule = scheduleFor(dhaka, now);
    final maghrib = schedule.windows.firstWhere(
      (window) =>
          window.prayer == 'Maghrib' &&
          window.prayerDay == DateTime(2026, 11, 8),
    );
    final isha = schedule.windows.firstWhere(
      (window) =>
          window.prayer == 'Isha' && window.prayerDay == DateTime(2026, 11, 8),
    );
    final nextFajr = schedule.windows.firstWhere(
      (window) =>
          window.prayer == 'Fajr' && window.prayerDay == DateTime(2026, 11, 9),
    );

    expect(
      isha.islamicMidnight,
      maghrib.start.add(nextFajr.start.difference(maghrib.start) ~/ 2),
    );
    expect(isha.end, nextFajr.start);
  });

  test('Isha marks an end on the next local date', () {
    final now = localInstant(dhaka, 2026, 11, 8, 12, 0, 0);
    final schedule = scheduleFor(dhaka, now);
    final isha = schedule.windows.firstWhere(
      (window) =>
          window.prayer == 'Isha' && window.prayerDay == DateTime(2026, 11, 8),
    );

    expect(isha.endsOnDifferentLocalDate, isTrue);
  });

  test(
    'Dhaka rollover state has the expected screen state at each requested time',
    () {
      final probes = <String, DateTime>{
        '00:30': localInstant(dhaka, 2026, 11, 8, 0, 30, 0),
        '04:49': localInstant(dhaka, 2026, 11, 8, 4, 49, 0),
        '04:50': localInstant(dhaka, 2026, 11, 8, 4, 50, 0),
        '06:07': localInstant(dhaka, 2026, 11, 8, 6, 7, 0),
        '06:08': localInstant(dhaka, 2026, 11, 8, 6, 8, 0),
        '11:50': localInstant(dhaka, 2026, 11, 8, 11, 50, 0),
        '23:59': localInstant(dhaka, 2026, 11, 8, 23, 59, 0),
      };

      for (final entry in probes.entries) {
        final schedule = scheduleFor(dhaka, entry.value);
        final current = schedule.currentWindow(entry.value);
        final next = schedule.nextWindow(entry.value);
        print(
          'Dhaka ${entry.key}: current=${current?.prayer ?? 'none'} '
          'prayerDay=${current?.prayerDay.toIso8601String() ?? '-'} '
          'next=${next?.prayer ?? 'none'}',
        );
      }
    },
  );

  for (final date in [DateTime(2026, 11, 1), DateTime(2026, 3, 8)]) {
    test('New York DST transition ${date.toIso8601String()} has no skipped '
        'or duplicated hour', () {
      final now = localInstant(
        newYork,
        date.year,
        date.month,
        date.day,
        12,
        0,
        0,
      );
      final schedule = scheduleFor(newYork, now);
      for (var index = 1; index < schedule.windows.length; index++) {
        expect(
          schedule.windows[index - 1].start.isBefore(
            schedule.windows[index].start,
          ),
          isTrue,
        );
      }

      final isha = schedule.windows.firstWhere(
        (window) => window.prayer == 'Isha' && window.prayerDay == date,
      );
      final maghrib = schedule.windows.firstWhere(
        (window) => window.prayer == 'Maghrib' && window.prayerDay == date,
      );
      final fajr = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Fajr' &&
            window.prayerDay == DateTime(date.year, date.month, date.day + 1),
      );
      final startLocal = newYork.toLocalTime(isha.start);
      final endLocal = newYork.toLocalTime(isha.end);
      final startOffset = startLocal.timeZoneOffset;
      final endOffset = endLocal.timeZoneOffset;
      final wallDuration =
          DateTime.utc(
            endLocal.year,
            endLocal.month,
            endLocal.day,
            endLocal.hour,
            endLocal.minute,
          ).difference(
            DateTime.utc(
              startLocal.year,
              startLocal.month,
              startLocal.day,
              startLocal.hour,
              startLocal.minute,
            ),
          );

      expect(isha.end, fajr.start);
      expect(
        isha.end.difference(isha.start),
        wallDuration - (endOffset - startOffset),
      );
      expect(
        isha.islamicMidnight,
        maghrib.start.add(fajr.start.difference(maghrib.start) ~/ 2),
      );
    });
  }

  test(
    'New York Islamic midnight is the UTC midpoint across fall-back DST',
    () {
      final now = localInstant(newYork, 2026, 11, 1, 12, 0, 0);
      final schedule = scheduleFor(newYork, now);
      final isha = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Isha' &&
            window.prayerDay == DateTime(2026, 11, 1),
      );
      final maghrib = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Maghrib' &&
            window.prayerDay == DateTime(2026, 11, 1),
      );
      final nextFajr = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Fajr' &&
            window.prayerDay == DateTime(2026, 11, 2),
      );

      expect(
        isha.islamicMidnight,
        maghrib.start.add(nextFajr.start.difference(maghrib.start) ~/ 2),
      );
    },
  );

  test('changing the selected city recomputes the current window', () async {
    var now = localInstant(dhaka, 2026, 11, 8, 0, 30, 0);
    final controller = PrayerLiveController(
      city: dhaka,
      calculationMethod: dhaka.automaticProfile.method,
      madhab: dhaka.automaticProfile.madhab,
      clock: () => now,
    );
    expect(controller.state.currentWindow?.prayerDay, DateTime(2026, 11, 7));

    controller.city = newYork;

    expect(controller.city, newYork);
    expect(controller.state.currentWindow, isNotNull);
    await controller.dispose();
  });

  test('resume after sleeping past a boundary shows the new window', () async {
    final initial = localInstant(dhaka, 2026, 11, 8, 4, 0, 0);
    var now = initial;
    final schedule = scheduleFor(dhaka, initial);
    final fajr = schedule.windows.firstWhere(
      (window) => window.prayer == 'Fajr',
    );
    final controller = PrayerLiveController(
      city: dhaka,
      calculationMethod: dhaka.automaticProfile.method,
      madhab: dhaka.automaticProfile.madhab,
      clock: () => now,
    );
    expect(controller.state.currentWindow?.prayer, 'Isha');

    now = fajr.start.add(const Duration(seconds: 1));
    controller.onAppResumed();

    expect(controller.state.currentWindow?.prayer, 'Fajr');
    await controller.dispose();
  });

  test('controller timer emits the new window after a boundary', () {
    fakeAsync((async) {
      final initial = localInstant(dhaka, 2026, 11, 8, 4, 0, 0);
      final schedule = scheduleFor(dhaka, initial);
      final emitted = <PrayerLiveState>[];
      final controller = PrayerLiveController(
        city: dhaka,
        calculationMethod: dhaka.automaticProfile.method,
        madhab: dhaka.automaticProfile.madhab,
        clock: () => initial.add(async.elapsed),
      );
      final subscription = controller.states.listen(emitted.add);

      final todayFajr = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Fajr' &&
            window.prayerDay == DateTime(2026, 11, 8),
      );
      async.elapse(
        todayFajr.start.difference(initial) + const Duration(seconds: 1),
      );

      expect(emitted.last.currentWindow?.prayer, 'Fajr');
      subscription.cancel();
      controller.dispose();
    });
  });

  test(
    'controller rebuilds the next evening after crossing local midnight',
    () async {
      var now = localInstant(dhaka, 2026, 11, 8, 23, 59, 0);
      final controller = PrayerLiveController(
        city: dhaka,
        calculationMethod: dhaka.automaticProfile.method,
        madhab: dhaka.automaticProfile.madhab,
        clock: () => now,
      );
      now = localInstant(dhaka, 2026, 11, 9, 20, 0, 0);
      controller.refresh();

      final schedule = scheduleFor(dhaka, now);
      final isha = schedule.windows.firstWhere(
        (window) =>
            window.prayer == 'Isha' &&
            window.prayerDay == DateTime(2026, 11, 9),
      );
      expect(isha.prayer, 'Isha');
      expect(isha.prayerDay, DateTime(2026, 11, 9));
      expect(isha.end, isNotNull);
      await controller.dispose();
    },
  );

  test(
    'city local date is used when the device instant is still UTC date before',
    () {
      final deviceUtcInstant = DateTime.utc(2026, 11, 7, 18, 30);
      final schedule = scheduleFor(dhaka, deviceUtcInstant);

      expect(schedule.localDate, DateTime(2026, 11, 8));
      expect(
        schedule.windows.any(
          (window) => window.prayerDay == DateTime(2026, 11, 8),
        ),
        isTrue,
      );
      expect(dhaka.localDateAt(deviceUtcInstant), DateTime(2026, 11, 8));
    },
  );

  void walk(PrayerCity city, DateTime start, int minutes) {
    var now = start;
    for (var index = 0; index <= minutes; index++) {
      final schedule = scheduleFor(city, now);
      final current = schedule.currentWindow(now);
      final nextBoundary = schedule.nextBoundary(now);
      final local = city.toLocalTime(now);
      final inGap = schedule.windows.any(
        (window) =>
            window.prayerDay == DateTime(local.year, local.month, local.day) &&
            window.prayer == 'Fajr' &&
            !now.isBefore(window.end) &&
            now.isBefore(
              schedule.windows
                  .firstWhere(
                    (candidate) =>
                        candidate.prayer == 'Dhuhr' &&
                        candidate.prayerDay ==
                            DateTime(local.year, local.month, local.day),
                  )
                  .start,
            ),
      );

      expect(current == null, inGap, reason: '$city at $now');
      expect(nextBoundary?.isAfter(now), isTrue, reason: '$city at $now');
      if (current != null) {
        expect(
          current.prayerDay,
          DateTime(
            city.toLocalTime(current.start).year,
            city.toLocalTime(current.start).month,
            city.toLocalTime(current.start).day,
          ),
        );
      }
      now = now.add(const Duration(minutes: 1));
    }
  }

  test('Dhaka walks 72 hours without stale or missing rollover state', () {
    walk(dhaka, localInstant(dhaka, 2026, 11, 7, 0, 0, 0), 72 * 60);
  });

  test(
    'New York walks across fall-back DST without stale or missing state',
    () {
      walk(newYork, localInstant(newYork, 2026, 10, 31, 0, 0, 0), 48 * 60);
    },
  );
}
