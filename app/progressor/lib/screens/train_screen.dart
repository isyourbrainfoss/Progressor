import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// Training suggestions, goals, best practices.
/// State of the art guidance for finger strength.
class TrainScreen extends StatefulWidget {
  const TrainScreen({super.key});

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  List<PullTest> _tests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await TestStorage().loadAll();
    if (mounted) {
      setState(() {
        _tests = t.reversed.toList(); // chronological for trend
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Train')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Best Practice Finger Training', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _protocolCard(
            'Max Strength Hangs',
            '3-5s max hangs on 18-20mm edge. 3-5 reps. Rest 3-5 min.',
            'Goal: Improve peak force. Aim for 120%+ bodyweight on half crimp for advanced.',
          ),
          _protocolCard(
            'Critical Force (CF) Repeaters',
            '7s on / 3s off @ ~60-70% max. Do 6-12 reps or to failure. 3-5 sets.',
            'Track CF. Good target: CF > 55-65% of your max hang for good endurance.',
          ),
          _protocolCard(
            'RFD / Power',
            'Explosive pulls. Focus on reaching 80% peak in <150-250ms. 4-6 reps.',
            'Improves contact strength and dynamic moves.',
          ),

          const SizedBox(height: 24),
          const Text('Your Progress Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 160,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildTrendChart(),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text('Your Goals (demo)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Card(
            child: ListTile(
              title: Text('Reach 100 kg Peak'),
              subtitle: Text('Current: 92 kg • 92% complete'),
              trailing: LinearProgressIndicator(value: 0.92, minHeight: 6),
            ),
          ),
          const Card(
            child: ListTile(
              title: Text('Improve CF to 65 kg'),
              subtitle: Text('Current estimate: 61 kg'),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Set new goal'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    if (_tests.isEmpty) {
      return const Center(
        child: Text('Record some tests in Live to see your peak force trend here.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final spots = <FlSpot>();
    for (int i = 0; i < _tests.length; i++) {
      final p = _tests[i].peakForceKg ?? 0;
      spots.add(FlSpot(i.toDouble(), p));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Text('T${v.toInt() + 1}', style: const TextStyle(fontSize: 10)),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withAlpha(40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _protocolCard(String title, String how, String goal) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            Text(how),
            const SizedBox(height: 8),
            Text(goal, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Start guided session'),
            ),
          ],
        ),
      ),
    );
  }
}