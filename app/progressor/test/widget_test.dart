import 'package:flutter_test/flutter_test.dart';

import 'package:progressor/main.dart';

void main() {
  testWidgets('Progressor app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProgressorApp());
    await tester.pumpAndSettle();

    // Adaptive shell renders tab labels (rail or bottom nav). Accept multiple.
    expect(find.text('Live'), findsAtLeastNWidgets(1));
    expect(find.text('History'), findsAtLeastNWidgets(1));
    expect(find.text('Train'), findsAtLeastNWidgets(1));
  });
}
