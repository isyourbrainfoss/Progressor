import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:progressor_core/progressor_core.dart';

/// Burst overlay + banner for a new personal record.
Future<void> showPrCelebration(
  BuildContext context, {
  required double peakKg,
  required int streak,
  List<Achievement> newlyUnlocked = const [],
}) async {
  HapticFeedback.heavyImpact();
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _PrCelebration(
      peakKg: peakKg,
      streak: streak,
      newlyUnlocked: newlyUnlocked,
      onDone: () {
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _PrCelebration extends StatefulWidget {
  const _PrCelebration({
    required this.peakKg,
    required this.streak,
    required this.newlyUnlocked,
    required this.onDone,
  });

  final double peakKg;
  final int streak;
  final List<Achievement> newlyUnlocked;
  final VoidCallback onDone;

  @override
  State<_PrCelebration> createState() => _PrCelebrationState();
}

class _Particle {
  _Particle(this.origin, this.velocity, this.color, this.size);
  final Offset origin;
  final Offset velocity;
  final Color color;
  final double size;
}

class _PrCelebrationState extends State<_PrCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(42);
    _particles = [
      for (var i = 0; i < 42; i++)
        _Particle(
          Offset(0.5 + (rnd.nextDouble() - 0.5) * 0.2, 0.38),
          Offset(
            (rnd.nextDouble() - 0.5) * 2.4,
            -0.6 - rnd.nextDouble() * 1.4,
          ),
          [
            const Color(0xFFFF6B35),
            const Color(0xFF00C4B4),
            Colors.amberAccent,
            Colors.white,
          ][i % 4],
          3 + rnd.nextDouble() * 5,
        ),
    ];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDone,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _ConfettiPainter(
                t: _ctrl.value,
                particles: _particles,
              ),
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: (1 - ((_ctrl.value - 0.75) / 0.25)).clamp(0.0, 1.0),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🎉', style: TextStyle(fontSize: 36)),
                            const SizedBox(height: 6),
                            const Text(
                              'NEW PR',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: Colors.amberAccent,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${widget.peakKg.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Streak ${widget.streak}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (widget.newlyUnlocked.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              for (final a in widget.newlyUnlocked.take(3))
                                Text(
                                  '${a.emoji} ${a.title}',
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.particles});

  final double t;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final x = (p.origin.dx + p.velocity.dx * t) * size.width;
      final y = (p.origin.dy + p.velocity.dy * t + 1.6 * t * t) * size.height;
      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
