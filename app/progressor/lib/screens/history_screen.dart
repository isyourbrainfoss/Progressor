import 'package:flutter/material.dart';

/// History of saved tests. Beautiful cards, filter, PRs.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDemoCard(context, 'Peak Force', '92.4 kg', '2 days ago', true),
          _buildDemoCard(context, 'Repeaters 7:3', 'CF 61.2 kg', 'Last week', false),
          _buildDemoCard(context, 'RFD', 'Peak 88 kg @ 180ms', '2 weeks ago', true),
          const SizedBox(height: 40),
          const Center(
            child: Text(
              'Pull tests will appear here.\nConnect and record to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.file_download),
        label: const Text('Export all'),
      ),
    );
  }

  Widget _buildDemoCard(BuildContext ctx, String title, String metric, String when, bool isPR) {
    return Card(
      child: ListTile(
        leading: Icon(isPR ? Icons.emoji_events : Icons.show_chart, color: isPR ? Colors.amber : null),
        title: Text(title),
        subtitle: Text('$metric • $when'),
        trailing: isPR ? const Chip(label: Text('PR')) : null,
        onTap: () {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Open detail for $title (demo)')));
        },
      ),
    );
  }
}
