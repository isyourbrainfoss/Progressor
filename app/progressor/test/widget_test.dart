import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/main.dart';
import 'package:progressor/sensors/ble_transport.dart';
import 'package:progressor/sensors/sensor_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Progressor app smoke test', (WidgetTester tester) async {
    final hub = SensorHub(
      bleBackend: const UnsupportedBleConnectionBackend(
        message: 'Test backend — no Bluetooth',
      ),
    );
    await tester.pumpWidget(
      ProgressorApp(sensorHub: hub, autoReconnectSensors: false),
    );
    // Avoid pumpAndSettle — async prefs / BLE probes can prevent settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Live'), findsAtLeastNWidgets(1));
    expect(find.text('History'), findsAtLeastNWidgets(1));
    expect(find.text('Train'), findsAtLeastNWidgets(1));

    expect(find.byKey(const Key('live_sensor_status')), findsOneWidget);
    expect(find.textContaining('No Progressor paired'), findsOneWidget);
    expect(find.byKey(const Key('live_pair')), findsOneWidget);
  });
}
