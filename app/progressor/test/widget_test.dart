import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/main.dart';
import 'package:progressor/persistence/session_store.dart';
import 'package:progressor/screens/onboarding_screen.dart';
import 'package:progressor/sensors/ble_transport.dart';
import 'package:progressor/sensors/sensor_hub.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

SensorHub _hub() => SensorHub(
  bleBackend: const UnsupportedBleConnectionBackend(
    message: 'Test backend — no Bluetooth',
  ),
);

ProgressorApp _app({SensorHub? hub, SessionStore? store}) {
  return ProgressorApp(
    sensorHub: hub ?? _hub(),
    sessionStore: store,
    autoReconnectSensors: false,
  );
}

PullTest _test({String id = 'hist1', double peak = 42.5}) {
  final samples = [
    ForceSample(timeMs: 0, forceKg: 1),
    ForceSample(timeMs: 200, forceKg: peak),
    ForceSample(timeMs: 400, forceKg: 10),
  ];
  return PullTest(
    id: id,
    startTime: DateTime.utc(2026, 5, 1, 10),
    type: TestType.peakForce,
    samples: samples,
    metrics: computeMetrics(samples).toJson(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    TestStorage.close();
    TestStorage.initializeMemory();
  });

  tearDown(TestStorage.close);

  testWidgets('Progressor app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Live'), findsAtLeastNWidgets(1));
    expect(find.text('History'), findsAtLeastNWidgets(1));
    expect(find.text('More'), findsAtLeastNWidgets(1));
    // Three tabs only: the training guide moved under More.
    expect(find.text('Train'), findsNothing);

    // Nothing connected: one clear choice, connect or try the demo.
    expect(find.byKey(const Key('live_sensor_status')), findsOneWidget);
    expect(find.text('No gauge connected'), findsOneWidget);
    expect(find.byKey(const Key('live_pair')), findsOneWidget);
    expect(find.byKey(const Key('live_try_demo')), findsOneWidget);
    // No Start / Tare until there is something to measure.
    expect(find.byKey(const Key('live_start')), findsNothing);
  });

  testWidgets('connect panel fits on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('live_try_demo')), findsOneWidget);
  });

  testWidgets('history lists persisted tests after reload', (tester) async {
    await TestStorage().save(_test());
    final store = SessionStore();
    await store.load();

    await tester.pumpWidget(_app(store: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('History').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('history_list')), findsOneWidget);
    expect(find.textContaining('Peak Force'), findsWidgets);
    expect(find.textContaining('42.5'), findsWidgets);
  });

  testWidgets('onboarding shows when not completed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Progressor'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('onboarding_start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('live_try_demo')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
  });

  testWidgets('training guide is reachable from More', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.text('More').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('more_guide_tile')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Training guide'), findsWidgets);
  });

  testWidgets('history warns when sessions cannot be saved to disk', (
    tester,
  ) async {
    progressorStorageIsPersistent = false;
    progressorStorageError = 'disk full';
    addTearDown(() {
      progressorStorageIsPersistent = true;
      progressorStorageError = null;
    });
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.text('History').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('storage_warning')), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });
}
