import 'dart:async';
import 'sample.dart';

export 'sample.dart';

enum SensorConnectionState { disconnected, connecting, connected, error }

abstract class SensorAdapter {
  Stream<SensorConnectionState> get state;
  Stream<SensorSample> get samples;

  Future<void> connect({String? deviceId});

  /// Drop the link. For Progressor, [sleep] (default true) sends CMD_ENTER_SLEEP
  /// so the device powers off like the official app.
  Future<void> disconnect({bool sleep = true});

  Future<void> tare();

  Future<int?> readBatteryPercent() async => null;
}