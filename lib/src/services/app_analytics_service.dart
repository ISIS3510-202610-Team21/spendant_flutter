import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import '../models/expense_model.dart';
import '../repositories/expense_analytics_repository.dart';
import 'expense_moment_service.dart';

class AppAnalyticsService {
  AppAnalyticsService({ExpenseAnalyticsRepository? repository})
    : _repository = repository ?? const ExpenseAnalyticsRepository();

  static final AppAnalyticsService instance = AppAnalyticsService();
  static const String _mixpanelToken = '687875bcf4d97ec5bd77a1ed4cc6d8c7';
  static const double _smallRecurringExpenseThreshold = 50000;

  final ExpenseAnalyticsRepository _repository;

  // Lazily initialized — avoids blocking app startup.
  static Mixpanel? _mixpanel;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> logModuleCrash(String moduleName, dynamic error) async {
    if (!_isAnalyticsPlatformSupported) return;

    try {
      final mp = await _resolveMixpanel();
      if (mp == null) return;

      final errorMessage = error.toString();
      mp.track('module_crash', properties: <String, dynamic>{
        'module_name': moduleName,
        'error_message': errorMessage.length > 100
            ? errorMessage.substring(0, 100)
            : errorMessage,
      });
    } catch (_) {
      // Analytics is best-effort — must never interrupt app flow.
    }
  }

  Future<void> logAllBusinessQuestions({required int userId}) async {
    if (userId < 0 || !_isAnalyticsPlatformSupported) return;

    try {
      final expenses = _repository.getCompletedExpensesForUser(userId);
      if (expenses.isEmpty) return;

      final mp = await _resolveMixpanel();
      if (mp == null) return;

      await _logDaysSinceLastExpense(mp, expenses);
      await _logUncategorizedExpenseRate(mp, expenses);
      await _logMostActiveHour(mp, expenses);
      await _logSmallRecurringExpenses(mp, expenses);
      await _logExpenseRegistrationMethods(mp, expenses);
    } catch (_) {
      // Analytics is best-effort — must never interrupt app flow.
    }
  }

  // ---------------------------------------------------------------------------
  // Private — platform guard
  // ---------------------------------------------------------------------------

  static bool get _isAnalyticsPlatformSupported {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private — Mixpanel singleton resolution
  // ---------------------------------------------------------------------------

  static Future<Mixpanel?> _resolveMixpanel() async {
    if (_mixpanel != null) return _mixpanel;
    try {
      _mixpanel = await Mixpanel.init(
        _mixpanelToken,
        trackAutomaticEvents: true,
      );
      return _mixpanel;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private — individual event loggers
  // ---------------------------------------------------------------------------

  Future<void> _logDaysSinceLastExpense(
    Mixpanel mp,
    List<ExpenseModel> expenses,
  ) async {
    final lastExpenseMoment = expenses
        .map(ExpenseMomentService.expenseMoment)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    final daysSinceLastExpense =
        DateTime.now().difference(lastExpenseMoment).inDays;

    mp.track('days_since_last_expense', properties: <String, dynamic>{
      'days': daysSinceLastExpense,
      'is_inactive': daysSinceLastExpense >= 3,
    });
  }

  Future<void> _logUncategorizedExpenseRate(
    Mixpanel mp,
    List<ExpenseModel> expenses,
  ) async {
    final uncategorizedCount =
        expenses.where((e) => e.isPendingCategory).length;
    final totalCount = expenses.length;
    if (totalCount == 0) return;

    final percentage = ((uncategorizedCount / totalCount) * 100).truncate();
    mp.track('uncategorized_expense_rate', properties: <String, dynamic>{
      'uncategorized_count': uncategorizedCount,
      'total_count': totalCount,
      'percentage': percentage,
    });
  }

  Future<void> _logMostActiveHour(
    Mixpanel mp,
    List<ExpenseModel> expenses,
  ) async {
    final hourCounts = <int, int>{};
    for (final expense in expenses) {
      final hour = ExpenseMomentService.expenseMoment(expense).hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
    if (hourCounts.isEmpty) return;

    final mostActiveHour = hourCounts.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;

    mp.track('most_active_hour', properties: <String, dynamic>{
      'hour': mostActiveHour,
      'session': _sessionForHour(mostActiveHour),
    });
  }

  Future<void> _logSmallRecurringExpenses(
    Mixpanel mp,
    List<ExpenseModel> expenses,
  ) async {
    final now = DateTime.now();
    final threeMonthsAgo = _addMonths(now, -3);
    final smallRecurring = expenses
        .where((e) => e.isRecurring)
        .where((e) {
          final moment = ExpenseMomentService.expenseMoment(e);
          return !moment.isBefore(threeMonthsAgo) &&
              !moment.isAfter(now) &&
              e.amount < _smallRecurringExpenseThreshold;
        })
        .toList(growable: false);

    if (smallRecurring.isEmpty) return;

    final totalAmount = smallRecurring.fold<double>(
      0,
      (sum, e) => sum + e.amount,
    );

    mp.track('small_recurring_expenses', properties: <String, dynamic>{
      'count': smallRecurring.length,
      'total_amount': totalAmount.round(),
    });
  }

  Future<void> _logExpenseRegistrationMethods(
    Mixpanel mp,
    List<ExpenseModel> expenses,
  ) async {
    final manualCount = expenses.where((e) => e.source == 'MANUAL').length;
    final ocrCount = expenses.where((e) => e.source == 'OCR').length;
    final googlePayCount =
        expenses.where((e) => e.source == 'GOOGLE_PAY').length;

    if (manualCount + ocrCount + googlePayCount == 0) return;

    final leastUsedMethod = <String, int>{
      'manual': manualCount,
      'ocr': ocrCount,
      'google_pay': googlePayCount,
    }.entries
        .reduce((left, right) => left.value <= right.value ? left : right)
        .key;

    mp.track('expense_registration_methods', properties: <String, dynamic>{
      'manual_count': manualCount,
      'ocr_count': ocrCount,
      'google_pay_count': googlePayCount,
      'least_used_method': leastUsedMethod,
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _sessionForHour(int hour) {
    if (hour >= 6 && hour <= 11) return 'morning';
    if (hour >= 12 && hour <= 17) return 'afternoon';
    if (hour >= 18 && hour <= 22) return 'evening';
    return 'night';
  }

  DateTime _addMonths(DateTime value, int monthsToAdd) {
    final totalMonths =
        (value.year * 12) + value.month - 1 + monthsToAdd;
    final year = totalMonths ~/ 12;
    final normalizedMonth = (totalMonths % 12) + 1;
    final lastDayOfMonth = DateTime(year, normalizedMonth + 1, 0).day;
    final day = value.day > lastDayOfMonth ? lastDayOfMonth : value.day;
    return DateTime(
      year, normalizedMonth, day,
      value.hour, value.minute, value.second,
      value.millisecond, value.microsecond,
    );
  }
}
