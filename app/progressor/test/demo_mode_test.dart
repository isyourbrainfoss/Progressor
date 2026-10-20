import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/live/protocol_session.dart';
import 'package:progressor/main.dart';
import 'package:progressor/persistence/session_store.dart';
import 'package:progressor/screens/onboarding_screen.dart';
import 'package:progressor/sensors/ble_transport.dart';
import 'package:progressor/sensors/sensor_hub.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs a [ProtocolSession] against the simulated Progressor for [seconds],
/// ticking every 100 ms like the Live screen does.
Future<(ProtocolSession, List<ForceSample>)> _runSession(
  TestType type, {
  double userMaxKg = 40,
  int seconds = 10,
}) async {
  final demo = DemoProgressorAdapter(realTime: false);
  final samples = <ForceSample>[];
  final session = ProtocolSession(type: type, userMaxKg: userMaxKg);
  demo.samples.listen((s) {
    samples.add(s);
    session.onSample(s);
  });
  await demo.connect();
  await demo.startMeasurement();
  await demo.tare();
  final t0 = DateTime(2026, 1, 1, 12);
  session.start(t0);
  for (var i = 1; i <= seconds * 10; i++) {
    demo.guide(
      recording: true,
      type: type,
      phase: session.phaseLabel,
      targetKg: session.targetForceKg,
    );
    demo.advance(const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration.zero);
    session.tick(t0.add(Duration(milliseconds: 100 * i)));
  }
  return (session, samples);
}

void main() {
  group('protocols driven by the demo device', () {
    test(
      'repeaters 7:3 × 6 completes with pulls in every WORK window',
      () async {
        final (session, samples) = await _runSession(
          TestType.repeaters,
          seconds: 62,
        );
        expect(session.phaseLabel, 'DONE');
        expect(session.metricsExtras['completedReps'], 6);
        // Count distinct pulls (threshold crossings).
        var pulls = 0;
        var above = false;
        for (final s in samples) {
          if (!above && s.forceKg > 8) {
            pulls++;
            above = true;
          } else if (above && s.forceKg < 3) {
            above = false;
          }
        }
        expect(pulls, 6);
        final m = computeMetrics(samples);
        expect(m.meanKg, closeTo(16, 2.5)); // 40 % of 40 kg, under load
        expect(m.cfEstimateKg, isNotNull);
      },
    );

    test('peak force: realistic peak, TTP and RFD', () async {
      final (session, samples) = await _runSession(TestType.peakForce);
      expect(session.phaseLabel, 'DONE');
      final peak = session.metricsExtras['sessionPeakKg'] as double;
      expect(peak, inInclusiveRange(38, 52));
      final m = computeMetrics(samples);
      expect(m.timeToPeakMs, inInclusiveRange(100, 3500));
      expect(m.rfdMax, inInclusiveRange(60, 600));
    });

    test('RFD: time-to-peak from onset and windowed RFD', () async {
      final (session, _) = await _runSession(TestType.rfd, seconds: 6);
      expect(session.phaseLabel, 'DONE');
      final ttp = session.metricsExtras['timeToPeakMs'] as int;
      expect(ttp, inInclusiveRange(80, 1200));
      final rfd = session.metricsExtras['rfdPeakKgPerS'] as double;
      expect(rfd, inInclusiveRange(100, 700));
    });

    test('follow the curve: virtual climber matches the target', () async {
      final (session, _) = await _runSession(TestType.followCurve, seconds: 12);
      expect(session.matchPercent, greaterThan(50));
    });
  });

  group('SensorHub demo device', () {
    test('start/stop demo makes it the active Progressor', () async {
      final hub = SensorHub(
        demoAdapterFactory: () => DemoProgressorAdapter(realTime: false),
      );
      expect(hub.hasLiveSource, isFalse);
      await hub.startDemo();
      expect(hub.isDemoActive, isTrue);
      expect(hub.hasLiveSource, isTrue);
      expect(hub.activeProgressor?.isDemo, isTrue);
      expect(hub.activeProgressor?.isMeasuring, isTrue);
      await hub.stopDemo();
      expect(hub.activeAdapter, isNull);
      hub.dispose();
    });
  });

  group('demo sessions do not touch real progress', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestStorage.close();
      TestStorage.initializeMemory();
    });
    tearDown(TestStorage.close);

    test('no PR, streak, XP or badges from demo sessions', () async {
      final store = SessionStore();
      await store.load();
      final r = await store.record(
        PullTest(
          id: 'demo1',
          startTime: DateTime(2026, 1, 1),
          type: TestType.peakForce,
          samples: const [
            ForceSample(timeMs: 0, forceKg: 0),
            ForceSample(timeMs: 500, forceKg: 120),
          ],
          metrics: const {'source': 'demo'},
        ),
      );
      expect(r.isNewPr, isFalse);
      expect(r.streak, 0);
      expect(store.xp, 0);
      expect(store.unlockedIds, isEmpty);
      expect(store.tests, hasLength(1));
      expect(store.index, 0);
    });
  });

  group('demo UI', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
      TestStorage.close();
      TestStorage.initializeMemory();
    });
    tearDown(TestStorage.close);

    late DemoProgressorAdapter demo;
    SensorHub hub() => SensorHub(
      bleBackend: const UnsupportedBleConnectionBackend(message: 'test'),
      demoAdapterFactory: () => demo = DemoProgressorAdapter(realTime: false),
    );

    testWidgets('Sensors screen lists a demo device; Live shows DEMO', (
      tester,
    ) async {
      final h = hub();
      await tester.pumpWidget(
        ProgressorApp(sensorHub: h, autoReconnectSensors: false),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Sensors'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final connect = find.byKey(const Key('sensors_demo_connect'));
      await tester.scrollUntilVisible(connect, 200);
      await tester.tap(connect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.isDemoActive, isTrue);
      expect(find.byKey(const Key('sensors_demo_disconnect')), findsOneWidget);
      expect(find.byKey(const Key('sensors_device_info')), findsOneWidget);
      expect(find.textContaining('DEMO'), findsWidgets);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('demo_badge')), findsOneWidget);

      // Samples flow to the readout.
      demo.advance(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('—'), findsNothing);
      await h.stopDemo();
      await tester.pump();
    });

    testWidgets('Live: demo → tare → START peak → STOP saves a DEMO session', (
      tester,
    ) async {
      final h = hub();
      final store = SessionStore();
      await store.load();
      await tester.pumpWidget(
        ProgressorApp(
          sensorHub: h,
          sessionStore: store,
          autoReconnectSensors: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('live_try_demo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.isDemoActive, isTrue);

      demo.advance(const Duration(milliseconds: 300));
      await tester.tap(find.text('Tare'));
      await tester.pump();
      expect(demo.tareOffsetKg, greaterThan(1));

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 70; i++) {
        demo.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('demo_badge')), findsOneWidget);
      await tester.tap(find.text('STOP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(store.tests, hasLength(1));
      final t = store.tests.single;
      expect(t.isDemo, isTrue);
      expect(t.notes, startsWith('DEMO'));
      expect(t.peakForceKg, greaterThan(30));
      // ~7 s at 80 Hz, no duplicated samples.
      expect(t.samples.length, inInclusiveRange(450, 620));
      await h.stopDemo();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('DEMO dart-define path starts in demo without onboarding', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final h = hub();
      await tester.pumpWidget(
        ProgressorApp(
          sensorHub: h,
          autoReconnectSensors: false,
          startInDemo: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Skip'), findsNothing);
      expect(h.isDemoActive, isTrue);
      expect(find.byKey(const Key('demo_badge')), findsOneWidget);
      await h.stopDemo();
      await tester.pump();
    });
  });
}
