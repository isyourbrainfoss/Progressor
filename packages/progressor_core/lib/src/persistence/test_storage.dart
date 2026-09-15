import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../db/schema.dart';
import '../models/force_sample.dart';
import '../models/pull_test.dart';
import '../models/test_type.dart';

/// SQLite-backed store for recorded tests.
///
/// Call [initialize] (file) or [initializeMemory] (tests) once at startup.
/// History / Live / Train all go through this single database — no second DB.
class TestStorage {
  TestStorage({Database? database}) : _dbOverride = database;

  final Database? _dbOverride;

  static Database? _shared;

  static bool get isInitialized => _shared != null;

  /// Open (or create) the on-disk database at [filePath].
  static void initialize(String filePath) {
    close();
    final db = sqlite3.open(filePath);
    applyProgressorSchema(db);
    _shared = db;
  }

  /// In-memory database for unit / widget tests.
  static void initializeMemory() {
    close();
    final db = sqlite3.openInMemory();
    applyProgressorSchema(db);
    _shared = db;
  }

  static void close() {
    try {
      _shared?.close();
    } catch (_) {}
    _shared = null;
  }

  Database get _db {
    final override = _dbOverride;
    if (override != null) return override;
    final shared = _shared;
    if (shared == null) {
      throw StateError(
        'TestStorage.initialize() or initializeMemory() must be called first',
      );
    }
    return shared;
  }

  Future<List<PullTest>> loadAll() async {
    final testRows = _db.select(
      'SELECT * FROM tests ORDER BY start_time DESC',
    );
    if (testRows.isEmpty) return const [];

    final samplesById = <String, List<ForceSample>>{};
    final sampleRows = _db.select(
      'SELECT test_id, time_ms, force_kg, force_n, raw_timestamp_us '
      'FROM samples ORDER BY test_id, time_ms',
    );
    for (final row in sampleRows) {
      final id = row['test_id'] as String;
      (samplesById[id] ??= []).add(_sampleFromRow(row));
    }

    return [
      for (final row in testRows)
        _testFromRow(row, samplesById[row['id'] as String] ?? const []),
    ];
  }

  Future<PullTest?> getById(String id) async {
    final testRows = _db.select('SELECT * FROM tests WHERE id = ?', [id]);
    if (testRows.isEmpty) return null;
    final sampleRows = _db.select(
      'SELECT test_id, time_ms, force_kg, force_n, raw_timestamp_us '
      'FROM samples WHERE test_id = ? ORDER BY time_ms',
      [id],
    );
    return _testFromRow(
      testRows.first,
      [for (final row in sampleRows) _sampleFromRow(row)],
    );
  }

  Future<void> save(PullTest test) async {
    final metricsJson =
        test.metrics == null ? null : jsonEncode(test.metrics);
    final updatedAt =
        (test.endTime ?? test.startTime).millisecondsSinceEpoch;

    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'INSERT INTO tests (id, start_time, end_time, type, grip_type, hand, '
        'bodyweight_kg, notes, device_name, metrics_json, updated_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?) '
        'ON CONFLICT(id) DO UPDATE SET '
        'start_time=excluded.start_time, end_time=excluded.end_time, '
        'type=excluded.type, grip_type=excluded.grip_type, hand=excluded.hand, '
        'bodyweight_kg=excluded.bodyweight_kg, notes=excluded.notes, '
        'device_name=excluded.device_name, metrics_json=excluded.metrics_json, '
        'updated_at=excluded.updated_at',
        [
          test.id,
          test.startTime.millisecondsSinceEpoch,
          test.endTime?.millisecondsSinceEpoch,
          test.type.name,
          test.gripType,
          test.hand,
          test.bodyweightKg,
          test.notes,
          test.deviceName,
          metricsJson,
          updatedAt,
        ],
      );
      _db.execute('DELETE FROM samples WHERE test_id = ?', [test.id]);
      final stmt = _db.prepare(
        'INSERT INTO samples (test_id, time_ms, force_kg, force_n, raw_timestamp_us) '
        'VALUES (?,?,?,?,?)',
      );
      try {
        for (final s in test.samples) {
          stmt.execute([
            test.id,
            s.timeMs,
            s.forceKg,
            s.forceN,
            s.rawTimestampUs,
          ]);
        }
      } finally {
        stmt.close();
      }
      _db.execute('COMMIT');
    } catch (e) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    _db.execute('DELETE FROM samples WHERE test_id = ?', [id]);
    _db.execute('DELETE FROM tests WHERE id = ?', [id]);
  }

  Future<void> clear() async {
    _db.execute('DELETE FROM samples');
    _db.execute('DELETE FROM tests');
  }

  Future<String?> getKv(String key) async {
    final rows = _db.select('SELECT value FROM kv WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String value) async {
    _db.execute(
      'INSERT INTO kv(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      [key, value],
    );
  }

  Future<void> removeKv(String key) async {
    _db.execute('DELETE FROM kv WHERE key = ?', [key]);
  }

  PullTest _testFromRow(Row row, List<ForceSample> samples) {
    Map<String, dynamic>? metrics;
    final raw = row['metrics_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          metrics = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    final typeName = row['type'] as String? ?? 'custom';
    return PullTest(
      id: row['id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: row['end_time'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['end_time'] as int),
      type: TestType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => TestType.custom,
      ),
      samples: samples,
      gripType: row['grip_type'] as String?,
      hand: row['hand'] as String?,
      bodyweightKg: (row['bodyweight_kg'] as num?)?.toDouble(),
      notes: row['notes'] as String?,
      deviceName: row['device_name'] as String?,
      metrics: metrics,
    );
  }

  ForceSample _sampleFromRow(Row row) {
    return ForceSample(
      timeMs: row['time_ms'] as int,
      forceKg: (row['force_kg'] as num).toDouble(),
      forceN: (row['force_n'] as num?)?.toDouble(),
      rawTimestampUs: row['raw_timestamp_us'] as int?,
    );
  }
}
