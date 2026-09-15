import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

PullTest _sample({
  String id = 't1',
  double peak = 55,
  TestType type = TestType.peakForce,
  DateTime? start,
}) {
  final samples = [
    ForceSample(timeMs: 0, forceKg: 1),
    ForceSample(timeMs: 200, forceKg: peak),
    ForceSample(timeMs: 400, forceKg: peak * 0.4),
  ];
  return PullTest(
    id: id,
    startTime: start ?? DateTime.utc(2026, 3, 1, 12),
    endTime: (start ?? DateTime.utc(2026, 3, 1, 12)).add(const Duration(seconds: 1)),
    type: type,
    samples: samples,
    hand: 'Right',
    notes: 'unit',
    metrics: computeMetrics(samples).toJson(),
  );
}

void main() {
  setUp(() {
    TestStorage.close();
    TestStorage.initializeMemory();
  });

  tearDown(TestStorage.close);

  test('save then loadAll round-trips samples and metrics', () async {
    final store = TestStorage();
    final original = _sample(peak: 61.25);
    await store.save(original);
    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.first.id, original.id);
    expect(all.first.samples, hasLength(3));
    expect(all.first.peakForceKg, closeTo(61.25, 0.001));
    expect(all.first.hand, 'Right');
    expect(all.first.computedMetrics.peakKg, closeTo(61.25, 0.001));
  });

  test('newest test is first', () async {
    final store = TestStorage();
    await store.save(_sample(id: 'old', start: DateTime.utc(2026, 1, 1)));
    await store.save(_sample(id: 'new', start: DateTime.utc(2026, 6, 1)));
    final all = await store.loadAll();
    expect(all.map((t) => t.id).toList(), ['new', 'old']);
  });

  test('upsert by id replaces samples', () async {
    final store = TestStorage();
    await store.save(_sample(id: 'same', peak: 20));
    await store.save(_sample(id: 'same', peak: 90));
    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.first.peakForceKg, closeTo(90, 0.01));
  });

  test('clear removes tests but kv survives', () async {
    final store = TestStorage();
    await store.save(_sample());
    await store.setKv('streak', '4');
    await store.clear();
    expect(await store.loadAll(), isEmpty);
    expect(await store.getKv('streak'), '4');
  });

  test('file database survives close and reopen', () async {
    final dir = await Directory.systemTemp.createTemp('progressor_db_');
    final path = p.join(dir.path, 'progressor.sqlite');
    addTearDown(() async {
      TestStorage.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    TestStorage.close();
    TestStorage.initialize(path);
    await TestStorage().save(_sample(id: 'disk', peak: 73));
    TestStorage.close();

    TestStorage.initialize(path);
    final all = await TestStorage().loadAll();
    expect(all, hasLength(1));
    expect(all.first.id, 'disk');
    expect(all.first.peakForceKg, closeTo(73, 0.01));
    expect(all.first.samples, hasLength(3));
  });

  test('getById returns null when missing', () async {
    expect(await TestStorage().getById('nope'), isNull);
  });
}
