import 'package:flutter/material.dart';

import '../sensors/sensor_hub.dart';
import 'sensors_screen.dart';

/// Settings, sync, about, gamification summary.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = SensorHubScope.maybeOf(context);

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
          ListTile(
            key: const Key('more_sensors_tile'),
            leading: const Icon(Icons.sensors),
            title: const Text('Sensors'),
            subtitle: Text(
              hub == null
                  ? 'Pair Tindeq Progressor'
                  : _sensorsSubtitle(hub),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SensorsScreen(),
                ),
              );
            },
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

  String _sensorsSubtitle(SensorHub hub) {
    final p = hub.progressor;
    if (p == null) return 'No Progressor paired • Tap to add';
    if (hub.isProgressorConnected) return 'Connected: ${p.name}';
    if (p.hasBleId) return 'Paired: ${p.name} • Not connected';
    return 'Added: ${p.name} • Scan to assign BLE id';
  }

  void _showSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nextcloud Sync'),
        content: const Text(
          'Connect to your Nextcloud / WebDAV to sync tests, goals and PRs across devices (phone + desktop).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Configure (demo)'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70),
        ),
      );
}
