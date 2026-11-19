import 'dart:async';

import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'prayer/prayer_schedule.dart';
import 'prayer/prayer_tier.dart';
import 'prayer/qada_state.dart';
import 'widgets/salah_dial_visualizer.dart';

void main() {
  tzdata.initializeTimeZones();
  runApp(const SalahQadaApp());
}

class SalahQadaApp extends StatelessWidget {
  const SalahQadaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF176B58);

    return MaterialApp(
      title: 'Salah & Qada',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAF8),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  PrayerCity _selectedCity = starterCities.first;
  PrayerSettingsMode _settingsMode = PrayerSettingsMode.automatic;
  PrayerCalculationMethod _manualCalculationMethod = calculationMethods[1];
  Madhab _manualMadhab = Madhab.shafi;

  PrayerCalculationProfile get _automaticProfile =>
      _selectedCity.automaticProfile;

  PrayerCalculationMethod get _selectedCalculationMethod =>
      _settingsMode == PrayerSettingsMode.automatic
      ? _automaticProfile.method
      : _manualCalculationMethod;

  Madhab get _selectedMadhab => _settingsMode == PrayerSettingsMode.automatic
      ? _automaticProfile.madhab
      : _manualMadhab;

  @override
  void initState() {
    super.initState();
    _loadLocalState();
  }

  Future<void> _loadLocalState() async {
    final tracker = PrayerTrackerState.instance;
    await tracker.initialize();
    final cityName = await tracker.getSelectedCity();
    if (!mounted) return;
    final matches = starterCities.where((item) => item.name == cityName);
    final city = matches.isEmpty ? null : matches.first;
    if (!mounted) return;
    setState(() {
      if (city != null) _selectedCity = city;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PrayerHomeScreen(
        city: _selectedCity,
        calculationMethod: _selectedCalculationMethod,
        madhab: _selectedMadhab,
      ),
      const QadaScreen(),
      const HistoryScreen(),
      SettingsScreen(
        selectedCity: _selectedCity,
        settingsMode: _settingsMode,
        selectedCalculationMethod: _selectedCalculationMethod,
        selectedMadhab: _selectedMadhab,
        automaticProfile: _automaticProfile,
        onCityChanged: (city) {
          setState(() => _selectedCity = city);
          unawaited(PrayerTrackerState.instance.setSelectedCity(city.name));
        },
        onSettingsModeChanged: (mode) => setState(() {
          _settingsMode = mode;
        }),
        onCalculationMethodChanged: (method) => setState(() {
          _manualCalculationMethod = method;
          _settingsMode = PrayerSettingsMode.manual;
        }),
        onMadhabChanged: (madhab) => setState(() {
          _manualMadhab = madhab;
          _settingsMode = PrayerSettingsMode.manual;
        }),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Salah',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Qada',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

const _debugPrayerClockOverride = String.fromEnvironment('PRAYER_DEBUG_NOW');
DateTime? _debugClockBase;
DateTime? _debugClockRealStart;

DateTime _prayerClock() {
  if (!kReleaseMode && _debugPrayerClockOverride.isNotEmpty) {
    final override = _debugClockBase ??= DateTime.tryParse(
      _debugPrayerClockOverride,
    );
    if (override != null) {
      _debugClockRealStart ??= DateTime.now();
      final elapsed = DateTime.now().difference(_debugClockRealStart!);
      return override.add(elapsed);
    }
  }
  return DateTime.now();
}

class PrayerHomeScreen extends StatefulWidget {
  const PrayerHomeScreen({
    super.key,
    required this.city,
    required this.calculationMethod,
    required this.madhab,
  });

  final PrayerCity city;
  final PrayerCalculationMethod calculationMethod;
  final Madhab madhab;

  @override
  State<PrayerHomeScreen> createState() => _PrayerHomeScreenState();
}

class _PrayerHomeScreenState extends State<PrayerHomeScreen>
    with WidgetsBindingObserver {
  late PrayerLiveController _controller;
  late StreamSubscription<PrayerLiveState> _stateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PrayerLiveController(
      city: widget.city,
      calculationMethod: widget.calculationMethod,
      madhab: widget.madhab,
      clock: _prayerClock,
    );
    _stateSubscription = _controller.states.listen((liveState) {
      unawaited(
        PrayerTrackerState.instance.syncWithLiveStatus(
          liveState.displayWindows,
          liveState.statuses,
        ),
      );
    });
    unawaited(
      PrayerTrackerState.instance.syncWithLiveStatus(
        _controller.state.displayWindows,
        _controller.state.statuses,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PrayerHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city) {
      _controller.city = widget.city;
    }
    if (oldWidget.calculationMethod != widget.calculationMethod) {
      _controller.calculationMethod = widget.calculationMethod;
    }
    if (oldWidget.madhab != widget.madhab) {
      _controller.madhab = widget.madhab;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSubscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrayerTrackerState.instance,
      builder: (context, _) {
        return StreamBuilder<PrayerLiveState>(
          stream: _controller.states,
          initialData: _controller.state,
          builder: (context, snapshot) {
            final liveState = snapshot.data!;
            final current = liveState.currentWindow;
            final theme = Theme.of(context);

            return Scaffold(
              appBar: AppBar(
                title: const Text('Salah & Qada'),
                backgroundColor: Colors.transparent,
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Text(
                      'Assalamu alaikum',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Stay mindful of each salah and keep your qada journey organized.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SalahDialVisualizer(
                      currentWindow: current,
                      nextWindow: liveState.nextWindow,
                      currentTier: current == null
                          ? null
                          : liveState.tiers[current],
                      timeRemaining: liveState.timeRemaining,
                      now: liveState.now,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prayer times',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.city.name} · ${widget.calculationMethod.name} · '
                              '${widget.madhab == Madhab.hanafi ? 'Hanafi' : 'Standard'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Today\'s prayers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...liveState.displayWindows.map((prayer) {
                      final isDone = PrayerTrackerState.instance.isPrayerDone(
                        prayer.prayer,
                        prayer.prayerDay,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PrayerCard(
                          prayer: prayer,
                          localTimes: liveState.localTimes[prayer]!,
                          status: liveState.statuses[prayer]!,
                          tier: liveState.tiers[prayer],
                          isDone: isDone,
                          onToggleDone: () {
                            PrayerTrackerState.instance.togglePrayer(
                              prayer.prayer,
                              prayer.prayerDay,
                              liveState.statuses[prayer],
                            );
                          },
                          onConfirmMissed: () {
                            PrayerTrackerState.instance.markMissedPrayerDone(
                              prayer.prayer,
                              prayer.prayerDay,
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.selectedCity,
    required this.settingsMode,
    required this.selectedCalculationMethod,
    required this.selectedMadhab,
    required this.automaticProfile,
    required this.onCityChanged,
    required this.onSettingsModeChanged,
    required this.onCalculationMethodChanged,
    required this.onMadhabChanged,
  });

  final PrayerCity selectedCity;
  final PrayerSettingsMode settingsMode;
  final PrayerCalculationMethod selectedCalculationMethod;
  final Madhab selectedMadhab;
  final PrayerCalculationProfile automaticProfile;
  final ValueChanged<PrayerCity> onCityChanged;
  final ValueChanged<PrayerSettingsMode> onSettingsModeChanged;
  final ValueChanged<PrayerCalculationMethod> onCalculationMethodChanged;
  final ValueChanged<Madhab> onMadhabChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Text(
            'Prayer settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a location and decide whether prayer times should use '
            'regional recommendations or your own settings.',
          ),
          const SizedBox(height: 20),
          _CitySelector(
            selectedCity: selectedCity,
            onCityChanged: onCityChanged,
          ),
          _CalculationSelector(
            selectedCity: selectedCity,
            settingsMode: settingsMode,
            selectedCalculationMethod: selectedCalculationMethod,
            selectedMadhab: selectedMadhab,
            automaticProfile: automaticProfile,
            onSettingsModeChanged: onSettingsModeChanged,
            onCalculationMethodChanged: onCalculationMethodChanged,
            onMadhabChanged: onMadhabChanged,
          ),
        ],
      ),
    );
  }
}

class _CitySelector extends StatelessWidget {
  const _CitySelector({
    required this.selectedCity,
    required this.onCityChanged,
  });

  final PrayerCity selectedCity;
  final ValueChanged<PrayerCity> onCityChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('Choose a city'),
        subtitle: Text(selectedCity.name),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('City')),
                DataColumn(label: Text('IANA time zone')),
                DataColumn(label: Text('Select')),
              ],
              rows: starterCities.map((city) {
                final isSelected = city.name == selectedCity.name;
                return DataRow(
                  cells: [
                    DataCell(Text(city.name)),
                    DataCell(Text(city.timeZone)),
                    DataCell(
                      IconButton(
                        tooltip: 'Select ${city.name}',
                        icon: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        onPressed: () => onCityChanged(city),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalculationSelector extends StatelessWidget {
  const _CalculationSelector({
    required this.selectedCity,
    required this.settingsMode,
    required this.selectedCalculationMethod,
    required this.selectedMadhab,
    required this.automaticProfile,
    required this.onSettingsModeChanged,
    required this.onCalculationMethodChanged,
    required this.onMadhabChanged,
  });

  final PrayerCity selectedCity;
  final PrayerSettingsMode settingsMode;
  final PrayerCalculationMethod selectedCalculationMethod;
  final Madhab selectedMadhab;
  final PrayerCalculationProfile automaticProfile;
  final ValueChanged<PrayerSettingsMode> onSettingsModeChanged;
  final ValueChanged<PrayerCalculationMethod> onCalculationMethodChanged;
  final ValueChanged<Madhab> onMadhabChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Calculation settings'),
            subtitle: Text(
              settingsMode == PrayerSettingsMode.automatic
                  ? 'Automatic for ${selectedCity.name}'
                  : 'Manual override',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<PrayerSettingsMode>(
                  segments: const [
                    ButtonSegment(
                      value: PrayerSettingsMode.automatic,
                      label: Text('Automatic'),
                      icon: Icon(Icons.auto_awesome),
                    ),
                    ButtonSegment(
                      value: PrayerSettingsMode.manual,
                      label: Text('Manual'),
                      icon: Icon(Icons.tune),
                    ),
                  ],
                  selected: {settingsMode},
                  onSelectionChanged: (selection) =>
                      onSettingsModeChanged(selection.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  settingsMode == PrayerSettingsMode.automatic
                      ? 'Recommended for ${selectedCity.name}: '
                            '${automaticProfile.method.name}, '
                            '${_madhabLabel(automaticProfile.madhab)} Asr.'
                      : 'Select a method and Asr school below.',
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Calculation method'),
            subtitle: Text(selectedCalculationMethod.name),
            children: [
              DataTable(
                columns: const [
                  DataColumn(label: Text('Method')),
                  DataColumn(label: Text('Select')),
                ],
                rows: calculationMethods.map((method) {
                  final isSelected =
                      method.name == selectedCalculationMethod.name;
                  return DataRow(
                    cells: [
                      DataCell(SizedBox(width: 260, child: Text(method.name))),
                      DataCell(
                        IconButton(
                          tooltip: 'Select ${method.name}',
                          icon: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          onPressed: () => onCalculationMethodChanged(method),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Asr juristic method'),
            subtitle: Text(_madhabLabel(selectedMadhab)),
            children: [
              DataTable(
                columns: const [
                  DataColumn(label: Text('Method')),
                  DataColumn(label: Text('Select')),
                ],
                rows: [
                  _madhabRow('Standard (Shafi, Maliki, Hanbali)', Madhab.shafi),
                  _madhabRow('Hanafi', Madhab.hanafi),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _madhabRow(String label, Madhab madhab) {
    final isSelected = selectedMadhab == madhab;
    return DataRow(
      cells: [
        DataCell(Text(label)),
        DataCell(
          IconButton(
            tooltip: 'Select $label',
            icon: Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () => onMadhabChanged(madhab),
          ),
        ),
      ],
    );
  }
}

class QadaScreen extends StatelessWidget {
  const QadaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrayerTrackerState.instance,
      builder: (context, _) {
        final tracker = PrayerTrackerState.instance;
        final pending = tracker.qadaList
            .where((item) => !item.isMadeUp)
            .toList();
        final grouped = {
          for (final prayer in const [
            'Fajr',
            'Dhuhr',
            'Asr',
            'Maghrib',
            'Isha',
          ])
            prayer: pending.where((item) => item.prayer == prayer).toList(),
        };

        return Scaffold(
          appBar: AppBar(
            title: const Text('Qada tracker'),
            backgroundColor: Colors.transparent,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCreateQadaDialog(context, tracker),
            icon: const Icon(Icons.add),
            label: const Text('Add Qada'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Card(
                elevation: 0,
                color: const Color(0xFF176B58).withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF176B58)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pending.isEmpty
                              ? 'No uncompleted prayers logged as Qada.'
                              : 'You have ${pending.length} uncompleted prayer(s) recorded.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (pending.isNotEmpty)
                FilledButton.icon(
                  onPressed: tracker.completeAllQada,
                  icon: const Icon(Icons.done_all),
                  label: const Text('Make up all'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              const SizedBox(height: 16),
              ...grouped.entries.map(
                (entry) => _QadaPrayerSection(
                  prayer: entry.key,
                  items: entry.value,
                  tracker: tracker,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _showCreateQadaDialog(
  BuildContext context,
  PrayerTrackerState tracker,
) async {
  final counts = {
    for (final prayer in const ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'])
      prayer: 0,
  };
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Qada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: counts.keys.map((prayer) {
            return Row(
              children: [
                Expanded(child: Text(prayer)),
                IconButton(
                  onPressed: counts[prayer]! == 0
                      ? null
                      : () => setState(
                          () => counts[prayer] = counts[prayer]! - 1,
                        ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${counts[prayer]}'),
                IconButton(
                  onPressed: () =>
                      setState(() => counts[prayer] = counts[prayer]! + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: counts.values.every((count) => count == 0)
                ? null
                : () {
                    for (final entry in counts.entries) {
                      if (entry.value > 0) {
                        unawaited(
                          tracker.addManualQada(entry.key, count: entry.value),
                        );
                      }
                    }
                    Navigator.pop(context);
                  },
            child: const Text('Add Qada'),
          ),
        ],
      ),
    ),
  );
}

class _QadaPrayerSection extends StatelessWidget {
  const _QadaPrayerSection({
    required this.prayer,
    required this.items,
    required this.tracker,
  });

  final String prayer;
  final List<QadaItem> items;
  final PrayerTrackerState tracker;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final week = items
        .where((item) => now.difference(item.missedAt).inDays < 7)
        .toList();
    final month = items.where((item) {
      final age = now.difference(item.missedAt).inDays;
      return age >= 7 && age < 31;
    }).toList();
    final older = items
        .where((item) => now.difference(item.missedAt).inDays >= 31)
        .toList();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(
          prayer,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: CircleAvatar(
          radius: 14,
          child: Text('${items.length}', style: const TextStyle(fontSize: 12)),
        ),
        children: [
          _QadaPeriod(title: 'This week', items: week, tracker: tracker),
          _QadaPeriod(title: 'This month', items: month, tracker: tracker),
          _QadaPeriod(title: 'Older', items: older, tracker: tracker),
        ],
      ),
    );
  }
}

class _QadaPeriod extends StatelessWidget {
  const _QadaPeriod({
    required this.title,
    required this.items,
    required this.tracker,
  });

  final String title;
  final List<QadaItem> items;
  final PrayerTrackerState tracker;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('$title (${items.length})'),
      initiallyExpanded: items.isNotEmpty,
      children: items.isEmpty
          ? [const ListTile(title: Text('None'))]
          : items.map((item) {
              return ListTile(
                leading: const Icon(Icons.history, color: Color(0xFFC53929)),
                title: Text(
                  item.isManual
                      ? 'Date not recorded'
                      : 'Missed on ${item.date}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isManual)
                      IconButton(
                        tooltip: 'Remove Qada',
                        onPressed: () async {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Remove Qada?'),
                              content: const Text(
                                'This manually added Qada will be deleted.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                          );
                          if (remove == true) {
                            await tracker.removeManualQada(item);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    FilledButton.tonal(
                      onPressed: () => tracker.completeQadaItem(item),
                      child: const Text('Make up'),
                    ),
                  ],
                ),
              );
            }).toList(),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<CompletedPrayer>> _history;

  @override
  void initState() {
    super.initState();
    _history = PrayerTrackerState.instance.completedHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: Colors.transparent,
      ),
      body: FutureBuilder<List<CompletedPrayer>>(
        future: _history,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: Text('Loading history...'));
          }
          final byDay = <String, List<CompletedPrayer>>{};
          for (final item in snapshot.data!) {
            final day = item.isQada
                ? item.completedAt.toLocal().toIso8601String().substring(0, 10)
                : item.prayerDay;
            byDay.putIfAbsent(day, () => []).add(item);
          }
          if (byDay.isEmpty) {
            return const Center(child: Text('No completed prayers yet.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: byDay.entries.map((entry) {
              final current = entry.value
                  .where((item) => !item.isQada)
                  .toList();
              final qada = entry.value.where((item) => item.isQada).toList();
              _sortHistoryPrayers(current);
              _sortHistoryPrayers(qada);
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: [
                    _HistoryBox(title: 'Current prayers', prayers: current),
                    _HistoryBox(title: 'Qada completed', prayers: qada),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

const _prayerOrder = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

void _sortHistoryPrayers(List<CompletedPrayer> prayers) {
  prayers.sort((a, b) {
    final prayerComparison = _prayerOrder
        .indexOf(a.prayer)
        .compareTo(_prayerOrder.indexOf(b.prayer));
    if (prayerComparison != 0) return prayerComparison;
    return a.completedAt.compareTo(b.completedAt);
  });
}

List<String> _historyPrayerLabels(
  List<CompletedPrayer> prayers,
  String historyDay,
) {
  final prayer = prayers.first.prayer;
  final today = prayers
      .where(
        (item) =>
            item.isQada &&
            item.prayerDay != 'unknown' &&
            item.prayerDay == historyDay,
      )
      .length;
  final otherCount = prayers.length - today;
  final labels = <String>[];
  if (otherCount > 0) {
    labels.add('$prayer${otherCount > 1 ? ' ($otherCount)' : ''}');
  }
  if (today > 0) {
    labels.add('$prayer (Today)');
  }
  return labels;
}

class _HistoryBox extends StatelessWidget {
  const _HistoryBox({required this.title, required this.prayers});
  final String title;
  final List<CompletedPrayer> prayers;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<CompletedPrayer>>{};
    for (final prayer in prayers) {
      grouped.putIfAbsent(prayer.prayer, () => []).add(prayer);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$title: ${prayers.isEmpty ? 'None' : grouped.values.expand((items) => _historyPrayerLabels(items, _historyDay)).join(', ')}',
      ),
    );
  }

  String get _historyDay => prayers.isEmpty
      ? ''
      : prayers.first.completedAt.toLocal().toIso8601String().substring(0, 10);
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.prayer,
    required this.localTimes,
    required this.status,
    required this.tier,
    required this.isDone,
    required this.onToggleDone,
    required this.onConfirmMissed,
  });

  final PrayerWindow prayer;
  final ({DateTime start, DateTime end}) localTimes;
  final PrayerStatus status;
  final PrayerTier? tier;
  final bool isDone;
  final VoidCallback onToggleDone;
  final VoidCallback onConfirmMissed;

  @override
  Widget build(BuildContext context) {
    final isPast = status == PrayerStatus.past;
    final isMissed = isPast && !isDone;
    final isUpcoming = status == PrayerStatus.upcoming;
    final isInactive = isMissed || isUpcoming;
    final tierColor = _tierColor(tier);

    final statusText = isDone
        ? 'Completed'
        : isMissed
        ? 'Missed (Qada)'
        : _tierLabel(status, tier);

    return Card(
      elevation: 0,
      color: isDone
          ? Colors.green.shade50.withValues(alpha: 0.5)
          : isInactive
          ? Colors.grey.shade100.withValues(alpha: 0.6)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDone
            ? BorderSide(color: Colors.green.shade300, width: 1.5)
            : isInactive
            ? BorderSide(color: Colors.grey.shade300, width: 1.2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isDone
              ? Colors.green.shade100
              : isInactive
              ? Colors.grey.shade200
              : tierColor.withValues(alpha: 0.14),
          foregroundColor: isDone
              ? const Color(0xFF218739)
              : isInactive
              ? Colors.grey.shade500
              : tierColor,
          child: Icon(
            isDone
                ? Icons.check
                : isMissed
                ? Icons.history
                : isUpcoming
                ? Icons.schedule_outlined
                : _tierIcon(tier),
          ),
        ),
        title: Text(
          prayer.prayer,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone
                ? Colors.grey.shade600
                : isInactive
                ? Colors.grey.shade500
                : null,
          ),
        ),
        subtitle: Text(
          '${_formatTime(localTimes.start)} – '
          '${_formatTime(localTimes.end)}'
          '${prayer.endsOnDifferentLocalDate ? ' (tomorrow)' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              statusText,
              style: TextStyle(
                color: isDone
                    ? const Color(0xFF218739)
                    : isMissed
                    ? Colors.grey.shade600
                    : tierColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isDone
                    ? const Color(0xFF218739)
                    : isInactive
                    ? Colors.grey.shade400
                    : Colors.grey.shade400,
                size: 26,
              ),
              tooltip: isMissed
                  ? 'Confirm this prayer was performed'
                  : isUpcoming
                  ? 'Available when the prayer time begins'
                  : (isDone ? 'Mark as not prayed' : 'Mark as prayed'),
              onPressed: isMissed
                  ? () => _confirmMissedPrayer(context)
                  : isUpcoming
                  ? null
                  : onToggleDone,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmMissedPrayer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm ${prayer.prayer}'),
        content: Text(
          'Did you perform ${prayer.prayer} even though it was not marked '
          'as completed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, mark it done'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onConfirmMissed();
    }
  }

  Color _tierColor(PrayerTier? tier) => switch (tier) {
    PrayerTier.green => const Color(0xFF218739),
    PrayerTier.yellow => const Color(0xFFB77900),
    PrayerTier.red => const Color(0xFFC53929),
    null => Colors.grey,
  };

  IconData _tierIcon(PrayerTier? tier) => switch (tier) {
    PrayerTier.green => Icons.check_circle_outline,
    PrayerTier.yellow => Icons.access_time,
    PrayerTier.red => Icons.warning_amber_outlined,
    null => Icons.schedule_outlined,
  };

  String _tierLabel(PrayerStatus status, PrayerTier? tier) => switch (tier) {
    PrayerTier.green => 'Optimal',
    PrayerTier.yellow => 'Normal',
    PrayerTier.red => 'Ending soon',
    null => status == PrayerStatus.past ? 'Past' : 'Upcoming',
  };
}

String _madhabLabel(Madhab madhab) =>
    madhab == Madhab.hanafi ? 'Hanafi' : 'Standard';

String _formatTime(DateTime time) {
  final hour = time.hour == 0 || time.hour == 12 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}
