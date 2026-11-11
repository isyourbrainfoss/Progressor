// Walks every screen / flow of the app against the simulated demo
// Progressor and saves screenshots. No real Tindeq hardware is involved.
//
//   xvfb-run -a flutter test integration_test -d linux \
//     --dart-define=SHOTS_DIR=/workspace/app-shots
//
// Screenshots are written only when SHOTS_DIR is set.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:progressor/main.dart';
import 'package:progressor/sensors/ble_transport.dart';
import 'package:progressor/sensors/sensor_hub.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shotsDir = String.fromEnvironment('SHOTS_DIR');
final _shotKey = GlobalKey();
final _shots = <String>[];

Future<void> _wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final err = tester.takeException();
  if (err != null) {
    fail('Framework error before screenshot "$name": $err');
  }
  if (_shotsDir.isEmpty) return;
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$_shotsDir/progressor-$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  _shots.add(file.path);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _wait(tester, const Duration(milliseconds: 400));
}

Future<void> _tab(WidgetTester tester, String label) async {
  final inNav = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await _tap(tester, inNav);
}

/// Open the mode sheet on Live and pick [type] (expanding "More modes" when
/// the mode is not one of the three basics).
Future<void> _pickMode(
  WidgetTester tester,
  TestType type, {
  String? shot,
}) async {
  await _tap(tester, find.byKey(const Key('live_mode')));
  final item = find.byKey(Key('mode_${type.name}'));
  if (item.evaluate().isEmpty) {
    await _tap(tester, find.byKey(const Key('mode_more')));
  }
  if (shot != null) await _shot(tester, shot);
  await _tap(tester, item);
  await _wait(tester, const Duration(milliseconds: 300));
}

Future<void> _start(WidgetTester tester) =>
    _tap(tester, find.byKey(const Key('live_start')));

Future<void> _stop(WidgetTester tester) async {
  await _tap(tester, find.byKey(const Key('live_stop')));
  await _wait(tester, const Duration(milliseconds: 1200));
  // Dismiss PR celebration / dialogs if any.
  final close = find.textContaining('Nice');
  if (close.evaluate().isNotEmpty) await _tap(tester, close.first);
}

/// Start [type], take [shots] at the given offsets, then stop.
Future<void> _run(
  WidgetTester tester,
  TestType type,
  List<(Duration, String)> shots, {
  Duration tail = Duration.zero,
}) async {
  await _pickMode(tester, type);
  await _start(tester);
  for (final (wait, name) in shots) {
    await _wait(tester, wait);
    await _shot(tester, name);
  }
  if (tail > Duration.zero) await _wait(tester, tail);
  await _stop(tester);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo walkthrough of every screen', (tester) async {
    // Phone-sized portrait layout.
    tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    TestStorage.close();
    TestStorage.initializeMemory();

    final hub = SensorHub(
      bleBackend: const UnsupportedBleConnectionBackend(
        message: 'Bluetooth disabled for the demo walkthrough.',
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: ProgressorApp(sensorHub: hub, autoReconnectSensors: false),
      ),
    );
    await _wait(tester, const Duration(seconds: 1));

    // ---- Welcome ----
    expect(find.byKey(const Key('onboarding_start')), findsOneWidget);
    await _shot(tester, '01-welcome');
    await _tap(tester, find.byKey(const Key('onboarding_start')));

    // ---- Live, nothing connected: connect or try the demo ----
    await _shot(tester, '02-live-not-connected');
    await _tap(tester, find.byKey(const Key('live_try_demo')));
    await _wait(tester, const Duration(seconds: 2));
    expect(hub.isDemoActive, isTrue);
    expect(find.byKey(const Key('demo_badge')), findsOneWidget);
    await _shot(tester, '03-live-demo-idle');

    await _tap(tester, find.byKey(const Key('live_tare')));
    await _wait(tester, const Duration(seconds: 1));
    final demo = hub.demoAdapter!;
    expect(demo.tareOffsetKg, greaterThan(1));

    // ---- Free pull (the default mode) ----
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 3500));
    await _shot(tester, '04-free-pull-mid-pull');
    await _wait(tester, const Duration(seconds: 3));
    await _stop(tester);
    await _shot(tester, '05-live-after-save');

    // ---- Max pull ----
    await _pickMode(tester, TestType.peakForce, shot: '06-mode-sheet');
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 1200));
    await _shot(tester, '07-max-ready');
    await _wait(tester, const Duration(milliseconds: 2400));
    await _shot(tester, '08-max-mid-pull');
    await _wait(tester, const Duration(seconds: 4));
    await _shot(tester, '09-max-done');
    await _stop(tester);
    // Peak survives Stop so you can read it after the pull.
    expect(find.byKey(const Key('live_peak_value')), findsOneWidget);
    await _shot(tester, '10-max-after-save');

    // ---- Repeaters ----
    await _run(tester, TestType.repeaters, [
      (const Duration(milliseconds: 14500), '11-repeaters-work'),
      (const Duration(milliseconds: 3000), '12-repeaters-rest'),
    ]);

    // ---- Everything under "More modes" ----
    await _pickMode(tester, TestType.followCurve, shot: '13-mode-sheet-all');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 8));
    await _shot(tester, '14-follow-curve');
    await _stop(tester);

    await _run(tester, TestType.rfd, [
      (const Duration(milliseconds: 2050), '15-explosive-mid-pull'),
    ], tail: const Duration(seconds: 3));
    await _run(tester, TestType.endurance, [
      (const Duration(seconds: 6), '16-endurance'),
    ]);
    await _run(tester, TestType.holdRelease, [
      (const Duration(seconds: 6), '17-hold-release'),
    ]);
    await _run(tester, TestType.warmupProgressive, [
      (const Duration(seconds: 6), '18-progressive'),
    ]);
    await _run(tester, TestType.fingerDrag, [
      (const Duration(seconds: 4), '19-finger-drag'),
    ]);
    await _run(tester, TestType.fingerCurl, [
      (const Duration(seconds: 5), '20-finger-curls'),
    ]);

    // ---- Warm-up tour ----
    await _pickMode(tester, TestType.warmupTour);
    await _start(tester);
    await _wait(tester, const Duration(seconds: 4));
    await _shot(tester, '21-tour-step');
    for (var i = 0; i < 6; i++) {
      if (find.text('Continue').evaluate().isNotEmpty) break;
      await _tap(tester, find.byKey(const Key('live_next')));
      await _wait(tester, const Duration(milliseconds: 600));
    }
    await _shot(tester, '22-tour-pause');
    await _stop(tester);

    // ---- Device menu → details ----
    await _pickMode(tester, TestType.custom);
    await _tap(tester, find.byKey(const Key('live_device')));
    await _shot(tester, '23-device-menu');
    await _tap(tester, find.text('Device details'));
    await _wait(tester, const Duration(milliseconds: 400));
    await _shot(tester, '24-sensors');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 600));

    // ---- History, detail, fullscreen ----
    await _tab(tester, 'History');
    await _wait(tester, const Duration(milliseconds: 600));
    expect(find.byKey(const Key('history_demo_chip')), findsWidgets);
    await _shot(tester, '25-history');
    final historyScroll = find.descendant(
      of: find.byKey(const Key('history_list')),
      matching: find.byType(Scrollable),
    );
    Future<void> openHistory(String label) async {
      final item = find.textContaining(label);
      await tester.scrollUntilVisible(
        item,
        300,
        scrollable: historyScroll.first,
      );
      await _tap(tester, item.first);
    }

    await openHistory('Repeaters / CF');
    await _wait(tester, const Duration(milliseconds: 600));
    await _shot(tester, '26-detail-repeaters');
    await _tap(tester, find.byTooltip('Fullscreen plot'));
    await _shot(tester, '27-fullscreen-repeaters');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));

    // ---- More: guide, sync ----
    await _tab(tester, 'More');
    await _shot(tester, '28-more');
    await _tap(tester, find.byKey(const Key('more_guide_tile')));
    await _shot(tester, '29-training-guide');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));
    await _tap(tester, find.text('Nextcloud Sync'));
    await _shot(tester, '30-sync');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));

    // CSV export content (sharing itself opens the OS share sheet / mailto).
    final csv = exportAllToCsv((await TestStorage().loadAll()).toList());
    expect(csv.split('\n').length, greaterThan(5));

    // ---- Wide (desktop) layout mid-pull ----
    await _tab(tester, 'Live');
    tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
    await _wait(tester, const Duration(milliseconds: 500));
    await _pickMode(tester, TestType.peakForce);
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 3600));
    await _shot(tester, '31-wide-max-mid-pull');
    await _wait(tester, const Duration(seconds: 4));
    await _stop(tester);

    // ---- Leave the demo from the device menu ----
    await _tap(tester, find.byKey(const Key('live_device')));
    await _tap(tester, find.text('Leave demo'));
    await _wait(tester, const Duration(milliseconds: 500));
    expect(hub.isDemoActive, isFalse);
    expect(demo.isConnected, isFalse);
    expect(find.byKey(const Key('live_try_demo')), findsOneWidget);
    await _shot(tester, '32-wide-not-connected');

    // ignore: avoid_print
    print('SHOTS:\n${_shots.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
