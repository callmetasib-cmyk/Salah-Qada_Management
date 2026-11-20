enum PrayerTier {
  green,
  yellow,
  red,
}

const defaultEarlyZoneDuration = Duration(minutes: 30);
const defaultFinalZoneDuration = Duration(minutes: 30);

class PrayerTierFractions {
  const PrayerTierFractions({
    required this.greenFraction,
    required this.yellowFraction,
    required this.redFraction,
  });

  final double greenFraction;
  final double yellowFraction;
  final double redFraction;
}

PrayerTierFractions calculateTierFractions({
  required DateTime prayerStart,
  required DateTime prayerEnd,
  String? prayer,
  DateTime? islamicMidnight,
  Duration earlyZoneDuration = defaultEarlyZoneDuration,
  Duration finalZoneDuration = defaultFinalZoneDuration,
}) {
  final totalSeconds = prayerEnd.difference(prayerStart).inSeconds;
  if (totalSeconds <= 0) {
    return const PrayerTierFractions(
      greenFraction: 0.33,
      yellowFraction: 0.34,
      redFraction: 0.33,
    );
  }

  final windowLength = prayerEnd.difference(prayerStart);

  if (prayer == 'Isha' && islamicMidnight != null) {
    var effectiveEarly = earlyZoneDuration;
    final untilMidnight = islamicMidnight.difference(prayerStart);
    if (untilMidnight > Duration.zero && effectiveEarly > untilMidnight ~/ 2) {
      effectiveEarly = untilMidnight ~/ 2;
    }

    final greenSeconds = effectiveEarly.inSeconds.clamp(0, totalSeconds);
    final yellowSeconds = (islamicMidnight.difference(prayerStart).inSeconds -
            greenSeconds)
        .clamp(0, totalSeconds - greenSeconds);
    final redSeconds = (totalSeconds - greenSeconds - yellowSeconds)
        .clamp(0, totalSeconds);

    return PrayerTierFractions(
      greenFraction: greenSeconds / totalSeconds,
      yellowFraction: yellowSeconds / totalSeconds,
      redFraction: redSeconds / totalSeconds,
    );
  }

  if (prayer == 'Maghrib') {
    final effectiveEarly = windowLength.inMinutes > 50
        ? const Duration(minutes: 15)
        : windowLength ~/ 4;
    final effectiveFinal = windowLength.inMinutes > 50
        ? const Duration(minutes: 15)
        : windowLength ~/ 4;

    final greenSeconds = effectiveEarly.inSeconds.clamp(0, totalSeconds);
    final redSeconds = effectiveFinal.inSeconds.clamp(
      0,
      totalSeconds - greenSeconds,
    );
    final yellowSeconds = totalSeconds - greenSeconds - redSeconds;

    return PrayerTierFractions(
      greenFraction: greenSeconds / totalSeconds,
      yellowFraction: yellowSeconds / totalSeconds,
      redFraction: redSeconds / totalSeconds,
    );
  }

  // Standard prayers
  var effectiveEarly = earlyZoneDuration;
  var effectiveFinal = finalZoneDuration;
  if (effectiveEarly + effectiveFinal >= windowLength) {
    effectiveEarly = windowLength ~/ 3;
    effectiveFinal = windowLength ~/ 3;
  }

  final greenSeconds = effectiveEarly.inSeconds.clamp(0, totalSeconds);
  final redSeconds = effectiveFinal.inSeconds.clamp(
    0,
    totalSeconds - greenSeconds,
  );
  final yellowSeconds = totalSeconds - greenSeconds - redSeconds;

  return PrayerTierFractions(
    greenFraction: greenSeconds / totalSeconds,
    yellowFraction: yellowSeconds / totalSeconds,
    redFraction: redSeconds / totalSeconds,
  );
}

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

    // Warning zone takes precedence for short windows
    if (!now.isBefore(prayerEnd.subtract(effectiveFinal))) {
      return PrayerTier.red;
    }
    if (now.isBefore(prayerStart.add(effectiveEarly))) {
      return PrayerTier.green;
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

  // Warning zone takes precedence for short windows
  if (!now.isBefore(prayerEnd.subtract(effectiveFinal))) {
    return PrayerTier.red;
  }

  if (now.isBefore(prayerStart.add(effectiveEarly))) {
    return PrayerTier.green;
  }

  return PrayerTier.yellow;
}
