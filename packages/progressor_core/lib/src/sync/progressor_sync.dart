// Progressor sync coordinator skeleton (Nextcloud / WebDAV based).
// See docs/PLAN.md and Flowlog for the intended design: push/pull of test records + blobs.

library progressor_core_sync;

import 'webdav_client.dart';

export 'webdav_client.dart';

/// High level sync service. Currently a stub.
class ProgressorSync {
  final WebDAVClient client;

  ProgressorSync(this.client);

  Future<void> push() async {
    // TODO: serialize local changes, upload
  }

  Future<void> pull() async {
    // TODO: download, merge
  }

  Future<void> sync() async {
    await push();
    await pull();
  }
}