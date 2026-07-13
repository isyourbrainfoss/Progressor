// Minimal WebDAV client skeleton for future Nextcloud sync (inspired by Flowlog).
// Full implementation would handle auth, PROPFIND, PUT/GET for blobs, conflict resolution etc.

library progressor_core_webdav;

class WebDAVClient {
  final String baseUrl;
  final String? username;
  final String? password;

  WebDAVClient({
    required this.baseUrl,
    this.username,
    this.password,
  });

  Future<void> connect() async {
    // TODO: implement login / check
  }

  Future<List<String>> list(String path) async {
    // TODO
    return const [];
  }

  Future<void> put(String path, List<int> data) async {
    // TODO
  }

  Future<List<int>> get(String path) async {
    // TODO
    return const [];
  }
}