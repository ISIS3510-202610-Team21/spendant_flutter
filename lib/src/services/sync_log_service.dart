import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

abstract final class SyncLogService {
  static const actionUpload = 'upload';
  static const actionMerge = 'merge';
  static const actionDelete = 'delete';

  static const entityExpense = 'expense';
  static const entityIncome = 'income';
  static const entityGoal = 'goal';
  static const entityLabel = 'label';
  static const entityUser = 'user';

  static const _dbFileName = 'sync_logs.db';
  static const _tableName = 'sync_logs';
  // v2 adds the nullable error_message column for failed operations.
  static const _dbVersion = 2;

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
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entity_type TEXT NOT NULL,
              entity_id TEXT,
              action TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              success INTEGER NOT NULL,
              error_message TEXT
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_sync_logs_success ON $_tableName(success)',
          );
          await db.execute(
            'CREATE INDEX idx_sync_logs_timestamp ON $_tableName(timestamp DESC)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 → v2: add optional error message column for failed sync ops.
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN error_message TEXT',
            );
          }
        },
      );
    } catch (error) {
      debugPrint('SyncLogService.init failed: $error');
      _db = null;
    }
  }

  /// Attempts a lazy re-initialization when [_db] is null.
  /// This recovers from transient initialization failures (e.g. disk busy at
  /// app start) without silently dropping every subsequent log entry.
  static Future<Database?> _ensureDb() async {
    if (_db != null) return _db;
    await init();
    if (_db == null) {
      debugPrint('SyncLogService: database still unavailable after re-init attempt.');
    }
    return _db;
  }

  static Future<void> logSync({
    required String entityType,
    String? entityId,
    required String action,
    required bool success,
    // Populated for failed operations to aid debugging via failedLogs().
    String? errorMessage,
  }) async {
    if (kIsWeb) return;

    final db = _db ?? await _ensureDb();
    if (db == null) {
      debugPrint(
        'SyncLogService.logSync: database unavailable — '
        'skipping log for $action $entityType ${entityId ?? '?'}',
      );
      return;
    }

    try {
      await db.insert(_tableName, {
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'success': success ? 1 : 0,
        if (errorMessage != null && errorMessage.isNotEmpty)
          'error_message': errorMessage,
      });
    } catch (error) {
      debugPrint('SyncLogService.logSync failed: $error');
    }
  }

  static Future<List<Map<String, Object?>>> recentLogs({int limit = 100}) async {
    if (kIsWeb) return const [];

    final db = _db ?? await _ensureDb();
    if (db == null) return const [];

    try {
      return await db.query(
        _tableName,
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (error) {
      debugPrint('SyncLogService.recentLogs failed: $error');
      return const [];
    }
  }

  static Future<List<Map<String, Object?>>> failedLogs({int limit = 100}) async {
    if (kIsWeb) return const [];

    final db = _db ?? await _ensureDb();
    if (db == null) return const [];

    try {
      return await db.query(
        _tableName,
        where: 'success = ?',
        whereArgs: [0],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (error) {
      debugPrint('SyncLogService.failedLogs failed: $error');
      return const [];
    }
  }
}
