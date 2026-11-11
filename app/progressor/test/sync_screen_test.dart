import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progressor/persistence/session_store.dart';
import 'package:progressor/screens/sync_screen.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sync_url': 'http://cloud.example/remote.php/dav/files/me/',
      'sync_user': 'me',
      'sync_password': 'secret',
    });
    TestStorage.close();
    TestStorage.initializeMemory();
  });
  tearDown(TestStorage.close);

  Future<void> pumpSync(WidgetTester tester) async {
    final store = SessionStore();
    await store.load();
    await tester.pumpWidget(
      SessionStoreScope(
        store: store,
        child: const MaterialApp(home: SyncScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('plain http:// shows a warning and asks before sending', (
    tester,
  ) async {
    await pumpSync(tester);
    expect(find.byKey(const Key('sync_http_warning')), findsOneWidget);

    await tester.tap(find.text('Test'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('sync_http_confirm')), findsOneWidget);

    // Cancel: nothing is sent, no status.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('sync_http_confirm')), findsNothing);
    expect(find.byKey(const Key('sync_status')), findsNothing);
  });

  testWidgets('https:// has no warning', (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_url': 'https://cloud.example/remote.php/dav/files/me/',
    });
    await pumpSync(tester);
    expect(find.byKey(const Key('sync_http_warning')), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'WebDAV URL'),
      'HTTP://nas.local/dav/',
    );
    await tester.pump();
    expect(find.byKey(const Key('sync_http_warning')), findsOneWidget);
  });
}
