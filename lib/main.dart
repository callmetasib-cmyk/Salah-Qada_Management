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
    final modeName = await tracker.getSettingsMode();
    final methodName = await tracker.getCalculationMethod();
    final madhabName = await tracker.getMadhab();
    if (!mounted) return;

    final matches = starterCities.where((item) => item.name == cityName);
    final city = matches.isEmpty ? null : matches.first;
    final mode = PrayerSettingsMode.values
        .where((item) => item.name == modeName)
        .firstOrNull;
    final method = calculationMethods
        .where((item) => item.name == methodName)
        .firstOrNull;
    final madhab = Madhab.values
        .where((item) => item.name == madhabName)
        .firstOrNull;

    if (!mounted) return;
    setState(() {
      if (city != null) _selectedCity = city;
      if (mode != null) _settingsMode = mode;
      if (method != null) _manualCalculationMethod = method;
      if (madhab != null) _manualMadhab = madhab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PrayerHomeScreen(
        city: _selectedCity,
        calculationMethod: _selectedCalculationMethod,
        madhab: _selectedMadhab,
        onCityChanged: (city) async {
          setState(() => _selectedCity = city);
          await PrayerTrackerState.instance.setSelectedCity(city.name);
          await PrayerTrackerState.instance.resetTodayCompletions();
        },
      ),
      const QadaScreen(),
      const HistoryScreen(),
      SettingsScreen(
        selectedCity: _selectedCity,
        settingsMode: _settingsMode,
        selectedCalculationMethod: _selectedCalculationMethod,
        selectedMadhab: _selectedMadhab,
        automaticProfile: _automaticProfile,
        onCityChanged: (city) async {
          setState(() => _selectedCity = city);
          await PrayerTrackerState.instance.setSelectedCity(city.name);
          await PrayerTrackerState.instance.resetTodayCompletions();
        },
        onSettingsModeChanged: (mode) {
          setState(() => _settingsMode = mode);
          unawaited(PrayerTrackerState.instance.setSettingsMode(mode.name));
        },
        onCalculationMethodChanged: (method) {
          setState(() {
            _manualCalculationMethod = method;
            _settingsMode = PrayerSettingsMode.manual;
          });
          unawaited(
            PrayerTrackerState.instance.setCalculationMethod(method.name),
          );
          unawaited(
            PrayerTrackerState.instance.setSettingsMode(
              PrayerSettingsMode.manual.name,
            ),
          );
        },
        onMadhabChanged: (madhab) {
          setState(() {
            _manualMadhab = madhab;
            _settingsMode = PrayerSettingsMode.manual;
          });
          unawaited(PrayerTrackerState.instance.setMadhab(madhab.name));
          unawaited(
            PrayerTrackerState.instance.setSettingsMode(
              PrayerSettingsMode.manual.name,
            ),
          );
        },
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
    this.onCityChanged,
  });

  final PrayerCity city;
  final PrayerCalculationMethod calculationMethod;
  final Madhab madhab;
  final ValueChanged<PrayerCity>? onCityChanged;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunch();
    });
  }

  Future<void> _checkFirstLaunch() async {
    final tracker = PrayerTrackerState.instance;
    await tracker.initialize();
    final isDone = await tracker.isFirstLaunchCompleted();
    if (isDone || !mounted) return;

    await _showFirstLaunchWizard();
  }

  Future<void> _showFirstLaunchWizard() async {
    final tracker = PrayerTrackerState.instance;
    var step = 0; // 0: Select City, 1: Check Today's Prayers
    var selectedCity = widget.city;
    var pastPrayers = <PrayerWindow>[];
    final checkedPrayers = <PrayerWindow, bool>{};

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setWizardState) {
          if (step == 0) {
            return AlertDialog(
              title: const Text('Welcome to Salah & Qada'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Where are you located? We will use this to calculate your exact local prayer times.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<PrayerCity>(
                    initialValue: selectedCity,
                    decoration: const InputDecoration(
                      labelText: 'Select your city',
                      border: OutlineInputBorder(),
                    ),
                    items: starterCities.map((city) {
                      return DropdownMenuItem(
                        value: city,
                        child: Text('${city.name} (${city.countryCode})'),
                      );
                    }).toList(),
                    onChanged: (newCity) {
                      if (newCity != null) {
                        setWizardState(() {
                          selectedCity = newCity;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    // Apply selected city
                    widget.onCityChanged?.call(selectedCity);
                    _controller.city = selectedCity;
                    await tracker.setSelectedCity(selectedCity.name);

                    // Recompute schedule for the selected city
                    final windows = _controller.state.displayWindows;
                    final statuses = _controller.state.statuses;

                    pastPrayers = windows
                        .where((w) => statuses[w] == PrayerStatus.past)
                        .toList();

                    for (final p in pastPrayers) {
                      checkedPrayers[p] = false;
                    }

                    if (pastPrayers.isEmpty) {
                      // No past prayers yet today in this city (e.g. early morning)
                      await tracker.setFirstLaunchCompleted();
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      await tracker.syncWithLiveStatus(windows, statuses);
                    } else {
                      // Move to Step 2
                      setWizardState(() {
                        step = 1;
                      });
                    }
                  },
                  child: const Text('Next →'),
                ),
              ],
            );
          }

          // Step 1: Today's checkoff
          return AlertDialog(
            title: Text('Today in ${selectedCity.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Which of today\'s earlier prayers did you already complete?',
                ),
                const SizedBox(height: 16),
                ...pastPrayers.map((prayer) {
                  return CheckboxListTile(
                    value: checkedPrayers[prayer] ?? false,
                    title: Text(prayer.prayer),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setWizardState(() {
                        checkedPrayers[prayer] = val ?? false;
                      });
                    },
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setWizardState(() {
                    step = 0;
                  });
                },
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () async {
                  for (final entry in checkedPrayers.entries) {
                    if (entry.value) {
                      await tracker.markMissedPrayerDone(
                        entry.key.prayer,
                        entry.key.prayerDay,
                      );
                    }
                  }
                  await tracker.setFirstLaunchCompleted();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  await tracker.syncWithLiveStatus(
                    _controller.state.displayWindows,
                    _controller.state.statuses,
                  );
                },
                child: const Text('Get Started'),
              ),
            ],
          );
        },
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
                      isDone: current != null &&
                          PrayerTrackerState.instance.isPrayerDone(
                            current.prayer,
                            current.prayerDay,
                          ),
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
                          onConfirmMissedOnTime: () {
                            PrayerTrackerState.instance.markMissedPrayerDone(
                              prayer.prayer,
                              prayer.prayerDay,
                            );
                          },
                          onConfirmMissedLate: () {
                            PrayerTrackerState.instance.markMissedPrayerLate(
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
                        onPressed: isSelected
                            ? null
                            : () => _confirmCitySwitch(context, city),
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

  Future<void> _confirmCitySwitch(
    BuildContext context,
    PrayerCity newCity,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Switch city to ${newCity.name}?'),
        content: Text(
          'Changing your location will recalculate today\'s schedule for '
          '${newCity.name} (${newCity.timeZone}).\n\n'
          'Any earlier prayers that have already passed today in ${newCity.name} '
          'will be tracked based on your new local time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Switch city'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onCityChanged(newCity);
    }
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
              if (pending.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  color: const Color(0xFFB77900).withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: const Color(0xFFB77900).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.track_changes, color: Color(0xFFB77900), size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Pace & Schedule Plan',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFFB77900),
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _showPlanSetupDialog(context, tracker),
                              icon: const Icon(Icons.tune, size: 16),
                              label: Text(
                                tracker.targetCompletionDate == null ? 'Set Target' : 'Edit Plan',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (tracker.targetCompletionDate == null)
                          const Text(
                            'Stack 1 Qada with each current prayer or set a target completion timeframe.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          )
                        else ...[
                          Text(
                            'Target: ${_formatDate(tracker.targetCompletionDate!)} (${tracker.targetCompletionDate!.difference(DateTime.now()).inDays + 1} days remaining)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: const ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'].map((p) {
                              final quota = tracker.getDailyQuotaFor(p);
                              final assigned = tracker.getAssignedCurrentPrayer(p);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB77900).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  quota > 0 ? '$p: +$quota / day (with $assigned)' : '$p: Done',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Make up all Qada?'),
                        content: Text(
                          'Are you sure you want to mark all ${pending.length} pending Qada prayer(s) as made up?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Yes, mark all made up'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await tracker.completeAllQada();
                    }
                  },
                  icon: const Icon(Icons.done_all),
                  label: const Text('Make up all pending'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ],
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
  final prayers = const ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  final controllers = {
    for (final prayer in prayers) prayer: TextEditingController(text: '0'),
  };

  void applyPreset(int amount, StateSetter setState) {
    setState(() {
      for (final p in prayers) {
        final current = int.tryParse(controllers[p]!.text) ?? 0;
        final next = (current + amount).clamp(0, 10000);
        controllers[p]!.text = '$next';
      }
    });
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final totalCount = prayers.fold<int>(
          0,
          (sum, p) => sum + (int.tryParse(controllers[p]!.text) ?? 0),
        );

        return AlertDialog(
          title: const Text('Add Qada Prayers'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add missed prayers to your tracker. Use presets or type an exact number.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('+1 Week'),
                      onPressed: () => applyPreset(7, setDialogState),
                    ),
                    ActionChip(
                      label: const Text('+1 Month'),
                      onPressed: () => applyPreset(30, setDialogState),
                    ),
                    ActionChip(
                      label: const Text('+1 Year'),
                      onPressed: () => applyPreset(365, setDialogState),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...prayers.map((prayer) {
                  final ctrl = controllers[prayer]!;
                  final count = int.tryParse(ctrl.text) ?? 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            prayer,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          iconSize: 20,
                          onPressed: count <= 0
                              ? null
                              : () {
                                  setDialogState(() {
                                    ctrl.text = '${(count - 1).clamp(0, 10000)}';
                                  });
                                },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        SizedBox(
                          width: 55,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              setDialogState(() {
                                final parsed = int.tryParse(val) ?? 0;
                                if (parsed > 10000) {
                                  ctrl.text = '10000';
                                }
                              });
                            },
                          ),
                        ),
                        IconButton(
                          iconSize: 20,
                          onPressed: count >= 10000
                              ? null
                              : () {
                                  setDialogState(() {
                                    ctrl.text = '${(count + 1).clamp(0, 10000)}';
                                  });
                                },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: totalCount <= 0
                  ? null
                  : () async {
                      for (final p in prayers) {
                        final count = int.tryParse(controllers[p]!.text) ?? 0;
                        if (count > 0) {
                          await tracker.addManualQada(p, count: count);
                        }
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
              child: Text(totalCount > 0 ? 'Add ($totalCount)' : 'Add'),
            ),
          ],
        );
      },
    ),
  );
  for (final c in controllers.values) {
    c.dispose();
  }
}

Future<void> _showPlanSetupDialog(
  BuildContext context,
  PrayerTrackerState tracker,
) async {
  DateTime selectedDate = tracker.targetCompletionDate ??
      DateTime.now().add(const Duration(days: 180));
  final pairings = Map<String, String>.from(tracker.customPairings);
  const prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final now = DateTime.now();
        final days = selectedDate.difference(now).inDays + 1;

        // Check if any current prayer has > 2 Qada assigned to it per day
        var hasBurnoutRisk = false;
        final dailyNeededByAssigned = <String, int>{};
        for (final qp in prayers) {
          final pending = tracker.getPendingCountFor(qp);
          final quotaForThisQada = days <= 0
              ? pending
              : (pending / days).ceil().clamp(0, pending);
          final assigned = pairings[qp] ?? qp;
          dailyNeededByAssigned[assigned] = (dailyNeededByAssigned[assigned] ?? 0) + quotaForThisQada;
        }

        for (final count in dailyNeededByAssigned.values) {
          if (count > 2) {
            hasBurnoutRisk = true;
            break;
          }
        }

        return AlertDialog(
          title: const Text('Qada Completion Plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a target timeframe to pace yourself comfortably.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      label: const Text('1 Week'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 7));
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('1 Month'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 30));
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('3 Months'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 90));
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('6 Months'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 180));
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('1 Year'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 365));
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('2 Years'),
                      onPressed: () {
                        setDialogState(() {
                          selectedDate = DateTime.now().add(const Duration(days: 730));
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(
                    'Target Date: ${_formatDate(selectedDate)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$days day(s) total'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: const Text('Pick Date'),
                  ),
                ),
                if (hasBurnoutRisk) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This pace requires more than 2 Qada per prayer session. Consider extending your timeframe to keep your habit sustainable and stress-free.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Prayer Pairing (Habit Stacking)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose which daily prayer to attach each Qada to.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ...prayers.map((qadaPrayer) {
                  final assigned = pairings[qadaPrayer] ?? qadaPrayer;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Qada $qadaPrayer with:',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        DropdownButton<String>(
                          value: assigned,
                          isDense: true,
                          items: prayers.map((p) {
                            return DropdownMenuItem<String>(
                              value: p,
                              child: Text(p, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                pairings[qadaPrayer] = val;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await tracker.setTargetCompletionDate(selectedDate);
                for (final p in prayers) {
                  await tracker.setPrayerPairing(p, pairings[p] ?? p);
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save Plan'),
            ),
          ],
        );
      },
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

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrayerTrackerState.instance,
      builder: (context, _) {
        final tracker = PrayerTrackerState.instance;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            backgroundColor: Colors.transparent,
          ),
          body: FutureBuilder<List<CompletedPrayer>>(
            future: tracker.completedHistory(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: Text('Loading history...'));
              }
              final completed = snapshot.data!;
              final nowDayStr = DateTime.now().toLocal().toIso8601String().substring(0, 10);

              // Collect all days represented in history (and include today if not empty)
              final daysSet = <String>{nowDayStr};
              for (final c in completed) {
                if (c.prayerDay.isNotEmpty && c.prayerDay != 'unknown' && c.prayerDay != 'Date not recorded') {
                  daysSet.add(c.prayerDay);
                }
                final completedDayStr = c.completedAt.toLocal().toIso8601String().substring(0, 10);
                daysSet.add(completedDayStr);
              }
              final sortedDays = daysSet.toList()..sort((a, b) => b.compareTo(a));

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: sortedDays.map((dayStr) {
                  const fivePrayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

                  // 1. Daily 5 prayers status for this day
                  final dailyStatuses = fivePrayers.map((p) {
                    // Check if completed on time
                    final onTimeRecord = completed.where(
                      (item) => item.prayer == p && item.prayerDay == dayStr && !item.isQada,
                    ).firstOrNull;

                    if (onTimeRecord != null) {
                      return (prayer: p, status: 'on_time');
                    }

                    // Check if made up as qada
                    final madeUpQada = completed.where(
                      (item) => item.prayer == p && item.prayerDay == dayStr && item.isQada,
                    ).firstOrNull;

                    if (madeUpQada != null) {
                      return (prayer: p, status: 'made_up');
                    }

                    // Check if pending automatic qada for this day (missed)
                    final isPendingMissed = tracker.qadaList.any(
                      (item) => item.prayer == p && item.date == dayStr && !item.isMadeUp,
                    );

                    if (isPendingMissed) {
                      return (prayer: p, status: 'missed');
                    }

                    // For today, check if it's already marked in RAM
                    if (dayStr == nowDayStr) {
                      final doneInRam = tracker.isPrayerDone(p, DateTime.now());
                      if (doneInRam) {
                        return (prayer: p, status: 'on_time');
                      }
                    }

                    return (prayer: p, status: 'unrecorded');
                  }).toList();

                  // 2. Qada completed on this date that is NOT of this day's daily prayers (historical backlog / catch-up)
                  final backlogCompleted = completed.where((item) {
                    final completedDate = item.completedAt.toLocal().toIso8601String().substring(0, 10);
                    if (completedDate != dayStr) return false;
                    // Exclude if it's this day's own daily prayer that was made up
                    if (item.prayerDay == dayStr) return false;
                    return item.isQada;
                  }).toList();

                  // Group backlog prayers: e.g. Fajr (x3)
                  final backlogCounts = <String, int>{};
                  for (final item in backlogCompleted) {
                    backlogCounts[item.prayer] = (backlogCounts[item.prayer] ?? 0) + 1;
                  }

                  final isToday = dayStr == nowDayStr;
                  final displayTitle = isToday ? 'Today ($dayStr)' : dayStr;

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ExpansionTile(
                      initiallyExpanded: isToday,
                      title: Text(
                        displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        _DailyPrayersBox(
                          title: isToday ? "Today's prayers" : 'Daily prayers',
                          items: dailyStatuses,
                        ),
                        _BacklogQadaBox(
                          title: 'Qada completed',
                          counts: backlogCounts,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        );
      },
    );
  }
}

class _DailyPrayersBox extends StatelessWidget {
  const _DailyPrayersBox({required this.title, required this.items});
  final String title;
  final List<({String prayer, String status})> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final (icon, color, labelText) = switch (item.status) {
              'on_time' => (
                Icons.check_circle_outline,
                const Color(0xFF218739),
                'On time',
              ),
              'made_up' => (
                Icons.history,
                const Color(0xFFB77900),
                'Made up',
              ),
              'missed' => (
                Icons.warning_amber_outlined,
                const Color(0xFFC53929),
                'Missed',
              ),
              _ => (
                Icons.remove_circle_outline,
                Colors.grey,
                'Pending',
              ),
            };

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    item.prayer,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: item.status == 'unrecorded' ? Colors.grey : null,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      labelText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BacklogQadaBox extends StatelessWidget {
  const _BacklogQadaBox({required this.title, required this.counts});
  final String title;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$title: None',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }

    const prayerOrder = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final sortedPrayers = counts.keys.toList()
      ..sort((a, b) {
        final ai = prayerOrder.indexOf(a);
        final bi = prayerOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...sortedPrayers.map((p) {
            final count = counts[p]!;
            final displayLabel = count > 1 ? '$p (x$count)' : p;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 16, color: Color(0xFFB77900)),
                  const SizedBox(width: 8),
                  Text(
                    displayLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB77900).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Made up',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB77900),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.prayer,
    required this.localTimes,
    required this.status,
    required this.tier,
    required this.isDone,
    required this.onToggleDone,
    required this.onConfirmMissedOnTime,
    required this.onConfirmMissedLate,
  });

  final PrayerWindow prayer;
  final ({DateTime start, DateTime end}) localTimes;
  final PrayerStatus status;
  final PrayerTier? tier;
  final bool isDone;
  final VoidCallback onToggleDone;
  final VoidCallback onConfirmMissedOnTime;
  final VoidCallback onConfirmMissedLate;

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

    final scheduledQadas = PrayerTrackerState.instance.getScheduledQadaFor(prayer.prayer);

    return Card(
      elevation: 0,
      color: isDone
          ? Colors.green.shade50.withValues(alpha: 0.35)
          : isInactive
          ? Colors.grey.shade100.withValues(alpha: 0.6)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDone
            ? BorderSide(color: Colors.green.shade200, width: 1.2)
            : isInactive
            ? BorderSide(color: Colors.grey.shade300, width: 1.2)
            : BorderSide.none,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
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
                color: isDone
                    ? Colors.green.shade900
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
          if (scheduledQadas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Qada goal:',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    children: scheduledQadas.map((qadaPrayer) {
                      final isQadaDone = PrayerTrackerState.instance.isPlanQadaDoneForToday(
                        prayer.prayer,
                        qadaPrayer,
                      );
                      final quota = PrayerTrackerState.instance.getDailyQuotaFor(qadaPrayer);
                      final completedToday = PrayerTrackerState.instance.getTodayCompletedPlanQadaCount(
                        prayer.prayer,
                        qadaPrayer,
                      );
                      return _InteractiveQadaPill(
                        currentPrayer: prayer.prayer,
                        qadaPrayer: qadaPrayer,
                        isDone: isQadaDone,
                        quota: quota,
                        completedToday: completedToday,
                        onComplete: (count) {
                          PrayerTrackerState.instance.completePlanQada(
                            prayer.prayer,
                            qadaPrayer,
                            count: count,
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmMissedPrayer(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record ${prayer.prayer}'),
        content: Text(
          'Did you pray ${prayer.prayer} on time during its window, or make it up late?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('late'),
            child: const Text('Prayed late'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('on_time'),
            child: const Text('Prayed on time'),
          ),
        ],
      ),
    );

    if (choice == 'on_time') {
      onConfirmMissedOnTime();
    } else if (choice == 'late') {
      onConfirmMissedLate();
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
    PrayerTier.red => prayer.prayer == 'Isha' ? 'Past midnight' : 'Ending soon',
    null => status == PrayerStatus.past ? 'Past' : 'Upcoming',
  };
}

class _InteractiveQadaPill extends StatefulWidget {
  const _InteractiveQadaPill({
    required this.currentPrayer,
    required this.qadaPrayer,
    required this.isDone,
    required this.quota,
    required this.completedToday,
    required this.onComplete,
  });

  final String currentPrayer;
  final String qadaPrayer;
  final bool isDone;
  final int quota;
  final int completedToday;
  final void Function(int count) onComplete;

  @override
  State<_InteractiveQadaPill> createState() => _InteractiveQadaPillState();
}

class _InteractiveQadaPillState extends State<_InteractiveQadaPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.isDone) return;

    // If quota > 1, show a small bottom sheet / picker dialog allowing the user
    // to choose how many they completed (e.g. 1 out of 5, or all 5).
    final pendingCount = PrayerTrackerState.instance.getPendingCountFor(widget.qadaPrayer);
    final remainingForQuota = (widget.quota - widget.completedToday).clamp(1, pendingCount);

    if (remainingForQuota > 1) {
      final selectedCount = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          int count = remainingForQuota;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('Make up ${widget.qadaPrayer}'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Target for this session: $remainingForQuota ${widget.qadaPrayer}. How many did you pray?',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: count <= 1
                              ? null
                              : () => setDialogState(() => count--),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: count >= remainingForQuota
                              ? null
                              : () => setDialogState(() => count++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, count),
                    child: Text('Confirm ($count)'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (selectedCount != null && selectedCount > 0) {
        await _animCtrl.forward();
        await _animCtrl.reverse();
        widget.onComplete(selectedCount);
      }
    } else {
      await _animCtrl.forward();
      await _animCtrl.reverse();
      widget.onComplete(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    const amberColor = Color(0xFFB77900);

    // Text formatting: only show text without duplicate check symbol
    // e.g. "Dhuhr (+5)" when pending, or "Dhuhr (5/5)" when done
    String label;
    if (widget.quota > 1) {
      if (widget.isDone) {
        label = '${widget.qadaPrayer} (${widget.quota}/${widget.quota})';
      } else if (widget.completedToday > 0) {
        label = '${widget.qadaPrayer} (${widget.completedToday}/${widget.quota})';
      } else {
        label = '${widget.qadaPrayer} (+${widget.quota})';
      }
    } else {
      label = widget.qadaPrayer;
    }

    return ScaleTransition(
      scale: _scaleAnim,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.isDone ? null : _handleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: widget.isDone
                  ? amberColor.withValues(alpha: 0.22)
                  : amberColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isDone ? amberColor : amberColor.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isDone ? Icons.check : Icons.history,
                  size: 13,
                  color: amberColor,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: amberColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _madhabLabel(Madhab madhab) =>
    madhab == Madhab.hanafi ? 'Hanafi' : 'Standard';

String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _formatTime(DateTime time) {
  final hour = time.hour == 0 || time.hour == 12 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}
