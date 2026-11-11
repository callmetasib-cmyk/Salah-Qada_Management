import 'package:flutter/foundation.dart';
import 'prayer_schedule.dart';

class QadaItem {
  QadaItem({
    required this.prayer,
    required this.date,
    required this.missedAt,
    this.isMadeUp = false,
  });

  final String prayer;
  final String date;
  final DateTime missedAt;
  bool isMadeUp;
}

class PrayerTrackerState extends ChangeNotifier {
  static final PrayerTrackerState instance = PrayerTrackerState._();
  PrayerTrackerState._();

  final Map<String, bool> _completedPrayers = {};
  final List<QadaItem> _qadaList = [];

  List<QadaItem> get qadaList => List.unmodifiable(_qadaList);
  int get totalPendingQada => _qadaList.where((item) => !item.isMadeUp).length;

  String _prayerKey(String prayer, DateTime prayerDay) =>
      '${prayerDay.toIso8601String().substring(0, 10)}_$prayer';

  bool isPrayerDone(String prayer, DateTime prayerDay) {
    return _completedPrayers[_prayerKey(prayer, prayerDay)] ?? false;
  }

  void togglePrayer(String prayer, DateTime prayerDay, [PrayerStatus? status]) {
    // Cannot check or uncheck a prayer once its time has passed (becomes Qada)
    if (status == PrayerStatus.past) return;

    final key = _prayerKey(prayer, prayerDay);
    final current = _completedPrayers[key] ?? false;
    _completedPrayers[key] = !current;

    // If marked done, remove from pending Qada for today if present
    if (!current) {
      final dateStr = prayerDay.toIso8601String().substring(0, 10);
      _qadaList.removeWhere(
        (q) => q.prayer == prayer && q.date == dateStr && !q.isMadeUp,
      );
    }
    notifyListeners();
  }

  void syncWithLiveStatus(
    List<PrayerWindow> displayWindows,
    Map<PrayerWindow, PrayerStatus> statuses,
  ) {
    var changed = false;
    for (final window in displayWindows) {
      final status = statuses[window];
      if (status == PrayerStatus.past) {
        final key = _prayerKey(window.prayer, window.prayerDay);
        final isDone = _completedPrayers[key] ?? false;
        final dateStr = window.prayerDay.toIso8601String().substring(0, 10);

        if (!isDone) {
          final alreadyLogged = _qadaList.any(
            (q) => q.prayer == window.prayer && q.date == dateStr,
          );
          if (!alreadyLogged) {
            _qadaList.add(
              QadaItem(
                prayer: window.prayer,
                date: dateStr,
                missedAt: window.end,
              ),
            );
            changed = true;
          }
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void completeQadaItem(QadaItem item) {
    item.isMadeUp = true;
    notifyListeners();
  }

  void completeAllQada() {
    for (final item in _qadaList) {
      item.isMadeUp = true;
    }
    notifyListeners();
  }
}
