import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/exchange_rate_model.dart';

/// Manages on-device persistence for exchange rates via SQLite.
///
/// Schema: exchange_rates(id, currency TEXT UNIQUE, rate REAL, fetched_at INTEGER)
///
/// All rates are stored COP-indexed (1 COP expressed in the target currency).
/// The web platform is guarded — SQLite is unavailable on web.
abstract final class ExchangeRateDbService {
  static const _dbFileName = 'exchange_rates.db';
  static const _tableName = 'exchange_rates';
  static const _dbVersion = 1;

  static Database? _db;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_db != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, _dbFileName);
      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id         INTEGER PRIMARY KEY AUTOINCREMENT,
              currency   TEXT    NOT NULL UNIQUE,
              rate       REAL    NOT NULL,
              fetched_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_er_currency ON $_tableName(currency)',
          );
        },
      );
    } catch (error) {
      debugPrint('ExchangeRateDbService.init failed: $error');
      _db = null;
    }
  }

  static Future<Database?> _ensureDb() async {
    if (_db != null) return _db;
    await init();
    return _db;
  }

  /// Returns true when the table contains no rows — first-install scenario.
  static Future<bool> isEmpty() async {
    if (kIsWeb) return true;
    final db = _db ?? await _ensureDb();
    if (db == null) return true;
    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $_tableName',
      );
      return (result.first['cnt'] as int) == 0;
    } catch (_) {
      return true;
    }
  }

  /// Returns the [DateTime] of the most recent fetch across all stored rates,
  /// or null when the table is empty.
  static Future<DateTime?> latestFetchTime() async {
    if (kIsWeb) return null;
    final db = _db ?? await _ensureDb();
    if (db == null) return null;
    try {
      final rows = await db.query(
        _tableName,
        columns: ['fetched_at'],
        orderBy: 'fetched_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        rows.first['fetched_at'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns all stored rates as a map from ISO code → [ExchangeRate].
  static Future<Map<String, ExchangeRate>> getAllAsMap() async {
    if (kIsWeb) return {};
    final db = _db ?? await _ensureDb();
    if (db == null) return {};
    try {
      final rows = await db.query(_tableName);
      return {
        for (final row in rows)
          row['currency'] as String: ExchangeRate.fromRow(row),
      };
    } catch (_) {
      return {};
    }
  }

  /// Upserts [rates] (currency → COP-indexed rate) into the table.
  ///
  /// Uses INSERT OR REPLACE to overwrite stale rows without duplicates.
  static Future<void> upsertRates(Map<String, double> rates) async {
    if (kIsWeb) return;
    final db = _db ?? await _ensureDb();
    if (db == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final entry in rates.entries) {
      batch.rawInsert(
        'INSERT OR REPLACE INTO $_tableName(currency, rate, fetched_at) '
        'VALUES(?, ?, ?)',
        [entry.key, entry.value, now],
      );
    }
    try {
      await batch.commit(noResult: true);
    } catch (error) {
      debugPrint('ExchangeRateDbService.upsertRates failed: $error');
    }
  }
}
