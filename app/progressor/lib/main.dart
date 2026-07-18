import 'dart:async';

import 'package:flutter/material.dart';

import 'sensors/ble_transport.dart';
import 'sensors/sensor_hub.dart';
import 'settings/paired_sensors_store.dart';
import 'shell/adaptive_shell.dart';
import 'theme/progressor_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProgressorApp());
}

class ProgressorApp extends StatefulWidget {
  const ProgressorApp({
    super.key,
    this.sensorHub,
    this.autoReconnectSensors = true,
  });

  /// Optional hub override for tests.
  final SensorHub? sensorHub;

  /// When false, skips background BLE reconnect on startup (widget tests).
  final bool autoReconnectSensors;

  @override
  State<ProgressorApp> createState() => _ProgressorAppState();
}

class _ProgressorAppState extends State<ProgressorApp> {
  late final SensorHub _sensorHub;
  late final bool _ownsHub;
  late final PairedSensorsStore _pairedStore;

  @override
  void initState() {
    super.initState();
    _pairedStore = PairedSensorsStore();
    _ownsHub = widget.sensorHub == null;
    _sensorHub = widget.sensorHub ??
        SensorHub(
          bleBackend: createBleConnectionBackend(),
          pairedSensorsStore: _pairedStore,
        );
    if (_ownsHub) {
      unawaited(_restorePaired());
    }
  }

  Future<void> _restorePaired() async {
    final records = await _pairedStore.load();
    for (final record in records) {
      _sensorHub.restoreDevice(SensorHub.entryFromRecord(record));
    }
    if (widget.autoReconnectSensors && mounted) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          _sensorHub.reconnectPaired,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_ownsHub) {
      _sensorHub.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SensorHubScope(
      hub: _sensorHub,
      child: MaterialApp(
        title: 'Progressor',
        debugShowCheckedModeBanner: false,
        theme: ProgressorTheme.dark,
        darkTheme: ProgressorTheme.dark,
        themeMode: ThemeMode.dark,
        home: const AdaptiveShell(),
      ),
    );
  }
}
