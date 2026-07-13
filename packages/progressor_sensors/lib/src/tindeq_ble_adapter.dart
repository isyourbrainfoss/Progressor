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

  final String targetNamePrefix;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _ctrlChar;

  final _stateCtrl = StreamController<SensorConnectionState>.broadcast();
  final _sampleCtrl = StreamController<SensorSample>.broadcast();

  StreamSubscription? _notifySub;
  DateTime? _startTime;

  @override
  Stream<SensorConnectionState> get state => _stateCtrl.stream;

  @override
  Stream<SensorSample> get samples => _sampleCtrl.stream;

  @override
  Future<void> connect({String? deviceId}) async {
    _stateCtrl.add(SensorConnectionState.connecting);

    try {
      BluetoothDevice? target;
      if (deviceId != null) {
        target = BluetoothDevice.fromId(deviceId);
      } else {
        // Simple scan
        final scanResults = FlutterBluePlus.scanResults;
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
        await for (final results in scanResults.timeout(const Duration(seconds: 7))) {
          for (final r in results) {
            if (r.device.platformName.startsWith(targetNamePrefix)) {
              target = r.device;
              break;
            }
          }
          if (target != null) break;
        }
        await FlutterBluePlus.stopScan();
      }

      if (target == null) throw Exception('No Progressor found');

      _device = target;
      // Use dynamic to tolerate different flutter_blue_plus versions (license param in newer)
      final connectFn = _device!.connect as dynamic;
      try { await connectFn(license: null); } catch (_) { await connectFn(); }
      _stateCtrl.add(SensorConnectionState.connected);

      final services = await _device!.discoverServices();
      BluetoothService? svc;
      for (final s in services) {
        if (s.uuid.str.toLowerCase().contains('7e4e1701')) {
          svc = s;
          break;
        }
      }
      if (svc == null) throw Exception('Progressor service not found');

      for (final c in svc.characteristics) {
        final u = c.uuid.str.toLowerCase();
        if (u.contains('7e4e1702')) _dataChar = c;
        if (u.contains('7e4e1703')) _ctrlChar = c;
      }

      if (_dataChar != null) {
        await _dataChar!.setNotifyValue(true);
        _notifySub = _dataChar!.onValueReceived.listen(_onData);
      }
    } catch (e) {
      _stateCtrl.add(SensorConnectionState.error);
      rethrow;
    }
  }

  void _onData(List<int> data) {
    if (data.isEmpty) return;
    final tag = data[0];
    if (tag == 1) {
      int i = 2;
      _startTime ??= DateTime.now();
      while (i + 8 <= data.length) {
        final kg = _toFloat(data.sublist(i, i + 4));
        final us = _toUint32(data.sublist(i + 4, i + 8));
        final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
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

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    if (_device != null) {
      await _device!.disconnect();
    }
    _stateCtrl.add(SensorConnectionState.disconnected);
    _device = null;
  }

  @override
  Future<void> tare() async {
    await _write([CMD_TARE]);
  }

  Future<void> startMeasurement() async {
    _startTime = DateTime.now();
    await _write([CMD_START]);
  }

  Future<void> stopMeasurement() async {
    await _write([CMD_STOP]);
  }

  Future<void> _write(List<int> data) async {
    if (_ctrlChar == null || _device == null) return;
    await _ctrlChar!.write(data, withoutResponse: true);
  }

  @override
  Future<int?> readBatteryPercent() async => null;
}
