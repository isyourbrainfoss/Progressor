import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:math' show max;

import '../widgets/protocol_selector.dart';

/// The main live measurement screen.
/// Beautiful large numbers, live plot, controls.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  SensorAdapter? _adapter;
  List<ForceSample> _samples = [];
  SensorConnectionState _connState = SensorConnectionState.disconnected;
  bool _isRecording = false;
  double? _currentForce;
  double? _peakForce;
  TestType _currentType = TestType.peakForce;
  DateTime? _recordStartTime; // for accurate save timing + gamif

  @override
  void initState() {
    super.initState();
    // Start with mock for beautiful demo without hardware
    _adapter = MockReplayAdapter();
    _listen();
  }

  void _listen() {
    _adapter?.state.listen((s) {
      if (mounted) setState(() => _connState = s);
    });
    _adapter?.samples.listen((s) {
      if (!_isRecording) return;
      setState(() {
        _samples = [..._samples, s];
        _currentForce = s.forceKg;
        if (_peakForce == null || s.forceKg > _peakForce!) {
          _peakForce = s.forceKg;
        }
      });
    });
  }

  Future<void> _toggleConnect() async {
    if (_connState == SensorConnectionState.connected) {
      await _adapter?.disconnect();
      setState(() {
        _samples = [];
        _currentForce = null;
        _peakForce = null;
        _isRecording = false;
        _recordStartTime = null;
      });
    } else {
      await _adapter?.connect();
    }
  }

  Future<void> _toggleRecord() async {
    // Capture context user before any awaits in async fn (for linter)
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    if (!_isRecording) {
      // start fresh
      final now = DateTime.now();
      setState(() {
        _samples = [];
        _peakForce = null;
        _currentForce = null;
        _isRecording = true;
        _recordStartTime = now;
      });
      if (_connState != SensorConnectionState.connected) {
        await _adapter?.connect();
      }
      if (_adapter is TindeqBleAdapter) {
        await (_adapter as TindeqBleAdapter).startMeasurement();
      }
      await _adapter?.tare();
    } else {
      setState(() => _isRecording = false);
      if (_adapter is TindeqBleAdapter) {
        await (_adapter as TindeqBleAdapter).stopMeasurement();
      }
      if (_samples.isNotEmpty) {
        // Proper timing for save (C6)
        final end = DateTime.now();
        final start = _recordStartTime ??
            end.subtract(Duration(milliseconds: _samples.last.timeMs));

        // Compute simple metrics
        final peaks = _samples.map((s) => s.forceKg);
        final peakKg = peaks.isNotEmpty ? peaks.reduce((a, b) => a > b ? a : b) : null;
        final avgKg = peaks.isNotEmpty ? peaks.reduce((a, b) => a + b) / peaks.length : null;
        final durationS = _samples.length > 1
            ? (_samples.last.timeMs - _samples.first.timeMs) / 1000.0
            : null;

        // Gamification on save (streak increment stub, PR detection) per C6
        final previous = await TestStorage().loadAll();
        final prevMax = previous.isEmpty
            ? 0.0
            : previous
                .map((p) => p.peakForceKg ?? 0.0)
                .reduce((a, b) => max(a, b));
        final isNewPR = peakKg != null && peakKg > prevMax;

        final streak = await _incrementStreakStub();

        final metrics = <String, dynamic>{
          'peakKg': peakKg,
          'avgKg': avgKg,
          'durationS': durationS,
          'isPR': isNewPR,
          'streakAtSave': streak,
        };

        final test = PullTest(
          id: const Uuid().v4(),
          startTime: start,
          type: _currentType,
          samples: List.of(_samples),
          endTime: end,
          notes: 'Recorded in Progressor',
          metrics: metrics,
        );
        await TestStorage().save(test);

        if (messenger != null && mounted) {
          final msg = isNewPR
              ? '🎉 Test saved! NEW PR! 🔥 Streak +1 ($streak)'
              : 'Test saved! 🔥 Streak +1 ($streak). View in History.';
          messenger.showSnackBar(SnackBar(content: Text(msg)));
        }
      }
      _recordStartTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connState == SensorConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          IconButton(
            icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
            onPressed: _toggleConnect,
            tooltip: isConnected ? 'Disconnect' : 'Connect / Demo',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _samples = [];
              _peakForce = null;
              _recordStartTime = null;
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Big beautiful force display
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(
                    _currentForce != null
                        ? _currentForce!.toStringAsFixed(1)
                        : '—',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontSize: 72,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  const Text('kg', style: TextStyle(fontSize: 20, color: Colors.white70)),
                  if (_peakForce != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'PEAK ${_peakForce!.toStringAsFixed(1)} kg',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),

            // Live pretty plot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LiveForceChart(
                samples: _samples,
                targetForceKg: 70, // example target
                peakForceKg: _peakForce,
                height: 160,
              ),
            ),

            const SizedBox(height: 8),

            ProtocolSelector(
              current: _currentType,
              onChanged: (t) => setState(() => _currentType = t),
            ),

            const Spacer(),

            // Controls
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.icon(
                    onPressed: _toggleConnect,
                    icon: Icon(isConnected ? Icons.link_off : Icons.link),
                    label: Text(isConnected ? 'Disconnect' : 'Connect Demo'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _toggleRecord,
                    icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(_isRecording ? 'STOP' : 'START'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.redAccent : null,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // hoist before await to avoid context-across-async lint
                      final m = mounted ? ScaffoldMessenger.of(context) : null;
                      await _adapter?.tare();
                      if (m != null && mounted) {
                        m.showSnackBar(
                          const SnackBar(content: Text('Tared'), duration: Duration(milliseconds: 800)),
                        );
                      }
                    },
                    icon: const Icon(Icons.balance),
                    label: const Text('TARE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _adapter?.disconnect();
    super.dispose();
  }

  /// Streak increment stub for gamification on save (C6).
  /// Always increments for demo/stub; real impl would check dates.
  Future<int> _incrementStreakStub() async {
    final prefs = await SharedPreferences.getInstance();
    int s = prefs.getInt('gamif_streak') ?? 0;
    s += 1;
    await prefs.setInt('gamif_streak', s);
    return s;
  }
}
