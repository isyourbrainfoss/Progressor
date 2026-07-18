import 'dart:async';

import 'package:flutter/material.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

import '../settings/paired_sensors_store.dart';
import 'ble_transport.dart';

/// A user-paired Progressor entry (persisted across restarts).
class PairedSensorEntry {
  PairedSensorEntry({
    required this.id,
    required this.name,
    this.bleRemoteId,
    this.state = SensorConnectionState.disconnected,
  });

  final String id;
  final String name;
  final String? bleRemoteId;
  SensorConnectionState state;

  PairedSensorEntry copyWith({
    SensorConnectionState? state,
    String? bleRemoteId,
    String? name,
  }) {
    return PairedSensorEntry(
      id: id,
      name: name ?? this.name,
      bleRemoteId: bleRemoteId ?? this.bleRemoteId,
      state: state ?? this.state,
    );
  }

  bool get hasBleId => bleRemoteId != null && bleRemoteId!.isNotEmpty;
}

/// In-app registry for the paired Progressor and its connection state.
///
/// Modeled on Flowlog's SensorHub: pair/scan once, reconnect by BLE id,
/// expose the live [SensorAdapter] for the Live tab.
class SensorHub extends ChangeNotifier {
  SensorHub({
    List<PairedSensorEntry>? initialDevices,
    BleConnectionBackend? bleBackend,
    PairedSensorsStore? pairedSensorsStore,
  })  : _devices = List.of(initialDevices ?? []),
        _bleBackend = bleBackend ?? const UnsupportedBleConnectionBackend(),
        _pairedSensorsStore = pairedSensorsStore;

  final List<PairedSensorEntry> _devices;
  final PairedSensorsStore? _pairedSensorsStore; // ignore: prefer_initializing_formals
  final BleConnectionBackend _bleBackend;
  final Map<String, SensorAdapter> _activeAdapters = {};
  final Map<String, StreamSubscription<SensorConnectionState>> _stateSubs = {};
  final Map<String, int?> _rssiByDevice = {};
  String? _lastError;
  int _idCounter = 0;

  List<PairedSensorEntry> get devices => List.unmodifiable(_devices);

  String? get lastError => _lastError;

  bool get hasProgressor => _devices.isNotEmpty;

  PairedSensorEntry? get progressor =>
      _devices.isEmpty ? null : _devices.first;

  SensorConnectionState get progressorState =>
      progressor?.state ?? SensorConnectionState.disconnected;

  bool get isProgressorConnected =>
      progressorState == SensorConnectionState.connected;

  int? rssiFor(String deviceId) => _rssiByDevice[deviceId];

  /// Active BLE adapter when connected.
  SensorAdapter? get activeAdapter {
    final p = progressor;
    if (p == null || p.state != SensorConnectionState.connected) return null;
    return _activeAdapters[p.id];
  }

  TindeqBleAdapter? get activeBleAdapter {
    final a = activeAdapter;
    return a is TindeqBleAdapter ? a : null;
  }

  void restoreDevice(PairedSensorEntry entry) {
    if (_devices.any((d) => d.id == entry.id)) return;
    // Only one Progressor for now.
    if (_devices.isNotEmpty) return;
    _devices.add(entry);
    _syncIdCounter();
    notifyListeners();
  }

  static PairedSensorEntry entryFromRecord(PairedSensorRecord record) {
    return PairedSensorEntry(
      id: record.id,
      name: record.name,
      bleRemoteId: record.bleRemoteId,
    );
  }

  /// Adds a Progressor slot if none exists yet.
  bool addProgressor({String? name}) {
    if (_devices.isNotEmpty) return false;
    _idCounter += 1;
    _devices.add(
      PairedSensorEntry(
        id: 'progressor-$_idCounter',
        name: (name?.trim().isNotEmpty ?? false)
            ? name!.trim()
            : 'Tindeq Progressor',
      ),
    );
    unawaited(_persist());
    notifyListeners();
    return true;
  }

  bool assignBleRemoteId({
    required String bleRemoteId,
    String? name,
    int? rssi,
  }) {
    if (_devices.isEmpty) return false;
    final device = _devices.first;
    _devices[0] = device.copyWith(
      bleRemoteId: bleRemoteId,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : device.name,
    );
    if (rssi != null) {
      _rssiByDevice[device.id] = rssi;
    }
    unawaited(_persist());
    notifyListeners();
    return true;
  }

  Future<BleScanAssignResult> scanAndAssign() async {
    final readyError = await _bleBackend.ensureReady();
    if (readyError != null) {
      setLastError(readyError);
      return BleScanAssignResult.unavailable(readyError);
    }

    final discovered = await _bleBackend.scan();
    if (discovered.isEmpty) {
      const message =
          'No Progressor found. Power it on (LED), keep it nearby, then Scan again.';
      setLastError(message);
      return BleScanAssignResult.notFound();
    }

    if (discovered.length > 1) {
      return BleScanAssignResult.multiple(discovered);
    }

    final match = discovered.first;
    if (_devices.isEmpty) {
      addProgressor(name: match.name);
    }
    assignBleRemoteId(
      bleRemoteId: match.remoteId,
      name: match.name,
      rssi: match.rssi,
    );
    setLastError(null);
    return BleScanAssignResult.assigned(match);
  }

  void removeDevice(String id) {
    unawaited(disconnect(id));
    final before = _devices.length;
    _devices.removeWhere((d) => d.id == id);
    _rssiByDevice.remove(id);
    if (_devices.length != before) {
      unawaited(_persist());
      notifyListeners();
    }
  }

  Future<void> reconnectPaired() async {
    final p = progressor;
    if (p == null || !p.hasBleId) return;
    if (p.state == SensorConnectionState.connected ||
        p.state == SensorConnectionState.connecting) {
      return;
    }
    await connect(p.id);
  }

  Future<void> connect(String id) async {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index < 0) return;

    final device = _devices[index];
    _devices[index] = device.copyWith(state: SensorConnectionState.connecting);
    notifyListeners();

    final readyError = await _bleBackend.ensureReady();
    if (readyError != null) {
      await _failConnect(index, device, readyError);
      return;
    }

    final bleRemoteId = device.bleRemoteId;
    if (bleRemoteId == null || bleRemoteId.isEmpty) {
      await _failConnect(
        index,
        device,
        'Scan for the Progressor first to assign its Bluetooth id.',
      );
      return;
    }

    try {
      await _stateSubs.remove(id)?.cancel();
      await _activeAdapters.remove(id)?.disconnect();

      final adapter =
          await _bleBackend.createAdapter(bleRemoteId: bleRemoteId);
      _activeAdapters[id] = adapter;
      _stateSubs[id] = adapter.state.listen((state) {
        _onAdapterStateChanged(id, state);
      });

      await adapter.connect(deviceId: bleRemoteId);

      final currentIndex = _devices.indexWhere((e) => e.id == id);
      if (currentIndex < 0) return;

      // Prefer device-reported name.
      var name = device.name;
      if (adapter is TindeqBleAdapter) {
        final n = adapter.connectedName;
        if (n != null && n.isNotEmpty) name = n;
      }

      _devices[currentIndex] = _devices[currentIndex].copyWith(
        state: SensorConnectionState.connected,
        name: name,
      );
      setLastError(null);
      notifyListeners();
    } on Object catch (error) {
      final message = 'BLE connect failed: $error';
      await _failConnect(index, device, message);
      await _stateSubs.remove(id)?.cancel();
      await _activeAdapters.remove(id)?.disconnect();
    }
  }

  Future<void> disconnect(String id) async {
    await _stateSubs.remove(id)?.cancel();
    final adapter = _activeAdapters.remove(id);
    if (adapter != null) {
      try {
        if (adapter is TindeqBleAdapter && adapter.isMeasuring) {
          await adapter.stopMeasurement();
        }
        await adapter.disconnect();
      } catch (_) {}
    }

    final index = _devices.indexWhere((d) => d.id == id);
    if (index < 0) return;
    _devices[index] =
        _devices[index].copyWith(state: SensorConnectionState.disconnected);
    notifyListeners();
  }

  Future<void> _failConnect(
    int index,
    PairedSensorEntry device,
    String message,
  ) async {
    _devices[index] =
        device.copyWith(state: SensorConnectionState.disconnected);
    setLastError(message);
    notifyListeners();
  }

  void _onAdapterStateChanged(String id, SensorConnectionState state) {
    final index = _devices.indexWhere((d) => d.id == id);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(state: state);
    if (state == SensorConnectionState.error) {
      setLastError('Sensor link error. Try reconnecting.');
    }
    notifyListeners();
  }

  void setLastError(String? message) {
    if (_lastError == message) return;
    _lastError = message;
    notifyListeners();
  }

  void _syncIdCounter() {
    for (final d in _devices) {
      final m = RegExp(r'^progressor-(\d+)$').firstMatch(d.id);
      if (m == null) continue;
      final v = int.tryParse(m.group(1) ?? '');
      if (v != null && v > _idCounter) _idCounter = v;
    }
  }

  Future<void> _persist() async {
    final store = _pairedSensorsStore;
    if (store == null) return;
    await store.save([
      for (final d in _devices)
        PairedSensorRecord(
          id: d.id,
          name: d.name,
          bleRemoteId: d.bleRemoteId,
        ),
    ]);
  }

  @override
  void dispose() {
    for (final sub in _stateSubs.values) {
      unawaited(sub.cancel());
    }
    _stateSubs.clear();
    for (final adapter in _activeAdapters.values) {
      unawaited(adapter.disconnect());
    }
    _activeAdapters.clear();
    super.dispose();
  }
}

/// Provides [SensorHub] to the widget tree.
class SensorHubScope extends InheritedNotifier<SensorHub> {
  const SensorHubScope({
    required SensorHub hub,
    required super.child,
    super.key,
  }) : super(notifier: hub);

  static SensorHub of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SensorHubScope>();
    assert(scope != null, 'SensorHubScope not found in context');
    return scope!.notifier!;
  }

  static SensorHub? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SensorHubScope>()
        ?.notifier;
  }
}
