import 'package:shared_preferences/shared_preferences.dart';

abstract final class NotificationsStore {
  static const _hasUnreadNotificationsKey = 'has_unread_notifications';

  static Future<bool> hasUnreadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasUnreadNotificationsKey) ?? true;
  }

  static Future<void> markNotificationsAsViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasUnreadNotificationsKey, false);
  }
}
