import 'package:shared_preferences/shared_preferences.dart';

/// Persists the set of Firestore document IDs that were intentionally deleted
/// by this user on this device.
///
/// Used by [CloudSyncService._mergeRemoteExpenses] to skip re-creating
/// documents that were deleted locally but may still exist on Firestore
/// (e.g. due to a transient network failure during the delete).
///
/// Key format: `tombstone_expenses_{userId}` → JSON-encoded list of doc IDs.
/// The set is intentionally kept small: entries older than [_maxAgedays] days
/// are pruned on write so the prefs key never grows unbounded.
abstract final class DeletedRecordsTombstone {
  static const int _maxAgeDays = 90;
  static const String _prefKeyPrefix = 'tombstone_expenses_';

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Records [serverId] as intentionally deleted for [userId].
  /// Prunes entries older than [_maxAgeDays] days.
  static Future<void> markDeleted({
    required int userId,
    required String serverId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(userId);
    final raw = prefs.getStringList(key) ?? [];
    final now = DateTime.now().millisecondsSinceEpoch;

    // Each entry: "serverId|epochMs"
    final pruned = raw.where((entry) {
      final parts = entry.split('|');
      if (parts.length < 2) return false;
      final ts = int.tryParse(parts[1]);
      if (ts == null) return false;
      return DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      ).inDays < _maxAgeDays;
    }).toList();

    // Add new entry (dedup by serverId).
    pruned.removeWhere((e) => e.startsWith('$serverId|'));
    pruned.add('$serverId|$now');

    await prefs.setStringList(key, pruned);
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns true if [serverId] was marked deleted for [userId].
  static Future<bool> isDeleted({
    required int userId,
    required String serverId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? [];
    return raw.any((e) => e.startsWith('$serverId|'));
  }

  /// Returns the full set of deleted server IDs for [userId].
  /// Cheaper to call once and reuse during a merge pass than calling
  /// [isDeleted] per-document.
  static Future<Set<String>> deletedIds(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? [];
    return raw.map((e) => e.split('|').first).toSet();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _key(int userId) => '$_prefKeyPrefix$userId';
}
