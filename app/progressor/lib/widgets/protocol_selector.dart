import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Short chip label. Explicit, because cutting [TestType.label] after one or
/// two words produced "Follow the" and "Hold &".
String protocolChipLabel(TestType t) => switch (t) {
      TestType.peakForce => 'Peak',
      TestType.rfd => 'Rate',
      TestType.repeaters => 'Repeaters',
      TestType.endurance => 'Endurance',
      TestType.custom => 'Custom',
      TestType.guidedWorkout => 'Guided',
      TestType.warmupProgressive => 'Progressive Warm-up',
      TestType.followCurve => 'Follow Curve',
      TestType.holdRelease => 'Hold & Release',
      TestType.fingerDrag => 'Finger Drag',
      TestType.fingerCurl => 'Finger Curls',
      TestType.warmupTour => 'Tour',
    };

class ProtocolSelector extends StatelessWidget {
  const ProtocolSelector({super.key, required this.current, required this.onChanged});

  final TestType current;
  final ValueChanged<TestType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: TestType.values.map((t) {
          final selected = t == current;
          final short = protocolChipLabel(t);
          return ChoiceChip(
            label: Text(short, style: const TextStyle(fontSize: 12)),
            selected: selected,
            onSelected: (_) => onChanged(t),
            avatar: Icon(_iconFor(t), size: 16),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }).toList(),
      ),
    );
  }

  IconData _iconFor(TestType t) {
    if (t == TestType.warmupTour) return Icons.tour;
    if (t.isWarmup) return Icons.accessibility_new;
    switch (t) {
      case TestType.peakForce:
        return Icons.arrow_upward;
      case TestType.rfd:
        return Icons.bolt;
      case TestType.repeaters:
      case TestType.endurance:
        return Icons.repeat;
      default:
        return Icons.edit;
    }
  }
}
