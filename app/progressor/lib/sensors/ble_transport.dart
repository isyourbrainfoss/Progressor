import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

/// A BLE device discovered during a Progressor scan.
class BleDiscoveredDevice {
  const BleDiscoveredDevice({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });

  final String remoteId;
  final String name;
  final int rssi;
}

/// Outcome of assigning a BLE remote id to the paired Progressor.
enum BleScanAssignOutcome {
  assigned,
  notFound,
  multiple,
  unavailable,
}

/// Result of a scan-and-assign attempt.
class BleScanAssignResult {
  const BleScanAssignResult._({
    required this.outcome,
    this.device,
    this.devices = const [],
    this.message,
  });

  final BleScanAssignOutcome outcome;
  final BleDiscoveredDevice? device;
  final List<BleDiscoveredDevice> devices;
  final String? message;

  factory BleScanAssignResult.assigned(BleDiscoveredDevice device) {
    return BleScanAssignResult._(
      outcome: BleScanAssignOutcome.assigned,
      device: device,
    );
  }

  factory BleScanAssignResult.notFound() {
    return const BleScanAssignResult._(outcome: BleScanAssignOutcome.notFound);
  }

  factory BleScanAssignResult.multiple(List<BleDiscoveredDevice> devices) {
    return BleScanAssignResult._(
      outcome: BleScanAssignOutcome.multiple,
      devices: devices,
    );
  }

  factory BleScanAssignResult.unavailable(String message) {
    return BleScanAssignResult._(
      outcome: BleScanAssignOutcome.unavailable,
      message: message,
    );
  }
}

/// High-level BLE operations used by [SensorHub].
abstract class BleConnectionBackend {
  Future<String?> ensureReady();

  Future<List<BleDiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  });

  Future<SensorAdapter> createAdapter({required String bleRemoteId});
}

/// BLE backend when Bluetooth is not available (tests / unsupported platforms).
class UnsupportedBleConnectionBackend implements BleConnectionBackend {
  const UnsupportedBleConnectionBackend({this.message});

  final String? message;

  @override
  Future<String?> ensureReady() async {
    return message ??
        'Bluetooth is not available on this device. '
            'Pair a Progressor on Android or Linux with Bluetooth enabled.';
  }

  @override
  Future<List<BleDiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return const [];
  }

  @override
  Future<SensorAdapter> createAdapter({required String bleRemoteId}) async {
    throw UnsupportedError((await ensureReady()) ?? 'Bluetooth unavailable');
  }
}

String resolveBleDeviceName({
  required String advName,
  required String platformName,
}) {
  if (advName.isNotEmpty) return advName;
  return platformName;
}

/// flutter_blue_plus wiring for Android and Linux (same approach as Flowlog).
class FlutterBlueBleConnectionBackend implements BleConnectionBackend {
  @override
  Future<String?> ensureReady() async {
    if (!Platform.isAndroid && !Platform.isLinux) {
      return 'Bluetooth connect is only enabled on Android and Linux.';
    }

    if (await FlutterBluePlus.isSupported == false) {
      return 'Bluetooth is not supported on this device.';
    }

    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } on Object {
        // User may decline; adapter state check below surfaces a clear message.
      }
    }

    final state = await FlutterBluePlus.adapterState
        .where((value) => value != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () {
      return BluetoothAdapterState.unknown;
    });

    return switch (state) {
      BluetoothAdapterState.on => null,
      BluetoothAdapterState.off =>
        'Turn on Bluetooth to scan and connect your Progressor.',
      BluetoothAdapterState.unauthorized =>
        'Bluetooth permission is required. Allow Nearby devices / Bluetooth.',
      BluetoothAdapterState.unavailable =>
        'Bluetooth is unavailable on this device.',
      BluetoothAdapterState.turningOn || BluetoothAdapterState.turningOff =>
        'Bluetooth is still starting. Try again in a moment.',
      BluetoothAdapterState.unknown => 'Bluetooth state is unknown. Try again.',
    };
  }

  @override
  Future<List<BleDiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final readyError = await ensureReady();
    if (readyError != null) {
      return const [];
    }

    final results = await TindeqBleAdapter.scanForProgressors(timeout: timeout);
    final devices = <BleDiscoveredDevice>[
      for (final r in results)
        BleDiscoveredDevice(
          remoteId: r.device.remoteId.str,
          name: resolveBleDeviceName(
            advName: r.advertisementData.advName,
            platformName: r.device.platformName,
          ),
          rssi: r.rssi,
        ),
    ];

    if (Platform.isLinux) {
      try {
        await _mergeLinuxCachedDevices(devices);
      } catch (_) {}
    }

    devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  Future<void> _mergeLinuxCachedDevices(List<BleDiscoveredDevice> devices) async {
    final existing = {for (final d in devices) d.remoteId};
    try {
      final systemDevices = await FlutterBluePlus.systemDevices(const []);
      for (final device in systemDevices) {
        final name = device.platformName;
        if (!TindeqBleAdapter.isProgressorName(name)) continue;
        if (existing.contains(device.remoteId.str)) continue;
        devices.add(
          BleDiscoveredDevice(
            remoteId: device.remoteId.str,
            name: name,
            rssi: -128,
          ),
        );
      }
    } on Object {
      // Discovery results are still usable when the system device list fails.
    }
  }

  @override
  Future<SensorAdapter> createAdapter({required String bleRemoteId}) async {
    return TindeqBleAdapter(deviceId: bleRemoteId);
  }
}

/// Production BLE backend on supported platforms.
BleConnectionBackend createBleConnectionBackend() {
  if (kIsWeb) {
    return const UnsupportedBleConnectionBackend(
      message: 'Bluetooth is not available in the web build.',
    );
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return FlutterBlueBleConnectionBackend();
  }
  return const UnsupportedBleConnectionBackend();
}
