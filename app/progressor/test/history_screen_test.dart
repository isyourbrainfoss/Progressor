import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/main.dart';
import 'package:progressor/persistence/session_store.dart';
import 'package:progressor/screens/history_screen.dart';
import 'package:progressor/screens/onboarding_screen.dart';
import 'package:progressor/sensors/ble_transport.dart';
import 'package:progressor/sensors/sensor_hub.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

PullTest _test(String id, double peak, {bool demo = false, int hour = 10}) {
  final samples = [
    ForceSample(timeMs: 0, forceKg: 1),
    ForceSample(timeMs: 200, forceKg: peak),
    ForceSample(timeMs: 400, forceKg: 10),
  ];
  return PullTest(
    id: id,
    startTime: DateTime.utc(2026, 5, 1, hour),
    type: TestType.peakForce,
    samples: samples,
    metrics: {...computeMetrics(samples).toJson(), if (demo) 'source': 'demo'},
  );
}

Future<SessionStore> _storeWith(List<PullTest> tests) async {
  for (final t in tests) {
    await TestStorage().save(t);
  }
  final store = SessionStore();
  await store.load();
  return store;
}

Future<void> _openHistory(WidgetTester tester, SessionStore store) async {
  await tester.pumpWidget(
    ProgressorApp(
      sensorHub: SensorHub(
        bleBackend: const UnsupportedBleConnectionBackend(message: 'none'),
      ),
      sessionStore: store,
      autoReconnectSensors: false,
    ),
  );
  await tester.pump();
  await tester.tap(find.text('History').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    TestStorage.close();
    TestStorage.initializeMemory();
  });
  tearDown(TestStorage.close);

  group('historyDateLabel', () {
    final now = DateTime(2026, 11, 11, 18);
    test('today and yesterday are relative', () {
      expect(
        historyDateLabel(DateTime(2026, 11, 11, 14, 40), now: now),
        'Today 14:40',
      );
      expect(
        historyDateLabel(DateTime(2026, 11, 10, 9, 5), now: now),
        'Yesterday 09:05',
      );
    });
    test('this week shows weekday, older shows date', () {
      expect(
        historyDateLabel(DateTime(2026, 11, 9, 18, 30), now: now),
        'Mon 9 Nov 18:30',
      );
      expect(
        historyDateLabel(DateTime(2026, 3, 2, 8, 0), now: now),
        '2 Mar 08:00',
      );
      expect(
        historyDateLabel(DateTime(2025, 1, 3, 10, 0), now: now),
        '3 Jan 2025 10:00',
      );
    });
  });

  testWidgets('demo-only history explains the missing best', (tester) async {
    final store = await _storeWith([_test('d1', 12, demo: true)]);
    await _openHistory(tester, store);
    expect(find.byKey(const Key('history_summary')), findsOneWidget);
    expect(find.textContaining("demo pulls don't count"), findsOneWidget);
    expect(find.byKey(const Key('history_demo_chip')), findsOneWidget);
    // Destructive actions live in the menu, not a floating button.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('summary shows best of real tests', (tester) async {
    final store = await _storeWith([
      _test('r1', 30.5, hour: 9),
      _test('d1', 50, demo: true, hour: 11),
    ]);
    await _openHistory(tester, store);
    expect(find.textContaining('Best 30.5 kg'), findsOneWidget);
    expect(find.textContaining('1 demo'), findsOneWidget);
  });

  testWidgets('remove demo tests keeps real ones', (tester) async {
    final store = await _storeWith([
      _test('r1', 30.5, hour: 9),
      _test('d1', 50, demo: true, hour: 11),
    ]);
    await _openHistory(tester, store);
    await tester.tap(find.byKey(const Key('history_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history_remove_demo')));
    await tester.pumpAndSettle();
    expect(store.tests.map((t) => t.id), ['r1']);
    expect((await TestStorage().loadAll()).map((t) => t.id), ['r1']);
  });

  testWidgets('swipe deletes one test and Undo restores it', (tester) async {
    final store = await _storeWith([
      _test('r1', 30.5, hour: 9),
      _test('r2', 31.5, hour: 11),
    ]);
    await _openHistory(tester, store);
    await tester.drag(
      find.byKey(const ValueKey('history_r2')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(store.tests.map((t) => t.id), ['r1']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.tests.map((t) => t.id), ['r2', 'r1']);
    expect((await TestStorage().loadAll()).length, 2);
  });

  testWidgets('clear all asks first', (tester) async {
    final store = await _storeWith([_test('r1', 30.5)]);
    await _openHistory(tester, store);
    await tester.tap(find.byKey(const Key('history_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history_clear_all')));
    await tester.pumpAndSettle();
    expect(find.text('Clear all history?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history_clear_confirm')));
    await tester.pumpAndSettle();
    expect(store.tests, isEmpty);
    expect(find.text('No tests yet'), findsOneWidget);
  });
}
