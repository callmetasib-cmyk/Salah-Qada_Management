import 'dart:async';

import 'package:adhan_dart/adhan_dart.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_tier.dart';

// placeholder, pending scholar review
const startSafetyMarginMinutes = 1;

enum PrayerStatus { past, current, upcoming }

class PrayerCalculationMethod {
  const PrayerCalculationMethod({required this.name, required this.parameters});

  final String name;
  final CalculationParameters Function() parameters;
}

enum PrayerSettingsMode { automatic, manual }

const calculationMethods = [
  PrayerCalculationMethod(
    name: 'University of Islamic Sciences, Karachi',
    parameters: CalculationMethodParameters.karachi,
  ),
  PrayerCalculationMethod(
    name: 'Muslim World League',
    parameters: CalculationMethodParameters.muslimWorldLeague,
  ),
  PrayerCalculationMethod(
    name: 'Egyptian General Authority of Survey',
    parameters: CalculationMethodParameters.egyptian,
  ),
  PrayerCalculationMethod(
    name: 'Umm al-Qura',
    parameters: CalculationMethodParameters.ummAlQura,
  ),
  PrayerCalculationMethod(
    name: 'Dubai',
    parameters: CalculationMethodParameters.dubai,
  ),
  PrayerCalculationMethod(
    name: 'North America (ISNA)',
    parameters: CalculationMethodParameters.northAmerica,
  ),
  PrayerCalculationMethod(
    name: 'Singapore',
    parameters: CalculationMethodParameters.singapore,
  ),
];

class PrayerCalculationProfile {
  const PrayerCalculationProfile({required this.method, required this.madhab});

  final PrayerCalculationMethod method;
  final Madhab madhab;
}

final _karachiHanafi = PrayerCalculationProfile(
  method: calculationMethods[0],
  madhab: Madhab.hanafi,
);
final _muslimWorldLeagueStandard = PrayerCalculationProfile(
  method: calculationMethods[1],
  madhab: Madhab.shafi,
);
final _egyptianStandard = PrayerCalculationProfile(
  method: calculationMethods[2],
  madhab: Madhab.shafi,
);
final _ummAlQuraStandard = PrayerCalculationProfile(
  method: calculationMethods[3],
  madhab: Madhab.shafi,
);
final _dubaiStandard = PrayerCalculationProfile(
  method: calculationMethods[4],
  madhab: Madhab.shafi,
);
final _isnaStandard = PrayerCalculationProfile(
  method: calculationMethods[5],
  madhab: Madhab.shafi,
);
final _singaporeStandard = PrayerCalculationProfile(
  method: calculationMethods[6],
  madhab: Madhab.shafi,
);

PrayerCalculationProfile profileForCountry(String countryCode) {
  return switch (countryCode) {
    'BD' || 'PK' => _karachiHanafi,
    'SA' => _ummAlQuraStandard,
    'AE' => _dubaiStandard,
    'EG' => _egyptianStandard,
    'US' || 'CA' => _isnaStandard,
    'MY' || 'ID' => _singaporeStandard,
    // Japan uses the general fallback until a verified local convention is selected.
    'JP' => _muslimWorldLeagueStandard,
    _ => _muslimWorldLeagueStandard,
  };
}

class PrayerCity {
  const PrayerCity({
    required this.name,
    required this.coordinates,
    required this.timeZone,
    required this.countryCode,
  });

  final String name;
  final Coordinates coordinates;
  final String timeZone;
  final String countryCode;

  PrayerCalculationProfile get automaticProfile =>
      profileForCountry(countryCode);

  DateTime toLocalTime(DateTime utcTime) {
    try {
      return tz.TZDateTime.from(utcTime.toUtc(), tz.getLocation(timeZone));
    } catch (_) {
      tzdata.initializeTimeZones();
      return tz.TZDateTime.from(utcTime.toUtc(), tz.getLocation(timeZone));
    }
  }

  DateTime localDateAt(DateTime instant) {
    final local = toLocalTime(instant);
    return DateTime.utc(local.year, local.month, local.day);
  }
}

class PrayerWindow {
  // The public parameter name keeps the window construction API readable.
  // ignore: prefer_initializing_formals
  const PrayerWindow({
    required this.prayer,
    required this.start,
    required this.end,
    required this.prayerDay,
    required this.islamicMidnight,
    required PrayerCity city,
  })
    // ignore: prefer_initializing_formals
    : _city = city;

  final String prayer;
  final DateTime start;
  final DateTime end;
  final DateTime prayerDay;
  final DateTime? islamicMidnight;

  bool get endsOnDifferentLocalDate {
    final startLocal = _localDate(start, _city);
    final endLocal = _localDate(end, _city);
    return startLocal != endLocal;
  }

  final PrayerCity _city;
}

DateTime _localDate(DateTime instant, PrayerCity city) {
  final local = city.toLocalTime(instant);
  return DateTime.utc(local.year, local.month, local.day);
}

class PrayerWindowSchedule {
  PrayerWindowSchedule({
    required this.city,
    required this.localDate,
    required this.windows,
  });

  final PrayerCity city;
  final DateTime localDate;
  final List<PrayerWindow> windows;

  PrayerWindow? currentWindow(DateTime now) {
    final instant = now.toUtc();
    for (final window in windows) {
      if (!instant.isBefore(window.start) && instant.isBefore(window.end)) {
        return window;
      }
    }
    return null;
  }

  PrayerWindow? nextWindow(DateTime now) {
    final instant = now.toUtc();
    for (final window in windows) {
      if (instant.isBefore(window.start)) {
        return window;
      }
    }
    return null;
  }

  DateTime? nextBoundary(DateTime now) {
    final instant = now.toUtc();
    final candidates = <DateTime>[
      for (final window in windows)
        if (window.start.isAfter(instant)) window.start,
      for (final window in windows)
        if (window.end.isAfter(instant)) window.end,
    ]..sort();
    return candidates.isEmpty ? null : candidates.first;
  }
}

class PrayerLiveState {
  const PrayerLiveState({
    required this.now,
    required this.schedule,
    required this.currentWindow,
    required this.nextWindow,
    required this.timeRemaining,
    required this.nextBoundary,
    required this.nextWindowStartLocal,
    required this.displayWindows,
    required this.statuses,
    required this.tiers,
    required this.localTimes,
  });

  final DateTime now;
  final PrayerWindowSchedule schedule;
  final PrayerWindow? currentWindow;
  final PrayerWindow? nextWindow;
  final Duration? timeRemaining;
  final DateTime? nextBoundary;
  final DateTime? nextWindowStartLocal;
  final List<PrayerWindow> displayWindows;
  final Map<PrayerWindow, PrayerStatus> statuses;
  final Map<PrayerWindow, PrayerTier?> tiers;
  final Map<PrayerWindow, ({DateTime start, DateTime end})> localTimes;
}

typedef PrayerClock = DateTime Function();

class PrayerLiveController {
  factory PrayerLiveController({
    required PrayerCity city,
    required PrayerCalculationMethod calculationMethod,
    required Madhab madhab,
    PrayerClock clock = DateTime.now,
    bool includeStartSafetyMargin = true,
  }) => PrayerLiveController._(
    city: city,
    calculationMethod: calculationMethod,
    madhab: madhab,
    clock: clock,
    includeStartSafetyMargin: includeStartSafetyMargin,
  );

  PrayerLiveController._({
    required this._city,
    required this._calculationMethod,
    required this._madhab,
    required this._clock,
    required this._includeStartSafetyMargin,
  }) {
    refresh();
    _startTicker();
  }

  PrayerCity _city;
  PrayerCalculationMethod _calculationMethod;
  Madhab _madhab;
  final PrayerClock _clock;
  final bool _includeStartSafetyMargin;
  final _states = StreamController<PrayerLiveState>.broadcast();
  Timer? _boundaryTimer;
  Timer? _tickerTimer;
  PrayerLiveState? _state;

  PrayerCity get city => _city;
  PrayerLiveState get state => _state!;
  Stream<PrayerLiveState> get states => _states.stream;

  set city(PrayerCity value) {
    _city = value;
    refresh();
  }

  set calculationMethod(PrayerCalculationMethod value) {
    _calculationMethod = value;
    refresh();
  }

  set madhab(Madhab value) {
    _madhab = value;
    refresh();
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = _clock().toUtc();
    if (_state != null &&
        _state!.nextBoundary != null &&
        !now.isBefore(_state!.nextBoundary!)) {
      refresh();
      return;
    }

    if (_state == null) return;

    final schedule = _state!.schedule;
    final current = schedule.currentWindow(now);
    final next = schedule.nextWindow(now);
    final nextStart = current == null ? next?.start : current.end;
    final remaining = nextStart == null
        ? null
        : nextStart.difference(now).isNegative
        ? Duration.zero
        : nextStart.difference(now);

    final displayWindows = _state!.displayWindows;
    final statuses = <PrayerWindow, PrayerStatus>{
      for (final window in displayWindows)
        window: _statusForWindow(
          now: now,
          start: window.start,
          end: window.end,
        ),
    };
    final tiers = <PrayerWindow, PrayerTier?>{
      for (final window in displayWindows)
        window: _tierForWindow(now: now, window: window),
    };

    _state = PrayerLiveState(
      now: now,
      schedule: schedule,
      currentWindow: current,
      nextWindow: next,
      timeRemaining: remaining,
      nextBoundary: _state!.nextBoundary,
      nextWindowStartLocal: _state!.nextWindowStartLocal,
      displayWindows: displayWindows,
      statuses: statuses,
      tiers: tiers,
      localTimes: _state!.localTimes,
    );
    if (!_states.isClosed) {
      _states.add(_state!);
    }
  }

  void refresh() {
    final now = _clock().toUtc();
    final schedule = buildPrayerWindowSchedule(
      city: _city,
      now: now,
      calculationMethod: _calculationMethod,
      madhab: _madhab,
      includeStartSafetyMargin: _includeStartSafetyMargin,
    );
    final current = schedule.currentWindow(now);
    final next = schedule.nextWindow(now);
    final boundary = schedule.nextBoundary(now);
    final nextStart = current == null ? next?.start : current.end;
    final remaining = nextStart == null
        ? null
        : nextStart.difference(now).isNegative
        ? Duration.zero
        : nextStart.difference(now);
    final activePrayerDay =
        current?.prayerDay ?? next?.prayerDay ?? schedule.localDate;
    final displayWindows = schedule.windows
        .where((window) => window.prayerDay == activePrayerDay)
        .toList();
    final statuses = <PrayerWindow, PrayerStatus>{
      for (final window in displayWindows)
        window: _statusForWindow(
          now: now,
          start: window.start,
          end: window.end,
        ),
    };
    final tiers = <PrayerWindow, PrayerTier?>{
      for (final window in displayWindows)
        window: _tierForWindow(now: now, window: window),
    };
    final localTimes = <PrayerWindow, ({DateTime start, DateTime end})>{
      for (final window in displayWindows)
        window: (
          start: _city.toLocalTime(window.start),
          end: _city.toLocalTime(window.end),
        ),
    };
    _state = PrayerLiveState(
      now: now,
      schedule: schedule,
      currentWindow: current,
      nextWindow: next,
      timeRemaining: remaining,
      nextBoundary: boundary,
      nextWindowStartLocal: next == null ? null : _city.toLocalTime(next.start),
      displayWindows: displayWindows,
      statuses: statuses,
      tiers: tiers,
      localTimes: localTimes,
    );
    _scheduleBoundary(boundary, now);
    if (!_states.isClosed) {
      _states.add(_state!);
    }
  }

  void onAppResumed() => refresh();

  void _scheduleBoundary(DateTime? boundary, DateTime now) {
    _boundaryTimer?.cancel();
    if (boundary == null) return;
    final delay = boundary.difference(now);
    _boundaryTimer = Timer(delay.isNegative ? Duration.zero : delay, refresh);
  }

  Future<void> dispose() async {
    _tickerTimer?.cancel();
    _boundaryTimer?.cancel();
    await _states.close();
  }
}

DateTime roundPrayerStart(DateTime rawTime, {bool includeSafetyMargin = true}) {
  final adjusted = rawTime.toUtc().add(
    Duration(minutes: includeSafetyMargin ? startSafetyMarginMinutes : 0),
  );
  return DateTime.fromMillisecondsSinceEpoch(
    ((adjusted.millisecondsSinceEpoch + Duration.millisecondsPerMinute - 1) ~/
            Duration.millisecondsPerMinute) *
        Duration.millisecondsPerMinute,
    isUtc: true,
  );
}

DateTime roundPrayerEnd(DateTime rawTime) {
  final utcTime = rawTime.toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    (utcTime.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute) *
        Duration.millisecondsPerMinute,
    isUtc: true,
  );
}

final starterCities = [
  PrayerCity(
    name: 'New York',
    coordinates: Coordinates(40.7128, -74.0060),
    timeZone: 'America/New_York',
    countryCode: 'US',
  ),
  PrayerCity(
    name: 'Osaka',
    coordinates: Coordinates(34.6937, 135.5023),
    timeZone: 'Asia/Tokyo',
    countryCode: 'JP',
  ),
  PrayerCity(
    name: 'Berlin',
    coordinates: Coordinates(52.5200, 13.4050),
    timeZone: 'Europe/Berlin',
    countryCode: 'DE',
  ),
  PrayerCity(
    name: 'Dhaka',
    coordinates: Coordinates(23.8103, 90.4125),
    timeZone: 'Asia/Dhaka',
    countryCode: 'BD',
  ),
  PrayerCity(
    name: 'London',
    coordinates: Coordinates(51.5074, -0.1278),
    timeZone: 'Europe/London',
    countryCode: 'GB',
  ),
  PrayerCity(
    name: 'Paris',
    coordinates: Coordinates(48.8566, 2.3522),
    timeZone: 'Europe/Paris',
    countryCode: 'FR',
  ),
  PrayerCity(
    name: 'Toronto',
    coordinates: Coordinates(43.6532, -79.3832),
    timeZone: 'America/Toronto',
    countryCode: 'CA',
  ),
  PrayerCity(
    name: 'Los Angeles',
    coordinates: Coordinates(34.0522, -118.2437),
    timeZone: 'America/Los_Angeles',
    countryCode: 'US',
  ),
  PrayerCity(
    name: 'Chicago',
    coordinates: Coordinates(41.8781, -87.6298),
    timeZone: 'America/Chicago',
    countryCode: 'US',
  ),
  PrayerCity(
    name: 'Istanbul',
    coordinates: Coordinates(41.0082, 28.9784),
    timeZone: 'Europe/Istanbul',
    countryCode: 'TR',
  ),
  PrayerCity(
    name: 'Karachi',
    coordinates: Coordinates(24.8607, 67.0011),
    timeZone: 'Asia/Karachi',
    countryCode: 'PK',
  ),
  PrayerCity(
    name: 'Cairo',
    coordinates: Coordinates(30.0444, 31.2357),
    timeZone: 'Africa/Cairo',
    countryCode: 'EG',
  ),
  PrayerCity(
    name: 'Riyadh',
    coordinates: Coordinates(24.7136, 46.6753),
    timeZone: 'Asia/Riyadh',
    countryCode: 'SA',
  ),
  PrayerCity(
    name: 'Dubai',
    coordinates: Coordinates(25.2048, 55.2708),
    timeZone: 'Asia/Dubai',
    countryCode: 'AE',
  ),
  PrayerCity(
    name: 'Kuala Lumpur',
    coordinates: Coordinates(3.1390, 101.6869),
    timeZone: 'Asia/Kuala_Lumpur',
    countryCode: 'MY',
  ),
  PrayerCity(
    name: 'Jakarta',
    coordinates: Coordinates(-6.2088, 106.8456),
    timeZone: 'Asia/Jakarta',
    countryCode: 'ID',
  ),
];

PrayerWindowSchedule buildPrayerWindowSchedule({
  required PrayerCity city,
  required DateTime now,
  required PrayerCalculationMethod calculationMethod,
  required Madhab madhab,
  bool includeStartSafetyMargin = true,
}) {
  final localToday = city.localDateAt(now);
  final windows = <PrayerWindow>[];
  for (var offset = -1; offset <= 1; offset++) {
    final prayerDay = DateTime.utc(
      localToday.year,
      localToday.month,
      localToday.day + offset,
    );
    windows.addAll(
      _buildPrayerWindowsForDay(
        city: city,
        prayerDay: prayerDay,
        calculationMethod: calculationMethod,
        madhab: madhab,
        includeStartSafetyMargin: includeStartSafetyMargin,
      ),
    );
  }
  windows.sort((a, b) => a.start.compareTo(b.start));
  return PrayerWindowSchedule(
    city: city,
    localDate: localToday,
    windows: windows,
  );
}

List<PrayerWindow> _buildPrayerWindowsForDay({
  required PrayerCity city,
  required DateTime prayerDay,
  required PrayerCalculationMethod calculationMethod,
  required Madhab madhab,
  required bool includeStartSafetyMargin,
}) {
  final rawTimes = calculateRawPrayerTimes(
    city: city,
    date: prayerDay,
    calculationMethod: calculationMethod,
    madhab: madhab,
  );
  final starts = <String, DateTime>{
    'Fajr': roundPrayerStart(
      rawTimes['Fajr']!,
      includeSafetyMargin: includeStartSafetyMargin,
    ),
    'Dhuhr': roundPrayerStart(
      rawTimes['Dhuhr']!,
      includeSafetyMargin: includeStartSafetyMargin,
    ),
    'Asr': roundPrayerStart(
      rawTimes['Asr']!,
      includeSafetyMargin: includeStartSafetyMargin,
    ),
    'Maghrib': roundPrayerStart(
      rawTimes['Maghrib']!,
      includeSafetyMargin: includeStartSafetyMargin,
    ),
    'Isha': roundPrayerStart(
      rawTimes['Isha']!,
      includeSafetyMargin: includeStartSafetyMargin,
    ),
  };
  final sunrise = roundPrayerEnd(rawTimes['Sunrise']!);
  final tomorrowFajr = roundPrayerStart(
    rawTimes['FajrTomorrow']!,
    includeSafetyMargin: includeStartSafetyMargin,
  );
  final boundaries = <String, DateTime>{
    'Fajr': sunrise,
    'Dhuhr': starts['Asr']!,
    'Asr': starts['Maghrib']!,
    'Maghrib': starts['Isha']!,
    'Isha': tomorrowFajr,
  };
  final islamicMidnight = starts['Maghrib']!.add(
    tomorrowFajr.difference(starts['Maghrib']!) ~/ 2,
  );

  return starts.entries
      .map(
        (entry) => PrayerWindow(
          prayer: entry.key,
          start: entry.value.toUtc(),
          end: boundaries[entry.key]!.toUtc(),
          prayerDay: prayerDay,
          islamicMidnight: entry.key == 'Isha' ? islamicMidnight : null,
          city: city,
        ),
      )
      .toList();
}

Map<String, DateTime> calculateRawPrayerTimes({
  required PrayerCity city,
  required DateTime date,
  required PrayerCalculationMethod calculationMethod,
  Madhab madhab = Madhab.shafi,
}) {
  final parameters = calculationMethod.parameters()
    ..madhab = madhab
    ..highLatitudeRule = HighLatitudeRule.twilightAngle;
  final times = PrayerTimes(
    coordinates: city.coordinates,
    date: DateTime.utc(date.year, date.month, date.day),
    calculationParameters: parameters,
    precision: true,
  );
  final tomorrow = PrayerTimes(
    coordinates: city.coordinates,
    date: DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).add(const Duration(days: 1)),
    calculationParameters: parameters,
    precision: true,
  );

  return {
    'Fajr': times.fajr,
    'Sunrise': times.sunrise,
    'Dhuhr': times.dhuhr,
    'Asr': times.asr,
    'Maghrib': times.maghrib,
    'Isha': times.isha,
    'FajrTomorrow': tomorrow.fajr,
  };
}

PrayerStatus _statusForWindow({
  required DateTime now,
  required DateTime start,
  required DateTime end,
}) {
  if (now.isBefore(start)) {
    return PrayerStatus.upcoming;
  }

  if (!now.isBefore(end)) {
    return PrayerStatus.past;
  }

  return PrayerStatus.current;
}

PrayerTier? _tierForWindow({
  required DateTime now,
  required PrayerWindow window,
}) {
  if (now.isBefore(window.start) || !now.isBefore(window.end)) {
    return null;
  }

  return classifyPrayerTier(
    now: now,
    prayerStart: window.start,
    prayerEnd: window.end,
    prayer: window.prayer,
    islamicMidnight: window.islamicMidnight,
  );
}
