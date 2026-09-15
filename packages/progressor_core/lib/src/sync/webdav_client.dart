import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when a WebDAV request fails.
class WebDavException implements Exception {
  WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// Minimal WebDAV client (Basic auth) for Nextcloud-style sync.
class WebDAVClient {
  WebDAVClient({
    required this.baseUrl,
    this.username,
    this.password,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String? username;
  final String? password;
  final http.Client httpClient;

  Map<String, String> _headers({Map<String, String>? extra}) {
    final h = <String, String>{
      if (username != null && username!.isNotEmpty)
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      ...?extra,
    };
    return h;
  }

  Uri resolve(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final rel = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(base).resolve(rel);
  }

  Future<void> connect() async {
    final req = http.Request('PROPFIND', resolve(''));
    req.headers.addAll(_headers(extra: {
      'Depth': '0',
      'Content-Type': 'application/xml; charset=utf-8',
    }));
    req.body =
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';
    final res = await http.Response.fromStream(await httpClient.send(req));
    if (res.statusCode >= 400) {
      throw WebDavException(
        'Could not reach WebDAV server',
        statusCode: res.statusCode,
      );
    }
  }

  /// Create a collection. Ignores "already exists" (405 / 409 / 301).
  Future<void> mkcol(String path) async {
    final req = http.Request('MKCOL', resolve(path));
    req.headers.addAll(_headers());
    final res = await http.Response.fromStream(await httpClient.send(req));
    if (res.statusCode >= 400 &&
        res.statusCode != 405 &&
        res.statusCode != 409 &&
        res.statusCode != 301) {
      throw WebDavException(
        'MKCOL failed for $path',
        statusCode: res.statusCode,
      );
    }
  }

  Future<List<String>> list(String path) async {
    final req = http.Request('PROPFIND', resolve(path));
    req.headers.addAll(_headers(extra: {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8',
    }));
    req.body =
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
    final res = await http.Response.fromStream(await httpClient.send(req));
    if (res.statusCode == 404) return const [];
    if (res.statusCode >= 400) {
      throw WebDavException('PROPFIND failed', statusCode: res.statusCode);
    }
    return _parseHrefs(res.body);
  }

  Future<void> put(String path, List<int> data) async {
    final res = await httpClient.put(
      resolve(path),
      headers: _headers(extra: {
        'Content-Type': 'application/json',
      }),
      body: data,
    );
    if (res.statusCode >= 400) {
      throw WebDavException('PUT failed for $path', statusCode: res.statusCode);
    }
  }

  Future<List<int>> get(String path) async {
    final res = await httpClient.get(resolve(path), headers: _headers());
    if (res.statusCode >= 400) {
      throw WebDavException('GET failed for $path', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  /// Best-effort href list from a PROPFIND multi-status body.
  static List<String> _parseHrefs(String xml) {
    final matches = RegExp(
      r'<[^>]*href[^>]*>([^<]+)</[^>]*href>',
      caseSensitive: false,
    ).allMatches(xml);
    final names = <String>[];
    for (final m in matches) {
      final raw = m.group(1);
      if (raw == null || raw.isEmpty) continue;
      final decoded = Uri.decodeFull(raw.trim());
      final base = decoded.split('?').first;
      final parts = base.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      names.add(parts.last);
    }
    return names;
  }
}
