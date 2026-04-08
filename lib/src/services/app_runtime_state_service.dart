import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppRuntimeStateService {
  static const String _isAppInForegroundKey = 'app_runtime_is_foreground';
  static const String _foregroundUpdatedAtKey = 'app_runtime_foreground_at';

  static Future<void> markForeground(bool isForeground) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isAppInForegroundKey, isForeground);
    await prefs.setInt(
      _foregroundUpdatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> isForeground() async {
    final prefs = await SharedPreferences.getInstance();
    final isForeground = prefs.getBool(_isAppInForegroundKey) ?? false;
    if (!isForeground) {
      return false;
    }

    final updatedAtMillis = prefs.getInt(_foregroundUpdatedAtKey);
    if (updatedAtMillis == null) {
      return false;
    }

    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMillis);
    final age = DateTime.now().difference(updatedAt);
    return age <= const Duration(seconds: 90);
  }
}
