import 'package:flutter/material.dart';
import 'package:progressor_charts/progressor_charts.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

import '../widgets/force_gauge.dart';
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
      });
    } else {
      await _adapter?.connect();
    }
  }

  Future<void> _toggleRecord() async {
    if (!_isRecording) {
      // start fresh
      setState(() {
        _samples = [];
        _peakForce = null;
        _currentForce = null;
        _isRecording = true;
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
      // TODO: save session via core
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
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Big beautiful force display
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
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
                      padding: const EdgeInsets.only(top: 8),
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
                height: 240,
              ),
            ),

            const SizedBox(height: 16),

            ProtocolSelector(
              current: _currentType,
              onChanged: (t) => setState(() => _currentType = t),
            ),

            const Spacer(),

            // Controls
            Padding(
              padding: const EdgeInsets.all(24.0),
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
                      await _adapter?.tare();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tared'), duration: Duration(milliseconds: 800)),
                      );
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
}
