import 'package:flutter_test/flutter_test.dart';

import 'package:progressor/main.dart';

void main() {
  testWidgets('Progressor app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProgressorApp());

    // Should have our tabs
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);
  });
}
