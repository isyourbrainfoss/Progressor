import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

List<ForceSample> _ramp({
  required double peakKg,
  int points = 50,
  int stepMs = 20,
}) {
  return [
    for (var i = 0; i < points; i++)
      ForceSample(timeMs: i * stepMs, forceKg: peakKg * (i / (points - 1))),
  ];
}

void main() {
  test('empty samples yield empty metrics', () {
    final m = computeMetrics(const []);
    expect(m.peakKg, isNull);
    expect(m.meanKg, isNull);
    expect(m.durationS, isNull);
  });

  test('peak, mean, duration and time-to-peak on a ramp', () {
    final samples = _ramp(peakKg: 80);
    final m = computeMetrics(samples);
    expect(m.peakKg, closeTo(80, 0.01));
    // Mean under load: samples below 10 % of peak (idle) are excluded.
    expect(m.meanKg, closeTo(44, 1.5));
    expect(m.durationS, closeTo(0.98, 0.05));
    expect(m.timeToPeakMs, greaterThan(0));
    expect(m.rfdMax, greaterThan(0));
  });

  test('RFD is force rise over time', () {
    final samples = [
      const ForceSample(timeMs: 0, forceKg: 0),
      const ForceSample(timeMs: 100, forceKg: 50), // 500 kg/s
      const ForceSample(timeMs: 200, forceKg: 50),
    ];
    final m = computeMetrics(samples);
    expect(m.rfdMax, closeTo(500, 0.1));
    expect(m.peakKg, closeTo(50, 0.01));
  });

  test('CF estimate uses the late window on long hangs', () {
    final samples = [
      for (var i = 0; i < 40; i++)
        ForceSample(
          timeMs: i * 500, // 20s
          forceKg: i < 24 ? 70 : 40,
        ),
    ];
    final m = computeMetrics(samples);
    expect(m.cfEstimateKg, isNotNull);
    expect(m.cfEstimateKg!, closeTo(40, 5));
  });

  test('PullTest.computedMetrics prefers stored metrics json', () {
    final t = PullTest(
      id: 'a',
      startTime: DateTime.utc(2026, 1, 1),
      type: TestType.peakForce,
      samples: _ramp(peakKg: 10),
      metrics: const {'peakKg': 99.0, 'meanKg': 1.0},
    );
    expect(t.computedMetrics.peakKg, 99.0);
  });

  test('peakForceKg falls back to stored metrics when samples are empty', () {
    final t = PullTest(
      id: 'b',
      startTime: DateTime.utc(2026, 1, 1),
      type: TestType.peakForce,
      samples: const [],
      metrics: const {'peakKg': 42.5},
    );
    expect(t.peakForceKg, 42.5);
  });
}
