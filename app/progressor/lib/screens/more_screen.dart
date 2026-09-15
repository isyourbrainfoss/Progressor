import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:share_plus/share_plus.dart';

import '../persistence/session_store.dart';
import '../sensors/sensor_hub.dart';
import 'sensors_screen.dart';
import 'sync_screen.dart';

/// Settings, sync, about, gamification summary.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = SensorHubScope.maybeOf(context);
    final store = SessionStoreScope.maybeOf(context);
    final streak = store?.streak ?? 0;
    final index = store?.index ?? 0;
    final level = store?.level ?? 1;
    final unlocked = store?.unlockedAchievements ?? const <Achievement>[];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          const _SectionHeader('Progress & Gamification'),
          ListTile(
            leading: const Icon(Icons.local_fire_department),
            title: const Text('Current Streak'),
            subtitle: Text(
              streak == 0
                  ? 'Log a session to start a streak'
                  : '$streak day${streak == 1 ? '' : 's'}',
            ),
            trailing: Text(streak > 0 ? '🔥' : '—',
                style: const TextStyle(fontSize: 24)),
          ),
          ListTile(
            leading: const Icon(Icons.military_tech),
            title: const Text('Strength Index'),
            subtitle: Text(
              '${index.toStringAsFixed(0)} • Level $level • ${store?.xp ?? 0} XP',
            ),
          ),
          if (unlocked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in unlocked)
                    Chip(
                      avatar: Text(a.emoji),
                      label: Text(a.title),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Badges unlock from real PRs, streaks, and session counts.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const Divider(),
          const _SectionHeader('Sync & Data'),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('Nextcloud Sync'),
            subtitle: const Text('WebDAV push / pull of saved tests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export data'),
            subtitle: const Text('CSV of all tests'),
            onTap: () async {
              final tests = store?.tests ?? const <PullTest>[];
              if (tests.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No tests to export')),
                );
                return;
              }
              await SharePlus.instance.share(
                ShareParams(
                  text: exportAllToCsv(tests),
                  subject: 'Progressor export',
                ),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Device'),
          ListTile(
            key: const Key('more_sensors_tile'),
            leading: const Icon(Icons.sensors),
            title: const Text('Sensors'),
            subtitle: Text(
              hub == null ? 'Pair Tindeq Progressor' : _sensorsSubtitle(hub),
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
          const ListTile(
            title: Text('About Progressor'),
            subtitle: Text('Open source • Made for climbers • v0.2'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              'Shortcuts: 1–4 switch tabs · Space start/stop · T tare · F1 help',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      );
}
