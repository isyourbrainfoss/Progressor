import 'dart:convert';

import '../models/pull_test.dart';
import '../persistence/test_storage.dart';
import 'webdav_client.dart';

/// Simple sync: upload all tests as JSON backup to Nextcloud WebDAV.
Future<bool> syncToNextcloud({
  required WebDavCredentials creds,
  required TestStorage storage,
}) async {
  try {
    final client = WebDavClient(creds);
    await client.ensureCollection('Progressor');

    final tests = await storage.loadAll();
    final payload = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'tests': tests.map((t) => t.toJson()).toList(),
    };

    await client.putText('Progressor/progressor-backup.json', jsonEncode(payload));
    return true;
  } catch (e) {
    print('Sync error: $e');
    return false;
  }
}
