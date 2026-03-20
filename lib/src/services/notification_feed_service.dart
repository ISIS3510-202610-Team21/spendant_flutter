import 'package:intl/intl.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
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
    int userId = 1,
  }) {
    final userExpenses =
        expenses.where((expense) => expense.userId == userId).toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final userGoals = goals.where((goal) => goal.userId == userId).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final prioritizedLabels = ExpenseVisuals.topCategoryTotalsForMonth(
      userExpenses,
    ).map((entry) => entry.label).toList(growable: false);

    final feed = <NotificationFeedItem>[
      ..._buildExpenseNotifications(
        userExpenses,
        prioritizedLabels: prioritizedLabels,
      ),
      ..._buildWarningNotifications(
        userExpenses,
        prioritizedLabels: prioritizedLabels,
      ),
      ..._buildAppNotifications(userGoals, appNotifications),
    ]..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    return feed;
  }

  static List<NotificationFeedItem> _buildExpenseNotifications(
    List<ExpenseModel> expenses, {
    required List<String> prioritizedLabels,
  }) {
    return expenses.take(8).map((expense) {
      final category = ExpenseVisuals.resolveDisplayLabel(
        expense,
        prioritizedLabels: prioritizedLabels,
      );

      return NotificationFeedItem(
        id: 'expense-${expense.key ?? expense.createdAt.microsecondsSinceEpoch}',
        type: NotificationFeedType.expense,
        createdAt: expense.createdAt,
        title: expense.name,
        subtitle: category,
        amount: expense.amount,
        category: category,
        expense: expense,
        detailTitle: expense.name,
        detailMessage: 'Expense saved in $category and ready to edit.',
      );
    }).toList();
  }

  static List<NotificationFeedItem> _buildWarningNotifications(
    List<ExpenseModel> expenses, {
    required List<String> prioritizedLabels,
  }) {
    final warnings = <NotificationFeedItem>[];

    for (final expense in expenses) {
      if (!_isUnusualExpense(expense, expenses)) {
        continue;
      }

      final category = ExpenseVisuals.resolveDisplayLabel(
        expense,
        prioritizedLabels: prioritizedLabels,
      );
      warnings.add(
        NotificationFeedItem(
          id: 'warning-${expense.key ?? expense.createdAt.microsecondsSinceEpoch}',
          type: NotificationFeedType.warning,
          createdAt: expense.createdAt,
          title: 'New Warning!',
          amount: expense.amount,
          category: category,
          expense: expense,
          detailTitle: '"Hey! Everything alright\nover there?"',
          detailMessage:
              'We noticed some unusual activity in $category. Before your future self gets the wrong idea, was this purchase planned or is it a stress treat? Think about it for two minutes.',
        ),
      );
    }

    return warnings.take(4).toList();
  }

  static List<NotificationFeedItem> _buildAppNotifications(
    List<GoalModel> goals,
    Iterable<AppNotificationModel> appNotifications,
  ) {
    final goalByIdentity = <String, GoalModel>{};
    for (final goal in goals) {
      final identity = _goalIdentity(goal);
      if (identity != null) {
        goalByIdentity[identity] = goal;
      }
    }

    return appNotifications.map((notification) {
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
    }).toList();
  }

  static bool _isUnusualExpense(
    ExpenseModel expense,
    List<ExpenseModel> allExpenses,
  ) {
    final category = normalizeCategory(expense.primaryCategory);
    final comparableExpenses = allExpenses.where((candidate) {
      return candidate != expense &&
          normalizeCategory(candidate.primaryCategory) == category;
    }).toList();

    if (category == 'Transport' && expense.amount >= 50000) {
      return true;
    }

    if (expense.amount < 35000 || comparableExpenses.length < 2) {
      return false;
    }

    final average =
        comparableExpenses.fold<double>(0, (sum, item) => sum + item.amount) /
        comparableExpenses.length;

    return expense.amount >= average * 1.8 &&
        (expense.amount - average) >= 15000;
  }

  static String normalizeCategory(String? category) {
    switch (category?.trim()) {
      case 'Food':
        return 'Food';
      case 'Transport':
        return 'Transport';
      case 'Services':
        return 'Services';
      default:
        return 'Other';
    }
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

    return DateFormat('d/M/y, HH:mm').format(timestamp);
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
