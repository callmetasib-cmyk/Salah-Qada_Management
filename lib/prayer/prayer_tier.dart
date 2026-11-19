enum PrayerTier {
  green,
  yellow,
  red,
}

const defaultEarlyZoneDuration = Duration(minutes: 30);
const defaultFinalZoneDuration = Duration(minutes: 30);

PrayerTier classifyPrayerTier({
  required DateTime now,
  required DateTime prayerStart,
  required DateTime prayerEnd,
  String? prayer,
  DateTime? islamicMidnight,
  Duration earlyZoneDuration = defaultEarlyZoneDuration,
  Duration finalZoneDuration = defaultFinalZoneDuration,
}) {
  if (!prayerEnd.isAfter(prayerStart)) {
    throw ArgumentError.value(
      prayerEnd,
      'prayerEnd',
      'Prayer end must be after prayer start.',
    );
  }

  // Windows are half-open: [prayerStart, prayerEnd)
  if (now.isBefore(prayerStart) || !now.isBefore(prayerEnd)) {
    throw ArgumentError.value(
      now,
      'now',
      'Current time must be within the prayer window.',
    );
  }

  final windowLength = prayerEnd.difference(prayerStart);

  // For Isha: optimal early zone, normal until Islamic midnight, then ending soon / red.
  if (prayer == 'Isha' && islamicMidnight != null) {
    var effectiveEarly = earlyZoneDuration;
    final untilMidnight = islamicMidnight.difference(prayerStart);
    if (untilMidnight > Duration.zero && effectiveEarly > untilMidnight ~/ 2) {
      effectiveEarly = untilMidnight ~/ 2;
    }

    if (now.isBefore(prayerStart.add(effectiveEarly))) {
      return PrayerTier.green;
    }
    if (now.isBefore(islamicMidnight)) {
      return PrayerTier.yellow;
    }
    return PrayerTier.red;
  }

  // Maghrib has a naturally short window (~60-75 min).
  // Dynamically allocate 15 min early, 15 min ending soon, and the rest normal.
  if (prayer == 'Maghrib') {
    final effectiveEarly = windowLength.inMinutes > 50
        ? const Duration(minutes: 15)
        : windowLength ~/ 4;
    final effectiveFinal = windowLength.inMinutes > 50
        ? const Duration(minutes: 15)
        : windowLength ~/ 4;

    if (now.isBefore(prayerStart.add(effectiveEarly))) {
      return PrayerTier.green;
    }
    if (!now.isBefore(prayerEnd.subtract(effectiveFinal))) {
      return PrayerTier.red;
    }
    return PrayerTier.yellow;
  }

  // Standard prayers with fixed early and final zones.
  // If window is short (< 90m), scale zones proportionally so yellow is preserved.
  var effectiveEarly = earlyZoneDuration;
  var effectiveFinal = finalZoneDuration;
  if (effectiveEarly + effectiveFinal >= windowLength) {
    effectiveEarly = windowLength ~/ 3;
    effectiveFinal = windowLength ~/ 3;
  }

  if (now.isBefore(prayerStart.add(effectiveEarly))) {
    return PrayerTier.green;
  }

  if (!now.isBefore(prayerEnd.subtract(effectiveFinal))) {
    return PrayerTier.red;
  }

  return PrayerTier.yellow;
}
