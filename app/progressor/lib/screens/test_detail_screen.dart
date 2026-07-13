import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:share_plus/share_plus.dart';

/// Basic detail view with replay chart + metrics. Can be expanded with compare, annotations.
class TestDetailScreen extends StatelessWidget {
  const TestDetailScreen({super.key, required this.test});

  final PullTest test;

  @override
  Widget build(BuildContext context) {
    final m = test.computedMetrics;
    return Scaffold(
      appBar: AppBar(title: Text(test.type.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Peak: ${(m.peakKg ?? 0).toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Duration: ${(m.durationS ?? 0).toStringAsFixed(1)} s'),
                  if (m.meanKg != null) Text('Mean: ${m.meanKg!.toStringAsFixed(1)} kg'),
                  if (m.rfdMax != null) Text('Max RFD: ${m.rfdMax!.toStringAsFixed(0)} kg/s'),
                  if (m.timeToPeakMs != null) Text('Time to ~peak: ${m.timeToPeakMs!.toStringAsFixed(0)} ms'),
                  if (m.cfEstimateKg != null) Text('Est. CF: ${m.cfEstimateKg!.toStringAsFixed(1)} kg'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Force over time', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          HistoryForceChart(samples: test.samples, height: 220),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final csv = exportTestToCsv(test);
              await SharePlus.instance.share(
                ShareParams(
                  text: csv,
                  subject: 'Progressor test ${test.id}',
                ),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('Share CSV'),
          ),
        ],
      ),
    );
  }
}
