import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

Future<(DemoProgressorAdapter, List<SensorSample>)> _connected() async {
  final demo = DemoProgressorAdapter(realTime: false);
  final samples = <SensorSample>[];
  demo.samples.listen(samples.add);
  await demo.connect();
  await demo.startMeasurement();
  return (demo, samples);
}

double _mean(Iterable<SensorSample> s) =>
    s.map((e) => e.forceKg).reduce((a, b) => a + b) / s.length;

double _max(Iterable<SensorSample> s) =>
    s.map((e) => e.forceKg).reduce(math.max);

void main() {
  test('implements the same interface as the BLE adapter', () {
    final ProgressorAdapter demo = DemoProgressorAdapter(realTime: false);
    expect(demo.isDemo, isTrue);
    expect(TindeqBleAdapter(), isA<ProgressorAdapter>());
  });

  test('connects, reports battery + firmware and a demo name', () async {
    final demo = DemoProgressorAdapter(realTime: false);
    final states = <SensorConnectionState>[];
    demo.state.listen(states.add);
    expect(await demo.readBatteryMillivolts(), isNull);
    await demo.connect();
    await Future<void>.delayed(Duration.zero);
    expect(states, [
      SensorConnectionState.connecting,
      SensorConnectionState.connected,
    ]);
    expect(demo.deviceName, contains('DEMO'));
    expect(await demo.readBatteryMillivolts(), inInclusiveRange(3300, 4250));
    expect(await demo.readBatteryPercent(), inInclusiveRange(1, 100));
    expect(await demo.readFirmwareVersion(), isNotEmpty);
  });

  test(
    'streams nothing until START, then ~80 Hz with device timestamps',
    () async {
      final demo = DemoProgressorAdapter(realTime: false);
      final samples = <SensorSample>[];
      demo.samples.listen(samples.add);
      await demo.connect();
      demo.advance(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(samples, isEmpty);

      await demo.startMeasurement();
      demo.advance(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(samples.length, inInclusiveRange(158, 162));
      expect(demo.packetsSent, greaterThan(20)); // batched notifications
      for (var i = 1; i < samples.length; i++) {
        final dt = samples[i].rawTimestampUs! - samples[i - 1].rawTimestampUs!;
        expect(dt, 12500);
      }
      await demo.stopMeasurement();
      final n = samples.length;
      demo.advance(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(samples.length, n);
    },
  );

  test('idles near the zero offset; tare brings it to ~0 kg', () async {
    final (demo, samples) = await _connected();
    demo.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(_mean(samples), closeTo(demo.climber.zeroOffsetKg, 0.2));

    await demo.tare();
    samples.clear();
    demo.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(_mean(samples), closeTo(0, 0.08));
    expect(_max(samples).abs(), lessThan(0.3));
  });

  test(
    'max pull: ramps with finite RFD, peaks near max, fades, releases',
    () async {
      final (demo, samples) = await _connected();
      await demo.tare();
      demo.guide(recording: true, type: TestType.peakForce, phase: 'READY');
      demo.advance(const Duration(milliseconds: 1500));
      demo.guide(recording: true, type: TestType.peakForce, phase: 'PULL');
      demo.advance(const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);

      final m = computeMetrics(samples);
      final maxKg = demo.climber.maxKg;
      expect(m.peakKg, inInclusiveRange(maxKg * 0.85, maxKg * 1.1));
      expect(m.rfdMax, inInclusiveRange(60, 600)); // realistic kg/s
      expect(m.timeToPeakMs, inInclusiveRange(150, 3000));
      // Released at the end.
      expect(samples.last.forceKg, lessThan(3));
      // Fatigue: last second of the hold below the peak.
      final peakT = samples
          .firstWhere((s) => s.forceKg >= m.peakKg! - 1e-9)
          .timeMs;
      final late = samples.where(
        (s) => s.timeMs > peakT + 2000 && s.forceKg > 10,
      );
      expect(_mean(late), lessThan(m.peakKg! * 0.98));
    },
  );

  test('repeaters follow the workout on/off timing', () async {
    final (demo, samples) = await _connected();
    await demo.tare();
    const target = 18.0;
    final windows = <(int, int)>[];
    var t = 0;
    for (var rep = 0; rep < 3; rep++) {
      demo.guide(
        recording: true,
        type: TestType.repeaters,
        phase: 'WORK',
        targetKg: target,
      );
      windows.add((t, t + 7000));
      demo.advance(const Duration(seconds: 7));
      demo.guide(
        recording: true,
        type: TestType.repeaters,
        phase: 'REST',
        targetKg: 0,
      );
      demo.advance(const Duration(seconds: 3));
      t += 10000;
    }
    await Future<void>.delayed(Duration.zero);
    for (final (start, end) in windows) {
      final hold = samples.where(
        (s) => s.timeMs > start + 1200 && s.timeMs < end,
      );
      expect(_mean(hold), closeTo(target, 2.5));
      final rest = samples.where(
        (s) => s.timeMs > end + 1200 && s.timeMs < end + 3000,
      );
      expect(_mean(rest).abs(), lessThan(1.0));
    }
  });

  test('follow-the-curve tracks a moving target with lag', () async {
    final (demo, samples) = await _connected();
    await demo.tare();
    for (var i = 0; i < 50; i++) {
      final target = 25.0 * (i / 50);
      demo.guide(
        recording: true,
        type: TestType.followCurve,
        phase: 'RAMP',
        targetKg: target,
      );
      demo.advance(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(Duration.zero);
    final last = samples.where((s) => s.timeMs > 4500);
    expect(_mean(last), closeTo(23, 3));
  });

  test('deterministic for a given seed', () async {
    Future<List<double>> run() async {
      final demo = DemoProgressorAdapter(
        realTime: false,
        climber: SimulatedClimber(seed: 7),
      );
      final out = <double>[];
      demo.samples.listen((s) => out.add(s.forceKg));
      await demo.connect();
      await demo.startMeasurement();
      demo.guide(recording: true, type: TestType.custom, phase: 'FREE');
      demo.advance(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      return out;
    }

    expect(await run(), await run());
  });

  test('real-time mode streams on a timer', () async {
    final demo = DemoProgressorAdapter(connectDelay: Duration.zero);
    final samples = <SensorSample>[];
    demo.samples.listen(samples.add);
    await demo.connect();
    await demo.startMeasurement();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await demo.disconnect();
    expect(samples.length, inInclusiveRange(30, 60));
  });
}
