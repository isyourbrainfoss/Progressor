import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pull_test.dart';

/// Simple JSON storage via shared prefs. Replace with Drift for production.
class TestStorage {
  static const _key = 'progressor_tests_v1';

  Future<List<PullTest>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(PullTest.fromJson).toList().reversed.toList(); // newest first-ish
  }

  Future<void> save(PullTest test) async {
    final all = await loadAll();
    final filtered = all.where((t) => t.id != test.id).toList();
    filtered.insert(0, test);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(filtered.map((t) => t.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
