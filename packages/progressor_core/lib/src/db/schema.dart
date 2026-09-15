import 'package:sqlite3/sqlite3.dart';

/// Current SQLite schema version (stored in [kv] as `schema_version`).
const int kProgressorSchemaVersion = 1;

/// Apply the Progressor session schema to [db].
///
/// Idempotent: safe to run on every open. This is the A4 store — one SQLite
/// file, no second database.
void applyProgressorSchema(Database db) {
  db.execute('PRAGMA foreign_keys = ON');
  try {
    db.execute('PRAGMA journal_mode = WAL');
  } catch (_) {
    // In-memory and some hosts reject WAL; ignore.
  }

  db.execute('''
    CREATE TABLE IF NOT EXISTS tests (
      id TEXT PRIMARY KEY,
      start_time INTEGER NOT NULL,
      end_time INTEGER,
      type TEXT NOT NULL,
      grip_type TEXT,
      hand TEXT,
      bodyweight_kg REAL,
      notes TEXT,
      device_name TEXT,
      metrics_json TEXT,
      updated_at INTEGER NOT NULL
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      test_id TEXT NOT NULL,
      time_ms INTEGER NOT NULL,
      force_kg REAL NOT NULL,
      force_n REAL,
      raw_timestamp_us INTEGER,
      FOREIGN KEY(test_id) REFERENCES tests(id) ON DELETE CASCADE
    )
  ''');

  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_samples_test ON samples(test_id, time_ms)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tests_start ON tests(start_time DESC)',
  );

  db.execute('''
    CREATE TABLE IF NOT EXISTS kv (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  db.execute(
    "INSERT OR IGNORE INTO kv(key, value) VALUES('schema_version', '$kProgressorSchemaVersion')",
  );
}
