import 'adapter.dart';

/// Common interface for a Tindeq Progressor — the real BLE gauge
/// ([TindeqBleAdapter]) and the simulated one ([DemoProgressorAdapter]).
abstract class ProgressorAdapter implements SensorAdapter {
  /// True for the simulated demo device.
  bool get isDemo;

  /// Device name (BLE advertised name, or "Progressor DEMO").
  String? get deviceName;

  bool get isMeasuring;

  /// CMD_START_WEIGHT_MEAS — the gauge only streams force after this.
  Future<void> startMeasurement();

  /// CMD_STOP_WEIGHT_MEAS.
  Future<void> stopMeasurement();

  /// CMD_GET_BATTERY_VOLTAGE → millivolts, or null when unavailable.
  Future<int?> readBatteryMillivolts();

  /// CMD_GET_APP_VERSION → firmware version string, or null.
  Future<String?> readFirmwareVersion();

  /// Fires when the device reports RES_LOW_PWR_WARNING.
  Stream<void> get lowPowerWarnings;
}
