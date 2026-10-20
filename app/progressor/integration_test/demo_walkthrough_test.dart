// Walks every screen / flow of the app against the simulated demo
// Progressor and saves screenshots.
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

Future<void> _selectProtocol(WidgetTester tester, String chip) async {
  await _tap(tester, find.widgetWithText(ChoiceChip, chip));
}

Future<void> _start(WidgetTester tester) => _tap(tester, find.text('START'));

Future<void> _stop(WidgetTester tester) async {
  final stop = find.byIcon(Icons.stop);
  await _tap(tester, stop.first);
  await _wait(tester, const Duration(milliseconds: 1200));
  // Dismiss PR celebration / dialogs if any.
  final close = find.textContaining('Nice');
  if (close.evaluate().isNotEmpty) await _tap(tester, close.first);
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

    // ---- Onboarding ----
    expect(find.text('Skip'), findsOneWidget);
    await _shot(tester, '01-onboarding');
    await _tap(tester, find.text('Skip'));

    // ---- Live, nothing connected ----
    await _shot(tester, '02-live-not-connected');

    // ---- Sensors: demo device entry ----
    await _tap(tester, find.byTooltip('Sensors'));
    await _shot(tester, '03-sensors');
    await _tap(tester, find.byKey(const Key('sensors_demo_connect')));
    await _wait(tester, const Duration(seconds: 1));
    expect(hub.isDemoActive, isTrue);
    await _shot(tester, '04-sensors-demo-connected');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 600));

    // ---- Live idle with demo stream; tare ----
    await _wait(tester, const Duration(seconds: 2));
    await _shot(tester, '05-live-demo-before-tare');
    await _tap(tester, find.text('Tare'));
    await _wait(tester, const Duration(seconds: 2));
    final demo = hub.demoAdapter!;
    expect(demo.tareOffsetKg, greaterThan(1));
    await _shot(tester, '06-live-demo-tared');

    // ---- Peak force ----
    await _selectProtocol(tester, 'Peak');
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 3400));
    await _shot(tester, '07-peak-mid-pull');
    await _wait(tester, const Duration(seconds: 4));
    await _shot(tester, '08-peak-done');
    await _stop(tester);
    await _shot(tester, '09-live-after-save');

    // ---- RFD ----
    await _selectProtocol(tester, 'Rate');
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 2050));
    await _shot(tester, '10-rfd-mid-pull');
    await _wait(tester, const Duration(milliseconds: 3500));
    await _shot(tester, '11-rfd-done');
    await _stop(tester);

    // ---- Repeaters 7:3 × 6 (full set) ----
    await _selectProtocol(tester, 'Repeaters');
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 14500));
    await _shot(tester, '12-repeaters-work');
    await _wait(tester, const Duration(milliseconds: 3000));
    await _shot(tester, '13-repeaters-rest');
    await _wait(tester, const Duration(seconds: 45));
    await _shot(tester, '14-repeaters-done');
    await _stop(tester);

    // ---- Endurance ----
    await _selectProtocol(tester, 'Endurance');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 8));
    await _shot(tester, '15-endurance');
    await _stop(tester);

    // ---- Custom / free log ----
    await _selectProtocol(tester, 'Custom');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 4));
    await _shot(tester, '16-custom-free-pull');
    await _wait(tester, const Duration(seconds: 6));
    await _stop(tester);

    // ---- Warm-ups ----
    await _selectProtocol(tester, 'Follow Curve');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 8));
    await _shot(tester, '17-follow-curve');
    await _wait(tester, const Duration(seconds: 5));
    await _stop(tester);

    await _selectProtocol(tester, 'Hold & Release');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 10));
    await _shot(tester, '18-hold-release');
    await _wait(tester, const Duration(seconds: 4));
    await _stop(tester);

    await _selectProtocol(tester, 'Progressive Warm-up');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 10));
    await _shot(tester, '19-progressive');
    await _stop(tester);

    await _selectProtocol(tester, 'Finger Drag');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 5));
    await _shot(tester, '20-finger-drag');
    await _stop(tester);

    await _selectProtocol(tester, 'Finger Curls');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 7));
    await _shot(tester, '21-finger-curls');
    await _stop(tester);

    await _selectProtocol(tester, 'Tour');
    await _start(tester);
    await _wait(tester, const Duration(seconds: 5));
    await _shot(tester, '22-tour-step');
    // Skip ahead to the first pause step.
    for (var i = 0; i < 6; i++) {
      final cont = find.text('CONTINUE');
      if (cont.evaluate().isNotEmpty) break;
      await _tap(tester, find.text('NEXT'));
      await _wait(tester, const Duration(milliseconds: 600));
    }
    await _shot(tester, '23-tour-pause');
    await _stop(tester);

    // ---- History, detail, fullscreen ----
    await _tab(tester, 'History');
    await _wait(tester, const Duration(milliseconds: 600));
    expect(find.byKey(const Key('history_demo_chip')), findsWidgets);
    await _shot(tester, '24-history');
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
    await _shot(tester, '25-detail-repeaters');
    await _tap(tester, find.byTooltip('Fullscreen plot'));
    await _shot(tester, '26-fullscreen-repeaters');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));
    await openHistory('Peak Force');
    await _shot(tester, '27-detail-peak');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));

    // ---- Train, More, Sync ----
    await _tab(tester, 'Train');
    await _shot(tester, '28-train');
    await _tab(tester, 'More');
    await _shot(tester, '29-more');
    await _tap(tester, find.text('Nextcloud Sync'));
    await _shot(tester, '30-sync');
    await tester.pageBack();
    await _wait(tester, const Duration(milliseconds: 400));

    // CSV export content (sharing itself opens the OS share sheet / mailto).
    final csv = exportAllToCsv((await TestStorage().loadAll()).toList());
    expect(csv.split('\n').length, greaterThan(5));

    // ---- Guide dialog ----
    await _tab(tester, 'Live');
    await _tap(tester, find.byTooltip('Guide'));
    await _shot(tester, '31-guide');
    await _tap(tester, find.text('Close'));

    // ---- Wide (desktop) layout mid-pull ----
    tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
    await _wait(tester, const Duration(milliseconds: 500));
    await _selectProtocol(tester, 'Peak');
    await _start(tester);
    await _wait(tester, const Duration(milliseconds: 3400));
    await _shot(tester, '32-wide-peak-mid-pull');
    await _wait(tester, const Duration(seconds: 4));
    await _stop(tester);

    // Leave demo mode.
    await hub.stopDemo();
    await _wait(tester, const Duration(milliseconds: 300));
    expect(hub.isDemoActive, isFalse);
    expect(demo.isConnected, isFalse);

    // ignore: avoid_print
    print('SHOTS:\n${_shots.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
