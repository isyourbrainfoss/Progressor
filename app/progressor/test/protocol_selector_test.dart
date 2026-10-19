import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/widgets/protocol_selector.dart';
import 'package:progressor_core/progressor_core.dart';

void main() {
  test('protocol chip labels never end on a dangling word', () {
    for (final t in TestType.values) {
      final label = protocolChipLabel(t);
      expect(label, isNotEmpty);
      final last = label.split(' ').last.toLowerCase();
      expect(['the', '&', 'and', 'of', '/'], isNot(contains(last)),
          reason: '${t.name} -> "$label"');
    }
  });
}
