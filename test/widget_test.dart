import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:salah_qada_tracker/main.dart';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });
  testWidgets('renders the Salah and Qada home shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SalahQadaApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Salah & Qada'), findsOneWidget);
    expect(find.text('Assalamu alaikum'), findsOneWidget);
    expect(find.text("Today's prayers"), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Dhuhr'), findsOneWidget);
    expect(find.text('Asr'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Maghrib'), findsOneWidget);
    expect(find.text('Isha'), findsOneWidget);

    await tester.tap(find.text('Qada'));
    await tester.pumpAndSettle();
    expect(find.text('Qada tracker'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsWidgets);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Prayer calculations'), findsOneWidget);
    expect(find.text('City / Location'), findsOneWidget);
  });
}
