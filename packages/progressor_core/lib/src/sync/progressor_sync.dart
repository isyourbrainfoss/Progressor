import 'dart:convert';

import '../models/pull_test.dart';
import '../persistence/test_storage.dart';
import 'webdav_client.dart';

export 'webdav_client.dart';

/// Result of a push+pull cycle.
class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.skipped = 0,
  });

  final int pushed;
  final int pulled;
  final int skipped;
}

/// Nextcloud / WebDAV coordinator: tests as JSON blobs under [remoteDir].
class ProgressorSync {
  ProgressorSync(
    this.client, {
    required this.storage,
    this.remoteDir = 'progressor/tests',
  });

  final WebDAVClient client;
  final TestStorage storage;
  final String remoteDir;

  Future<void> ensureRemoteFolder() async {
    final parts = remoteDir.split('/').where((p) => p.isNotEmpty).toList();
    var acc = '';
    for (final part in parts) {
      acc = acc.isEmpty ? part : '$acc/$part';
      await client.mkcol(acc);
    }
  }

  Future<void> push() async {
    await sync();
  }

  Future<void> pull() async {
    await sync();
  }

  Future<SyncResult> sync() async {
    await ensureRemoteFolder();
    final local = await storage.loadAll();
    final localById = {for (final t in local) t.id: t};

    var names = <String>[];
    try {
      names = await client.list(remoteDir);
    } on WebDavException catch (e) {
      if (e.statusCode != 404) rethrow;
    }

    var pushed = 0;
    var pulled = 0;
    var skipped = 0;

    final remoteIds = <String>{};
    for (final name in names) {
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - 5);
      remoteIds.add(id);
    }

    for (final t in local) {
      await client.put(
        '$remoteDir/${t.id}.json',
        utf8.encode(jsonEncode(t.toJson())),
      );
      pushed++;
    }

    for (final id in remoteIds) {
      if (localById.containsKey(id)) {
        skipped++;
        continue;
      }
      final bytes = await client.get('$remoteDir/$id.json');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) continue;
      final test = PullTest.fromJson(Map<String, dynamic>.from(decoded));
      await storage.save(test);
      pulled++;
    }

    return SyncResult(pushed: pushed, pulled: pulled, skipped: skipped);
  }
}
