import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

PullTest _t(String id, double peak, {bool demo = false}) => PullTest(
  id: id,
  startTime: DateTime(2026, 1, 1),
  type: TestType.peakForce,
  samples: [ForceSample(timeMs: 0, forceKg: peak)],
  metrics: demo ? const {'source': 'demo'} : null,
);

void main() {
  test('demo sessions never count as PRs or unlock badges', () {
    final real = _t('r', 40);
    final demo = _t('d', 120, demo: true);
    expect(demo.isDemo, isTrue);
    expect(isNewPersonalRecord([real], demo), isFalse);
    expect(isNewPersonalRecord([demo], _t('r2', 41)), isTrue);
    expect(chronologicalPrIds([real, demo]), {'r'});
    expect(unlockedAchievementIds(tests: [demo], streak: 0), isEmpty);
    expect(xpForTest(demo), 0);
    expect(strengthIndex([demo]), 0);
  });
}
