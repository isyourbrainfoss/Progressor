import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Beautiful live scrolling force vs time chart.
/// Uses CustomPainter for buttery smooth  high update rates.
class LiveForceChart extends StatefulWidget {
  const LiveForceChart({
    super.key,
    required this.samples,
    this.maxPoints = 600,
    this.targetForceKg,
    this.peakForceKg,
    this.height = 220,
  });

  final List<ForceSample> samples;
  final int maxPoints;
  final double? targetForceKg;
  final double? peakForceKg;
  final double height;

  @override
  State<LiveForceChart> createState() => _LiveForceChartState();
}

class _LiveForceChartState extends State<LiveForceChart> {
  @override
  Widget build(BuildContext context) {
    final displaySamples = widget.samples.length > widget.maxPoints
        ? widget.samples.sublist(widget.samples.length - widget.maxPoints)
        : widget.samples;

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _ForcePainter(
            samples: displaySamples,
            target: widget.targetForceKg,
            peak: widget.peakForceKg,
            colorScheme: Theme.of(context).colorScheme,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ForcePainter extends CustomPainter {
  _ForcePainter({
    required this.samples,
    this.target,
    this.peak,
    required this.colorScheme,
  });

  final List<ForceSample> samples;
  final double? target;
  final double? peak;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }

    final paintGrid = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.3)
      ..strokeWidth = 1;

    final paintLine = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colorScheme.primary.withOpacity(0.35),
          colorScheme.primary.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final paintTarget = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Compute bounds
    double maxF = samples.map((s) => s.forceKg).fold(0.0, (p, c) => p > c ? p : c);
    maxF = (maxF * 1.2).clamp(10.0, 300.0);
    final minF = 0.0;
    final durationMs = (samples.last.timeMs - samples.first.timeMs).toDouble().clamp(1000.0, 300000.0);

    // Draw grid
    const hLines = 5;
    for (int i = 0; i <= hLines; i++) {
      final y = size.height - (i / hLines) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    // Draw line + fill
    final path = Path();
    final fillPath = Path();
    bool first = true;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x = durationMs > 0
          ? ((s.timeMs - samples.first.timeMs) / durationMs) * size.width
          : (i / (samples.length - 1)) * size.width;
      final norm = (s.forceKg - minF) / (maxF - minF);
      final y = size.height - norm.clamp(0.0, 1.0) * size.height;

      if (first) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);

    // Target line
    if (target != null && target! > 0) {
      final ty = size.height - (target! / maxF).clamp(0.0, 1.0) * size.height;
      canvas.drawLine(Offset(0, ty), Offset(size.width, ty), paintTarget);
      final tp = TextPainter(
        text: TextSpan(
          text: '${target!.toStringAsFixed(1)} kg target',
          style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, ty - 14));
    }

    // Peak annotation
    if (peak != null) {
      final py = size.height - (peak! / maxF).clamp(0.0, 1.0) * size.height;
      final ppaint = Paint()..color = colorScheme.tertiary..strokeWidth = 1;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), ppaint);
    }

    // Labels
    final maxLabel = TextPainter(
      text: TextSpan(
        text: '${maxF.toStringAsFixed(0)} kg',
        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxLabel.paint(canvas, const Offset(4, 4));
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final p = Paint()..color = colorScheme.outlineVariant.withOpacity(0.2);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.3, size.width, size.height * 0.4), p);
  }

  @override
  bool shouldRepaint(covariant _ForcePainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.target != target ||
      oldDelegate.peak != peak;
}
