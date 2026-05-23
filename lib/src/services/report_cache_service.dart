import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/financial_report.dart';

/// Persists generated [FinancialReport]s in SQLite with a 24-hour TTL.
///
/// Key format: `{userId}_{startDate}_{endDate}` (dates as YYYY-MM-DD).
/// Usage counter stored in SharedPreferences under `report_usage_{userId}`.
abstract final class ReportCacheService {
  static const _dbFileName  = 'financial_reports.db';
  static const _tableName   = 'reports';
  static const _dbVersion   = 1;
  static const _ttl         = Duration(hours: 24);
  static const _usagePrefPrefix = 'report_usage_';

  static Database? _db;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_db != null) return;
    try {
      final path = p.join(await getDatabasesPath(), _dbFileName);
      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              cache_key    TEXT PRIMARY KEY,
              report_json  TEXT NOT NULL,
              generated_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_reports_gen ON $_tableName(generated_at DESC)',
          );
        },
      );
    } catch (error) {
      debugPrint('ReportCacheService.init failed: $error');
      _db = null;
    }
  }

  static Future<Database?> _ensureDb() async {
    if (_db != null) return _db;
    await init();
    return _db;
  }

  // ---------------------------------------------------------------------------
  // Usage counter (BQ: how many reports has this user generated?)
  // ---------------------------------------------------------------------------

  static Future<int> getUsageCount(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_usagePrefPrefix$userId') ?? 0;
  }

  static Future<void> incrementUsageCount(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('$_usagePrefPrefix$userId') ?? 0;
    await prefs.setInt('$_usagePrefPrefix$userId', current + 1);
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Returns a cached report for the exact [startDate]–[endDate] range if
  /// it exists and is < 24 h old; null otherwise.
  static Future<FinancialReport?> get(
    int userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (kIsWeb) return null;
    final db = _db ?? await _ensureDb();
    if (db == null) return null;

    final key = _key(userId, startDate, endDate);
    try {
      final rows = await db.query(
        _tableName,
        where: 'cache_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final generatedAt = DateTime.fromMillisecondsSinceEpoch(
        rows.first['generated_at'] as int,
      );
      if (_isExpired(generatedAt)) {
        await db.delete(_tableName, where: 'cache_key = ?', whereArgs: [key]);
        return null;
      }
      return FinancialReport.fromJsonString(rows.first['report_json'] as String);
    } catch (error) {
      debugPrint('ReportCacheService.get failed: $error');
      return null;
    }
  }

  /// Stores a report, overwriting any previous entry for the same key.
  static Future<void> store(int userId, FinancialReport report) async {
    if (kIsWeb) return;
    final db = _db ?? await _ensureDb();
    if (db == null) return;
    try {
      await db.rawInsert(
        'INSERT OR REPLACE INTO $_tableName(cache_key, report_json, generated_at)'
        ' VALUES(?,?,?)',
        [
          _key(userId, report.startDate, report.endDate),
          report.toJsonString(),
          report.generatedAt.millisecondsSinceEpoch,
        ],
      );
    } catch (error) {
      debugPrint('ReportCacheService.store failed: $error');
    }
  }

  /// Returns the most recent reports for [userId], newest first, up to [limit].
  /// Only returns reports generated within the last 24 h (i.e. valid cache).
  static Future<List<FinancialReport>> listRecent(
    int userId, {
    int limit = 5,
  }) async {
    if (kIsWeb) return const [];
    final db = _db ?? await _ensureDb();
    if (db == null) return const [];

    final cutoff = DateTime.now().subtract(_ttl).millisecondsSinceEpoch;
    final prefix = '${userId}_';

    try {
      final rows = await db.query(
        _tableName,
        where: 'cache_key LIKE ? AND generated_at > ?',
        whereArgs: ['$prefix%', cutoff],
        orderBy: 'generated_at DESC',
        limit: limit,
      );
      return rows
          .map((r) => FinancialReport.fromJsonString(r['report_json'] as String))
          .toList();
    } catch (error) {
      debugPrint('ReportCacheService.listRecent failed: $error');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _key(int userId, DateTime start, DateTime end) {
    final s = _fmt(start);
    final e = _fmt(end);
    return '${userId}_${s}_$e';
  }

  static String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static bool _isExpired(DateTime generatedAt) =>
      DateTime.now().difference(generatedAt) > _ttl;
}
