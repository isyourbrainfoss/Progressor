import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:progressor_core/progressor_core.dart';

import 'adapter.dart';

/// Tindeq Progressor 200 BLE adapter (flutter_blue_plus).
///
/// Prefer constructing with a known [deviceId] from a prior scan (Flowlog-style
/// pair-then-connect). If [deviceId] is null, [connect] will scan for a name
/// starting with [targetNamePrefix].
class TindeqBleAdapter implements SensorAdapter {
  TindeqBleAdapter({
    this.deviceId,
    this.targetNamePrefix = 'Progressor',
  });

  static const String serviceUuid = '7e4e1701-1ea6-40c9-9dcc-13d34ffead57';
  static const String dataCharUuid = '7e4e1702-1ea6-40c9-9dcc-13d34ffead57';
  static const String ctrlCharUuid = '7e4e1703-1ea6-40c9-9dcc-13d34ffead57';

  static const int CMD_TARE = 100;
  static const int CMD_START = 101;
  static const int CMD_STOP = 102;
  /// Official app sends this on disconnect so the Progressor powers off (stops red blink).
  static const int CMD_ENTER_SLEEP = 110;

  /// BLE remote id from a previous scan (e.g. FlutterBluePlus remoteId.str).
  final String? deviceId;
  final String targetNamePrefix;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _ctrlChar;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();

  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;
  DateTime? _startTime;
  int? _firstDeviceUs;
  bool _measuring = false;

  String? lastError;
  String? connectedName;
  String? connectedRemoteId;

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  bool get isMeasuring => _measuring;

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
      await connectFn(license: License.nonprofit, timeout: const Duration(seconds: 15));
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
      throw Exception('Connected, but Progressor service not found. Wrong device?');
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
    // Merge onValueReceived + lastValueStream (some Android stacks only fire one).
    final dataChar = _dataChar!;
    _notifySub = Stream<List<int>>.multi((controller) {
      final subs = <StreamSubscription<List<int>>>[
        dataChar.onValueReceived.listen(controller.add, onError: controller.addError),
      ];
      try {
        subs.add(
          dataChar.lastValueStream.listen(controller.add, onError: controller.addError),
        );
      } catch (_) {}
      controller.onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    }).listen(_onData);
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  /// Scan until a Progressor is found or timeout.
  static Future<BluetoothDevice?> scanForFirstProgressor({
    Duration timeout = const Duration(seconds: 8),
    String namePrefix = 'Progressor',
  }) async {
    final results = await scanForProgressors(timeout: timeout, namePrefix: namePrefix);
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
    if (data.isEmpty) return;
    final tag = data[0];
    // 1 = RES_WEIGHT_MEAS — [tag, len, (float32 kg, uint32 us)*N]
    if (tag == 1) {
      // Header is [tag, len]; payload starts at index 2.
      // Some firmwares omit len or pack tightly — try offset 2, fall back to 1.
      int i = (data.length >= 10) ? 2 : 1;
      if (data.length >= 2 && data[1] > 0 && data[1] <= data.length - 2) {
        i = 2;
      }
      _startTime ??= DateTime.now();
      while (i + 8 <= data.length) {
        final kg = _toFloat(data.sublist(i, i + 4));
        final us = _toUint32(data.sublist(i + 4, i + 8));
        // Skip obvious garbage floats (NaN / absurd loads).
        if (kg.isNaN || kg.isInfinite || kg.abs() > 500) {
          i += 8;
          continue;
        }
        _firstDeviceUs ??= us;
        // Prefer host clock for UI smoothness; keep device us in rawTimestampUs.
        final elapsedHostMs =
            DateTime.now().difference(_startTime!).inMilliseconds;
        _sampleCtrl.add(
          ForceSample(
            timeMs: elapsedHostMs.clamp(0, 1 << 30),
            forceKg: kg,
            rawTimestampUs: us,
          ),
        );
        i += 8;
      }
    }
  }

  double _toFloat(List<int> bytes) {
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return bd.getFloat32(0, Endian.little);
  }

  int _toUint32(List<int> bytes) {
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return bd.getUint32(0, Endian.little);
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

  Future<void> startMeasurement() async {
    _startTime = DateTime.now();
    _firstDeviceUs = null;
    await _write([CMD_START]);
    _measuring = true;
  }

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

  @override
  Future<int?> readBatteryPercent() async => null;
}
