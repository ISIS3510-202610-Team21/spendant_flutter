import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import '../models/expense_model.dart';
import '../repositories/expense_analytics_repository.dart';
import 'daily_budget_service.dart';
import 'expense_moment_service.dart';
import 'local_storage_service.dart';

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
      await _logMonthlyGoalProgress(mp, userId);
      await _logMonthlyBudgetConsumption(mp, userId, expenses);
      await _logHighestGrowthCategory(mp, expenses);
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

  // ---------------------------------------------------------------------------
  // BQ6 — Monthly savings goal progress vs expected pace
  // ---------------------------------------------------------------------------

  Future<void> _logMonthlyGoalProgress(Mixpanel mp, int userId) async {
    final goals = LocalStorageService.goalBox.values
        .where((g) => g.userId == userId)
        .toList();
    if (goals.isEmpty) return;

    final now        = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth  = now.day;
    final summary     = DailyBudgetService.buildSummaryForUser(userId);

    for (final goal in goals) {
      final state = summary.stateFor(goal);
      if (state == null || goal.targetAmount <= 0) continue;

      final actualPct   = ((state.currentAmount / goal.targetAmount) * 100).clamp(0.0, 100.0);
      final expectedPct = ((dayOfMonth / daysInMonth) * 100);
      final delta       = actualPct - expectedPct;

      mp.track('monthly_goal_progress', properties: <String, dynamic>{
        'goal_name':          goal.name,
        'target_amount_cop':  goal.targetAmount.round(),
        'current_amount_cop': state.currentAmount.round(),
        'actual_pct':         actualPct.truncate(),
        'expected_pct':       expectedPct.truncate(),
        'delta_pct':          delta.truncate(),  // positive = ahead, negative = behind
        'day_of_month':       dayOfMonth,
        'status':             delta >= 0 ? 'on_track' : 'behind',
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BQ7 — Monthly budget consumed vs midpoint threshold
  // ---------------------------------------------------------------------------

  Future<void> _logMonthlyBudgetConsumption(
    Mixpanel mp,
    int userId,
    List<ExpenseModel> allExpenses,
  ) async {
    final now   = DateTime.now();
    final start = DateTime(now.year, now.month, 1);

    final monthExpenses = allExpenses.where((e) {
      final moment = ExpenseMomentService.expenseMoment(e);
      return !moment.isBefore(start) && !moment.isAfter(now);
    }).toList();

    if (monthExpenses.isEmpty) return;

    final dayOfMonth  = now.day;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    final summary = DailyBudgetService.buildSummaryForUser(userId);
    // Monthly budget ≈ dailyBudget × days-in-month (incomes are daily-normalized)
    final monthlyIncome = summary.internalDailyBudget * daysInMonth;
    if (monthlyIncome <= 0) return;

    final consumed = monthExpenses.fold<double>(0, (sum, e) => sum + e.amount);
    final consumedPct = ((consumed / monthlyIncome) * 100).clamp(0.0, 200.0);
    final monthProgress = (dayOfMonth / daysInMonth * 100).truncate();

    mp.track('monthly_budget_midpoint_consumption', properties: <String, dynamic>{
      'consumed_cop':    consumed.round(),
      'budget_cop':      monthlyIncome.round(),
      'consumed_pct':    consumedPct.truncate(),
      'day_of_month':    dayOfMonth,
      'month_progress_pct': monthProgress,
      // Flag when > 60% budget used with < 50% month elapsed
      'overpace_alert':  consumedPct > 60 && monthProgress < 50,
    });
  }

  // ---------------------------------------------------------------------------
  // BQ8 — Highest category growth vs same period last month
  // ---------------------------------------------------------------------------

  Future<void> _logHighestGrowthCategory(
    Mixpanel mp,
    List<ExpenseModel> allExpenses,
  ) async {
    final now      = DateTime.now();
    final thisStart = DateTime(now.year, now.month, 1);
    final lastStart = DateTime(now.year, now.month - 1, 1);
    final lastEnd   = DateTime(now.year, now.month - 1, now.day, 23, 59, 59);

    Map<String, double> sumByCategory(
      List<ExpenseModel> expenses,
      DateTime from,
      DateTime to,
    ) {
      final totals = <String, double>{};
      for (final e in expenses) {
        final m = ExpenseMomentService.expenseMoment(e);
        if (m.isBefore(from) || m.isAfter(to)) continue;
        final cat = e.primaryCategory ?? 'Other';
        totals[cat] = (totals[cat] ?? 0) + e.amount;
      }
      return totals;
    }

    final thisPeriod = sumByCategory(allExpenses, thisStart, now);
    final lastPeriod = sumByCategory(allExpenses, lastStart, lastEnd);

    if (thisPeriod.isEmpty) return;

    String? topCategory;
    double topGrowthPct = double.negativeInfinity;

    for (final entry in thisPeriod.entries) {
      final prev   = lastPeriod[entry.key] ?? 0;
      final growth = prev > 0
          ? ((entry.value - prev) / prev) * 100
          : entry.value > 0 ? 100.0 : 0.0;
      if (growth > topGrowthPct) {
        topGrowthPct = growth;
        topCategory  = entry.key;
      }
    }

    if (topCategory == null) return;

    mp.track('highest_growth_category', properties: <String, dynamic>{
      'category':          topCategory,
      'current_amount_cop': thisPeriod[topCategory]!.round(),
      'previous_amount_cop': (lastPeriod[topCategory] ?? 0).round(),
      'growth_pct':        topGrowthPct.truncate(),
      'is_new_category':   !(lastPeriod.containsKey(topCategory)),
    });
  }
}
