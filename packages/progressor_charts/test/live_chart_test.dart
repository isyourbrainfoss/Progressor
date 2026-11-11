import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

  group('y-scale', () {
    test('niceChartMax lands on round steps with headroom', () {
      expect(niceChartMax(0), 10);
      expect(niceChartMax(8), 10);
      expect(niceChartMax(9), 20); // 9 * 1.15 > 10
      expect(niceChartMax(42), 50);
      expect(niceChartMax(44), 60);
      expect(niceChartMax(1000), 300);
    });

    test('ticks are 2–5 round values up to the top', () {
      expect(liveChartTicks(20), [5, 10, 15, 20].map((e) => e.toDouble()));
      expect(liveChartTicks(50), [10, 20, 30, 40, 50].map((e) => e.toDouble()));
      expect(liveChartTicks(60), [20, 40, 60].map((e) => e.toDouble()));
      for (final top in kLiveChartScaleSteps) {
        final t = liveChartTicks(top);
        expect(t.length, inInclusiveRange(2, 5), reason: 'top $top');
        expect(t.last, lessThanOrEqualTo(top));
      }
    });

    test('scale grows at once but does not breathe', () {
      final s = LiveChartScale();
      expect(s.update(1), 20); // idle noise sits on a 20 kg axis
      expect(s.update(42), 50);
      // Release after a pull: stays put until clearly lower.
      expect(s.update(30), 50);
      expect(s.update(25), 50);
      // While recording it never shrinks.
      expect(s.update(2, allowShrink: false), 50);
      // Idle and clearly lower: shrink back.
      expect(s.update(2), 20);
      s.reset();
      expect(s.maxKg, 20);
    });
  });

  group('painter', () {
    LiveForcePainter painter({
      List<ForceSample> samples = const [],
      double? peak,
      double? target,
      List<ForceSample>? targetSamples,
      double? maxKg,
    }) => LiveForcePainter(
      samples: samples,
      peak: peak,
      target: target,
      targetSamples: targetSamples,
      maxKg: maxKg,
      windowMs: 12000,
      emptyHint: 'Waiting…',
      lineColor: Colors.orange,
      textColor: Colors.white,
      gridColor: Colors.grey,
      peakColor: Colors.amber,
      targetColor: Colors.green,
    );

    void paint(LiveForcePainter p, {Size size = const Size(400, 300)}) {
      final rec = ui.PictureRecorder();
      p.paint(Canvas(rec), size);
      rec.endRecording().dispose();
    }

    List<ForceSample> pull({int n = 80 * 20, double peak = 42}) => [
      for (var i = 0; i < n; i++)
        ForceSample(
          timeMs: (i * 12.5).round(),
          forceKg: i > n / 2 && i < n / 2 + 300 ? peak : 0.5,
        ),
    ];

    test('paints empty, dense, target and tiny sizes without throwing', () {
      paint(painter());
      paint(painter(samples: pull(), peak: 42, maxKg: 50));
      paint(painter(samples: pull(), target: 16, maxKg: 20));
      paint(
        painter(
          samples: pull(),
          targetSamples: [
            for (var t = 0; t < 20000; t += 100)
              ForceSample(timeMs: t, forceKg: (t % 12000) / 500),
          ],
        ),
      );
      paint(painter(samples: pull()), size: const Size(10, 10));
      paint(painter(samples: pull()), size: const Size(2000, 120));
    });

    test('derives a nice axis from data when none is given', () {
      expect(painter(samples: pull(peak: 42)).resolveMaxKg(), 50);
      expect(painter(samples: pull(peak: 3)).resolveMaxKg(), 20);
      expect(painter(target: 70).resolveMaxKg(), 100);
      expect(painter(maxKg: 120).resolveMaxKg(), 120);
    });

    test('repaints when a sample is appended to the same list', () {
      final list = pull(n: 100);
      final a = painter(samples: list);
      list.add(const ForceSample(timeMs: 99999, forceKg: 3));
      final b = painter(samples: list);
      expect(b.shouldRepaint(a), isTrue);
      expect(painter(samples: list).shouldRepaint(b), isFalse);
    });
  });

  testWidgets('chart reports now / peak / target for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveForceChart(
            samples: const [
              ForceSample(timeMs: 0, forceKg: 1),
              ForceSample(timeMs: 100, forceKg: 12.34),
            ],
            peakForceKg: 40,
            targetForceKg: 16,
            height: 200,
          ),
        ),
      ),
    );
    final sem = tester.getSemantics(find.byType(LiveForceChart));
    expect(sem.value, contains('now 12.3 kg'));
    expect(sem.value, contains('peak 40.0 kg'));
    expect(sem.value, contains('target 16.0 kg'));
  });
}
