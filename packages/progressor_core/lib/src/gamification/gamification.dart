import 'dart:math' show max, min;

import '../metrics.dart' show PullTestMetrics;
import '../models/pull_test.dart';
import '../models/test_type.dart';

/// Badge definition (UI maps [emoji] + copy; no Flutter types here).
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
  });

  final String id;
  final String title;
  final String description;
  final String emoji;
}

/// Catalog of unlockable badges.
const kAchievements = <Achievement>[
  Achievement(
    id: 'first_pull',
    title: 'First Pull',
    description: 'Log your first session',
    emoji: '🧗',
  ),
  Achievement(
    id: 'fifty_kg',
    title: 'Half Century',
    description: 'Hit 50 kg peak',
    emoji: '💪',
  ),
  Achievement(
    id: 'centurion',
    title: 'Centurion',
    description: 'Hit 100 kg peak',
    emoji: '🏆',
  ),
  Achievement(
    id: 'rfd_beast',
    title: 'RFD Beast',
    description: 'Rate of force ≥ 400 kg/s',
    emoji: '⚡',
  ),
  Achievement(
    id: 'ten_sessions',
    title: 'Regular',
    description: 'Log 10 tests',
    emoji: '🔟',
  ),
  Achievement(
    id: 'week_streak',
    title: 'Consistent Climber',
    description: 'Train 7 days in a row',
    emoji: '🔥',
  ),
  Achievement(
    id: 'iron_fingers',
    title: 'Iron Fingers',
    description: 'Peak 80 kg or more',
    emoji: '🦾',
  ),
  Achievement(
    id: 'enduro',
    title: 'Enduro',
    description: 'Finish a repeaters or endurance test',
    emoji: '⏱️',
  ),
  Achievement(
    id: 'warmup_pro',
    title: 'Warm-up Pro',
    description: 'Complete a warm-up tour',
    emoji: '🧘',
  ),
];

final Map<String, Achievement> kAchievementsById = {
  for (final a in kAchievements) a.id: a,
};

/// Daily streak: same calendar day keeps the count; yesterday increments;
/// a gap resets to 1.
(int streak, DateTime day) nextDailyStreak({
  required int previousStreak,
  required DateTime? lastStreakDay,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  if (lastStreakDay != null) {
    final last = DateTime(
      lastStreakDay.year,
      lastStreakDay.month,
      lastStreakDay.day,
    );
    if (last == today) {
      return (previousStreak <= 0 ? 1 : previousStreak, today);
    }
    final yesterday = today.subtract(const Duration(days: 1));
    if (last == yesterday) {
      return (previousStreak + 1, today);
    }
  }
  return (1, today);
}

/// True when [incoming] sets a new all-time peak among non-warmup tests.
bool isNewPersonalRecord(List<PullTest> previous, PullTest incoming) {
  if (incoming.type.isWarmup || incoming.isDemo) return false;
  final peak = incoming.peakForceKg;
  if (peak == null) return false;
  var prevMax = 0.0;
  for (final t in previous) {
    if (t.id == incoming.id || t.type.isWarmup || t.isDemo) continue;
    final p = t.peakForceKg ?? 0;
    if (p > prevMax) prevMax = p;
  }
  return peak > prevMax + 0.01;
}

/// Chronological PR ids (oldest → newest): each test that raised the max peak.
Set<String> chronologicalPrIds(List<PullTest> tests) {
  final chronological = List<PullTest>.from(tests)
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final ids = <String>{};
  var maxSeen = 0.0;
  for (final t in chronological) {
    if (t.type.isWarmup || t.isDemo) continue;
    final p = t.peakForceKg ?? 0;
    if (p > maxSeen + 0.001) {
      maxSeen = p;
      ids.add(t.id);
    }
  }
  return ids;
}

double strengthIndex(List<PullTest> allTests, {int streak = 0}) {
  final tests = allTests.where((t) => !t.isDemo).toList();
  if (tests.isEmpty) return 0;
  var best = 0.0;
  var counted = 0;
  for (final t in tests) {
    final p = t.peakForceKg ?? 0;
    if (p > best) best = p;
    counted++;
  }
  if (best <= 0) return 0;
  final peakScore = (best / 100.0).clamp(0.0, 1.0) * 70.0;
  final consistency = (min(streak, 30) / 30.0) * 15.0;
  final volume = (min(counted, 40) / 40.0) * 15.0;
  return (peakScore + consistency + volume).clamp(0.0, 100.0);
}

int xpForTest(PullTest test) {
  if (test.isDemo) return 0;
  final peak = test.peakForceKg ?? 0;
  final base = test.type.isWarmup ? 8 : 15;
  return base + (peak / 2).round();
}

int levelForXp(int xp) => max(1, (xp ~/ 100) + 1);

/// Achievement ids unlocked by [tests] + [streak].
Set<String> unlockedAchievementIds({
  required List<PullTest> tests,
  required int streak,
}) {
  // Demo (simulated) sessions never unlock badges.
  tests = tests.where((t) => !t.isDemo).toList();
  final ids = <String>{};
  if (tests.isEmpty) return ids;

  ids.add('first_pull');
  if (tests.length >= 10) ids.add('ten_sessions');
  if (streak >= 7) ids.add('week_streak');

  var best = 0.0;
  var bestRfd = 0.0;
  for (final t in tests) {
    final p = t.peakForceKg ?? 0;
    if (p > best) best = p;
    final rfd = (t.metrics?['rfdMax'] as num?)?.toDouble() ?? 0;
    if (rfd > bestRfd) bestRfd = rfd;
    if (t.type == TestType.repeaters || t.type == TestType.endurance) {
      ids.add('enduro');
    }
    if (t.type == TestType.warmupTour) ids.add('warmup_pro');
  }
  if (best >= 50) ids.add('fifty_kg');
  if (best >= 80) ids.add('iron_fingers');
  if (best >= 100) ids.add('centurion');
  if (bestRfd >= 400) ids.add('rfd_beast');
  return ids;
}

List<Achievement> achievementsForIds(Iterable<String> ids) {
  return [
    for (final id in ids)
      if (kAchievementsById[id] != null) kAchievementsById[id]!,
  ];
}
