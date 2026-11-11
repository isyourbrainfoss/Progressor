import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

    final demoCount = tests.where((t) => t.isDemo).length;
    final best = _bestPeak(tests);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: store.load,
          ),
          if (tests.isNotEmpty)
            PopupMenuButton<_HistoryAction>(
              key: const Key('history_menu'),
              tooltip: 'More options',
              onSelected: (a) => _onAction(context, store, a, demoCount),
              itemBuilder: (_) => [
                if (demoCount > 0)
                  PopupMenuItem(
                    key: const Key('history_remove_demo'),
                    value: _HistoryAction.removeDemo,
                    child: Text('Remove demo tests ($demoCount)'),
                  ),
                const PopupMenuItem(
                  key: Key('history_clear_all'),
                  value: _HistoryAction.clearAll,
                  child: Text('Clear all history…'),
                ),
              ],
            ),
        ],
      ),
      body: _withStorageWarning(
        !store.loaded
            ? const Center(child: CircularProgressIndicator())
            : tests.isEmpty
            ? const _EmptyHistory()
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
                            _summary(tests.length, demoCount, best),
                            key: const Key('history_summary'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      key: const Key('history_list'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: tests.length,
                      itemBuilder: (ctx, i) {
                        final t = tests[i];
                        return Dismissible(
                          key: ValueKey('history_${t.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).colorScheme.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: Theme.of(ctx).colorScheme.onError,
                            ),
                          ),
                          onDismissed: (_) => _deleteWithUndo(ctx, store, t),
                          child: _HistoryRow(
                            test: t,
                            isPr: prIds.contains(t.id),
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
      ),
    );
  }

  /// One-line summary above the list. Demo pulls never count toward the
  /// best, so say that instead of showing an unexplained "Best: —".
  static String _summary(int total, int demo, double best) {
    final real = total - demo;
    final count = '$total ${total == 1 ? 'test' : 'tests'}';
    if (real == 0) {
      return '$count • demo pulls don\'t count toward your best';
    }
    final bestStr = best > 0 ? ' • Best ${best.toStringAsFixed(1)} kg' : '';
    final demoStr = demo > 0 ? ' • $demo demo' : '';
    return '$count$bestStr$demoStr';
  }

  static Future<void> _deleteWithUndo(
    BuildContext context,
    SessionStore store,
    PullTest test,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await store.deleteTest(test.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${test.type.label}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreTest(test),
          ),
        ),
      );
  }

  static Future<void> _onAction(
    BuildContext context,
    SessionStore store,
    _HistoryAction action,
    int demoCount,
  ) async {
    switch (action) {
      case _HistoryAction.removeDemo:
        await store.clearDemoTests();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed $demoCount demo ${demoCount == 1 ? 'test' : 'tests'}',
              ),
            ),
          );
        }
      case _HistoryAction.clearAll:
        final scheme = Theme.of(context).colorScheme;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear all history?'),
            content: const Text(
              'This permanently deletes every saved test on this device. '
              'Streak and badges are kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('history_clear_confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete all'),
              ),
            ],
          ),
        );
        if (ok == true) await store.clearTests();
    }
  }

  /// Sessions only live in memory when the database could not be opened.
  /// Say so, instead of letting them vanish silently on restart.
  static Widget _withStorageWarning(Widget body) {
    if (progressorStorageIsPersistent) return body;
    return Column(
      children: [
        Material(
          key: const Key('storage_warning'),
          color: const Color(0xFF5C2B29),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Storage unavailable: sessions are kept only until the '
                    'app closes.'
                    '${progressorStorageError != null ? '\n$progressorStorageError' : ''}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  static double _bestPeak(List<PullTest> tests) {
    if (tests.isEmpty) return 0;
    final real = tests.where((t) => !t.isDemo);
    if (real.isEmpty) return 0;
    return real.map((t) => t.peakForceKg ?? 0).reduce((a, b) => a > b ? a : b);
  }

  static List<ForceSample>? _compareFor(
    List<PullTest> tests,
    PullTest current,
  ) {
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

enum _HistoryAction { removeDemo, clearAll }

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: Colors.white38),
            SizedBox(height: 12),
            Text(
              'No tests yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Saved pulls from Live show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today 14:40", "Yesterday 09:12", "Mon 9 Nov 18:30", "3 Jan 2025 10:00".
String historyDateLabel(DateTime when, {DateTime? now}) {
  final t = when.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final hm = DateFormat.Hm().format(t);
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today $hm';
  if (diff == 1) return 'Yesterday $hm';
  if (diff > 1 && diff < 7) return '${DateFormat('EEE d MMM').format(t)} $hm';
  if (t.year == n.year) return '${DateFormat('d MMM').format(t)} $hm';
  return '${DateFormat('d MMM y').format(t)} $hm';
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.test,
    required this.isPr,
    required this.onTap,
  });

  final PullTest test;
  final bool isPr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = test.computedMetrics;
    final peak = m.peakKg ?? test.peakForceKg;
    final details = <String>[
      if (m.meanKg != null) 'avg ${m.meanKg!.toStringAsFixed(1)} kg',
      if (m.rfdMax != null) 'RFD ${m.rfdMax!.toStringAsFixed(0)} kg/s',
      if (m.cfEstimateKg != null &&
          (test.type == TestType.repeaters || test.type == TestType.endurance))
        'CF ~${m.cfEstimateKg!.toStringAsFixed(1)} kg',
    ];
    final when = historyDateLabel(test.startTime);
    final dur = m.durationS != null
        ? ' • ${m.durationS!.toStringAsFixed(1)} s'
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              Icon(
                isPr ? Icons.emoji_events : Icons.show_chart,
                color: isPr ? Colors.amber : Colors.white54,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            test.type.label,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (test.isDemo) ...[
                          const SizedBox(width: 8),
                          const _Tag(
                            key: Key('history_demo_chip'),
                            label: 'DEMO',
                            color: Colors.white54,
                          ),
                        ] else if (isPr) ...[
                          const SizedBox(width: 8),
                          const _Tag(label: 'PR', color: Colors.amber),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$when$dur',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    peak != null ? peak.toStringAsFixed(1) : '–',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'kg peak',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
