import 'package:intl/intl.dart';

import '../models/app_notification_model.dart';
import 'app_date_format_service.dart';
import 'auth_memory_store.dart';

enum NotificationFeedType {
  warning,
  goalCreated,
  goalHalfway,
  goalAchieved,
  incomeCreated,
  incomeDue,
  budgetWarning,
}

class NotificationFeedItem {
  const NotificationFeedItem({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.title,
    required this.detailTitle,
    required this.detailMessage,
    this.subtitle,
    this.amount,
    this.category,
    this.routeName,
    this.routeArgumentInt,
  });

  final String id;
  final NotificationFeedType type;
  final DateTime createdAt;
  final String title;
  final String? subtitle;
  final double? amount;
  final String? category;
  final String detailTitle;
  final String detailMessage;
  final String? routeName;
  final int? routeArgumentInt;
}

abstract final class NotificationFeedService {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static List<NotificationFeedItem> buildFeed({
    required Iterable<AppNotificationModel> appNotifications,
    int? userId,
  }) {
    final resolvedUserId = userId ?? AuthMemoryStore.currentUserIdOrGuest;
    final feed = _buildAppNotifications(
      appNotifications,
      resolvedUserId: resolvedUserId,
    )..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    return feed;
  }

  static List<NotificationFeedItem> _buildAppNotifications(
    Iterable<AppNotificationModel> appNotifications, {
    required int resolvedUserId,
  }) {
    return appNotifications
        .where((notification) => notification.userId == resolvedUserId)
        .map((notification) {
          return NotificationFeedItem(
            id: notification.id,
            type: _mapType(notification.type),
            createdAt: notification.createdAt,
            title: notification.title,
            subtitle: notification.subtitle,
            amount: notification.amount,
            category: notification.category,
            detailTitle: notification.detailTitle,
            detailMessage: notification.detailMessage,
            routeName: notification.routeName,
            routeArgumentInt: notification.routeArgumentInt,
          );
        })
        .toList();
  }

  static String formatAmount(double amount) {
    return 'COP ${_currencyFormat.format(amount.round())}';
  }

  static String formatTimestamp(DateTime timestamp, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final difference = reference.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    }
    if (_isSameDay(timestamp, reference)) {
      return 'Today, ${DateFormat('HH:mm').format(timestamp)}';
    }

    final yesterday = reference.subtract(const Duration(days: 1));
    if (_isSameDay(timestamp, yesterday)) {
      return 'Yesterday, ${DateFormat('HH:mm').format(timestamp)}';
    }

    return AppDateFormatService.longDateWithTime(timestamp);
  }

  static bool isToday(DateTime value, {DateTime? now}) {
    return _isSameDay(value, now ?? DateTime.now());
  }

  static bool isYesterday(DateTime value, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    return _isSameDay(value, reference);
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static NotificationFeedType _mapType(String type) {
    switch (type) {
      case AppNotificationTypes.goalCreated:
        return NotificationFeedType.goalCreated;
      case AppNotificationTypes.goalHalfway:
        return NotificationFeedType.goalHalfway;
      case AppNotificationTypes.goalAchieved:
        return NotificationFeedType.goalAchieved;
      case AppNotificationTypes.incomeCreated:
        return NotificationFeedType.incomeCreated;
      case AppNotificationTypes.incomeDue:
        return NotificationFeedType.incomeDue;
      case AppNotificationTypes.budgetWarning:
        return NotificationFeedType.budgetWarning;
      case AppNotificationTypes.expenseCategoryNeeded:
      case AppNotificationTypes.spendingSpike:
      case AppNotificationTypes.spendingPace:
      case AppNotificationTypes.spendingPattern:
      case AppNotificationTypes.habitFixerWarning:
      case AppNotificationTypes.weeklyInsight:
        return NotificationFeedType.warning;
      default:
        return NotificationFeedType.warning;
    }
  }
}
