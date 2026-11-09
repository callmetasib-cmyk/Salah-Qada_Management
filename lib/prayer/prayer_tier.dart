enum PrayerTier {
  green,
  yellow,
  red,
}

PrayerTier classifyPrayerTier({
  required DateTime now,
  required DateTime prayerStart,
  required DateTime prayerEnd,
}) {
  if (!prayerEnd.isAfter(prayerStart)) {
    throw ArgumentError.value(
      prayerEnd,
      'prayerEnd',
      'Prayer end must be after prayer start.',
    );
  }

  if (now.isBefore(prayerStart) || now.isAfter(prayerEnd)) {
    throw ArgumentError.value(
      now,
      'now',
      'Current time must be within the prayer window.',
    );
  }

  final elapsed = now.difference(prayerStart);
  final windowLength = prayerEnd.difference(prayerStart);

  if (elapsed < windowLength ~/ 3) {
    return PrayerTier.green;
  }

  if (elapsed < windowLength * 2 ~/ 3) {
    return PrayerTier.yellow;
  }

  return PrayerTier.red;
}
