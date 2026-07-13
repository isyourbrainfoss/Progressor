import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:progressor_core/progressor_core.dart';
import 'adapter.dart';



/// Replay recorded samples from a jsonl fixture for demo / tests without hardware.
class MockReplayAdapter implements SensorAdapter {
  MockReplayAdapter({this.fixturePath, List<ForceSample>? samples})
      : _samples = samples ?? const [];

  final String? fixturePath;
  List<ForceSample> _samples;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  bool _connected = false;

  @override
  Future<void> connect({String? deviceId}) async {
    _stateCtrl.add(SensorConnectionState.connecting);
    if (fixturePath != null && _samples.isEmpty) {
      await _loadFixture(fixturePath!);
    }
    _connected = true;
    _stateCtrl.add(SensorConnectionState.connected);

    // Replay at original timing or sped up
    if (_samples.isNotEmpty) {
      _replaySamples();
    }
  }

  Future<void> _loadFixture(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      // Fallback: generate synthetic data
      _samples = _generateSynthetic();
      return;
    }
    final lines = await file.readAsLines();
    _samples = [];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        _samples.add(ForceSample(
          timeMs: data['timeMs'] as int? ?? 0,
          forceKg: (data['forceKg'] as num).toDouble(),
        ));
      } catch (_) {}
    }
    if (_samples.isEmpty) _samples = _generateSynthetic();
  }

  List<ForceSample> _generateSynthetic() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = <ForceSample>[];
    for (int i = 0; i < 800; i++) { // ~8s at ~100hz
      final t = i * 10; // 10ms steps
      // Simulate a hang: ramp up, hold ~75kg, slight fatigue
      double f = 20 + (55 * (1 - (i - 200).clamp(0, 400) / 600.0)).clamp(0, 1);
      if (i < 150) f = (i / 150.0) * 75; // ramp
      if (i > 550) f *= (1 - (i - 550) / 250.0).clamp(0, 1);
      list.add(ForceSample(timeMs: t, forceKg: f + (i % 7 - 3) * 0.3));
    }
    return list;
  }

  void _replaySamples() async {
    for (int i = 0; i < _samples.length; i++) {
      if (!_connected) break;
      final s = _samples[i];
      _sampleCtrl.add(s);
      if (i + 1 < _samples.length) {
        final dt = (_samples[i + 1].timeMs - s.timeMs).clamp(1, 1000);
        await Future.delayed(Duration(milliseconds: dt));
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _stateCtrl.add(SensorConnectionState.disconnected);
  }

  @override
  Future<void> tare() async {
    // No-op for mock or reset baseline in replay
  }

  @override
  Future<int?> readBatteryPercent() async => 87;
}
