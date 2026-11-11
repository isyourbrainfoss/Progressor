import 'dart:math' as math;

import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

void main() {
  test('batched samples keep device spacing instead of arrival time', () {
    final c = MonotonicSampleClock();
    // 4 samples (12.5 ms apart) all arriving in one notification at t=1000.
    final times = [
      for (var i = 0; i < 4; i++)
        c.timeFor(hostMs: 1000, deviceUs: 2000000 + i * 12500),
    ];
    expect(times, [1000, 1012, 1025, 1037]);
    // Next notification 50 ms later continues the device timeline.
    expect(c.timeFor(hostMs: 1050, deviceUs: 2050000), 1050);
  });

  test('device clock restart re-anchors without going backwards', () {
    final c = MonotonicSampleClock();
    c.timeFor(hostMs: 1000, deviceUs: 5000000);
    final a = c.timeFor(hostMs: 1100, deviceUs: 5100000);
    final b = c.timeFor(hostMs: 1150, deviceUs: 0); // START again
    expect(b, greaterThanOrEqualTo(a));
    expect(c.timeFor(hostMs: 1200, deviceUs: 50000), b + 50);
  });

  test('large drift snaps back to host time', () {
    final c = MonotonicSampleClock(maxDriftMs: 500);
    c.timeFor(hostMs: 0, deviceUs: 0);
    // App paused 5 s but device only advanced 100 ms (lost packets).
    expect(c.timeFor(hostMs: 5000, deviceUs: 100000), 5000);
  });

  test('without device timestamps falls back to host time', () {
    final c = MonotonicSampleClock();
    expect(c.timeFor(hostMs: 10), 10);
    expect(c.timeFor(hostMs: 5), 10); // never decreases
  });

  group('metrics on realistic pulls', () {
    // Idle 2 s, 300 ms ramp to 50 kg, 3 s hold, release; 80 Hz with noise.
    List<ForceSample> pull({double noise = 0.2}) {
      final r = math.Random(1);
      return [
        for (var i = 0; i < 80 * 7; i++)
          () {
            final t = i * 12.5;
            double f;
            if (t < 2000) {
              f = 0;
            } else if (t < 2300) {
              f = 50 * (t - 2000) / 300;
            } else if (t < 5300) {
              f = 50;
            } else {
              f = math.max(0, 50 - (t - 5300) / 300 * 50);
            }
            return ForceSample(
              timeMs: t.round(),
              forceKg: f + (r.nextDouble() * 2 - 1) * noise,
            );
          }(),
      ];
    }

    test('time to peak is measured from pull onset, not session start', () {
      final m = computeMetrics(pull(noise: 0));
      expect(m.timeToPeakMs, closeTo(270, 40));
    });

    test('RFD is robust to 80 Hz sensor noise', () {
      final m = computeMetrics(pull());
      // True RFD = 50 kg / 0.3 s ≈ 167 kg/s. Raw sample-to-sample slopes
      // with ±0.2 kg noise would add up to ±32 kg/s on top.
      expect(m.rfdMax, closeTo(167, 15));
    });

    test('mean is under load (idle time excluded)', () {
      final m = computeMetrics(pull(noise: 0));
      expect(m.meanKg, greaterThan(40));
    });

    test('CF estimate ignores rest phases of repeaters', () {
      final s = <ForceSample>[];
      for (var rep = 0; rep < 6; rep++) {
        for (var i = 0; i < 100; i++) {
          final t = rep * 10000 + i * 100;
          s.add(ForceSample(timeMs: t, forceKg: i < 70 ? 30.0 - rep : 0));
        }
      }
      final m = computeMetrics(s);
      expect(m.cfEstimateKg, closeTo(25.5, 1.5));
    });
  });
}
