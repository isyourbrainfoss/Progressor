import 'dart:async';

import 'package:progressor_core/progressor_core.dart';

import 'adapter.dart';
import 'progressor_adapter.dart';
import 'simulated_climber.dart';
import 'tindeq_ble_adapter.dart' show TindeqSampleDecoder;
import 'tindeq_protocol.dart';

/// A simulated Tindeq Progressor 200 ("demo device").
///
/// Behaves like [TindeqBleAdapter] from the app's point of view: connect,
/// START/STOP weight measurement, tare, battery and firmware queries. Samples
/// are generated at the real 80 Hz, packed into real Tindeq weight
/// notifications (`[0x01, len, (f32 kg, u32 µs)*N]`) and decoded with the same
/// parser as the BLE adapter, so the protocol path is exercised too.
///
/// A [SimulatedClimber] produces the force; call [guide] with the current
/// protocol phase/target so pulls follow the workout (repeaters on/off,
/// follow-the-curve, max pulls…). With no session the climber stays idle and
/// the gauge reads ~0 kg after tare (≈1.4 kg before — carabiner weight).
///
/// For tests pass `realTime: false` and drive time with [advance].
class DemoProgressorAdapter implements ProgressorAdapter {
  DemoProgressorAdapter({
    SimulatedClimber? climber,
    this.sampleRateHz = TindeqProtocol.sampleRateHz,
    this.packetInterval = const Duration(milliseconds: 50),
    this.realTime = true,
    this.connectDelay = const Duration(milliseconds: 400),
    this.batteryMillivolts = 3980,
    this.firmwareVersion = '1.2.5-demo',
    this.name = 'Progressor DEMO',
  }) : climber = climber ?? SimulatedClimber();

  final SimulatedClimber climber;
  final int sampleRateHz;
  final Duration packetInterval;
  final bool realTime;
  final Duration connectDelay;
  final int batteryMillivolts;
  final String firmwareVersion;
  final String name;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();
  final _lowPowerCtrl = StreamController<void>.broadcast();
  final _decoder = TindeqSampleDecoder();
  final _stopwatch = Stopwatch();

  Timer? _timer;
  bool _connected = false;
  bool _measuring = false;

  /// Manual clock (µs) when [realTime] is false.
  int _manualUs = 0;
  int _measureStartUs = 0;
  int _emitted = 0;

  /// Raw kg subtracted from readings (set by tare).
  double _tareOffsetKg = 0;
  final List<double> _recentRaw = [];

  /// Every raw notification sent (for tests / debugging).
  int packetsSent = 0;

  @override
  bool get isDemo => true;

  @override
  String? get deviceName => _connected ? name : null;

  bool get isConnected => _connected;

  @override
  bool get isMeasuring => _measuring;

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  @override
  Stream<void> get lowPowerWarnings => _lowPowerCtrl.stream;

  /// Forward app guidance (protocol, phase, target) to the virtual climber.
  void guide({
    required bool recording,
    TestType? type,
    String phase = '',
    double? targetKg,
  }) {
    climber.guide(
      recording: recording,
      type: type,
      phase: phase,
      targetKg: targetKg,
    );
  }

  int get _nowUs => realTime ? _stopwatch.elapsedMicroseconds : _manualUs;

  @override
  Future<void> connect({String? deviceId}) async {
    _stateCtrl.add(SensorConnectionState.connecting);
    if (realTime && connectDelay > Duration.zero) {
      await Future<void>.delayed(connectDelay);
    }
    _connected = true;
    if (realTime) {
      _stopwatch
        ..reset()
        ..start();
    }
    _stateCtrl.add(SensorConnectionState.connected);
  }

  @override
  Future<void> startMeasurement() async {
    _ensureConnected();
    _decoder.reset();
    _measuring = true;
    _measureStartUs = _nowUs;
    _emitted = 0;
    if (realTime) {
      _timer?.cancel();
      _timer = Timer.periodic(packetInterval, (_) => pump());
    }
  }

  @override
  Future<void> stopMeasurement() async {
    _measuring = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Test helper: advance the manual clock and emit due samples.
  void advance(Duration d) {
    assert(!realTime, 'advance() is for realTime: false');
    final stepUs = packetInterval.inMicroseconds;
    var remaining = d.inMicroseconds;
    while (remaining > 0) {
      final s = remaining < stepUs ? remaining : stepUs;
      _manualUs += s;
      remaining -= s;
      pump();
    }
  }

  /// Generate all samples due since the last call and send them as one
  /// notification (the real gauge also batches samples per notification).
  void pump() {
    if (!_measuring || !_connected) return;
    final elapsedUs = _nowUs - _measureStartUs;
    var due = (elapsedUs * sampleRateHz) ~/ 1000000 - _emitted;
    if (due <= 0) return;
    // After a long stall (app paused) don't flood: skip ahead.
    if (due > sampleRateHz * 2) {
      _emitted += due - sampleRateHz ~/ 4;
      due = sampleRateHz ~/ 4;
    }
    final dt = 1.0 / sampleRateHz;
    final records = <TindeqWeightRecord>[];
    for (var i = 0; i < due; i++) {
      final raw = climber.step(dt);
      _recentRaw.add(raw);
      if (_recentRaw.length > 16) _recentRaw.removeAt(0);
      final idx = _emitted + i;
      records.add(
        TindeqWeightRecord(
          kg: raw - _tareOffsetKg,
          timestampUs: (idx * 1000000) ~/ sampleRateHz,
        ),
      );
    }
    _emitted += due;
    // Real packets hold up to ~30 records; split like the device would.
    const maxPerPacket = 30;
    for (var i = 0; i < records.length; i += maxPerPacket) {
      final chunk = records.sublist(
        i,
        i + maxPerPacket > records.length ? records.length : i + maxPerPacket,
      );
      _receive(TindeqProtocol.encodeWeightPacket(chunk));
    }
  }

  void _receive(List<int> bytes) {
    packetsSent++;
    final n = TindeqProtocol.parse(bytes);
    if (n.kind == TindeqNotificationKind.weight) {
      for (final s in _decoder.decode(n.records)) {
        _sampleCtrl.add(s);
      }
    }
  }

  @override
  Future<void> tare() async {
    _ensureConnected();
    // Device zeroes on the current (averaged) raw reading.
    // The firmware averages the load cell itself, so tare works even before
    // the first sample has been streamed.
    final base = _recentRaw.isEmpty
        ? climber.zeroOffsetKg + climber.force
        : _recentRaw.reduce((a, b) => a + b) / _recentRaw.length;
    _tareOffsetKg = base;
  }

  /// Current tare offset (raw kg subtracted from readings).
  double get tareOffsetKg => _tareOffsetKg;

  @override
  Future<int?> readBatteryMillivolts() async {
    if (!_connected) return null;
    // Round-trip through the real response encoding.
    final n = TindeqProtocol.parse(
      TindeqProtocol.encodeUint32Response(batteryMillivolts),
    );
    return TindeqProtocol.payloadUint32(n.payload);
  }

  @override
  Future<int?> readBatteryPercent() async {
    final mv = await readBatteryMillivolts();
    return mv == null ? null : TindeqProtocol.batteryPercentFromMillivolts(mv);
  }

  @override
  Future<String?> readFirmwareVersion() async {
    if (!_connected) return null;
    final n = TindeqProtocol.parse(
      TindeqProtocol.encodeCmdResponse(firmwareVersion.codeUnits),
    );
    return TindeqProtocol.payloadString(n.payload);
  }

  @override
  Future<void> disconnect({bool sleep = true}) async {
    _timer?.cancel();
    _timer = null;
    _measuring = false;
    _connected = false;
    _stopwatch.stop();
    climber.idle();
    _stateCtrl.add(SensorConnectionState.disconnected);
  }

  void _ensureConnected() {
    if (!_connected) throw StateError('Demo Progressor not connected');
  }
}
