import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:progressor_core/progressor_core.dart';

import 'adapter.dart';

/// Tindeq Progressor 200 BLE adapter.
/// Compatible with recent flutter_blue_plus.
class TindeqBleAdapter implements SensorAdapter {
  TindeqBleAdapter({this.targetNamePrefix = 'Progressor'});

  static const String serviceUuid = '7e4e1701-1ea6-40c9-9dcc-13d34ffead57';
  static const String dataCharUuid = '7e4e1702-1ea6-40c9-9dcc-13d34ffead57';
  static const String ctrlCharUuid = '7e4e1703-1ea6-40c9-9dcc-13d34ffead57';

  static const int CMD_TARE = 100;
  static const int CMD_START = 101;
  static const int CMD_STOP = 102;
  static const int CMD_GET_BATTERY_VOLTAGE = 111;

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

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  bool get isMeasuring => _measuring;

  @override
  Future<void> connect({String? deviceId}) async {
    lastError = null;
    connectedName = null;
    _stateCtrl.add(SensorConnectionState.connecting);

    try {
      if (!await FlutterBluePlus.isSupported) {
        throw Exception(
          'Bluetooth LE is not supported on this device. Use Demo mode, or run on Android/Linux with BLE.',
        );
      }

      // Wait for adapter on (also surfaces permission dialogs on some platforms).
      final adapterState = await FlutterBluePlus.adapterState
          .where((s) =>
              s == BluetoothAdapterState.on ||
              s == BluetoothAdapterState.unauthorized ||
              s == BluetoothAdapterState.unavailable)
          .first
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => BluetoothAdapterState.unknown,
          );

      if (adapterState == BluetoothAdapterState.unauthorized) {
        throw Exception(
          'Bluetooth permission denied. Allow nearby devices / Bluetooth in system settings.',
        );
      }
      if (adapterState != BluetoothAdapterState.on) {
        // Best-effort turn-on (Android).
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        final on = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 15), onTimeout: () => BluetoothAdapterState.off);
        if (on != BluetoothAdapterState.on) {
          throw Exception('Turn on Bluetooth, then try again.');
        }
      }

      BluetoothDevice? target;
      if (deviceId != null && deviceId.isNotEmpty) {
        target = BluetoothDevice.fromId(deviceId);
      } else {
        target = await _scanForProgressor();
      }

      if (target == null) {
        throw Exception(
          'No Progressor found. Power it on (LED), keep it nearby, and try again.',
        );
      }

      _device = target;
      connectedName = _deviceName(target);

      // Tolerate different flutter_blue_plus versions (license param in newer).
      final connectFn = _device!.connect as dynamic;
      try {
        await connectFn(license: null, timeout: const Duration(seconds: 15));
      } catch (_) {
        try {
          await connectFn(timeout: const Duration(seconds: 15));
        } catch (_) {
          await connectFn();
        }
      }

      // Watch disconnects from the device side.
      await _connSub?.cancel();
      _connSub = _device!.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _measuring = false;
          _stateCtrl.add(SensorConnectionState.disconnected);
        }
      });

      final services = await _device!.discoverServices();
      BluetoothService? svc;
      for (final s in services) {
        final u = s.uuid.str.toLowerCase();
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
        final u = c.uuid.str.toLowerCase();
        if (u.contains('7e4e1702')) _dataChar = c;
        if (u.contains('7e4e1703')) _ctrlChar = c;
      }

      if (_dataChar == null || _ctrlChar == null) {
        throw Exception('Progressor characteristics missing on device.');
      }

      await _dataChar!.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = _dataChar!.onValueReceived.listen(_onData);

      _stateCtrl.add(SensorConnectionState.connected);
    } catch (e) {
      lastError = e.toString();
      _stateCtrl.add(SensorConnectionState.error);
      await _cleanupPartial();
      rethrow;
    }
  }

  Future<BluetoothDevice?> _scanForProgressor() async {
    BluetoothDevice? found;

    // Prefer service UUID filter; some firmwares also need name match.
    final results = <ScanResult>[];
    final sub = FlutterBluePlus.scanResults.listen((list) {
      results
        ..clear()
        ..addAll(list);
      for (final r in list) {
        if (_isProgressor(r)) {
          found = r.device;
          break;
        }
      }
    }, onError: (_) {});

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 6),
      );
    } catch (_) {
      // Some stacks reject withServices filter; fall through to open scan.
    }

    // If nothing via service filter, open scan by name.
    if (found == null) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      final deadline = DateTime.now().add(const Duration(seconds: 9));
      while (found == null && DateTime.now().isBefore(deadline)) {
        for (final r in results) {
          if (_isProgressor(r)) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub.cancel();
    return found;
  }

  bool _isProgressor(ScanResult r) {
    final names = <String>[
      r.device.platformName,
      r.advertisementData.advName,
      ...r.advertisementData.serviceUuids.map((g) => g.str),
    ];
    for (final n in names) {
      if (n.toLowerCase().contains(targetNamePrefix.toLowerCase())) return true;
      if (n.toLowerCase().contains('7e4e1701')) return true;
    }
    // Service UUID advertised?
    for (final u in r.advertisementData.serviceUuids) {
      if (u.str.toLowerCase().contains('7e4e1701')) return true;
    }
    return false;
  }

  String _deviceName(BluetoothDevice d) {
    final n = d.platformName;
    if (n.isNotEmpty) return n;
    return d.remoteId.str;
  }

  void _onData(List<int> data) {
    if (data.isEmpty) return;
    final tag = data[0];
    // 1 = RES_WEIGHT_MEAS — [tag, len, (float32 kg, uint32 us)*N]
    if (tag == 1) {
      int i = 2;
      _startTime ??= DateTime.now();
      while (i + 8 <= data.length) {
        final kg = _toFloat(data.sublist(i, i + 4));
        final us = _toUint32(data.sublist(i + 4, i + 8));
        _firstDeviceUs ??= us;
        final elapsedDeviceMs = ((us - _firstDeviceUs!) / 1000).round();
        final elapsedHostMs = DateTime.now().difference(_startTime!).inMilliseconds;
        final elapsed = elapsedDeviceMs >= 0 ? elapsedDeviceMs : elapsedHostMs;
        _sampleCtrl.add(ForceSample(timeMs: elapsed, forceKg: kg, rawTimestampUs: us));
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
  Future<void> disconnect() async {
    if (_measuring) {
      try {
        await stopMeasurement();
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

  Future<void> _write(List<int> data) async {
    if (_ctrlChar == null || _device == null) {
      throw Exception('Not connected to Progressor');
    }
    await _ctrlChar!.write(data, withoutResponse: true);
  }

  @override
  Future<int?> readBatteryPercent() async {
    // Voltage query is async via notify; not fully wired. Leave null for now.
    return null;
  }
}
