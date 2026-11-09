import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'prayer/prayer_schedule.dart';
import 'prayer/prayer_tier.dart';

void main() {
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
      const StreakScreen(),
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
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department),
            label: 'Streak',
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

DateTime _prayerClock() {
  if (!kReleaseMode && _debugPrayerClockOverride.isNotEmpty) {
    final override = DateTime.tryParse(_debugPrayerClockOverride);
    if (override != null) {
      return override;
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
                const SizedBox(height: 8),
                Text(
                  'Stay mindful of each salah and keep your qada journey organized.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prayer times',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.city.name} · ${widget.calculationMethod.name} · '
                          '${widget.madhab == Madhab.hanafi ? 'Hanafi' : 'Standard'} · local time',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  current == null
                      ? 'Next: ${liveState.nextWindow?.prayer ?? 'none'} at '
                            '${liveState.nextWindowStartLocal == null ? '--:--' : _formatTime(liveState.nextWindowStartLocal!)}'
                      : '${current.prayer}: '
                            '${_formatTime(liveState.localTimes[current]!.start)} – '
                            '${_formatTime(liveState.localTimes[current]!.end)}'
                            '${current.endsOnDifferentLocalDate ? ' (tomorrow)' : ''} · '
                            '${_formatDuration(liveState.timeRemaining)} remaining',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...liveState.displayWindows.map(
                  (prayer) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PrayerCard(
                      prayer: prayer,
                      localTimes: liveState.localTimes[prayer]!,
                      status: liveState.statuses[prayer]!,
                      tier: liveState.tiers[prayer],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    return const _PlaceholderScreen(
      title: 'Qada tracker',
      icon: Icons.checklist_outlined,
      message: 'Qada tracking and planning will be added here next.',
    );
  }
}

class StreakScreen extends StatelessWidget {
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScreen(
      title: 'Streak',
      icon: Icons.local_fire_department_outlined,
      message: 'Your salah streak and progress will appear here later.',
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
  });

  final PrayerWindow prayer;
  final ({DateTime start, DateTime end}) localTimes;
  final PrayerStatus status;
  final PrayerTier? tier;

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor(tier);
    return Card(
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: tierColor.withValues(alpha: 0.14),
          foregroundColor: tierColor,
          child: Icon(_tierIcon(tier)),
        ),
        title: Text(
          prayer.prayer,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_formatTime(localTimes.start)} – '
          '${_formatTime(localTimes.end)}'
          '${prayer.endsOnDifferentLocalDate ? ' (tomorrow)' : ''}',
        ),
        trailing: Text(
          _tierLabel(status, tier),
          style: TextStyle(color: tierColor, fontWeight: FontWeight.w700),
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
    PrayerTier.red => 'Danger',
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

String _formatDuration(Duration? duration) {
  if (duration == null) {
    return '--';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}
