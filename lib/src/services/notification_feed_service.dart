import 'package:intl/intl.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
import 'app_date_format_service.dart';
import 'auth_memory_store.dart';
import 'expense_moment_service.dart';
import '../theme/expense_visuals.dart';

enum NotificationFeedType {
  expense,
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
    this.expense,
    this.goal,
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
  final ExpenseModel? expense;
  final GoalModel? goal;
  final String? routeName;
  final int? routeArgumentInt;
}

abstract final class NotificationFeedService {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static List<NotificationFeedItem> buildFeed({
    required Iterable<ExpenseModel> expenses,
    required Iterable<GoalModel> goals,
    required Iterable<AppNotificationModel> appNotifications,
    int? userId,
  }) {
    final resolvedUserId = userId ?? AuthMemoryStore.currentUserIdOrGuest;
    final userExpenses =
        expenses
            .where(
              (expense) =>
                  expense.userId == resolvedUserId &&
                  !ExpenseMomentService.isFutureExpense(expense),
            )
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final userGoals =
        goals.where((goal) => goal.userId == resolvedUserId).toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final prioritizedLabels = ExpenseVisuals.topCategoryTotalsForMonth(
      userExpenses,
    ).map((entry) => entry.label).toList(growable: false);

    final feed = <NotificationFeedItem>[
      ..._buildExpenseNotifications(
        userExpenses,
        prioritizedLabels: prioritizedLabels,
      ),
      ..._buildAppNotifications(
        userGoals,
        appNotifications,
        resolvedUserId: resolvedUserId,
      ),
    ]..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    return feed;
  }

  static List<NotificationFeedItem> _buildExpenseNotifications(
    List<ExpenseModel> expenses, {
    required List<String> prioritizedLabels,
  }) {
    return expenses.take(8).map((expense) {
      final isPendingCategory =
          expense.isPendingCategory ||
          (expense.detailLabels.isEmpty &&
              (expense.primaryCategory?.trim().isEmpty ?? true));
      final category = isPendingCategory
          ? null
          : ExpenseVisuals.resolveDisplayLabel(
              expense,
              prioritizedLabels: prioritizedLabels,
            );
      final subtitle = isPendingCategory ? 'Needs category' : category;
      final detailMessage = isPendingCategory
          ? 'Expense saved without a category. Open it to choose a label.'
          : 'Expense saved in $category and ready to edit.';

      return NotificationFeedItem(
        id: 'expense-${expense.key ?? expense.createdAt.microsecondsSinceEpoch}',
        type: NotificationFeedType.expense,
        createdAt: expense.createdAt,
        title: expense.name,
        subtitle: subtitle,
        amount: expense.amount,
        category: category,
        expense: expense,
        detailTitle: expense.name,
        detailMessage: detailMessage,
      );
    }).toList();
  }

  static List<NotificationFeedItem> _buildAppNotifications(
    List<GoalModel> goals,
    Iterable<AppNotificationModel> appNotifications, {
    required int resolvedUserId,
  }) {
    final goalByIdentity = <String, GoalModel>{};
    for (final goal in goals) {
      final identity = _goalIdentity(goal);
      if (identity != null) {
        goalByIdentity[identity] = goal;
      }
    }

    return appNotifications
        .where((notification) => notification.userId == resolvedUserId)
        .map((notification) {
          final goal = _goalForNotification(notification, goalByIdentity);
          return NotificationFeedItem(
            id: notification.id,
            type: _mapType(notification.type),
            createdAt: notification.createdAt,
            title: notification.title,
            subtitle: notification.subtitle,
            amount: notification.amount,
            category: notification.category,
            goal: goal,
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

  static GoalModel? _goalForNotification(
    AppNotificationModel notification,
    Map<String, GoalModel> goalByIdentity,
  ) {
    final id = notification.id;
    const prefixes = <String>['goal-created-', 'goal-50-', 'goal-100-'];

    for (final prefix in prefixes) {
      if (!id.startsWith(prefix)) {
        continue;
      }

      return goalByIdentity[id.substring(prefix.length)];
    }

    return null;
  }

  static String? _goalIdentity(GoalModel goal) {
    final key = goal.serverId ?? goal.key?.toString();
    if (key != null && key.isNotEmpty) {
      return key;
    }

    return goal.createdAt.microsecondsSinceEpoch.toString();
  }
}
