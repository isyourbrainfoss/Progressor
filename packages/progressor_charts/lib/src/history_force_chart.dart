import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// History / replay force chart.
///
/// When [interactive] is true: pinch or scroll-wheel zoom, drag to pan,
/// double-tap to reset. Peak is marked with a dot + label.
class HistoryForceChart extends StatefulWidget {
  const HistoryForceChart({
    super.key,
    required this.samples,
    this.compareSamples,
    this.height = 180,
    this.showRfd = false,
    this.interactive = false,
    this.showPeak = true,
  });

  final List<ForceSample> samples;
  final List<ForceSample>? compareSamples;
  final double? height;
  final bool showRfd;
  final bool interactive;
  final bool showPeak;

  @override
  State<HistoryForceChart> createState() => _HistoryForceChartState();
}

class _HistoryForceChartState extends State<HistoryForceChart> {
  /// Visible time window as fractions of the full span (0–1).
  double _t0 = 0;
  double _t1 = 1;
  double _yZoom = 1;

  double _scaleStartT0 = 0;
  double _scaleStartT1 = 1;
  double _scaleStartY = 1;

  void _reset() {
    setState(() {
      _t0 = 0;
      _t1 = 1;
      _yZoom = 1;
    });
  }

  void _applyZoom({
    required double scale,
    required double focalFrac,
  }) {
    final startSpan = (_scaleStartT1 - _scaleStartT0).clamp(0.02, 1.0);
    final newSpan = (startSpan / scale).clamp(0.02, 1.0);
    var t0 = _scaleStartT0 + (startSpan - newSpan) * focalFrac;
    var t1 = t0 + newSpan;
    if (t0 < 0) {
      t1 -= t0;
      t0 = 0;
    }
    if (t1 > 1) {
      t0 -= (t1 - 1);
      t1 = 1;
    }
    t0 = t0.clamp(0.0, 1.0);
    t1 = t1.clamp(0.0, 1.0);
    if (t1 - t0 < 0.02) t1 = (t0 + 0.02).clamp(0.0, 1.0);

    final y = (_scaleStartY * scale).clamp(0.6, 8.0);
    setState(() {
      _t0 = t0;
      _t1 = t1;
      _yZoom = y;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.samples.isEmpty) {
      return SizedBox(
        height: widget.height ?? 180,
        child: const Center(child: Text('No data')),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final peak = widget.samples
        .map((s) => s.forceKg)
        .reduce((a, b) => a > b ? a : b);

    Widget chart = CustomPaint(
      painter: _HistoryPainter(
        samples: widget.samples,
        compareSamples: widget.compareSamples,
        colorScheme: cs,
        t0: _t0,
        t1: _t1,
        yZoom: _yZoom,
        showPeak: widget.showPeak,
      ),
      child: const SizedBox.expand(),
    );

    if (widget.interactive) {
      chart = Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize || box.size.width <= 0) return;
            final local = box.globalToLocal(signal.position);
            _scaleStartT0 = _t0;
            _scaleStartT1 = _t1;
            _scaleStartY = _yZoom;
            final scale = signal.scrollDelta.dy > 0 ? 0.85 : 1.18;
            _applyZoom(
              scale: scale,
              focalFrac: (local.dx / box.size.width).clamp(0.0, 1.0),
            );
          }
        },
        child: GestureDetector(
          onDoubleTap: _reset,
          onScaleStart: (d) {
            _scaleStartT0 = _t0;
            _scaleStartT1 = _t1;
            _scaleStartY = _yZoom;
          },
          onScaleUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize || box.size.width <= 0) return;
            if (d.pointerCount >= 2 || d.scale != 1.0) {
              _applyZoom(
                scale: d.scale,
                focalFrac:
                    (d.localFocalPoint.dx / box.size.width).clamp(0.0, 1.0),
              );
            } else {
              final span = _t1 - _t0;
              final shift = -d.focalPointDelta.dx / box.size.width * span;
              var t0 = (_t0 + shift).clamp(0.0, 1.0);
              var t1 = t0 + span;
              if (t1 > 1) {
                t1 = 1;
                t0 = (1 - span).clamp(0.0, 1.0);
              }
              setState(() {
                _t0 = t0;
                _t1 = t1;
              });
            }
          },
          child: chart,
        ),
      );
    }

    chart = Semantics(
      label: 'Force curve, peak ${peak.toStringAsFixed(1)} kilograms',
      child: chart,
    );

    if (widget.height == null) {
      return chart;
    }
    return SizedBox(height: widget.height, child: chart);
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.samples,
    required this.colorScheme,
    required this.t0,
    required this.t1,
    required this.yZoom,
    this.compareSamples,
    this.showPeak = true,
  });

  final List<ForceSample> samples;
  final List<ForceSample>? compareSamples;
  final ColorScheme colorScheme;
  final double t0;
  final double t1;
  final double yZoom;
  final bool showPeak;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final sorted = List<ForceSample>.from(samples)
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    if (sorted.isEmpty) return;

    final minT = sorted.first.timeMs.toDouble();
    final maxT = sorted.last.timeMs.toDouble();
    final fullSpan = (maxT - minT).clamp(1.0, 1e12);
    final viewMinT = minT + fullSpan * t0;
    final viewMaxT = minT + fullSpan * t1;
    final viewSpan = (viewMaxT - viewMinT).clamp(1.0, 1e12);

    var maxF = 1.0;
    for (final s in sorted) {
      if (s.forceKg > maxF) maxF = s.forceKg;
    }
    if (compareSamples != null) {
      for (final s in compareSamples!) {
        if (s.forceKg > maxF) maxF = s.forceKg;
      }
    }
    maxF = (maxF * 1.12 / yZoom).clamp(1.0, 1000.0);

    const leftPad = 36.0;
    const bottomPad = 22.0;
    const topPad = 8.0;
    final plot = Rect.fromLTWH(
      leftPad,
      topPad,
      (size.width - leftPad - 8).clamp(1.0, size.width),
      (size.height - topPad - bottomPad).clamp(1.0, size.height),
    );

    final grid = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: (maxF * i / 4).toStringAsFixed(0),
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.55),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(plot.left - label.width - 4, y - label.height / 2),
      );
    }

    double xFor(int timeMs) {
      return plot.left + ((timeMs - viewMinT) / viewSpan).clamp(0.0, 1.0) * plot.width;
    }

    double yFor(double kg) {
      return plot.bottom - (kg / maxF).clamp(0.0, 1.0) * plot.height;
    }

    void drawSeries(List<ForceSample> series, Color color, {double width = 2}) {
      if (series.isEmpty) return;
      final ordered = List<ForceSample>.from(series)
        ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      for (final s in ordered) {
        if (s.timeMs < viewMinT - 1 || s.timeMs > viewMaxT + 1) {
          if (s.timeMs > viewMaxT) break;
          continue;
        }
        final x = xFor(s.timeMs);
        final y = yFor(s.forceKg);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (started) canvas.drawPath(path, paint);
    }

    if (compareSamples != null && compareSamples!.isNotEmpty) {
      drawSeries(
        compareSamples!,
        colorScheme.secondary.withValues(alpha: 0.7),
        width: 1.6,
      );
    }
    drawSeries(sorted, colorScheme.primary, width: 2.2);

    if (showPeak) {
      ForceSample? peakS;
      for (final s in sorted) {
        if (peakS == null || s.forceKg > peakS.forceKg) peakS = s;
      }
      if (peakS != null &&
          peakS.timeMs >= viewMinT &&
          peakS.timeMs <= viewMaxT) {
        final p = Offset(xFor(peakS.timeMs), yFor(peakS.forceKg));
        canvas.drawCircle(p, 5, Paint()..color = colorScheme.tertiary);
        canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = colorScheme.surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${peakS.forceKg.toStringAsFixed(1)} kg',
            style: TextStyle(
              color: colorScheme.tertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = (p.dx + 8).clamp(plot.left, plot.right - tp.width);
        final ly = (p.dy - 16).clamp(plot.top, plot.bottom - tp.height);
        tp.paint(canvas, Offset(lx, ly));
      }
    }

    final durS = (viewMaxT - viewMinT) / 1000.0;
    final startS = (viewMinT - minT) / 1000.0;
    final timeStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.55),
      fontSize: 10,
    );
    final tLeft = TextPainter(
      text: TextSpan(text: '${startS.toStringAsFixed(1)}s', style: timeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tLeft.paint(canvas, Offset(plot.left, plot.bottom + 4));
    final tRight = TextPainter(
      text: TextSpan(
        text: '${(startS + durS).toStringAsFixed(1)}s',
        style: timeStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tRight.paint(
      canvas,
      Offset(plot.right - tRight.width, plot.bottom + 4),
    );
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter old) {
    return old.samples != samples ||
        old.compareSamples != compareSamples ||
        old.colorScheme != colorScheme ||
        old.t0 != t0 ||
        old.t1 != t1 ||
        old.yZoom != yZoom ||
        old.showPeak != showPeak;
  }
}
