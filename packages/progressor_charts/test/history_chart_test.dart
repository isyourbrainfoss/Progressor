import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';

void main() {
  testWidgets('HistoryForceChart paints a non-empty series', (tester) async {
    final samples = [
      for (var i = 0; i < 20; i++)
        ForceSample(timeMs: i * 50, forceKg: i * 2.0),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryForceChart(
            samples: samples,
            interactive: true,
            height: 180,
          ),
        ),
      ),
    );
    expect(find.byType(HistoryForceChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty series shows placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HistoryForceChart(samples: []),
        ),
      ),
    );
    expect(find.text('No data'), findsOneWidget);
  });
}
