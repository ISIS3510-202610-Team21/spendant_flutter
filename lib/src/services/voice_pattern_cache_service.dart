import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/voice_parse_result.dart';

/// Persistent SQLite cache for recognized voice phrases.
///
/// SCHEMA: voice_pattern_cache
///   id           INTEGER PK
///   phrase_hash  TEXT UNIQUE  — SHA-256 of the normalized phrase
///   raw_text     TEXT
///   parsed_json  TEXT         — JSON-encoded [VoiceParseResult]
///   created_at   INTEGER      — Unix ms
///
/// PURPOSE (Hash-Phrase caching):
///   When Isolate 3 successfully parses a phrase, the normalized hash is
///   stored here.  On subsequent identical phrases, Isolate 3 is bypassed
///   entirely — the cached result is returned in microseconds.
abstract final class VoicePatternCacheService {
  static const _dbFileName = 'voice_pattern_cache.db';
  static const _tableName = 'voice_pattern_cache';
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
              id           INTEGER PRIMARY KEY AUTOINCREMENT,
              phrase_hash  TEXT    NOT NULL UNIQUE,
              raw_text     TEXT    NOT NULL,
              parsed_json  TEXT    NOT NULL,
              created_at   INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_vpc_hash ON $_tableName(phrase_hash)',
          );
        },
      );
    } catch (error) {
      debugPrint('VoicePatternCacheService.init failed: $error');
      _db = null;
    }
  }

  static Future<Database?> _ensureDb() async {
    if (_db != null) return _db;
    await init();
    return _db;
  }

  // ---------------------------------------------------------------------------
  // Hash helpers
  // ---------------------------------------------------------------------------

  /// Normalizes [text] to a canonical form before hashing.
  ///
  /// Lowercase + collapse whitespace + strip punctuation → consistent hash
  /// across minor dictation variations ("I paid" vs "i paid").
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String hashPhrase(String normalizedText) {
    final bytes = utf8.encode(normalizedText);
    return sha256.convert(bytes).toString();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Looks up a cached parse result for [rawText].
  /// Returns null on a cache miss or if the DB is unavailable.
  static Future<VoiceParseResult?> lookup(String rawText) async {
    if (kIsWeb) return null;
    final db = _db ?? await _ensureDb();
    if (db == null) return null;

    final hash = hashPhrase(normalize(rawText));
    try {
      final rows = await db.query(
        _tableName,
        where: 'phrase_hash = ?',
        whereArgs: [hash],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return VoiceParseResult.fromJsonString(
        rows.first['parsed_json'] as String,
      );
    } catch (error) {
      debugPrint('VoicePatternCacheService.lookup failed: $error');
      return null;
    }
  }

  /// Stores [result] in the cache keyed by the normalized hash of [rawText].
  /// Uses INSERT OR REPLACE to overwrite stale entries.
  static Future<void> store(String rawText, VoiceParseResult result) async {
    if (kIsWeb) return;
    final db = _db ?? await _ensureDb();
    if (db == null) return;

    final hash = hashPhrase(normalize(rawText));
    try {
      await db.rawInsert(
        'INSERT OR REPLACE INTO $_tableName'
        '(phrase_hash, raw_text, parsed_json, created_at) VALUES(?,?,?,?)',
        [
          hash,
          rawText,
          result.toJsonString(),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } catch (error) {
      debugPrint('VoicePatternCacheService.store failed: $error');
    }
  }

  /// Returns all cached entries (most recent first), useful for debugging.
  static Future<List<Map<String, Object?>>> recentEntries({
    int limit = 20,
  }) async {
    if (kIsWeb) return const [];
    final db = _db ?? await _ensureDb();
    if (db == null) return const [];
    try {
      return await db.query(
        _tableName,
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (_) {
      return const [];
    }
  }
}
