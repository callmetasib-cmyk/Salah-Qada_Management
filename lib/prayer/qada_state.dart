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
    this.source = 'current',
  });

  final String prayer;
  final String prayerDay;
  final DateTime completedAt;
  final bool isQada;
  final String source;
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

  DateTime? _targetCompletionDate;
  final Map<String, String> _customPairings = {}; // Qada prayer -> Assigned Current prayer
  final Map<String, int> _todayCompletedPlanQada = {}; // Track completed count for: 'YYYY-MM-DD_currentPrayer_qadaPrayer' -> count

  DateTime? get targetCompletionDate => _targetCompletionDate;
  Map<String, String> get customPairings => Map.unmodifiable(_customPairings);

  List<QadaItem> get qadaList => List.unmodifiable(_qadaList);
  int get totalPendingQada => _qadaList.where((item) => !item.isMadeUp).length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initialization != null) return _initialization!;
    try {
      _initialization = _loadFromDatabase();
      await _initialization!;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _loadFromDatabase() async {
    final records = await _database.getAllRecords();
    final automaticRecords = <String, PrayerRecord>{};

    for (final record in records) {
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

      if (record.source == 'manual') {
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
    }

    final completedQadaKeys = automaticRecords.values
        .where((r) => r.completed)
        .map((r) => '${r.prayerDay}_${r.prayer}')
        .toSet();

    for (final record in records) {
      if (record.source == 'current') {
        final key = '${record.prayerDay}_${record.prayer}';
        if (completedQadaKeys.contains(key) && record.completed) {
          await _database.setCompleted(record.id, false, null);
          _completedPrayers[key] = true;
          continue;
        }
        _completedPrayers[key] = record.completed;
      }
    }

    for (final record in automaticRecords.values) {
      if (record.completed) {
        _completedPrayers['${record.prayerDay}_${record.prayer}'] = true;
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

    final targetDateStr = await _database.getSetting('qada_target_date');
    if (targetDateStr != null) {
      _targetCompletionDate = DateTime.tryParse(targetDateStr);
    }
    const prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    for (final p in prayers) {
      final pairedWith = await _database.getSetting('pairing_$p');
      if (pairedWith != null && pairedWith.isNotEmpty) {
        _customPairings[p] = pairedWith;
      }
    }

    // Check today's completed qada to track which planned qadas are done today
    final todayStr = DateTime.now().toLocal().toIso8601String().substring(0, 10);
    final completedRecords = await _database.getCompletedRecords();
    for (final cr in completedRecords) {
      if (cr.source != 'current' && cr.completedAt != null) {
        final completedDateStr = cr.completedAt!.toLocal().toIso8601String().substring(0, 10);
        if (completedDateStr == todayStr) {
          final assignedCurrent = getAssignedCurrentPrayer(cr.prayer);
          final key = '${todayStr}_${assignedCurrent}_${cr.prayer}';
          _todayCompletedPlanQada[key] = (_todayCompletedPlanQada[key] ?? 0) + 1;
        }
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  String getAssignedCurrentPrayer(String qadaPrayer) {
    return _customPairings[qadaPrayer] ?? qadaPrayer;
  }

  Future<void> setTargetCompletionDate(DateTime? targetDate) async {
    _targetCompletionDate = targetDate;
    if (targetDate == null) {
      await _database.setSetting('qada_target_date', '');
    } else {
      await _database.setSetting('qada_target_date', targetDate.toIso8601String());
    }
    notifyListeners();
  }

  Future<void> setPrayerPairing(String qadaPrayer, String assignedCurrentPrayer) async {
    if (assignedCurrentPrayer == qadaPrayer) {
      _customPairings.remove(qadaPrayer);
      await _database.setSetting('pairing_$qadaPrayer', '');
    } else {
      _customPairings[qadaPrayer] = assignedCurrentPrayer;
      await _database.setSetting('pairing_$qadaPrayer', assignedCurrentPrayer);
    }
    notifyListeners();
  }

  int getPendingCountFor(String prayer) {
    return _qadaList.where((item) => !item.isMadeUp && item.prayer == prayer).length;
  }

  int getDailyQuotaFor(String qadaPrayer) {
    final pending = getPendingCountFor(qadaPrayer);
    if (pending == 0) return 0;
    if (_targetCompletionDate == null) return 1;

    final now = DateTime.now();
    final remainingDays = _targetCompletionDate!.difference(now).inDays + 1;
    if (remainingDays <= 0) return pending;
    return (pending / remainingDays).ceil().clamp(1, pending);
  }

  int getTodayCompletedPlanQadaCount(String currentPrayer, String qadaPrayer) {
    final todayStr = DateTime.now().toLocal().toIso8601String().substring(0, 10);
    return _todayCompletedPlanQada['${todayStr}_${currentPrayer}_$qadaPrayer'] ?? 0;
  }

  bool isPlanQadaDoneForToday(String currentPrayer, String qadaPrayer) {
    final completedCount = getTodayCompletedPlanQadaCount(currentPrayer, qadaPrayer);
    final quota = getDailyQuotaFor(qadaPrayer);
    final pending = getPendingCountFor(qadaPrayer);
    return completedCount >= quota || pending == 0;
  }

  List<String> getScheduledQadaFor(String currentPrayer) {
    const prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final result = <String>[];
    for (final qadaPrayer in prayers) {
      if (getAssignedCurrentPrayer(qadaPrayer) == currentPrayer) {
        if (getPendingCountFor(qadaPrayer) > 0 || getTodayCompletedPlanQadaCount(currentPrayer, qadaPrayer) > 0) {
          result.add(qadaPrayer);
        }
      }
    }
    return result;
  }

  Future<void> completePlanQada(String currentPrayer, String qadaPrayer, {int count = 1}) async {
    final todayStr = DateTime.now().toLocal().toIso8601String().substring(0, 10);
    final key = '${todayStr}_${currentPrayer}_$qadaPrayer';

    // Find the oldest uncompleted QadaItems for qadaPrayer up to count
    final itemsToComplete = _qadaList
        .where((element) => !element.isMadeUp && element.prayer == qadaPrayer)
        .take(count)
        .toList();

    for (final item in itemsToComplete) {
      await completeQadaItem(item);
    }

    _todayCompletedPlanQada[key] = (_todayCompletedPlanQada[key] ?? 0) + itemsToComplete.length;
    notifyListeners();
  }

  Future<String?> getThemeMode() => _database.getSetting('theme_mode');

  Future<void> setThemeMode(String mode) {
    return _database.setSetting('theme_mode', mode);
  }

  Future<void> setSelectedCity(String cityName) {
    return _database.setSetting('selected_city', cityName);
  }

  Future<String?> getSelectedCity() => _database.getSetting('selected_city');

  Future<void> setSettingsMode(String mode) {
    return _database.setSetting('settings_mode', mode);
  }

  Future<String?> getSettingsMode() => _database.getSetting('settings_mode');

  Future<void> setCalculationMethod(String method) {
    return _database.setSetting('manual_calculation_method', method);
  }

  Future<String?> getCalculationMethod() =>
      _database.getSetting('manual_calculation_method');

  Future<void> setMadhab(String madhab) {
    return _database.setSetting('manual_madhab', madhab);
  }

  Future<String?> getMadhab() => _database.getSetting('manual_madhab');

  Future<bool> isFirstLaunchCompleted() async {
    final value = await _database.getSetting('first_launch_completed');
    return value == 'true';
  }

  Future<void> setFirstLaunchCompleted() {
    return _database.setSetting('first_launch_completed', 'true');
  }

  Future<void> resetTodayCompletions() async {
    final nowStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    _completedPrayers.removeWhere((key, _) => key.startsWith(nowStr));

    final records = await _database.getAllRecords();
    for (final r in records) {
      if (r.source == 'current' && r.prayerDay == nowStr && r.completed) {
        await _database.setCompleted(r.id, false, null);
      }
    }
    notifyListeners();
  }

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
            source: record.source,
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

  Future<void> markMissedPrayerLate(String prayer, DateTime prayerDay) async {
    final key = _prayerKey(prayer, prayerDay);
    _completedPrayers[key] = true;

    final dateStr = prayerDay.toIso8601String().substring(0, 10);

    // If there is any 'current' record for this prayer today, ensure it is NOT marked completed
    final currentRecord = await _database.findRecord(
      prayer: prayer,
      prayerDay: dateStr,
      source: 'current',
    );
    if (currentRecord != null && currentRecord.completed) {
      await _database.setCompleted(currentRecord.id, false, null);
    }

    final matching = _qadaList
        .where((item) => item.prayer == prayer && item.date == dateStr)
        .firstOrNull;

    if (matching != null) {
      await completeQadaItem(matching);
    } else {
      final now = DateTime.now();
      final id = await _database.insertRecord(
        prayer: prayer,
        prayerDay: dateStr,
        source: 'automatic',
        createdAt: now,
        completed: true,
        completedAt: now,
      );
      _qadaList.add(
        QadaItem(
          prayer: prayer,
          date: dateStr,
          missedAt: now,
          source: 'automatic',
          recordId: id,
          isMadeUp: true,
        ),
      );
    }
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
    final firstLaunchDone = await isFirstLaunchCompleted();
    if (!firstLaunchDone) {
      // Clean start: don't auto-log Qada until onboarding is completed or dismissed
      return;
    }
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
    if (item.isMadeUp) return;
    item.isMadeUp = true;
    if (item.recordId != null) {
      await _database.setCompleted(item.recordId!, true, DateTime.now());
    }
    await _markRelatedPrayerDone(item);
    notifyListeners();
  }

  Future<void> completeAllQada() async {
    final now = DateTime.now();
    var changed = false;
    for (final item in _qadaList) {
      if (item.isMadeUp) continue;
      item.isMadeUp = true;
      changed = true;
      if (item.recordId != null) {
        await _database.setCompleted(item.recordId!, true, now);
      }
      await _markRelatedPrayerDone(item);
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _markRelatedPrayerDone(QadaItem item) async {
    if (item.date == 'unknown' || item.date == 'Date not recorded') return;
    final prayerDay = DateTime.tryParse(item.date);
    if (prayerDay == null) return;

    // Satisfy today's screen card without polluting on-time history
    _completedPrayers[_prayerKey(item.prayer, prayerDay)] = true;
  }

  Future<void> addManualQada(String prayer, {int count = 1}) async {
    await initialize();
    if (count <= 0) return;
    final clampedCount = count.clamp(1, 10000);
    final now = DateTime.now();

    final companions = [
      for (var index = 0; index < clampedCount; index++)
        PrayerRecordsCompanion.insert(
          prayer: prayer,
          prayerDay: 'unknown',
          source: 'manual',
          createdAt: now,
        ),
    ];

    final ids = await _database.batchInsertRecords(companions);
    for (final id in ids) {
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
        completed: completed,
        completedAt: completed ? DateTime.now() : null,
      );
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
