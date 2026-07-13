import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

import 'test_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// History of saved tests. Loads real saved PullTests.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PullTest> _tests = [];
  bool _loading = true;
  int _currentStreak = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tests = await TestStorage().loadAll();
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt('gamif_streak') ?? 0;
    if (mounted) {
      setState(() {
        _tests = tests;
        _currentStreak = streak;
        _loading = false;
      });
    }
  }

  double _computeBestPeak() {
    if (_tests.isEmpty) return 0;
    return _tests
        .map((t) => t.peakForceKg ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  bool _isPRIndex(int i) {
    // Chronological PR detection: mark tests that set a new max peak at their time
    // (scans oldest->newest). Simple metrics improvement for C6.
    if (_tests.isEmpty) return false;
    double maxSeen = 0;
    // _tests from storage is newest first (see load reversed), so reverse scan
    for (int j = _tests.length - 1; j >= 0; j--) {
      final p = _tests[j].peakForceKg ?? 0;
      if (p > maxSeen + 0.001) {
        maxSeen = p;
        if (j == i) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tests.isEmpty
              ? const Center(
                  child: Text(
                    'No tests yet.\nRecord in Live to populate history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : Column(
                  children: [
                    // Simple metrics header (C6 improvement)
                    if (_currentStreak > 0 || _tests.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            if (_currentStreak > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withAlpha(51),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('🔥 Streak: $_currentStreak', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            const SizedBox(width: 8),
                            Text('${_tests.length} tests • Best: ${_computeBestPeak()} kg',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tests.length,
                        itemBuilder: (ctx, i) {
                          final t = _tests[i];
                          final m = t.computedMetrics;
                          final peak = (m.peakKg ?? t.peakForceKg)?.toStringAsFixed(1) ?? '?';
                          final dur = m.durationS != null ? '${m.durationS!.toStringAsFixed(1)}s' : '?';
                          final avgStr = m.meanKg?.toStringAsFixed(1);
                          final isPR = _isPRIndex(i); // improved real PR detection (chronological max)
                          return Card(
                            child: ListTile(
                              leading: Icon(isPR ? Icons.emoji_events : Icons.show_chart, color: isPR ? Colors.amber : null),
                              title: Text('${t.type.label} • $peak kg'),
                              subtitle: Text(
                                '${t.startTime.toLocal().toString().substring(0, 16)}  • $dur'
                                '${avgStr != null ? ' • avg ${avgStr}kg' : ''}'
                                ' • ${t.samples.length} samples'
                                '${m.rfdMax != null ? ' • RFD ${m.rfdMax!.toStringAsFixed(0)}kg/s' : ''}'
                                '${m.cfEstimateKg != null ? ' • CF~${m.cfEstimateKg!.toStringAsFixed(1)}' : ''}',
                              ),
                              trailing: isPR ? const Chip(label: Text('PR')) : null,
                              onTap: () {
                                Navigator.of(ctx).push(MaterialPageRoute(
                                  builder: (_) => TestDetailScreen(test: t),
                                ));
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await TestStorage().clear();
          await _load();
        },
        icon: const Icon(Icons.delete_sweep),
        label: const Text('Clear'),
      ),
    );
  }
}