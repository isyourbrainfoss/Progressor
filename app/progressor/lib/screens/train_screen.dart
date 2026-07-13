import 'package:flutter/material.dart';

/// Training suggestions, goals, best practices.
/// State of the art guidance for finger strength.
class TrainScreen extends StatelessWidget {
  const TrainScreen({super.key});

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
