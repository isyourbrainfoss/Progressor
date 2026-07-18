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
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Tindeq Progressor'),
            subtitle: const Text(
              'Connect from the Live tab: choose Progressor, power on the device, tap Connect.',
            ),
            isThreeLine: true,
            onTap: () => _showDeviceHelp(context),
          ),
          ListTile(
            leading: const Icon(Icons.science),
            title: const Text('Demo mode'),
            subtitle: const Text(
              'Also on Live: switch the segment control to Demo for synthetic data without hardware.',
            ),
            isThreeLine: true,
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

  void _showDeviceHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect Progressor'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Open the Live tab.\n'
            '2. Select Progressor (not Demo).\n'
            '3. Power on your Progressor 200 (LED on).\n'
            '4. Tap Connect — allow Bluetooth / nearby devices if prompted.\n'
            '5. Tap START to stream force and record a test.\n\n'
            'Tips:\n'
            '• Keep the Progressor within a few meters of the phone.\n'
            '• If scan fails, power-cycle the Progressor and try again.\n'
            '• On Linux Flatpak, Bluetooth (BlueZ) must be available to the app.\n'
            '• Use Demo when you only want to try the UI.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
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
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
      );
}
