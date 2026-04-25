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
  static const _dbVersion = 1;

  static Database? _db;

  static Future<void> init() async {
    if (kIsWeb) {
      return;
    }
    if (_db != null) {
      return;
    }

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
              success INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_sync_logs_success ON $_tableName(success)',
          );
          await db.execute(
            'CREATE INDEX idx_sync_logs_timestamp ON $_tableName(timestamp DESC)',
          );
        },
      );
    } catch (error) {
      debugPrint('SyncLogService.init failed: $error');
      _db = null;
    }
  }

  static Future<void> logSync({
    required String entityType,
    String? entityId,
    required String action,
    required bool success,
  }) async {
    if (kIsWeb) {
      return;
    }
    final db = _db;
    if (db == null) {
      return;
    }

    try {
      await db.insert(_tableName, {
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'success': success ? 1 : 0,
      });
    } catch (error) {
      debugPrint('SyncLogService.logSync failed: $error');
    }
  }

  static Future<List<Map<String, Object?>>> recentLogs({int limit = 100}) async {
    if (kIsWeb) {
      return const [];
    }
    final db = _db;
    if (db == null) {
      return const [];
    }

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
    if (kIsWeb) {
      return const [];
    }
    final db = _db;
    if (db == null) {
      return const [];
    }

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
