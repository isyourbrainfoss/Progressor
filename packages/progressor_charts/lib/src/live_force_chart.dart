import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Live scrolling force-vs-time plot, built to be read at arm's length while
/// pulling:
///
/// * a fixed, stable y-scale with a few labelled gridlines (no jumping axis),
/// * one thick force line with a dot at the current value,
/// * the peak as a labelled dashed line,
/// * a target as a soft band (with tolerance) rather than a thin line,
/// * nothing else.
///
/// Pass a stable [maxKg] (see [LiveChartScale]) so the axis does not rescale
/// on every sample. Without one, the chart picks a "nice" scale from the
/// visible data.
class LiveForceChart extends StatelessWidget {
  const LiveForceChart({
    super.key,
    required this.samples,
    this.maxPoints = 4000,
    this.targetForceKg,
    this.targetToleranceKg,
    this.peakForceKg,
    this.height = 220,
    this.targetSamples,
    this.windowMs = 15000,
    this.maxKg,
    this.emptyHint = 'Waiting for force…',
    this.lineColor,
  });

  /// Force samples, oldest first, times in ms on a monotonic clock.
  final List<ForceSample> samples;

  /// Only the newest [maxPoints] samples are considered.
  final int maxPoints;

  /// Current target force, drawn as a band.
  final double? targetForceKg;

  /// Half-height of the target band. Defaults to [defaultTargetToleranceKg].
  final double? targetToleranceKg;

  /// Peak force, drawn as a labelled dashed line.
  final double? peakForceKg;

  /// Fixed height. Use `double.infinity` to fill the parent (e.g. inside an
  /// [Expanded]).
  final double height;

  /// Optional target path over time (follow-the-curve), same clock as
  /// [samples].
  final List<ForceSample>? targetSamples;

  /// Visible time window (ms). Newest samples enter on the right.
  final int windowMs;

  /// Top of the y-axis in kg. When null a nice value is derived from the data.
  final double? maxKg;

  /// Shown centred when there are no samples yet.
  final String emptyHint;

  /// Force line colour (defaults to the theme's primary colour).
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final display = samples.length > maxPoints
        ? samples.sublist(samples.length - maxPoints)
        : samples;
    List<ForceSample>? targets = targetSamples;
    if (targets != null && targets.length > maxPoints) {
      targets = targets.sublist(targets.length - maxPoints);
    }
    final cs = Theme.of(context).colorScheme;
    final peak = peakForceKg;
    final target = targetForceKg;
    return Semantics(
      label: 'Force plot',
      value: [
        if (display.isNotEmpty)
          'now ${display.last.forceKg.toStringAsFixed(1)} kg',
        if (peak != null && peak > 0) 'peak ${peak.toStringAsFixed(1)} kg',
        if (target != null && target > 0)
          'target ${target.toStringAsFixed(1)} kg',
      ].join(', '),
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: LiveForcePainter(
              samples: display,
              target: target,
              targetTolerance: targetToleranceKg,
              peak: peak,
              targetSamples: targets,
              windowMs: windowMs,
              maxKg: maxKg,
              emptyHint: emptyHint,
              lineColor: lineColor ?? cs.primary,
              textColor: cs.onSurface,
              gridColor: cs.outlineVariant,
              peakColor: const Color(0xFFFFC94D),
              targetColor: const Color(0xFF4ADE80),
            ),
          ),
        ),
      ),
    );
  }
}

/// Default half-width of the "on target" band: 12 % of the target, 1.5–8 kg.
double defaultTargetToleranceKg(double targetKg) =>
    (targetKg * 0.12).clamp(1.5, 8.0);

/// Axis tops used by the live plot. Coarse on purpose: the scale should
/// change rarely and land on round numbers.
const List<double> kLiveChartScaleSteps = [
  10,
  20,
  30,
  40,
  50,
  60,
  80,
  100,
  120,
  150,
  200,
  250,
  300,
];

/// Smallest step in [kLiveChartScaleSteps] that is >= [kg] (with headroom).
double niceChartMax(double kg, {double headroom = 1.15}) {
  final need = math.max(0.0, kg) * headroom;
  for (final s in kLiveChartScaleSteps) {
    if (need <= s) return s;
  }
  return kLiveChartScaleSteps.last;
}

/// Gridline values (excluding 0) for an axis that tops out at [maxKg]:
/// 2–5 evenly spaced round numbers.
List<double> liveChartTicks(double maxKg) {
  const candidates = [2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0];
  var step = candidates.last;
  for (final c in candidates) {
    if (maxKg / c <= 5) {
      step = c;
      break;
    }
  }
  final ticks = <double>[];
  for (var v = step; v <= maxKg + 1e-9; v += step) {
    ticks.add(v);
  }
  return ticks;
}

/// A y-axis top that grows immediately but only shrinks when the data has
/// clearly fallen away, so the plot does not "breathe" during a pull.
class LiveChartScale {
  LiveChartScale({this.minKg = 20});

  /// Never scale below this (a 20 kg axis keeps idle noise flat).
  final double minKg;

  double _maxKg = 0;

  double get maxKg => math.max(_maxKg, minKg);

  /// Feed the largest value that must be visible (window max, peak, target).
  /// When [allowShrink] is false (e.g. while recording) the axis only grows.
  double update(double neededKg, {bool allowShrink = true}) {
    final wanted = math.max(niceChartMax(neededKg), minKg);
    if (wanted > _maxKg) {
      _maxKg = wanted;
    } else if (allowShrink && neededKg < _maxKg * 0.45) {
      _maxKg = wanted;
    }
    return maxKg;
  }

  void reset() => _maxKg = 0;
}

/// Painter for [LiveForceChart]. Public for tests.
class LiveForcePainter extends CustomPainter {
  LiveForcePainter({
    required this.samples,
    required this.windowMs,
    required this.lineColor,
    required this.textColor,
    required this.gridColor,
    required this.peakColor,
    required this.targetColor,
    this.target,
    this.targetTolerance,
    this.peak,
    this.targetSamples,
    this.maxKg,
    this.emptyHint = '',
  }) : _sampleCount = samples.length,
       _lastTimeMs = samples.isEmpty ? null : samples.last.timeMs,
       _lastForceKg = samples.isEmpty ? null : samples.last.forceKg,
       _targetCount = targetSamples?.length ?? 0,
       _lastTargetTimeMs = (targetSamples == null || targetSamples.isEmpty)
           ? null
           : targetSamples.last.timeMs;

  final List<ForceSample> samples;
  final double? target;
  final double? targetTolerance;
  final double? peak;
  final List<ForceSample>? targetSamples;
  final int windowMs;
  final double? maxKg;
  final String emptyHint;
  final Color lineColor;
  final Color textColor;
  final Color gridColor;
  final Color peakColor;
  final Color targetColor;

  // Snapshots for shouldRepaint: the live list is mutated in place.
  final int _sampleCount;
  final int? _lastTimeMs;
  final double? _lastForceKg;
  final int _targetCount;
  final int? _lastTargetTimeMs;

  static const double _labelGutter = 34; // right-hand axis labels

  /// Axis top actually used for [samples] etc.
  double resolveMaxKg() {
    if (maxKg != null && maxKg! > 0) return maxKg!;
    var m = 0.0;
    for (final s in samples) {
      if (s.forceKg > m) m = s.forceKg;
    }
    for (final s in targetSamples ?? const <ForceSample>[]) {
      if (s.forceKg > m) m = s.forceKg;
    }
    if ((peak ?? 0) > m) m = peak!;
    if ((target ?? 0) > m) m = target!;
    return math.max(niceChartMax(m), 20);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= _labelGutter + 10 || size.height <= 20) return;
    final plot = Rect.fromLTWH(
      0,
      8,
      size.width - _labelGutter,
      size.height - 8 - 18,
    );
    final top = resolveMaxKg();

    double yFor(double kg) =>
        plot.bottom - (kg / top).clamp(-0.02, 1.0) * plot.height;

    // ---- grid + axis labels ----
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final base = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, base);
    _label(
      canvas,
      '0',
      Offset(plot.right + 6, plot.bottom - 7),
      textColor.withValues(alpha: 0.5),
      11,
    );
    for (final v in liveChartTicks(top)) {
      final y = yFor(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(
        canvas,
        v == top ? '${_fmtInt(v)} kg' : _fmtInt(v),
        Offset(plot.right + 6, y - 7),
        textColor.withValues(alpha: 0.5),
        11,
      );
    }
    _label(
      canvas,
      '−${(windowMs / 1000).round()} s',
      Offset(plot.left + 2, plot.bottom + 3),
      textColor.withValues(alpha: 0.4),
      11,
    );
    _label(
      canvas,
      'now',
      Offset(plot.right - 26, plot.bottom + 3),
      textColor.withValues(alpha: 0.4),
      11,
    );

    final (tMin, _, durMs) = liveChartTimeBounds(
      samples,
      targetSamples,
      windowMs,
    );
    double xFor(int t) =>
        plot.left +
        (durMs <= 0 ? 0 : ((t - tMin) / durMs).clamp(0.0, 1.0)) * plot.width;

    // ---- target band / path ----
    final t = target;
    if (t != null && t > 0) {
      final tol = targetTolerance ?? defaultTargetToleranceKg(t);
      final band = Rect.fromLTRB(
        plot.left,
        yFor(t + tol),
        plot.right,
        yFor(math.max(0, t - tol)),
      );
      canvas.drawRect(
        band,
        Paint()..color = targetColor.withValues(alpha: 0.14),
      );
      canvas.drawLine(
        Offset(plot.left, yFor(t)),
        Offset(plot.right, yFor(t)),
        Paint()
          ..color = targetColor.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
      _pill(
        canvas,
        'target ${t.toStringAsFixed(t >= 10 ? 0 : 1)}',
        Offset(plot.left + 6, band.bottom + 4),
        targetColor,
        plot,
      );
    }
    final ts = targetSamples;
    if (ts != null && ts.length > 1) {
      final p = Path();
      var first = true;
      for (final s in ts) {
        if (s.timeMs < tMin) continue;
        final o = Offset(xFor(s.timeMs), yFor(s.forceKg));
        if (first) {
          p.moveTo(o.dx, o.dy);
          first = false;
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      if (!first) {
        // Neutral colour so it reads apart from the (green when on
        // target) force line.
        canvas.drawPath(
          p,
          Paint()
            ..color = textColor.withValues(alpha: 0.55)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // ---- empty state ----
    if (samples.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: emptyHint,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.45),
            fontSize: 15,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: plot.width);
      tp.paint(
        canvas,
        Offset(
          plot.left + (plot.width - tp.width) / 2,
          plot.top + (plot.height - tp.height) / 2,
        ),
      );
      return;
    }

    // ---- force line (min/max per pixel column when dense) ----
    final pts = _decimate(xFor, yFor, plot.width);
    if (pts.isNotEmpty) {
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        line.lineTo(pts[i].dx, pts[i].dy);
      }
      final fill = Path.from(line)
        ..lineTo(pts.last.dx, plot.bottom)
        ..lineTo(pts.first.dx, plot.bottom)
        ..close();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, plot.right, plot.bottom));
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.28),
              lineColor.withValues(alpha: 0.0),
            ],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = lineColor
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.restore();

      // Current value: a dot at the leading edge.
      final head = Offset(
        xFor(samples.last.timeMs),
        yFor(samples.last.forceKg),
      );
      canvas.drawCircle(
        head,
        9,
        Paint()..color = lineColor.withValues(alpha: 0.25),
      );
      canvas.drawCircle(head, 5, Paint()..color = lineColor);
    }

    // ---- peak ----
    // Peak line only once it means something (not for idle sensor noise).
    final pk = peak;
    if (pk != null && pk >= math.max(2.0, top * 0.08)) {
      final y = yFor(pk);
      _dashed(
        canvas,
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = peakColor.withValues(alpha: 0.9)
          ..strokeWidth = 1.5,
      );
      _pill(
        canvas,
        'peak ${pk.toStringAsFixed(1)}',
        Offset(plot.left + 6, y - 22),
        peakColor,
        plot,
      );
    }
  }

  /// Screen points for the force line. When there are more samples than
  /// pixel columns, keep each column's min and max so spikes survive.
  List<Offset> _decimate(
    double Function(int) xFor,
    double Function(double) yFor,
    double width,
  ) {
    final (tMin, _, _) = liveChartTimeBounds(samples, targetSamples, windowMs);
    final visible = <ForceSample>[];
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      if (s.timeMs < tMin) {
        // Keep one point left of the window so the line enters from the edge.
        if (i + 1 < samples.length && samples[i + 1].timeMs >= tMin) {
          visible.add(s);
        }
        continue;
      }
      visible.add(s);
    }
    if (visible.length <= width * 2) {
      return [for (final s in visible) Offset(xFor(s.timeMs), yFor(s.forceKg))];
    }
    final out = <Offset>[];
    var col = -1;
    ForceSample? lo;
    ForceSample? hi;
    void flush() {
      final l = lo, h = hi;
      if (l == null || h == null) return;
      // Emit the column's extremes in time order.
      final first = l.timeMs <= h.timeMs ? l : h;
      final second = identical(first, l) ? h : l;
      out.add(Offset(xFor(first.timeMs), yFor(first.forceKg)));
      if (!identical(first, second)) {
        out.add(Offset(xFor(second.timeMs), yFor(second.forceKg)));
      }
    }

    for (final s in visible) {
      final c = xFor(s.timeMs).floor();
      if (c != col) {
        flush();
        col = c;
        lo = s;
        hi = s;
      } else {
        if (s.forceKg < lo!.forceKg) lo = s;
        if (s.forceKg > hi!.forceKg) hi = s;
      }
    }
    flush();
    return out;
  }

  void _label(Canvas c, String text, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  void _pill(Canvas c, String text, Offset at, Color color, Rect plot) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final y = at.dy.clamp(plot.top, plot.bottom - tp.height - 4);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, y, tp.width + 10, tp.height + 4),
      const Radius.circular(6),
    );
    c.drawRRect(r, Paint()..color = color);
    tp.paint(c, Offset(at.dx + 5, y + 2));
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 8.0, gap = 6.0;
    var x = a.dx;
    while (x < b.dx) {
      c.drawLine(Offset(x, a.dy), Offset(math.min(x + dash, b.dx), a.dy), p);
      x += dash + gap;
    }
  }

  static String _fmtInt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(covariant LiveForcePainter old) =>
      old.target != target ||
      old.targetTolerance != targetTolerance ||
      old.peak != peak ||
      old.windowMs != windowMs ||
      old.maxKg != maxKg ||
      old.emptyHint != emptyHint ||
      old.lineColor != lineColor ||
      old.textColor != textColor ||
      old._sampleCount != _sampleCount ||
      old._lastTimeMs != _lastTimeMs ||
      old._lastForceKg != _lastForceKg ||
      old._targetCount != _targetCount ||
      old._lastTargetTimeMs != _lastTargetTimeMs;
}

/// Returns (tMin, tMax, durationMs) for the visible window.
///
/// Always uses a **fixed** [windowMs] duration so the force curve never
/// compresses into a thin strip as the session gets longer (oscilloscope
/// style: new samples enter from the right, older ones scroll off left).
@visibleForTesting
(double, double, double) liveChartTimeBounds(
  List<ForceSample> samples,
  List<ForceSample>? targetSamples,
  int windowMs,
) {
  final win = windowMs.toDouble().clamp(2000.0, 300000.0);

  int? latest;
  int? earliest;
  var nonMonotonic = false;
  int? prev;

  void consider(int t) {
    if (prev != null && t + 500 < prev!) {
      // Time base reset (e.g. re-startMeasurement) — treat as non-monotonic.
      nonMonotonic = true;
    }
    prev = t;
    earliest = earliest == null ? t : (t < earliest! ? t : earliest);
    latest = latest == null ? t : (t > latest! ? t : latest);
  }

  for (final s in samples) {
    consider(s.timeMs);
  }
  if (targetSamples != null) {
    // Each series is checked for monotonicity on its own.
    prev = null;
    for (final s in targetSamples) {
      consider(s.timeMs);
    }
  }

  if (earliest == null || latest == null || nonMonotonic) {
    return (0.0, win, win);
  }

  final tMax = latest!.toDouble();
  final tMin = tMax - win;
  return (tMin, tMax, win);
}
