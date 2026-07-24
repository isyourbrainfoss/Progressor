import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Beautiful live scrolling force vs time chart.
/// Uses CustomPainter for buttery smooth high update rates.
class LiveForceChart extends StatefulWidget {
  const LiveForceChart({
    super.key,
    required this.samples,
    this.maxPoints = 600,
    this.targetForceKg,
    this.peakForceKg,
    this.height = 220,
    this.targetSamples,
    this.targetHistoryKg,
    this.windowMs = 15000,
  });

  final List<ForceSample> samples;
  final int maxPoints;

  /// Current target force as a horizontal orange guideline.
  final double? targetForceKg;

  /// Optional peak force horizontal line.
  final double? peakForceKg;
  final double height;

  /// Optional target path over time (Follow-the-Curve). Preferred when times
  /// are known; drawn as an orange stroke aligned to the same x-axis as [samples].
  final List<ForceSample>? targetSamples;

  /// Optional parallel target history in kg (same order/length as [samples] or
  /// a dense series). Used when [targetSamples] is null.
  final List<double>? targetHistoryKg;

  /// Rolling x-axis window in milliseconds. When samples span a larger range,
  /// only the last [windowMs] is shown so the plot scrolls.
  final int windowMs;

  @override
  State<LiveForceChart> createState() => _LiveForceChartState();
}

class _LiveForceChartState extends State<LiveForceChart> {
  @override
  Widget build(BuildContext context) {
    final displaySamples = widget.samples.length > widget.maxPoints
        ? widget.samples.sublist(widget.samples.length - widget.maxPoints)
        : widget.samples;

    List<ForceSample>? displayTargets;
    if (widget.targetSamples != null && widget.targetSamples!.isNotEmpty) {
      final t = widget.targetSamples!;
      displayTargets =
          t.length > widget.maxPoints ? t.sublist(t.length - widget.maxPoints) : t;
    }

    List<double>? displayTargetHistory;
    if (displayTargets == null &&
        widget.targetHistoryKg != null &&
        widget.targetHistoryKg!.isNotEmpty) {
      final h = widget.targetHistoryKg!;
      displayTargetHistory =
          h.length > widget.maxPoints ? h.sublist(h.length - widget.maxPoints) : h;
    }

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _ForcePainter(
            samples: displaySamples,
            target: widget.targetForceKg,
            peak: widget.peakForceKg,
            targetSamples: displayTargets,
            targetHistoryKg: displayTargetHistory,
            windowMs: widget.windowMs,
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
    this.targetSamples,
    this.targetHistoryKg,
    required this.windowMs,
    required this.colorScheme,
  })  : _sampleCount = samples.length,
        _lastTimeMs = samples.isEmpty ? null : samples.last.timeMs,
        _lastForceKg = samples.isEmpty ? null : samples.last.forceKg,
        _targetSampleCount = targetSamples?.length ?? 0,
        _lastTargetTimeMs = (targetSamples == null || targetSamples.isEmpty)
            ? null
            : targetSamples.last.timeMs,
        _lastTargetForceKg = (targetSamples == null || targetSamples.isEmpty)
            ? null
            : targetSamples.last.forceKg,
        _targetHistoryCount = targetHistoryKg?.length ?? 0,
        _lastTargetHistoryKg = (targetHistoryKg == null || targetHistoryKg.isEmpty)
            ? null
            : targetHistoryKg.last;

  final List<ForceSample> samples;
  final double? target;
  final double? peak;
  final List<ForceSample>? targetSamples;
  final List<double>? targetHistoryKg;
  final int windowMs;
  final ColorScheme colorScheme;

  // Snapshots for shouldRepaint — list identity is unreliable when the same
  // List is mutated in place by the live stream.
  final int _sampleCount;
  final int? _lastTimeMs;
  final double? _lastForceKg;
  final int _targetSampleCount;
  final int? _lastTargetTimeMs;
  final double? _lastTargetForceKg;
  final int _targetHistoryCount;
  final double? _lastTargetHistoryKg;

  @override
  void paint(Canvas canvas, Size size) {
    final hasTargetPath = (targetSamples != null && targetSamples!.isNotEmpty) ||
        (targetHistoryKg != null && targetHistoryKg!.isNotEmpty);
    if (samples.isEmpty && !hasTargetPath) {
      _drawEmpty(canvas, size);
      // Still show a current horizontal target if known (Follow-the-Curve start).
      if (target != null && target! > 0) {
        final maxF = (target! * 1.2).clamp(10.0, 300.0);
        final ty = size.height - (target! / maxF).clamp(0.0, 1.0) * size.height;
        final paintTarget = Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(0, ty), Offset(size.width, ty), paintTarget);
        final tp = TextPainter(
          text: TextSpan(
            text: '${target!.toStringAsFixed(1)} kg target',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelY = (ty - 14).clamp(0.0, size.height - 14);
        tp.paint(canvas, Offset(4, labelY));
      }
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

    final paintTargetPath = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.9)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintTarget = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // ---- Time window (rolling) ----
    final (tMin, _, durationMs) = _timeBounds();

    // ---- Y bounds ----
    double maxF = 10.0;
    for (final s in samples) {
      if (s.forceKg > maxF) maxF = s.forceKg;
    }
    if (targetSamples != null) {
      for (final s in targetSamples!) {
        if (s.forceKg > maxF) maxF = s.forceKg;
      }
    }
    if (targetHistoryKg != null) {
      for (final v in targetHistoryKg!) {
        if (v > maxF) maxF = v;
      }
    }
    if (target != null && target! > maxF) maxF = target!;
    if (peak != null && peak! > maxF) maxF = peak!;
    maxF = (maxF * 1.2).clamp(10.0, 300.0);
    const minF = 0.0;

    // Draw grid
    const hLines = 5;
    for (int i = 0; i <= hLines; i++) {
      final y = size.height - (i / hLines) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }
    // Light vertical ticks
    const vLines = 4;
    for (int i = 1; i < vLines; i++) {
      final x = (i / vLines) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }

    double xForTime(int timeMs) {
      if (durationMs <= 0) return 0;
      return ((timeMs - tMin) / durationMs).clamp(0.0, 1.0) * size.width;
    }

    double yForForce(double forceKg) {
      final norm = (forceKg - minF) / (maxF - minF);
      return size.height - norm.clamp(0.0, 1.0) * size.height;
    }

    // ---- Target path (orange) ----
    if (targetSamples != null && targetSamples!.isNotEmpty) {
      final path = Path();
      bool first = true;
      for (final s in targetSamples!) {
        if (s.timeMs < tMin) continue;
        final x = xForTime(s.timeMs);
        final y = yForForce(s.forceKg);
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      if (!first) canvas.drawPath(path, paintTargetPath);
    } else if (targetHistoryKg != null && targetHistoryKg!.isNotEmpty) {
      // Align history by index to visible samples when possible; otherwise
      // spread evenly across the window.
      final path = Path();
      final n = targetHistoryKg!.length;
      if (samples.isNotEmpty && samples.length == n) {
        bool first = true;
        for (int i = 0; i < n; i++) {
          final s = samples[i];
          if (s.timeMs < tMin) continue;
          final x = xForTime(s.timeMs);
          final y = yForForce(targetHistoryKg![i]);
          if (first) {
            path.moveTo(x, y);
            first = false;
          } else {
            path.lineTo(x, y);
          }
        }
        if (!first) canvas.drawPath(path, paintTargetPath);
      } else {
        for (int i = 0; i < n; i++) {
          final x = n == 1 ? size.width / 2 : (i / (n - 1)) * size.width;
          final y = yForForce(targetHistoryKg![i]);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, paintTargetPath);
      }
    }

    // ---- Force line + fill ----
    if (samples.isNotEmpty) {
      final path = Path();
      final fillPath = Path();
      bool first = true;
      double lastX = 0;

      for (int i = 0; i < samples.length; i++) {
        final s = samples[i];
        if (s.timeMs < tMin) continue;
        final x = xForTime(s.timeMs);
        final y = yForForce(s.forceKg);
        lastX = x;

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

      if (!first) {
        fillPath.lineTo(lastX, size.height);
        fillPath.close();
        canvas.drawPath(fillPath, paintFill);
        canvas.drawPath(path, paintLine);
      }
    }

    // Current target horizontal line
    if (target != null && target! > 0) {
      final ty = yForForce(target!);
      canvas.drawLine(Offset(0, ty), Offset(size.width, ty), paintTarget);
      final tp = TextPainter(
        text: TextSpan(
          text: '${target!.toStringAsFixed(1)} kg target',
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelY = (ty - 14).clamp(0.0, size.height - 14);
      tp.paint(canvas, Offset(4, labelY));
    }

    // Peak annotation
    if (peak != null && peak! > 0) {
      final py = yForForce(peak!);
      final ppaint = Paint()
        ..color = colorScheme.tertiary
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), ppaint);
    }

    // Labels
    final maxLabel = TextPainter(
      text: TextSpan(
        text: '${maxF.toStringAsFixed(0)} kg',
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.6),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxLabel.paint(canvas, const Offset(4, 4));
  }

  /// Returns (tMin, tMax, durationMs) for the visible rolling window.
  (double, double, double) _timeBounds() {
    int? earliest;
    int? latest;

    void consider(int t) {
      earliest = earliest == null ? t : (t < earliest! ? t : earliest);
      latest = latest == null ? t : (t > latest! ? t : latest);
    }

    for (final s in samples) {
      consider(s.timeMs);
    }
    if (targetSamples != null) {
      for (final s in targetSamples!) {
        consider(s.timeMs);
      }
    }

    if (earliest == null || latest == null) {
      // Index-only targetHistory without times: synthetic window.
      final win = windowMs.toDouble().clamp(1000.0, 300000.0);
      return (0.0, win, win);
    }

    var tMax = latest!.toDouble();
    var tMin = earliest!.toDouble();
    final span = (tMax - tMin).clamp(0.0, 300000.0);
    final win = windowMs.toDouble().clamp(1000.0, 300000.0);

    if (span > win) {
      // Scroll: show last windowMs ending at latest sample.
      tMin = tMax - win;
    } else if (span < 1000.0) {
      // Minimum readable span early in a session.
      tMin = tMax - 1000.0;
      if (tMin < earliest!) tMin = earliest!.toDouble();
      // If still tiny (first sample), pad forward.
      if (tMax - tMin < 1000.0) {
        tMax = tMin + 1000.0;
      }
    }

    final durationMs = (tMax - tMin).clamp(1000.0, 300000.0);
    return (tMin, tMax, durationMs);
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.25)
      ..strokeWidth = 1;

    // Faint horizontal grid
    const hLines = 5;
    for (int i = 0; i <= hLines; i++) {
      final y = size.height - (i / hLines) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    // Faint vertical grid
    const vLines = 4;
    for (int i = 0; i <= vLines; i++) {
      final x = (i / vLines) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
    }

    // Soft baseline band
    final band = Paint()..color = colorScheme.outlineVariant.withOpacity(0.08);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45),
      band,
    );

    // Axis-ish zero label
    final zeroLabel = TextPainter(
      text: TextSpan(
        text: '0 kg',
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.35),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    zeroLabel.paint(canvas, Offset(4, size.height - 14));

    final hint = TextPainter(
      text: TextSpan(
        text: 'pull to see curve',
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.45),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    hint.paint(
      canvas,
      Offset(
        (size.width - hint.width) / 2,
        (size.height - hint.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ForcePainter oldDelegate) {
    if (oldDelegate.target != target ||
        oldDelegate.peak != peak ||
        oldDelegate.windowMs != windowMs ||
        oldDelegate.colorScheme != colorScheme) {
      return true;
    }

    // Prefer snapshot fingerprints — catches in-place List mutation.
    if (oldDelegate._sampleCount != _sampleCount ||
        oldDelegate._lastTimeMs != _lastTimeMs ||
        oldDelegate._lastForceKg != _lastForceKg) {
      return true;
    }
    if (oldDelegate._targetSampleCount != _targetSampleCount ||
        oldDelegate._lastTargetTimeMs != _lastTargetTimeMs ||
        oldDelegate._lastTargetForceKg != _lastTargetForceKg) {
      return true;
    }
    if (oldDelegate._targetHistoryCount != _targetHistoryCount ||
        oldDelegate._lastTargetHistoryKg != _lastTargetHistoryKg) {
      return true;
    }

    return false;
  }
}
