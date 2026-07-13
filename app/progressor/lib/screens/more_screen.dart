import 'package:flutter/material.dart';

/// Settings, sync, about, gamification summary.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          const _SectionHeader('Progress & Gamification'),
          ListTile(
            leading: const Icon(Icons.local_fire_department),
            title: const Text('Current Streak'),
            subtitle: const Text('7 days • Personal best: 19 days'),
            trailing: const Text('🔥', style: TextStyle(fontSize: 24)),
          ),
          ListTile(
            leading: const Icon(Icons.military_tech),
            title: const Text('Strength Index'),
            subtitle: const Text('87 • Advanced level'),
            trailing: const Chip(label: Text('+4 this week')),
          ),
          const Divider(),
          const _SectionHeader('Sync & Data'),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('Nextcloud Sync'),
            subtitle: const Text('Not configured • Tap to set up'),
            onTap: () => _showSyncDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export data'),
            onTap: () {},
          ),
          const Divider(),
          const _SectionHeader('Device'),
          const ListTile(
            leading: Icon(Icons.bluetooth),
            title: Text('Tindeq Progressor'),
            subtitle: Text('Demo / Mock mode active'),
          ),
          const Divider(),
          ListTile(
            title: const Text('About Progressor'),
            subtitle: const Text('Open source • Made for climbers'),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nextcloud Sync'),
        content: const Text(
            'Connect to your Nextcloud / WebDAV to sync tests, goals and PRs across devices (phone + desktop).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Configure (demo)')),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
      );
}
