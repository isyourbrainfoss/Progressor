import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

class ProtocolSelector extends StatelessWidget {
  const ProtocolSelector({super.key, required this.current, required this.onChanged});

  final TestType current;
  final ValueChanged<TestType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: TestType.values.map((t) {
          final selected = t == current;
          return ChoiceChip(
            label: Text(t.label.split(' ').first),
            selected: selected,
            onSelected: (_) => onChanged(t),
            avatar: Icon(_iconFor(t), size: 18),
          );
        }).toList(),
      ),
    );
  }

  IconData _iconFor(TestType t) {
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
