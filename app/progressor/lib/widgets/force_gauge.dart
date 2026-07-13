import 'package:flutter/material.dart';

/// Simple circular-ish force gauge for visual flair (optional use).
class ForceGauge extends StatelessWidget {
  const ForceGauge({super.key, required this.forceKg, this.maxKg = 150});

  final double? forceKg;
  final double maxKg;

  @override
  Widget build(BuildContext context) {
    final pct = ((forceKg ?? 0) / maxKg).clamp(0.0, 1.0);
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 12,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white12,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(forceKg?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('kg', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
