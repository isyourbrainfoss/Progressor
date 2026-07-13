import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Simple WebDAV client for Nextcloud sync (inspired by Flowlog).
@immutable
class WebDavCredentials {
  const WebDavCredentials({required this.serverUrl, required this.username, required this.password});

  final String serverUrl;
  final String username;
  final String password;

  String get basicAuth => 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;
  @override
  String toString() => 'WebDavException: $message';
}

abstract class WebDavTransport {
  Future<void> ensureCollection(String name);
  Future<String?> getText(String path);
  Future<void> putText(String path, String content);
}

class WebDavClient implements WebDavTransport {
  WebDavClient(this.credentials);

  final WebDavCredentials credentials;
  late final String _base = _normalize(credentials.serverUrl);

  String _normalize(String url) {
    var u = url.trim();
    if (!u.endsWith('/')) u += '/';
    if (u.contains('/remote.php/dav/files/')) return u;
    // assume nextcloud root
    final user = credentials.username;
    return '$u/remote.php/dav/files/$user/';
  }

  Map<String, String> get _headers => {
        'Authorization': credentials.basicAuth,
        'Content-Type': 'text/plain; charset=utf-8',
      };

  @override
  Future<void> ensureCollection(String name) async {
    final uri = Uri.parse('$_base$name/');
    final resp = await http.request('MKCOL', uri, headers: _headers);
    if (resp.statusCode != 201 && resp.statusCode != 405 /* already exists */) {
      // ignore some errors
    }
  }

  @override
  Future<String?> getText(String path) async {
    final uri = Uri.parse('$_base$path');
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 400) throw WebDavException('GET $path -> ${resp.statusCode}');
    return resp.body;
  }

  @override
  Future<void> putText(String path, String content) async {
    final uri = Uri.parse('$_base$path');
    final resp = await http.put(uri, headers: _headers, body: content);
    if (resp.statusCode >= 400) throw WebDavException('PUT $path -> ${resp.statusCode}');
  }
}
