import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:share_plus/share_plus.dart';

/// Detail view with zoomable replay chart + metrics.
class TestDetailScreen extends StatelessWidget {
  const TestDetailScreen({
    super.key,
    required this.test,
    this.compareSamples,
  });

  final PullTest test;
  final List<ForceSample>? compareSamples;

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenPlotPage(
          title: test.type.label,
          samples: test.samples,
          compareSamples: compareSamples,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = test.computedMetrics;
    return Scaffold(
      appBar: AppBar(
        title: Text(test.type.label),
        actions: [
          IconButton(
            tooltip: 'Fullscreen plot',
            icon: const Icon(Icons.fullscreen),
            onPressed: () => _openFullscreen(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Peak: ${(m.peakKg ?? 0).toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Duration: ${(m.durationS ?? 0).toStringAsFixed(1)} s'),
                  if (m.meanKg != null)
                    Text('Mean: ${m.meanKg!.toStringAsFixed(1)} kg'),
                  if (m.rfdMax != null)
                    Text('Max RFD: ${m.rfdMax!.toStringAsFixed(0)} kg/s'),
                  if (m.timeToPeakMs != null)
                    Text(
                      'Time to ~peak: ${m.timeToPeakMs!.toStringAsFixed(0)} ms',
                    ),
                  if (m.cfEstimateKg != null)
                    Text('Est. CF: ${m.cfEstimateKg!.toStringAsFixed(1)} kg'),
                  if (test.hand != null) Text('Hand: ${test.hand}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Force over time',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openFullscreen(context),
                icon: const Icon(Icons.zoom_in, size: 18),
                label: const Text('Zoom'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pinch to zoom · drag to pan · double-tap to reset',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          HistoryForceChart(
            samples: test.samples,
            compareSamples: compareSamples,
            height: 240,
            interactive: true,
            showPeak: true,
          ),
          if (compareSamples != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Teal overlay is your best pull of this type.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
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

class FullscreenPlotPage extends StatelessWidget {
  const FullscreenPlotPage({
    super.key,
    required this.title,
    required this.samples,
    this.compareSamples,
  });

  final String title;
  final List<ForceSample> samples;
  final List<ForceSample>? compareSamples;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'pinch · pan',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: HistoryForceChart(
            samples: samples,
            compareSamples: compareSamples,
            height: null,
            interactive: true,
            showPeak: true,
          ),
        ),
      ),
    );
  }
}
