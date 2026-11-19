import 'package:flutter/foundation.dart';

import 'prayer_schedule.dart';
import '../storage/local_database.dart';

class QadaItem {
  QadaItem({
    required this.prayer,
    required this.date,
    required this.missedAt,
    required this.source,
    this.recordId,
    this.isMadeUp = false,
  });

  final String prayer;
  final String date;
  final DateTime missedAt;
  final String source;
  final int? recordId;
  bool isMadeUp;

  bool get isManual => source == 'manual';
}

class CompletedPrayer {
  const CompletedPrayer({
    required this.prayer,
    required this.prayerDay,
    required this.completedAt,
    required this.isQada,
  });

  final String prayer;
  final String prayerDay;
  final DateTime completedAt;
  final bool isQada;
}

class PrayerTrackerState extends ChangeNotifier {
  static final PrayerTrackerState instance = PrayerTrackerState._();
  PrayerTrackerState._();

  final Map<String, bool> _completedPrayers = {};
  final List<QadaItem> _qadaList = [];
  final LocalDatabase _database = LocalDatabase();
  bool _isInitialized = false;
  bool _isSyncing = false;
  Future<void>? _initialization;

  List<QadaItem> get qadaList => List.unmodifiable(_qadaList);
  int get totalPendingQada => _qadaList.where((item) => !item.isMadeUp).length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initialization != null) return _initialization!;
    _initialization = _loadFromDatabase();
    return _initialization!;
  }

  Future<void> _loadFromDatabase() async {
    final records = await _database.getAllRecords();
    final automaticRecords = <String, PrayerRecord>{};
    for (final record in records) {
      if (record.source == 'current') {
        _completedPrayers['${record.prayerDay}_${record.prayer}'] =
            record.completed;
        continue;
      }

      if (record.source == 'automatic') {
        final key = '${record.prayerDay}_${record.prayer}';
        final existing = automaticRecords[key];
        if (existing == null) {
          automaticRecords[key] = record;
        } else if (record.completed && !existing.completed) {
          await _database.deleteRecord(existing.id);
          automaticRecords[key] = record;
        } else {
          await _database.deleteRecord(record.id);
        }
        continue;
      }

      _qadaList.add(
        QadaItem(
          prayer: record.prayer,
          date: record.prayerDay,
          missedAt: record.createdAt,
          source: record.source,
          recordId: record.id,
          isMadeUp: record.completed,
        ),
      );
    }
    for (final record in automaticRecords.values) {
      _qadaList.add(
        QadaItem(
          prayer: record.prayer,
          date: record.prayerDay,
          missedAt: record.createdAt,
          source: record.source,
          recordId: record.id,
          isMadeUp: record.completed,
        ),
      );
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setSelectedCity(String cityName) {
    return _database.setSetting('selected_city', cityName);
  }

  Future<String?> getSelectedCity() => _database.getSetting('selected_city');

  Future<List<CompletedPrayer>> completedHistory() async {
    final records = await _database.getCompletedRecords();
    return [
      for (final record in records)
        if (record.completedAt != null)
          CompletedPrayer(
            prayer: record.prayer,
            prayerDay: record.prayerDay,
            completedAt: record.completedAt!,
            isQada: record.source != 'current',
          ),
    ];
  }

  String _prayerKey(String prayer, DateTime prayerDay) =>
      '${prayerDay.toIso8601String().substring(0, 10)}_$prayer';

  bool isPrayerDone(String prayer, DateTime prayerDay) {
    return _completedPrayers[_prayerKey(prayer, prayerDay)] ?? false;
  }

  Future<void> togglePrayer(
    String prayer,
    DateTime prayerDay, [
    PrayerStatus? status,
  ]) async {
    // Only the active prayer can be toggled directly. Missed prayers use the
    // explicit confirmation flow.
    if (status != null && status != PrayerStatus.current) return;

    final key = _prayerKey(prayer, prayerDay);
    final current = _completedPrayers[key] ?? false;
    _completedPrayers[key] = !current;
    await _saveCurrentPrayer(
      prayer: prayer,
      prayerDay: prayerDay,
      completed: !current,
    );

    // If marked done, remove from pending Qada for today if present
    if (!current) {
      final dateStr = prayerDay.toIso8601String().substring(0, 10);
      await _removePendingAutomaticQada(prayer, dateStr);
    }
    notifyListeners();
  }

  Future<void> markMissedPrayerDone(String prayer, DateTime prayerDay) async {
    final key = _prayerKey(prayer, prayerDay);
    _completedPrayers[key] = true;
    await _saveCurrentPrayer(
      prayer: prayer,
      prayerDay: prayerDay,
      completed: true,
    );
    final dateStr = prayerDay.toIso8601String().substring(0, 10);
    await _removePendingAutomaticQada(prayer, dateStr);
    notifyListeners();
  }

  Future<void> _removePendingAutomaticQada(String prayer, String date) async {
    final matching = _qadaList
        .where(
          (item) =>
              item.prayer == prayer &&
              item.date == date &&
              item.source == 'automatic' &&
              !item.isMadeUp,
        )
        .toList();
    for (final item in matching) {
      if (item.recordId != null) {
        await _database.deleteRecord(item.recordId!);
      }
      _qadaList.remove(item);
    }
  }

  Future<void> syncWithLiveStatus(
    List<PrayerWindow> displayWindows,
    Map<PrayerWindow, PrayerStatus> statuses,
  ) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _syncWithLiveStatus(displayWindows, statuses);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncWithLiveStatus(
    List<PrayerWindow> displayWindows,
    Map<PrayerWindow, PrayerStatus> statuses,
  ) async {
    await initialize();
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
            final recordId = await _saveQada(
              prayer: window.prayer,
              prayerDay: dateStr,
              source: 'automatic',
              createdAt: window.end,
            );
            _qadaList.add(
              QadaItem(
                prayer: window.prayer,
                date: dateStr,
                missedAt: window.end,
                source: 'automatic',
                recordId: recordId,
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

  Future<void> completeQadaItem(QadaItem item) async {
    item.isMadeUp = true;
    if (item.recordId != null) {
      await _database.setCompleted(item.recordId!, true, DateTime.now());
    }
    await _markRelatedPrayerDone(item);
    notifyListeners();
  }

  Future<void> completeAllQada() async {
    for (final item in _qadaList) {
      item.isMadeUp = true;
      if (item.recordId != null) {
        await _database.setCompleted(item.recordId!, true, DateTime.now());
      }
      await _markRelatedPrayerDone(item);
    }
    notifyListeners();
  }

  Future<void> _markRelatedPrayerDone(QadaItem item) async {
    if (item.date == 'unknown' || item.date == 'Date not recorded') return;
    final prayerDay = DateTime.tryParse(item.date);
    if (prayerDay == null) return;

    _completedPrayers[_prayerKey(item.prayer, prayerDay)] = true;
    await _saveCurrentPrayer(
      prayer: item.prayer,
      prayerDay: prayerDay,
      completed: true,
    );
  }

  Future<void> addManualQada(String prayer, {int count = 1}) async {
    await initialize();
    for (var index = 0; index < count; index++) {
      final now = DateTime.now();
      final id = await _database.insertRecord(
        prayer: prayer,
        prayerDay: 'unknown',
        source: 'manual',
        createdAt: now,
      );
      _qadaList.add(
        QadaItem(
          prayer: prayer,
          date: 'Date not recorded',
          missedAt: now,
          source: 'manual',
          recordId: id,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> removeManualQada(QadaItem item) async {
    if (!item.isManual || item.recordId == null) return;
    await _database.deleteRecord(item.recordId!);
    _qadaList.remove(item);
    notifyListeners();
  }

  Future<void> _saveCurrentPrayer({
    required String prayer,
    required DateTime prayerDay,
    required bool completed,
  }) async {
    final day = prayerDay.toIso8601String().substring(0, 10);
    final existing = await _database.findRecord(
      prayer: prayer,
      prayerDay: day,
      source: 'current',
    );
    if (existing == null) {
      await _database.insertRecord(
        prayer: prayer,
        prayerDay: day,
        source: 'current',
        createdAt: DateTime.now(),
      );
      final inserted = await _database.findRecord(
        prayer: prayer,
        prayerDay: day,
        source: 'current',
      );
      if (inserted != null) {
        await _database.setCompleted(
          inserted.id,
          completed,
          completed ? DateTime.now() : null,
        );
      }
      return;
    }
    await _database.setCompleted(
      existing.id,
      completed,
      completed ? DateTime.now() : null,
    );
  }

  Future<int> _saveQada({
    required String prayer,
    required String prayerDay,
    required String source,
    required DateTime createdAt,
  }) async {
    final existing = await _database.findRecord(
      prayer: prayer,
      prayerDay: prayerDay,
      source: source,
    );
    if (existing == null) {
      return _database.insertRecord(
        prayer: prayer,
        prayerDay: prayerDay,
        source: source,
        createdAt: createdAt,
      );
    }
    return existing.id;
  }
}
