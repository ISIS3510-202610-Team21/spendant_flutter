import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import '../models/goal_model.dart';

enum NotificationFeedType { expense, warning, goalAchieved }

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
}

abstract final class NotificationFeedService {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static List<NotificationFeedItem> buildFeed({
    required Iterable<ExpenseModel> expenses,
    required Iterable<GoalModel> goals,
    int userId = 1,
  }) {
    final userExpenses = expenses.where((expense) => expense.userId == userId).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final userGoals = goals.where((goal) => goal.userId == userId).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    final feed = <NotificationFeedItem>[
      ..._buildExpenseNotifications(userExpenses),
      ..._buildWarningNotifications(userExpenses),
      ..._buildGoalNotifications(userGoals),
    ]..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    return feed;
  }

  static List<NotificationFeedItem> _buildExpenseNotifications(
    List<ExpenseModel> expenses,
  ) {
    return expenses.take(8).map((expense) {
      final category = normalizeCategory(expense.primaryCategory);

      return NotificationFeedItem(
        id: 'expense-${expense.key ?? expense.createdAt.microsecondsSinceEpoch}',
        type: NotificationFeedType.expense,
        createdAt: expense.createdAt,
        title: expense.name,
        subtitle: expense.detailLabels.isNotEmpty ? expense.detailLabels.first : category,
        amount: expense.amount,
        category: category,
        expense: expense,
        detailTitle: expense.name,
        detailMessage: 'Expense saved in $category and ready to edit.',
      );
    }).toList();
  }

  static List<NotificationFeedItem> _buildWarningNotifications(
    List<ExpenseModel> expenses,
  ) {
    final warnings = <NotificationFeedItem>[];

    for (final expense in expenses) {
      if (!_isUnusualExpense(expense, expenses)) {
        continue;
      }

      final category = normalizeCategory(expense.primaryCategory);
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

  static List<NotificationFeedItem> _buildGoalNotifications(List<GoalModel> goals) {
    return goals.where(_isGoalAchieved).map((goal) {
      return NotificationFeedItem(
        id: 'goal-${goal.key ?? goal.createdAt.microsecondsSinceEpoch}',
        type: NotificationFeedType.goalAchieved,
        createdAt: goal.createdAt,
        title: 'Goal Achieved!',
        goal: goal,
        detailTitle: 'Lvl. Up! Goal\nAccomplished!',
        detailMessage:
            "Look at you. You just smashed your goal: COP ${_currencyFormat.format(goal.targetAmount.round())} for ${goal.name}. Your future self is already doing a happy dance. Treat yourself to something small. You've earned the bragging rights.",
      );
    }).toList();
  }

  static bool _isGoalAchieved(GoalModel goal) {
    return goal.isCompleted || goal.currentAmount >= goal.targetAmount;
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

    return expense.amount >= average * 1.8 && (expense.amount - average) >= 15000;
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
}
