import 'package:flutter_test/flutter_test.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:progressor_sensors/progressor_sensors.dart';

void main() {
  test('demo adapter without a fixture streams synthetic force', () async {
    final adapter = MockReplayAdapter();
    final got = <double>[];
    final sub = adapter.samples.listen((s) => got.add(s.forceKg));
    await adapter.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await adapter.disconnect();
    await sub.cancel();
    expect(got, isNotEmpty, reason: 'Demo mode produced no samples');
  });

  test('synthetic pull ramps to a realistic peak and returns to rest', () {
    final s = MockReplayAdapter.generateSyntheticPull();
    final peak = s.map((e) => e.forceKg).reduce((a, b) => a > b ? a : b);
    expect(peak, inInclusiveRange(38, 46));
    expect(s.first.forceKg, lessThan(1));
    expect(s.last.forceKg, lessThan(1));
    for (var i = 1; i < s.length; i++) {
      expect(s[i].timeMs, greaterThan(s[i - 1].timeMs));
    }
  });

  test('replay loops with monotonic timestamps until disconnect', () async {
    final adapter = MockReplayAdapter(samples: const [
      ForceSample(timeMs: 0, forceKg: 1),
      ForceSample(timeMs: 5, forceKg: 2),
    ]);
    final got = <ForceSample>[];
    final sub = adapter.samples.listen(got.add);
    await adapter.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await adapter.disconnect();
    final n = got.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(n, greaterThan(4), reason: 'should loop past the 2 samples');
    expect(got.length, n, reason: 'no samples after disconnect');
    for (var i = 1; i < got.length; i++) {
      expect(got[i].timeMs, greaterThan(got[i - 1].timeMs));
    }
  });
}
