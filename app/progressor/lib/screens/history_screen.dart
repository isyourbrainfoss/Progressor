import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

import '../persistence/session_store.dart';
import 'test_detail_screen.dart';

/// History of saved tests. Reads the shared [SessionStore] (SQLite).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SessionStoreScope.of(context);
    final tests = store.tests;
    final prIds = chronologicalPrIds(tests);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: store.load,
          ),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : tests.isEmpty
              ? const Center(
                  child: Text(
                    'No tests yet.\nRecord in Live to populate history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          if (store.streak > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '🔥 Streak: ${store.streak}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (store.streak > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${tests.length} tests • Best: ${_bestPeak(tests) > 0 ? '${_bestPeak(tests).toStringAsFixed(1)} kg' : '—'}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const Key('history_list'),
                        // Bottom inset keeps the last card clear of the FAB.
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: tests.length,
                        itemBuilder: (ctx, i) {
                          final t = tests[i];
                          final m = t.computedMetrics;
                          final peak = (m.peakKg ?? t.peakForceKg)
                                  ?.toStringAsFixed(1) ??
                              '?';
                          final dur = m.durationS != null
                              ? '${m.durationS!.toStringAsFixed(1)}s'
                              : '?';
                          final avgStr = m.meanKg?.toStringAsFixed(1);
                          final isPR = prIds.contains(t.id);
                          final showCf = m.cfEstimateKg != null &&
                              (t.type == TestType.repeaters ||
                                  t.type == TestType.endurance);
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                isPR ? Icons.emoji_events : Icons.show_chart,
                                color: isPR ? Colors.amber : null,
                              ),
                              title: Text('${t.type.label} • $peak kg'),
                              subtitle: Text(
                                '${t.startTime.toLocal().toString().substring(0, 16)}  • $dur'
                                '${avgStr != null ? ' • avg ${avgStr}kg' : ''}'
                                ' • ${t.samples.length} samples'
                                '${m.rfdMax != null ? ' • RFD ${m.rfdMax!.toStringAsFixed(0)}kg/s' : ''}'
                                '${showCf ? ' • CF~${m.cfEstimateKg!.toStringAsFixed(1)}' : ''}',
                              ),
                              trailing: t.isDemo
                                  ? const Chip(
                                      key: Key('history_demo_chip'),
                                      label: Text('DEMO'),
                                    )
                                  : (isPR
                                      ? const Chip(label: Text('PR'))
                                      : null),
                              onTap: () {
                                Navigator.of(ctx).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TestDetailScreen(
                                      test: t,
                                      compareSamples: _compareFor(tests, t),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: tests.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear history?'),
                    content: const Text(
                      'This deletes saved tests on this device. '
                      'Streak and badges are kept.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await store.clearTests();
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear'),
            ),
    );
  }

  static double _bestPeak(List<PullTest> tests) {
    if (tests.isEmpty) return 0;
    final real = tests.where((t) => !t.isDemo);
    if (real.isEmpty) return 0;
    return real
        .map((t) => t.peakForceKg ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  static List<ForceSample>? _compareFor(List<PullTest> tests, PullTest current) {
    PullTest? best;
    for (final t in tests) {
      if (t.id == current.id || t.type != current.type) continue;
      final p = t.peakForceKg ?? 0;
      if (best == null || p > (best.peakForceKg ?? 0)) best = t;
    }
    if (best == null || best.samples.isEmpty) return null;
    return best.samples;
  }
}
