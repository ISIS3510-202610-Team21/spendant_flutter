import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/expense_model.dart';
import '../repositories/expense_analytics_repository.dart';
import 'expense_moment_service.dart';

class AppAnalyticsService {
  AppAnalyticsService({ExpenseAnalyticsRepository? repository})
    : _repository = repository ?? const ExpenseAnalyticsRepository();

  static final AppAnalyticsService instance = AppAnalyticsService();
  static const Duration _firebaseRetryDelay = Duration(milliseconds: 250);
  static const int _firebaseRetryAttempts = 20;
  static const double _smallRecurringExpenseThreshold = 50000;

  final ExpenseAnalyticsRepository _repository;

  Future<void> logModuleCrash(String moduleName, dynamic error) async {
    if (!_isAnalyticsPlatformSupported) {
      return;
    }

    try {
      final analytics = await _resolveAnalytics();
      if (analytics == null) {
        return;
      }

      final errorMessage = error.toString();
      await analytics.logEvent(
        name: 'module_crash',
        parameters: <String, Object>{
          'module_name': moduleName,
          'error_message': errorMessage.length > 100
              ? errorMessage.substring(0, 100)
              : errorMessage,
        },
      );
    } catch (_) {
      // Analytics is best-effort and must not interrupt the app flow.
    }
  }

  Future<void> logAllBusinessQuestions({required int userId}) async {
    if (userId < 0 || !_isAnalyticsPlatformSupported) {
      return;
    }

    try {
      final expenses = _repository.getCompletedExpensesForUser(userId);
      if (expenses.isEmpty) {
        return;
      }

      final analytics = await _resolveAnalytics();
      if (analytics == null) {
        return;
      }

      await _logDaysSinceLastExpense(analytics, expenses);
      await _logUncategorizedExpenseRate(analytics, expenses);
      await _logMostActiveHour(analytics, expenses);
      await _logSmallRecurringExpenses(analytics, expenses);
      await _logExpenseRegistrationMethods(analytics, expenses);
    } catch (_) {
      // Analytics is best-effort and must not interrupt the app flow.
    }
  }

  static bool get _isAnalyticsPlatformSupported {
    if (kIsWeb) {
      return true;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  Future<FirebaseAnalytics?> _resolveAnalytics() async {
    for (var attempt = 0; attempt < _firebaseRetryAttempts; attempt++) {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAnalytics.instance;
      }
      await Future<void>.delayed(_firebaseRetryDelay);
    }

    return Firebase.apps.isNotEmpty ? FirebaseAnalytics.instance : null;
  }

  Future<void> _logDaysSinceLastExpense(
    FirebaseAnalytics analytics,
    List<ExpenseModel> expenses,
  ) async {
    final lastExpenseMoment = expenses
        .map(ExpenseMomentService.expenseMoment)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final daysSinceLastExpense = DateTime.now()
        .difference(lastExpenseMoment)
        .inDays;

    await analytics.logEvent(
      name: 'days_since_last_expense',
      parameters: <String, Object>{
        'days': daysSinceLastExpense,
        'is_inactive': daysSinceLastExpense >= 3 ? 'true' : 'false',
      },
    );
  }

  Future<void> _logUncategorizedExpenseRate(
    FirebaseAnalytics analytics,
    List<ExpenseModel> expenses,
  ) async {
    final uncategorizedCount = expenses
        .where((expense) => expense.isPendingCategory)
        .length;
    final totalCount = expenses.length;
    if (totalCount == 0) {
      return;
    }

    final percentage = ((uncategorizedCount / totalCount) * 100).truncate();
    await analytics.logEvent(
      name: 'uncategorized_expense_rate',
      parameters: <String, Object>{
        'uncategorized_count': uncategorizedCount,
        'total_count': totalCount,
        'percentage': percentage,
      },
    );
  }

  Future<void> _logMostActiveHour(
    FirebaseAnalytics analytics,
    List<ExpenseModel> expenses,
  ) async {
    final hourCounts = <int, int>{};
    for (final expense in expenses) {
      final hour = ExpenseMomentService.expenseMoment(expense).hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }

    if (hourCounts.isEmpty) {
      return;
    }

    final mostActiveHour = hourCounts.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;

    await analytics.logEvent(
      name: 'most_active_hour',
      parameters: <String, Object>{
        'hour': mostActiveHour,
        'session': _sessionForHour(mostActiveHour),
      },
    );
  }

  Future<void> _logSmallRecurringExpenses(
    FirebaseAnalytics analytics,
    List<ExpenseModel> expenses,
  ) async {
    final now = DateTime.now();
    final threeMonthsAgo = _addMonths(now, -3);
    final smallRecurringExpenses = expenses
        .where((expense) => expense.isRecurring)
        .where((expense) {
          final moment = ExpenseMomentService.expenseMoment(expense);
          return !moment.isBefore(threeMonthsAgo) &&
              !moment.isAfter(now) &&
              expense.amount < _smallRecurringExpenseThreshold;
        })
        .toList(growable: false);

    if (smallRecurringExpenses.isEmpty) {
      return;
    }

    final totalAmount = smallRecurringExpenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );

    await analytics.logEvent(
      name: 'small_recurring_expenses',
      parameters: <String, Object>{
        'count': smallRecurringExpenses.length,
        'total_amount': totalAmount.round(),
      },
    );
  }

  Future<void> _logExpenseRegistrationMethods(
    FirebaseAnalytics analytics,
    List<ExpenseModel> expenses,
  ) async {
    final manualCount = expenses
        .where((expense) => expense.source == 'MANUAL')
        .length;
    final ocrCount = expenses
        .where((expense) => expense.source == 'OCR')
        .length;
    final googlePayCount = expenses
        .where((expense) => expense.source == 'GOOGLE_PAY')
        .length;

    if (manualCount + ocrCount + googlePayCount == 0) {
      return;
    }

    final leastUsedMethod =
        <String, int>{
              'manual': manualCount,
              'ocr': ocrCount,
              'google_pay': googlePayCount,
            }.entries
            .reduce((left, right) => left.value <= right.value ? left : right)
            .key;

    await analytics.logEvent(
      name: 'expense_registration_methods',
      parameters: <String, Object>{
        'manual_count': manualCount,
        'ocr_count': ocrCount,
        'google_pay_count': googlePayCount,
        'least_used_method': leastUsedMethod,
      },
    );
  }

  String _sessionForHour(int hour) {
    if (hour >= 6 && hour <= 11) {
      return 'morning';
    }
    if (hour >= 12 && hour <= 17) {
      return 'afternoon';
    }
    if (hour >= 18 && hour <= 22) {
      return 'evening';
    }
    return 'night';
  }

  DateTime _addMonths(DateTime value, int monthsToAdd) {
    final totalMonths = (value.year * 12) + value.month - 1 + monthsToAdd;
    final year = totalMonths ~/ 12;
    final normalizedMonth = (totalMonths % 12) + 1;
    final lastDayOfMonth = DateTime(year, normalizedMonth + 1, 0).day;
    final day = value.day > lastDayOfMonth ? lastDayOfMonth : value.day;

    return DateTime(
      year,
      normalizedMonth,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
}
