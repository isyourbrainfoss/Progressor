import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:progressor_core/progressor_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Open the on-disk SQLite file (no-op if already initialized).
Future<void> initProgressorStorage() async {
  if (TestStorage.isInitialized) return;
  try {
    final dir = await getApplicationDocumentsDirectory();
    TestStorage.initialize(p.join(dir.path, 'progressor.sqlite'));
  } on MissingPluginException {
    TestStorage.initializeMemory();
  } on FileSystemException {
    TestStorage.initializeMemory();
  } catch (_) {
    TestStorage.initializeMemory();
  }
}

class SessionSaveResult {
  const SessionSaveResult({
    required this.test,
    required this.isNewPr,
    required this.streak,
    required this.newlyUnlocked,
    required this.strengthIndex,
  });

  final PullTest test;
  final bool isNewPr;
  final int streak;
  final List<Achievement> newlyUnlocked;
  final double strengthIndex;
}

/// In-memory catalog of saved tests + gamification. Backed by [TestStorage].
class SessionStore extends ChangeNotifier {
  SessionStore({TestStorage? storage}) : _storage = storage ?? TestStorage();

  final TestStorage _storage;

  List<PullTest> _tests = [];
  int _streak = 0;
  DateTime? _streakDay;
  int _xp = 0;
  Set<String> _unlocked = {};
  bool _loaded = false;

  List<PullTest> get tests => _tests;
  int get streak => _streak;
  int get xp => _xp;
  int get level => levelForXp(_xp);
  Set<String> get unlockedIds => _unlocked;
  bool get loaded => _loaded;
  double get index => strengthIndex(_tests, streak: _streak);

  List<Achievement> get unlockedAchievements =>
      achievementsForIds(_unlocked);

  Future<void> load() async {
    await _migrateLegacyPrefs();
    _tests = await _storage.loadAll();
    _streak = int.tryParse(await _storage.getKv('streak') ?? '') ?? 0;
    _xp = int.tryParse(await _storage.getKv('xp') ?? '') ?? 0;
    final dayRaw = await _storage.getKv('streak_day');
    _streakDay = dayRaw == null ? null : DateTime.tryParse(dayRaw);
    final unlockedRaw = await _storage.getKv('unlocked');
    _unlocked = {};
    if (unlockedRaw != null && unlockedRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(unlockedRaw);
        if (decoded is List) {
          _unlocked = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }
    // Recompute badges from history so older installs pick up new ones.
    _unlocked = {
      ..._unlocked,
      ...unlockedAchievementIds(tests: _tests, streak: _streak),
    };
    _loaded = true;
    notifyListeners();
  }

  Future<SessionSaveResult> record(PullTest test) async {
    if (!_loaded) await load();
    final isPr = isNewPersonalRecord(_tests, test);
    final now = DateTime.now();
    // Demo (simulated) sessions are saved for browsing but never count
    // towards streaks / XP / badges.
    final (nextStreak, day) = test.isDemo && _streakDay != null
        ? (_streak, _streakDay!)
        : test.isDemo
            ? (_streak, DateTime(now.year, now.month, now.day))
            : nextDailyStreak(
                previousStreak: _streak,
                lastStreakDay: _streakDay,
                now: now,
              );
    final metrics = <String, dynamic>{
      ...?test.metrics,
      'isPR': isPr,
      'streakAtSave': nextStreak,
    };
    final saved = test.copyWith(metrics: metrics);
    await _storage.save(saved);

    final all = [saved, ..._tests.where((t) => t.id != saved.id)];
    final before = Set<String>.from(_unlocked);
    final after = unlockedAchievementIds(tests: all, streak: nextStreak);
    final newly = achievementsForIds(after.difference(before));
    final xp = _xp + xpForTest(saved);

    await _storage.setKv('streak', '$nextStreak');
    if (!test.isDemo) {
      await _storage.setKv('streak_day', day.toIso8601String());
    }
    await _storage.setKv('xp', '$xp');
    await _storage.setKv('unlocked', jsonEncode(after.toList()));

    _tests = all..sort((a, b) => b.startTime.compareTo(a.startTime));
    _streak = nextStreak;
    if (!test.isDemo) _streakDay = day;
    _xp = xp;
    _unlocked = after;
    _loaded = true;
    notifyListeners();

    return SessionSaveResult(
      test: saved,
      isNewPr: isPr,
      streak: nextStreak,
      newlyUnlocked: newly,
      strengthIndex: strengthIndex(_tests, streak: _streak),
    );
  }

  Future<void> clearTests() async {
    await _storage.clear();
    _tests = [];
    notifyListeners();
  }

  Future<void> _migrateLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('progressor_tests_v1');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              await _storage.save(
                PullTest.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
        await prefs.remove('progressor_tests_v1');
      }
      final streak = prefs.getInt('gamif_streak');
      if (streak != null && streak > 0) {
        final existing = await _storage.getKv('streak');
        if (existing == null) {
          await _storage.setKv('streak', '$streak');
        }
        await prefs.remove('gamif_streak');
      }
    } catch (_) {
      // Prefs unavailable (some tests) — skip migration.
    }
  }
}

class SessionStoreScope extends InheritedNotifier<SessionStore> {
  const SessionStoreScope({
    super.key,
    required SessionStore store,
    required super.child,
  }) : super(notifier: store);

  static SessionStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionStoreScope>();
    assert(scope != null, 'SessionStoreScope not found');
    return scope!.notifier!;
  }

  static SessionStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SessionStoreScope>()?.notifier;
  }
}
