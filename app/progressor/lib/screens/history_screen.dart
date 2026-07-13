import 'package:flutter/material.dart';
import 'package:progressor_core/progressor_core.dart';

/// History of saved tests. Loads real saved PullTests.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PullTest> _tests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tests = await TestStorage().loadAll();
    if (mounted) {
      setState(() {
        _tests = tests;
        _loading = false;
      });
    }
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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tests.length,
                  itemBuilder: (ctx, i) {
                    final t = _tests[i];
                    final peak = t.peakForceKg?.toStringAsFixed(1) ?? '?';
                    final isPR = i == 0; // simplistic
                    return Card(
                      child: ListTile(
                        leading: Icon(isPR ? Icons.emoji_events : Icons.show_chart, color: isPR ? Colors.amber : null),
                        title: Text('${t.type.label} • $peak kg'),
                        subtitle: Text('${t.startTime.toLocal().toString().substring(0,16)}  • ${t.samples.length} samples'),
                        trailing: isPR ? const Chip(label: Text('PR')) : null,
                        onTap: () {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Detail view for ${t.id} (extend with plots)')),
                          );
                        },
                      ),
                    );
                  },
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
