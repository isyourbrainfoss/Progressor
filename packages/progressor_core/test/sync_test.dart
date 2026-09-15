import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    TestStorage.close();
    TestStorage.initializeMemory();
  });
  tearDown(TestStorage.close);

  test('WebDAV list parses href basenames', () async {
    final client = WebDAVClient(
      baseUrl: 'https://cloud.example/dav/',
      username: 'climber',
      password: 'secret',
      httpClient: MockClient((req) async {
        expect(req.method, 'PROPFIND');
        return http.Response(
          '<?xml version="1.0"?>'
          '<d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/dav/progressor/tests/</d:href></d:response>'
          '<d:response><d:href>/dav/progressor/tests/abc.json</d:href></d:response>'
          '</d:multistatus>',
          207,
        );
      }),
    );
    final names = await client.list('progressor/tests');
    expect(names, contains('abc.json'));
  });

  test('sync pushes local tests and pulls missing remote json', () async {
    final store = TestStorage();
    final local = PullTest(
      id: 'local1',
      startTime: DateTime.utc(2026, 2, 1),
      type: TestType.peakForce,
      samples: const [
        ForceSample(timeMs: 0, forceKg: 10),
        ForceSample(timeMs: 50, forceKg: 40),
      ],
    );
    await store.save(local);

    final remoteTest = PullTest(
      id: 'remote1',
      startTime: DateTime.utc(2026, 2, 2),
      type: TestType.rfd,
      samples: const [
        ForceSample(timeMs: 0, forceKg: 5),
        ForceSample(timeMs: 80, forceKg: 22),
      ],
    );

    final blobs = <String, List<int>>{};
    final httpClient = MockClient((req) async {
      final path = req.url.path;
      if (req.method == 'MKCOL') {
        return http.Response('', 201);
      }
      if (req.method == 'PROPFIND') {
        final hrefs = blobs.keys
            .map((k) => '<d:response><d:href>$k</d:href></d:response>')
            .join();
        return http.Response(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">$hrefs</d:multistatus>',
          207,
        );
      }
      if (req.method == 'PUT') {
        blobs[path] = req.bodyBytes;
        return http.Response('', 201);
      }
      if (req.method == 'GET') {
        final data = blobs[path];
        if (data == null) return http.Response('missing', 404);
        return http.Response.bytes(data, 200);
      }
      return http.Response('nope', 500);
    });

    blobs['/dav/progressor/tests/remote1.json'] =
        utf8.encode(jsonEncode(remoteTest.toJson()));

    final dav = WebDAVClient(
      baseUrl: 'https://cloud.example/dav/',
      httpClient: httpClient,
    );
    final sync = ProgressorSync(dav, storage: store);
    final result = await sync.sync();

    expect(result.pushed, 1);
    expect(result.pulled, 1);
    final all = await store.loadAll();
    expect(all.map((t) => t.id), containsAll(['local1', 'remote1']));
  });
}
