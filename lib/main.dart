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
        onCityChanged: (city) => setState(() => _selectedCity = city),
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
    final override =
        _debugClockBase ??= DateTime.tryParse(_debugPrayerClockOverride);
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              PrayerTrackerState.instance.syncWithLiveStatus(
                liveState.displayWindows,
                liveState.statuses,
              );
            });

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
                      currentTier:
                          current == null ? null : liveState.tiers[current],
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
                    ...liveState.displayWindows.map(
                      (prayer) {
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
                              );
                            },
                          ),
                        );
                      },
                    ),
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
        final pending =
            tracker.qadaList.where((item) => !item.isMadeUp).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Qada tracker'),
            backgroundColor: Colors.transparent,
          ),
          body: pending.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'All caught up!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No uncompleted prayers logged as Qada.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Card(
                      elevation: 0,
                      color: const Color(0xFF176B58).withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF176B58),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You have ${pending.length} uncompleted prayer(s) recorded.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: tracker.completeAllQada,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Make up all'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...pending.map((item) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x22C53929),
                            foregroundColor: Color(0xFFC53929),
                            child: Icon(Icons.history),
                          ),
                          title: Text(
                            item.prayer,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Missed on ${item.date}'),
                          trailing: FilledButton.tonal(
                            onPressed: () => tracker.completeQadaItem(item),
                            child: const Text('Make up'),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
        );
      },
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(
      title: 'History',
      icon: Icons.calendar_month_outlined,
      message: 'Your salah history, consistency, and progress will appear here.',
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
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
  });

  final PrayerWindow prayer;
  final ({DateTime start, DateTime end}) localTimes;
  final PrayerStatus status;
  final PrayerTier? tier;
  final bool isDone;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final isPast = status == PrayerStatus.past;
    final isMissed = isPast && !isDone;
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
          : isMissed
              ? Colors.grey.shade100.withValues(alpha: 0.6)
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDone
            ? BorderSide(color: Colors.green.shade300, width: 1.5)
            : isMissed
                ? BorderSide(color: Colors.grey.shade300, width: 1.2)
                : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isDone
              ? Colors.green.shade100
              : isMissed
                  ? Colors.grey.shade200
                  : tierColor.withValues(alpha: 0.14),
          foregroundColor: isDone
              ? const Color(0xFF218739)
              : isMissed
                  ? Colors.grey.shade500
                  : tierColor,
          child: Icon(
            isDone
                ? Icons.check
                : isMissed
                    ? Icons.history
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
                : isMissed
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
            // Once the prayer window passes, the checkbox locks and cannot be checked/unchecked.
            IconButton(
              icon: Icon(
                isDone
                    ? Icons.check_circle
                    : isMissed
                        ? Icons.lock_outline
                        : Icons.radio_button_unchecked,
                color: isDone
                    ? const Color(0xFF218739)
                    : isMissed
                        ? Colors.grey.shade400
                        : Colors.grey.shade400,
                size: 26,
              ),
              tooltip: isPast
                  ? (isDone
                      ? 'Prayed on time (Window closed)'
                      : 'Time passed — moved to Qada')
                  : (isDone ? 'Mark as not prayed' : 'Mark as prayed'),
              onPressed: isPast ? null : onToggleDone,
            ),
          ],
        ),
      ),
    );
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
