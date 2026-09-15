import 'package:progressor_core/progressor_core.dart';
import 'package:test/test.dart';

PullTest _t({
  required String id,
  required double peak,
  TestType type = TestType.peakForce,
  DateTime? start,
  double? rfd,
}) {
  return PullTest(
    id: id,
    startTime: start ?? DateTime.utc(2026, 1, 1),
    type: type,
    samples: [
      ForceSample(timeMs: 0, forceKg: 0),
      ForceSample(timeMs: 100, forceKg: peak),
    ],
    metrics: {
      'peakKg': peak,
      'rfdMax': ?rfd,
    },
  );
}

void main() {
  test('daily streak increments across consecutive days and resets on a gap', () {
    final day1 = DateTime(2026, 4, 1, 18);
    final (s1, d1) = nextDailyStreak(
      previousStreak: 0,
      lastStreakDay: null,
      now: day1,
    );
    expect(s1, 1);

    final (s2, _) = nextDailyStreak(
      previousStreak: s1,
      lastStreakDay: d1,
      now: DateTime(2026, 4, 2, 9),
    );
    expect(s2, 2);

    final (sameDay, _) = nextDailyStreak(
      previousStreak: s2,
      lastStreakDay: DateTime(2026, 4, 2, 8),
      now: DateTime(2026, 4, 2, 21),
    );
    expect(sameDay, 2);

    final (reset, _) = nextDailyStreak(
      previousStreak: s2,
      lastStreakDay: DateTime(2026, 4, 2),
      now: DateTime(2026, 4, 5),
    );
    expect(reset, 1);
  });

  test('PR detection ignores warm-ups and requires a new max', () {
    final prev = [
      _t(id: 'a', peak: 40),
      _t(id: 'w', peak: 90, type: TestType.warmupTour),
    ];
    expect(isNewPersonalRecord(prev, _t(id: 'b', peak: 41)), isTrue);
    expect(isNewPersonalRecord(prev, _t(id: 'c', peak: 39)), isFalse);
    expect(
      isNewPersonalRecord(prev, _t(id: 'd', peak: 100, type: TestType.followCurve)),
      isFalse,
    );
  });

  test('chronological PR ids mark each new max', () {
    final tests = [
      _t(id: 'late', peak: 50, start: DateTime.utc(2026, 1, 3)),
      _t(id: 'first', peak: 30, start: DateTime.utc(2026, 1, 1)),
      _t(id: 'mid', peak: 45, start: DateTime.utc(2026, 1, 2)),
    ];
    expect(chronologicalPrIds(tests), {'first', 'mid', 'late'});
  });

  test('achievements unlock from real thresholds', () {
    final tests = [
      for (var i = 0; i < 10; i++)
        _t(
          id: 't$i',
          peak: i == 9 ? 102 : 40,
          type: i == 0 ? TestType.repeaters : TestType.peakForce,
          rfd: i == 9 ? 420 : 10,
          start: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        ),
      _t(id: 'tour', peak: 20, type: TestType.warmupTour),
    ];
    final ids = unlockedAchievementIds(tests: tests, streak: 7);
    expect(ids, containsAll(['first_pull', 'ten_sessions', 'week_streak']));
    expect(ids, containsAll(['fifty_kg', 'iron_fingers', 'centurion']));
    expect(ids, containsAll(['rfd_beast', 'enduro', 'warmup_pro']));
  });

  test('strength index is 0 without tests and rises with peak + streak', () {
    expect(strengthIndex(const []), 0);
    final weak = strengthIndex([_t(id: 'a', peak: 20)], streak: 0);
    final strong = strengthIndex([_t(id: 'b', peak: 100)], streak: 30);
    expect(strong, greaterThan(weak));
    expect(strong, greaterThan(80));
  });
}
