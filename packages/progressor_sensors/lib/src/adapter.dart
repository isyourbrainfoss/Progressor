import 'dart:async';
import 'sample.dart';

export 'sample.dart';

enum SensorConnectionState { disconnected, connecting, connected, error }

abstract class SensorAdapter {
  Stream<SensorConnectionState> get state;
  Stream<SensorSample> get samples;

  Future<void> connect({String? deviceId});
  Future<void> disconnect();

  Future<void> tare();

  Future<int?> readBatteryPercent() async => null;
}