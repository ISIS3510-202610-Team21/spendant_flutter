import 'package:shared_preferences/shared_preferences.dart';

abstract final class NotificationsStore {
  static const _viewedNotificationIdsKey = 'viewed_notification_ids';

  static Future<bool> hasUnreadNotifications({
    required Iterable<String> notificationIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final viewedIds = prefs.getStringList(_viewedNotificationIdsKey) ?? <String>[];
    final viewedSet = viewedIds.toSet();

    for (final id in notificationIds) {
      if (!viewedSet.contains(id)) {
        return true;
      }
    }

    return false;
  }

  static Future<void> markNotificationsAsViewed(Iterable<String> notificationIds) async {
    final prefs = await SharedPreferences.getInstance();
    final viewedIds = prefs.getStringList(_viewedNotificationIdsKey) ?? <String>[];
    final mergedIds = <String>{...viewedIds, ...notificationIds}.toList();

    if (mergedIds.length > 200) {
      await prefs.setStringList(
        _viewedNotificationIdsKey,
        mergedIds.sublist(mergedIds.length - 200),
      );
      return;
    }

    await prefs.setStringList(_viewedNotificationIdsKey, mergedIds);
  }
}
