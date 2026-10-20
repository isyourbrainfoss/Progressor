import 'package:flutter_test/flutter_test.dart';
import 'package:progressor_charts/src/live_force_chart.dart';
import 'package:progressor_core/progressor_core.dart';

void main() {
  test('window ends at the latest sample when a target path is present', () {
    final samples = [
      for (var t = 0; t <= 20000; t += 100) ForceSample(timeMs: t, forceKg: 1),
    ];
    final targets = [
      for (var t = 0; t <= 20000; t += 100) ForceSample(timeMs: t, forceKg: 5),
    ];
    final (tMin, tMax, dur) = liveChartTimeBounds(samples, targets, 12000);
    expect(tMax, 20000);
    expect(tMin, 8000);
    expect(dur, 12000);
  });

  test('a real time-base reset still falls back to a fixed window', () {
    final samples = [
      const ForceSample(timeMs: 9000, forceKg: 1),
      const ForceSample(timeMs: 100, forceKg: 1),
    ];
    final (tMin, _, dur) = liveChartTimeBounds(samples, null, 12000);
    expect(tMin, 0);
    expect(dur, 12000);
  });
}
