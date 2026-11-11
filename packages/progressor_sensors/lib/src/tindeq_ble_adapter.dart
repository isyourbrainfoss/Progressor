import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:progressor_core/progressor_core.dart';

import 'adapter.dart';
import 'progressor_adapter.dart';
import 'tindeq_protocol.dart';

/// Tindeq Progressor 200 BLE adapter (flutter_blue_plus).
///
/// Prefer constructing with a known [deviceId] from a prior scan (Flowlog-style
/// pair-then-connect). If [deviceId] is null, [connect] will scan for a name
/// starting with [targetNamePrefix].
class TindeqBleAdapter implements ProgressorAdapter {
  TindeqBleAdapter({this.deviceId, this.targetNamePrefix = 'Progressor'});

  static const String serviceUuid = TindeqProtocol.serviceUuid;
  static const String dataCharUuid = TindeqProtocol.dataCharUuid;
  static const String ctrlCharUuid = TindeqProtocol.ctrlCharUuid;

  static const int CMD_TARE = TindeqProtocol.cmdTare;
  static const int CMD_START = TindeqProtocol.cmdStartWeightMeas;
  static const int CMD_STOP = TindeqProtocol.cmdStopWeightMeas;

  /// Official app sends this on disconnect so the Progressor powers off (stops red blink).
  static const int CMD_ENTER_SLEEP = TindeqProtocol.cmdEnterSleep;

  /// BLE remote id from a previous scan (e.g. FlutterBluePlus remoteId.str).
  final String? deviceId;
  final String targetNamePrefix;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _ctrlChar;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();

  final _lowPowerCtrl = StreamController<void>.broadcast();

  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;
  final TindeqSampleDecoder _decoder = TindeqSampleDecoder();
  bool _measuring = false;

  /// Single outstanding command that expects a RES_CMD_RESPONSE (tag 0).
  /// Responses carry no command id, so requests are serialized.
  Completer<List<int>>? _pendingResponse;
  Future<void> _requestChain = Future<void>.value();

  String? lastError;
  String? connectedName;
  String? connectedRemoteId;

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  @override
  bool get isMeasuring => _measuring;

  @override
  bool get isDemo => false;

  @override
  String? get deviceName => connectedName;

  @override
  Stream<void> get lowPowerWarnings => _lowPowerCtrl.stream;

  /// Whether [name] looks like a Tindeq Progressor advertisement.
  static bool isProgressorName(String name) {
    final n = name.trim().toLowerCase();
    return n.startsWith('progressor') || n.contains('progressor');
  }

  @override
  Future<void> connect({String? deviceId}) async {
    lastError = null;
    connectedName = null;
    connectedRemoteId = null;
    _stateCtrl.add(SensorConnectionState.connecting);

    final targetId = (deviceId != null && deviceId.isNotEmpty)
        ? deviceId
        : this.deviceId;

    try {
      BluetoothDevice? target;
      if (targetId != null && targetId.isNotEmpty) {
        target = BluetoothDevice.fromId(targetId);
      } else {
        target = await scanForFirstProgressor();
      }

      if (target == null) {
        throw Exception(
          'No Progressor found. Power it on (LED), keep it nearby, then Scan from Sensors.',
        );
      }

      _device = target;
      connectedName = _deviceName(target);
      connectedRemoteId = target.remoteId.str;

      await _connectDevice(target);

      await _connSub?.cancel();
      _connSub = _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _measuring = false;
          _stateCtrl.add(SensorConnectionState.disconnected);
        }
      });

      await _discoverAndSubscribe();
      _stateCtrl.add(SensorConnectionState.connected);
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      _stateCtrl.add(SensorConnectionState.error);
      await _cleanupPartial();
      rethrow;
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    // flutter_blue_plus requires a license argument on recent versions.
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      return;
    } catch (_) {
      // Fall through for older plugin APIs.
    }
    final connectFn = device.connect as dynamic;
    try {
      await connectFn(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      try {
        await connectFn(timeout: const Duration(seconds: 15));
      } catch (_) {
        await connectFn();
      }
    }
  }

  Future<void> _discoverAndSubscribe() async {
    final services = await _device!.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      final u = s.uuid.str.toLowerCase().replaceAll('-', '');
      if (u.contains('7e4e1701')) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      throw Exception(
        'Connected, but Progressor service not found. Wrong device?',
      );
    }

    _dataChar = null;
    _ctrlChar = null;
    for (final c in svc.characteristics) {
      final u = c.uuid.str.toLowerCase().replaceAll('-', '');
      if (u.contains('7e4e1702')) _dataChar = c;
      if (u.contains('7e4e1703')) _ctrlChar = c;
    }

    if (_dataChar == null || _ctrlChar == null) {
      throw Exception('Progressor characteristics missing on device.');
    }

    // Notify first (required by protocol), then wait briefly before commands.
    await _dataChar!.setNotifyValue(true);
    await _notifySub?.cancel();
    // onValueReceived fires for every notification. (Previously this merged
    // lastValueStream too, which fires for the same notifications — every
    // packet was delivered twice — and replays a stale value on subscribe.)
    _notifySub = _dataChar!.onValueReceived.listen(_onData, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  /// Scan until a Progressor is found or timeout.
  static Future<BluetoothDevice?> scanForFirstProgressor({
    Duration timeout = const Duration(seconds: 8),
    String namePrefix = 'Progressor',
  }) async {
    final results = await scanForProgressors(
      timeout: timeout,
      namePrefix: namePrefix,
    );
    if (results.isEmpty) return null;
    return results.first.device;
  }

  /// Discover nearby Progressors (name match). Sorted by RSSI (strongest first).
  static Future<List<ScanResult>> scanForProgressors({
    Duration timeout = const Duration(seconds: 8),
    String namePrefix = 'Progressor',
  }) async {
    final found = <String, ScanResult>{};

    final sub = FlutterBluePlus.onScanResults.listen((list) {
      for (final r in list) {
        final name = _scanName(r);
        if (!isProgressorName(name) &&
            !name.toLowerCase().startsWith(namePrefix.toLowerCase())) {
          // Also accept service UUID advertisement.
          final hasSvc = r.advertisementData.serviceUuids.any(
            (u) => u.str.toLowerCase().contains('7e4e1701'),
          );
          if (!hasSvc) continue;
        }
        found[r.device.remoteId.str] = r;
      }
    }, onError: (_) {});

    FlutterBluePlus.cancelWhenScanComplete(sub);

    try {
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8));
      }

      await FlutterBluePlus.startScan(timeout: timeout);

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning
            .where((scanning) => scanning == false)
            .first
            .timeout(timeout + const Duration(seconds: 3));
      }
    } catch (_) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    } finally {
      await sub.cancel();
    }

    final list = found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  static String _scanName(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    return r.device.platformName;
  }

  void _onData(List<int> data) {
    final n = TindeqProtocol.parse(data);
    switch (n.kind) {
      case TindeqNotificationKind.weight:
        for (final sample in _decoder.decode(n.records)) {
          _sampleCtrl.add(sample);
        }
      case TindeqNotificationKind.cmdResponse:
        final pending = _pendingResponse;
        _pendingResponse = null;
        if (pending != null && !pending.isCompleted)
          pending.complete(n.payload);
      case TindeqNotificationKind.lowPower:
        _lowPowerCtrl.add(null);
      case TindeqNotificationKind.unknown:
        break;
    }
  }

  String _deviceName(BluetoothDevice d) {
    final n = d.platformName;
    if (n.isNotEmpty) return n;
    return d.remoteId.str;
  }

  Future<void> _cleanupPartial() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    _dataChar = null;
    _ctrlChar = null;
    _measuring = false;
  }

  @override
  Future<void> disconnect({bool sleep = true}) async {
    // Match official Tindeq app: stop streaming, then put device to sleep so
    // it powers off (LED stops blinking red) instead of advertising forever.
    if (_measuring) {
      try {
        await stopMeasurement();
      } catch (_) {}
    }
    if (sleep && _ctrlChar != null && _device != null) {
      try {
        await enterSleep();
        // Give the firmware a moment to process sleep before link drop.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } catch (_) {}
    }
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    _dataChar = null;
    _ctrlChar = null;
    connectedName = null;
    connectedRemoteId = null;
    _measuring = false;
    _stateCtrl.add(SensorConnectionState.disconnected);
  }

  @override
  Future<void> tare() async {
    await _write([CMD_TARE]);
  }

  @override
  Future<void> startMeasurement() async {
    _decoder.reset();
    await _write([CMD_START]);
    _measuring = true;
  }

  @override
  Future<void> stopMeasurement() async {
    await _write([CMD_STOP]);
    _measuring = false;
  }

  /// CMD_ENTER_SLEEP (110) — powers the Progressor off (official client behavior).
  Future<void> enterSleep() async {
    await _write([CMD_ENTER_SLEEP]);
    _measuring = false;
  }

  Future<void> _write(List<int> data) async {
    if (_ctrlChar == null || _device == null) {
      throw Exception('Not connected to Progressor');
    }
    // Progressor control point accepts write without response; fall back if needed.
    try {
      await _ctrlChar!.write(data, withoutResponse: true);
    } catch (_) {
      await _ctrlChar!.write(data, withoutResponse: false);
    }
  }

  /// Send [cmd] and wait for its RES_CMD_RESPONSE payload.
  Future<List<int>?> _request(
    int cmd, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    final result = _requestChain.then((_) async {
      final c = Completer<List<int>>();
      _pendingResponse = c;
      try {
        await _write([cmd]);
        return await c.future.timeout(timeout);
      } catch (_) {
        return null;
      } finally {
        if (identical(_pendingResponse, c)) _pendingResponse = null;
      }
    });
    _requestChain = result.then((_) {});
    return result;
  }

  @override
  Future<int?> readBatteryMillivolts() async {
    if (_ctrlChar == null) return null;
    final payload = await _request(TindeqProtocol.cmdGetBatteryVoltage);
    return payload == null ? null : TindeqProtocol.payloadUint32(payload);
  }

  @override
  Future<String?> readFirmwareVersion() async {
    if (_ctrlChar == null) return null;
    final payload = await _request(TindeqProtocol.cmdGetAppVersion);
    if (payload == null || payload.isEmpty) return null;
    return TindeqProtocol.payloadString(payload);
  }

  @override
  Future<int?> readBatteryPercent() async {
    final mv = await readBatteryMillivolts();
    return mv == null ? null : TindeqProtocol.batteryPercentFromMillivolts(mv);
  }
}

/// Turns parsed weight records into [ForceSample]s with device-accurate
/// timing, dropping duplicate records (same device timestamp delivered twice).
///
/// [ForceSample.timeMs] is ms since the first record after [reset] (i.e. since
/// START_WEIGHT_MEAS); [ForceSample.rawTimestampUs] keeps the device clock.
class TindeqSampleDecoder {
  int? _firstUs;
  int? _lastUs;

  void reset() {
    _firstUs = null;
    _lastUs = null;
  }

  List<ForceSample> decode(List<TindeqWeightRecord> records) {
    final out = <ForceSample>[];
    for (final r in records) {
      final last = _lastUs;
      if (last != null && r.timestampUs <= last) {
        // Same or slightly older timestamp → duplicate delivery. A big jump
        // back means the device restarted its clock (new START): re-base.
        if (last - r.timestampUs < 2000000) continue;
        _firstUs = null;
      }
      _firstUs ??= r.timestampUs;
      _lastUs = r.timestampUs;
      out.add(
        ForceSample(
          timeMs: (r.timestampUs - _firstUs!) ~/ 1000,
          forceKg: r.kg,
          rawTimestampUs: r.timestampUs,
        ),
      );
    }
    return out;
  }
}
