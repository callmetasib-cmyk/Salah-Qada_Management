import 'dart:math';
import 'package:flutter/material.dart';
import '../prayer/prayer_schedule.dart';
import '../prayer/prayer_tier.dart';

class SalahDialVisualizer extends StatelessWidget {
  const SalahDialVisualizer({
    super.key,
    required this.currentWindow,
    required this.nextWindow,
    required this.currentTier,
    required this.timeRemaining,
    required this.now,
  });

  final PrayerWindow? currentWindow;
  final PrayerWindow? nextWindow;
  final PrayerTier? currentTier;
  final Duration? timeRemaining;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResting = currentWindow == null;

    final tierColor = isResting
        ? Colors.grey.shade400
        : switch (currentTier) {
            PrayerTier.green => const Color(0xFF218739),
            PrayerTier.yellow => const Color(0xFFB77900),
            PrayerTier.red => const Color(0xFFC53929),
            null => Colors.grey.shade400,
          };

    final stateTitle = isResting
        ? 'Resting / Gap'
        : switch (currentTier) {
            PrayerTier.green => 'Optimal time',
            PrayerTier.yellow => 'Normal time',
            PrayerTier.red => 'Ending soon',
            null => 'Active',
          };

    final stateSubtitle = isResting
        ? 'Next: ${nextWindow?.prayer ?? 'None'}'
        : '${currentWindow!.prayer} in progress';

    // Calculate progress within active prayer window (0.0 to 1.0)
    double progress = 0.0;
    if (currentWindow != null) {
      final total = currentWindow!.end.difference(currentWindow!.start).inSeconds;
      final elapsed = now.toUtc().difference(currentWindow!.start).inSeconds;
      if (total > 0) {
        progress = (elapsed / total).clamp(0.0, 1.0);
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // The Circular Gauge with Needle
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _DialPainter(
                  progress: isResting ? null : progress,
                  tierColor: tierColor,
                  isResting: isResting,
                ),
              ),
            ),
            const SizedBox(width: 20),
            // The State and Time Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tierColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stateTitle,
                          style: TextStyle(
                            color: tierColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isResting
                        ? (nextWindow != null ? nextWindow!.prayer : 'None')
                        : currentWindow!.prayer,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    stateSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeRemaining == null
                        ? '--'
                        : '${_formatDuration(timeRemaining!)} remaining',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tierColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.tierColor,
    required this.isResting,
  });

  final double? progress;
  final Color tierColor;
  final bool isResting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    const strokeWidth = 10.0;

    final paintArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Total active sweep angle is 280 degrees, starting at 130 degrees (bottom-left)
    // The remaining 80 degrees is the grey resting buffer zone.
    const startAngle = 135 * (pi / 180);
    const activeSweep = 270 * (pi / 180);
    const restSweep = 70 * (pi / 180);
    const gap = 10 * (pi / 180);

    // Green zone (first ~30% of active)
    paintArc.color = const Color(0xFF218739);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      activeSweep * 0.30,
      false,
      paintArc,
    );

    // Yellow zone (middle ~45% of active)
    paintArc.color = const Color(0xFFB77900);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + activeSweep * 0.30,
      activeSweep * 0.45,
      false,
      paintArc,
    );

    // Red zone (final ~25% of active)
    paintArc.color = const Color(0xFFC53929);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + activeSweep * 0.75,
      activeSweep * 0.25,
      false,
      paintArc,
    );

    // Grey resting zone (buffer between prayer windows)
    paintArc.color = Colors.grey.shade300;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + activeSweep + gap,
      restSweep,
      false,
      paintArc,
    );

    // Calculate needle angle
    double needleAngle;
    if (isResting || progress == null) {
      // Needle rests in the center of the grey zone
      needleAngle = startAngle + activeSweep + gap + (restSweep / 2);
    } else {
      needleAngle = startAngle + (progress! * activeSweep);
    }

    // Draw the needle
    final needleLength = radius - strokeWidth;
    final needleEnd = Offset(
      center.dx + needleLength * cos(needleAngle),
      center.dy + needleLength * sin(needleAngle),
    );

    final needlePaint = Paint()
      ..color = tierColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleEnd, needlePaint);

    // Center pivot hub
    final hubPaint = Paint()..color = tierColor;
    canvas.drawCircle(center, 5.5, hubPaint);

    final hubInner = Paint()..color = Colors.white;
    canvas.drawCircle(center, 2.5, hubInner);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.tierColor != tierColor ||
        oldDelegate.isResting != isResting;
  }
}
