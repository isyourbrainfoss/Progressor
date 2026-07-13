import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Simple history / replay chart using CustomPainter (fast) + fl_chart option.
class HistoryForceChart extends StatelessWidget {
  const HistoryForceChart({
    super.key,
    required this.samples,
    this.height = 180,
    this.showRfd = false,
  });

  final List<ForceSample> samples;
  final double height;
  final bool showRfd;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return SizedBox(height: height, child: const Center(child: Text('No data')));
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _HistoryPainter(samples: samples, colorScheme: Theme.of(context).colorScheme),
        size: Size.infinite,
      ),
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.samples, required this.colorScheme});

  final List<ForceSample> samples;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final sorted = List<ForceSample>.from(samples)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final minT = sorted.first.timeMs.toDouble();
    final maxT = sorted.last.timeMs.toDouble();
    final maxF = sorted.map((s) => s.forceKg).reduce((a, b) => a > b ? a : b) * 1.15;

    final linePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final x = maxT > minT ? ((s.timeMs - minT) / (maxT - minT)) * size.width : i * size.width / sorted.length;
      final y = size.height - (s.forceKg / maxF) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // Grid
    final grid = Paint()..color = colorScheme.outlineVariant.withOpacity(0.3)..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => oldDelegate.samples != samples;
}