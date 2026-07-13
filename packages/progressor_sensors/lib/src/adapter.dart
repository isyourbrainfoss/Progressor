import 'dart:async';

import 'package:progressor_core/progressor_core.dart';

import 'sample.dart';

typedef SensorSample = ForceSample;

enum SensorConnectionState { disconnected, connecting, connected, error }

/// Generic adapter for a force sensor (BLE Tindeq or mock).
abstract class SensorAdapter {
  Stream<SensorConnectionState> get state;
  Stream<SensorSample> get samples;

  Future<void> connect({String? deviceId});
  Future<void> disconnect();

  /// Send tare command if supported.
  Future<void> tare();

  /// Optional: battery percent 0-100.
  Future<int?> readBatteryPercent() async => null;
}
