import 'dart:async';

import 'package:flutter/material.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

import '../sensors/ble_transport.dart';
import '../sensors/sensor_hub.dart';

/// Pair / scan / connect Progressor — Flowlog-style Sensors screen.
class SensorsScreen extends StatelessWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hub = SensorHubScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sensors')),
      body: ListenableBuilder(
        listenable: hub,
        builder: (context, _) {
          final devices = hub.devices;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Tindeq Progressor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Pair your Progressor here (like Flowlog pairs a Pressensor). '
                'Scan assigns the Bluetooth id, then Connect. Live uses the '
                'connected device for force measurement.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              if (devices.isEmpty)
                const _EmptySensorsState()
              else ...[
                Text('Paired devices', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                for (final device in devices) ...[
                  _PairedDeviceCard(
                    hub: hub,
                    device: device,
                    onConnect: () => _connect(context, hub, device.id),
                    onDisconnect: () => _disconnect(context, hub, device.id),
                    onScan: () => runProgressorScanFlow(context, hub),
                    onRemove: () => hub.removeDevice(device.id),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('add_progressor_button'),
                onPressed: devices.isNotEmpty
                    ? null
                    : () => _addAndScan(context, hub),
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Add Progressor'),
              ),
              if (hub.lastError != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      hub.lastError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Demo (no hardware)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'On the Live tab you can also run Demo mode to replay synthetic '
                'force data without a Progressor.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addAndScan(BuildContext context, SensorHub hub) async {
    hub.addProgressor();
    if (context.mounted) {
      await runProgressorScanFlow(context, hub);
    }
  }

  Future<void> _disconnect(
    BuildContext context,
    SensorHub hub,
    String deviceId,
  ) async {
    final device = hub.devices.firstWhere((e) => e.id == deviceId);
    await hub.disconnect(deviceId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Disconnected from ${device.name}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    SensorHub hub,
    String deviceId,
  ) async {
    await hub.connect(deviceId);
    if (!context.mounted) return;
    final device = hub.devices.firstWhere((e) => e.id == deviceId);
    final message = switch (device.state) {
      SensorConnectionState.connected => 'Connected to ${device.name}.',
      SensorConnectionState.connecting => 'Connecting to ${device.name}…',
      _ => hub.lastError ??
          'Could not connect to ${device.name}. Check Bluetooth and try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Shared scan flow (progress dialog + multi-device pick). Used by Sensors + Live.
Future<void> runProgressorScanFlow(BuildContext context, SensorHub hub) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  if (!hub.hasProgressor) {
    hub.addProgressor();
  }

  BuildContext? dialogContext;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) {
        dialogContext = dctx;
        return const AlertDialog(
          key: Key('scan_progress_progressor'),
          title: Text('Scanning for Progressor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('Power on your Progressor and keep it nearby.'),
            ],
          ),
        );
      },
    ),
  );

  await Future<void>.delayed(Duration.zero);

  BleScanAssignResult result;
  try {
    result = await hub.scanAndAssign();
  } catch (e) {
    hub.setLastError('Scan failed: $e');
    result = BleScanAssignResult.unavailable('Scan error: $e');
  } finally {
    final dc = dialogContext;
    if (dc != null) {
      try {
        if (Navigator.canPop(dc)) Navigator.pop(dc);
      } catch (_) {}
    }
  }

  if (!context.mounted && !navigator.mounted) return;
  final dialogNavContext = navigator.context;

  switch (result.outcome) {
    case BleScanAssignOutcome.assigned:
      final device = result.device!;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Found ${device.name} (${device.remoteId}). Tap Connect.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    case BleScanAssignOutcome.notFound:
      await showDialog<void>(
        context: dialogNavContext,
        builder: (dialogContext) => AlertDialog(
          key: const Key('scan_not_found_dialog'),
          title: const Text('Progressor not found'),
          content: const Text(
            'No nearby Progressor was detected. Power it on (LED), '
            'stay within a few meters, then tap Scan again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    case BleScanAssignOutcome.multiple:
      final selected = await showDialog<BleDiscoveredDevice>(
        context: dialogNavContext,
        builder: (dialogContext) => _PickScannedDeviceDialog(devices: result.devices),
      );
      if (selected != null) {
        hub.assignBleRemoteId(
          bleRemoteId: selected.remoteId,
          name: selected.name,
          rssi: selected.rssi,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text('Assigned ${selected.name}. Tap Connect.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    case BleScanAssignOutcome.unavailable:
      await showDialog<void>(
        context: dialogNavContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bluetooth unavailable'),
          content: Text(
            result.message ?? 'Bluetooth is not available on this device.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
  }
}

class _EmptySensorsState extends StatelessWidget {
  const _EmptySensorsState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('No Progressor paired', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Add your Tindeq Progressor 200 below to measure real force.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairedDeviceCard extends StatelessWidget {
  const _PairedDeviceCard({
    required this.hub,
    required this.device,
    required this.onConnect,
    required this.onDisconnect,
    required this.onScan,
    required this.onRemove,
  });

  final SensorHub hub;
  final PairedSensorEntry device;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onScan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final connected = device.state == SensorConnectionState.connected;
    final connecting = device.state == SensorConnectionState.connecting;
    final rssi = hub.rssiFor(device.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: connected ? Colors.greenAccent : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        _subtitle(device, connected, connecting, rssi),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: connecting ? null : onScan,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('Scan'),
                ),
                if (connected)
                  FilledButton.tonalIcon(
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: (connecting || !device.hasBleId) ? null : onConnect,
                    icon: connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link, size: 18),
                    label: Text(connecting ? 'Connecting…' : 'Connect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(
    PairedSensorEntry device,
    bool connected,
    bool connecting,
    int? rssi,
  ) {
    final id = device.bleRemoteId;
    final idPart = id == null || id.isEmpty ? 'not scanned yet' : id;
    final state = connecting
        ? 'Connecting…'
        : connected
            ? 'Connected'
            : 'Disconnected';
    final rssiPart = rssi != null ? ' · $rssi dBm' : '';
    return '$state · $idPart$rssiPart';
  }
}

class _PickScannedDeviceDialog extends StatelessWidget {
  const _PickScannedDeviceDialog({required this.devices});

  final List<BleDiscoveredDevice> devices;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Progressor'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: devices.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final device = devices[index];
            return ListTile(
              title: Text(device.name.isEmpty ? 'Progressor' : device.name),
              subtitle: Text('${device.remoteId} · ${device.rssi} dBm'),
              onTap: () => Navigator.pop(context, device),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
