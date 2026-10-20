import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:progressor_core/progressor_core.dart';
import 'adapter.dart';

/// Replay recorded samples from a jsonl fixture for demo / tests without
/// hardware. With no fixture or samples, a synthetic pull cycle is used.
///
/// By default the samples loop for as long as the adapter is connected, so
/// Demo mode keeps producing force whenever the user presses Start.
class MockReplayAdapter implements SensorAdapter {
  MockReplayAdapter({
    this.fixturePath,
    List<ForceSample>? samples,
    this.loop = true,
  }) : _samples = samples ?? const [];

  final String? fixturePath;

  /// Restart from the first sample after the last one.
  final bool loop;

  List<ForceSample> _samples;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  bool _connected = false;
  int _generation = 0;

  @override
  Future<void> connect({String? deviceId}) async {
    if (_stateCtrl.isClosed) {
      throw StateError('MockReplayAdapter used after dispose()');
    }
    _stateCtrl.add(SensorConnectionState.connecting);
    if (_samples.isEmpty) {
      if (fixturePath != null) {
        await _loadFixture(fixturePath!);
      } else {
        _samples = generateSyntheticPull();
      }
    }
    _connected = true;
    _stateCtrl.add(SensorConnectionState.connected);

    if (_samples.isNotEmpty) {
      unawaited(_replaySamples(++_generation));
    }
  }

  Future<void> _loadFixture(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _samples = generateSyntheticPull();
      return;
    }
    final lines = await file.readAsLines();
    final loaded = <ForceSample>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        loaded.add(ForceSample(
          timeMs: data['timeMs'] as int? ?? 0,
          forceKg: (data['forceKg'] as num).toDouble(),
        ));
      } catch (_) {}
    }
    _samples = loaded.isEmpty ? generateSyntheticPull() : loaded;
  }

  /// One ~10 s finger-strength pull at 100 Hz: rest, ramp to ~42 kg, a 4.5 s
  /// hold with slight fatigue, controlled release, rest.
  static List<ForceSample> generateSyntheticPull() {
    const hz = 100;
    const restEnd = 2.0, rampEnd = 3.5, holdEnd = 8.0, releaseEnd = 9.5;
    const total = 10.0, peak = 42.0, fatigue = 6.0;
    final list = <ForceSample>[];
    for (var i = 0; i < (total * hz).round(); i++) {
      final t = i / hz;
      double f;
      if (t < restEnd) {
        f = 0;
      } else if (t < rampEnd) {
        f = peak * (t - restEnd) / (rampEnd - restEnd);
      } else if (t < holdEnd) {
        f = peak - fatigue * (t - rampEnd) / (holdEnd - rampEnd);
      } else if (t < releaseEnd) {
        f = (peak - fatigue) * (1 - (t - holdEnd) / (releaseEnd - holdEnd));
      } else {
        f = 0;
      }
      // Small deterministic jitter so the trace looks like a real sensor.
      final jitter = ((i * 37) % 11 - 5) * 0.06;
      list.add(ForceSample(
        timeMs: i * 1000 ~/ hz,
        forceKg: (f + jitter).clamp(0, double.infinity).toDouble(),
      ));
    }
    return list;
  }

  /// Restart the replay from the first sample (e.g. when a recording
  /// starts), so a Demo-mode session always captures a full pull instead of
  /// joining the loop mid-hold. Timestamps stay monotonic across restarts.
  /// No-op unless connected.
  void restart() {
    if (!_connected || _samples.isEmpty || _sampleCtrl.isClosed) return;
    unawaited(_replaySamples(++_generation));
  }

  /// Timestamp offset for the next replayed sample (monotonic across loops
  /// and restarts).
  int _offsetMs = 0;
  int _lastEmittedMs = -1;

  Future<void> _replaySamples(int generation) async {
    // Continue after the last emitted sample so timestamps never go back.
    _offsetMs = _lastEmittedMs < 0 ? 0 : _lastEmittedMs + 10;
    while (_connected && generation == _generation) {
      final base = _offsetMs - _samples.first.timeMs;
      for (var i = 0; i < _samples.length; i++) {
        if (!_connected || generation != _generation || _sampleCtrl.isClosed) {
          return;
        }
        final s = _samples[i];
        final t = base + s.timeMs;
        _lastEmittedMs = t;
        _sampleCtrl.add(ForceSample(
          timeMs: t,
          forceKg: s.forceKg,
          forceN: s.forceN,
          rawTimestampUs: s.rawTimestampUs,
        ));
        final next = i + 1 < _samples.length ? _samples[i + 1].timeMs : null;
        final dt = next == null ? 10 : (next - s.timeMs).clamp(1, 1000);
        await Future<void>.delayed(Duration(milliseconds: dt));
      }
      if (!loop) return;
      _offsetMs = _lastEmittedMs + 10;
    }
  }

  @override
  Future<void> disconnect({bool sleep = true}) async {
    _connected = false;
    _generation++;
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(SensorConnectionState.disconnected);
    }
  }

  /// Stop replay and close the streams. The adapter cannot be reused.
  Future<void> dispose() async {
    if (_connected) await disconnect();
    _generation++;
    await Future.wait([_stateCtrl.close(), _sampleCtrl.close()]);
  }

  @override
  Future<void> tare() async {
    // No-op for mock or reset baseline in replay
  }

  @override
  Future<int?> readBatteryPercent() async => 87;
}
