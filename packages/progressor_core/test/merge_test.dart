import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

void main() {
  test('merge sorts and drops duplicate time+force', () {
    const a = [
      ForceSample(timeMs: 20, forceKg: 5),
      ForceSample(timeMs: 0, forceKg: 1),
    ];
    const b = [
      ForceSample(timeMs: 20, forceKg: 5),
      ForceSample(timeMs: 40, forceKg: 9),
    ];
    final merged = mergeSampleStreams([a, b]);
    expect(merged.map((s) => s.timeMs).toList(), [0, 20, 40]);
    expect(merged.last.forceKg, 9);
  });

  test('preferDeviceTimestamps rebases from earliest µs', () {
    const a = [
      ForceSample(timeMs: 999, forceKg: 1, rawTimestampUs: 2_000_000),
      ForceSample(timeMs: 999, forceKg: 2, rawTimestampUs: 3_000_000),
    ];
    final merged = mergeSampleStreams([a], preferDeviceTimestamps: true);
    expect(merged.map((s) => s.timeMs).toList(), [0, 1000]);
  });

  test('empty streams yield empty list', () {
    expect(mergeSampleStreams(const []), isEmpty);
  });
}
