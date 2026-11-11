import 'dart:async';

import 'package:flutter/material.dart';

import 'persistence/session_store.dart';
import 'sensors/ble_transport.dart';
import 'sensors/sensor_hub.dart';
import 'settings/paired_sensors_store.dart';
import 'shell/adaptive_shell.dart';
import 'theme/progressor_theme.dart';

/// `flutter run --dart-define=DEMO=true` starts straight into the simulated
/// Progressor (skips onboarding and BLE auto-reconnect) — handy for
/// screenshots and trying the app without hardware.
const bool kStartInDemo = bool.fromEnvironment('DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initProgressorStorage();
  runApp(const ProgressorApp());
}

class ProgressorApp extends StatefulWidget {
  const ProgressorApp({
    super.key,
    this.sensorHub,
    this.sessionStore,
    this.autoReconnectSensors = true,
    this.startInDemo = kStartInDemo,
  });

  /// Connect the simulated demo Progressor on startup (see [kStartInDemo]).
  final bool startInDemo;

  /// Optional hub override for tests.
  final SensorHub? sensorHub;

  /// Optional session catalog override for tests.
  final SessionStore? sessionStore;

  /// When false, skips background BLE reconnect on startup (widget tests).
  final bool autoReconnectSensors;

  @override
  State<ProgressorApp> createState() => _ProgressorAppState();
}

class _ProgressorAppState extends State<ProgressorApp> {
  late final SensorHub _sensorHub;
  late final bool _ownsHub;
  late final SessionStore _sessions;
  late final bool _ownsSessions;
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
    _ownsSessions = widget.sessionStore == null;
    _sessions = widget.sessionStore ?? SessionStore();
    unawaited(_sessions.load());
    if (_ownsHub) {
      unawaited(_restorePaired());
    }
    if (widget.startInDemo) {
      unawaited(_sensorHub.startDemo());
    }
  }

  Future<void> _restorePaired() async {
    final records = await _pairedStore.load();
    for (final record in records) {
      _sensorHub.restoreDevice(SensorHub.entryFromRecord(record));
    }
    if (widget.autoReconnectSensors && !widget.startInDemo && mounted) {
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
    if (_ownsSessions) {
      _sessions.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SensorHubScope(
      hub: _sensorHub,
      child: SessionStoreScope(
        store: _sessions,
        child: MaterialApp(
          title: 'Progressor',
          debugShowCheckedModeBanner: false,
          theme: ProgressorTheme.dark,
          darkTheme: ProgressorTheme.dark,
          themeMode: ThemeMode.dark,
          home: AdaptiveShell(skipOnboarding: widget.startInDemo),
        ),
      ),
    );
  }
}
