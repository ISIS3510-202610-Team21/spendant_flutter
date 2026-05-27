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

  static Mixpanel? _mixpanel;

  // ---------------------------------------------------------------------------
  // Init — optional eager init from main.dart
  // ---------------------------------------------------------------------------

  void init(Mixpanel mp) => _mixpanel = mp;

  // ---------------------------------------------------------------------------
  // Private — fire-and-forget track
  // ---------------------------------------------------------------------------

  void _track(String event, Map<String, dynamic> props) {
    unawaited(Future(() async {
      final mp = await _resolveMixpanel();
      if (mp == null) return;
      mp.track(event, properties: props);
    }));
  }

  // ---------------------------------------------------------------------------
  // BQ1 — Module crash
  // ---------------------------------------------------------------------------

  void logModuleCrash(String moduleName, dynamic error) {
    if (!_isAnalyticsPlatformSupported) return;
    final msg = error.toString();
    _track('module_crash', {
      'module_name': moduleName,
      'error_message': msg.length > 100 ? msg.substring(0, 100) : msg,
    });
  }

  // ---------------------------------------------------------------------------
  // BQ2 — Days since last expense
  // ---------------------------------------------------------------------------

  void logDaysSinceLastExpense(int userId, int days) =>
      _track('days_since_expense', {
        'user_id': userId,
        'days': days,
        'is_inactive': days >= 3,
      });

  // ---------------------------------------------------------------------------
  // BQ3 — OCR edit rate (called separately after OCR flow, not from logAllBQs)
  // ---------------------------------------------------------------------------

  void logOcrEditRate(int userId, int fieldsPopulated, int fieldsEdited) =>
      _track('ocr_edit_rate', {
        'user_id': userId,
        'fields_populated': fieldsPopulated,
        'fields_edited': fieldsEdited,
        'edit_rate': fieldsPopulated > 0 ? fieldsEdited / fieldsPopulated : 0.0,
      });

  // ---------------------------------------------------------------------------
  // BQ4 — Most active hour
  // ---------------------------------------------------------------------------

  void logMostActiveHour(int userId, int hour) =>
      _track('active_hour', {
        'user_id': userId,
        'hour': hour,
        'session': _sessionForHour(hour),
      });

  // ---------------------------------------------------------------------------
  // BQ5 — Small recurring expenses
  // ---------------------------------------------------------------------------

  void logSmallRecurringExpenses(int userId, int count, double totalAmount) =>
      _track('small_recurring_expenses', {
        'user_id': userId,
        'count': count,
        'total_amount': totalAmount,
      });

  // ---------------------------------------------------------------------------
  // BQ6 — Registration methods breakdown
  // ---------------------------------------------------------------------------

  void logExpenseRegistrationMethods(
    int userId,
    int manualCount,
    int ocrCount,
    int googlePayCount, {
    int wearVoiceCount = 0,
    int wearManualCount = 0,
  }) {
    final leastUsed = <String, int>{
      'manual': manualCount,
      'ocr': ocrCount,
      'google_pay': googlePayCount,
      'wear_voice': wearVoiceCount,
      'wear_manual': wearManualCount,
    }.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
    _track('registration_methods', {
      'user_id': userId,
      'manual_count': manualCount,
      'ocr_count': ocrCount,
      'google_pay_count': googlePayCount,
      'wear_voice_count': wearVoiceCount,
      'wear_manual_count': wearManualCount,
      'least_used_method': leastUsed,
    });
  }

  // ---------------------------------------------------------------------------
  // BQ7 — Savings goal progress
  // ---------------------------------------------------------------------------

  void logSavingsGoalProgress(
    int userId,
    double achievedPercent,
    int goalsCount,
  ) =>
      _track('savings_goal_progress', {
        'user_id': userId,
        'achieved_percent': achievedPercent,
        'active_goals_count': goalsCount,
        'is_on_track': achievedPercent >= 50.0,
      });

  // ---------------------------------------------------------------------------
  // BQ8 — Budget consumption at month midpoint
  // ---------------------------------------------------------------------------

  void logBudgetMidpointConsumption(
    int userId,
    double consumedPercent,
    bool evaluatedAtMidpoint,
  ) =>
      _track('budget_midpoint_consumption', {
        'user_id': userId,
        'consumed_percent': consumedPercent,
        'evaluated_at_midpoint': evaluatedAtMidpoint,
        'is_overspending': consumedPercent > 50.0 && evaluatedAtMidpoint,
      });

  // ---------------------------------------------------------------------------
  // BQ9 — Category highest spending growth vs previous month
  // ---------------------------------------------------------------------------

  void logCategoryHighestGrowth(
    int userId,
    String categoryName,
    double currentAmount,
    double previousAmount,
    double growthPercent,
  ) =>
      _track('category_highest_growth', {
        'user_id': userId,
        'category_name': categoryName,
        'current_amount': currentAmount,
        'previous_amount': previousAmount,
        'growth_percent': growthPercent,
      });

  // ---------------------------------------------------------------------------
  // Orchestrator — call on app resume + after each expense saved
  // ---------------------------------------------------------------------------

  Future<void> logAllBQs(int userId) async {
    if (userId < 0 || !_isAnalyticsPlatformSupported) return;
    try {
      final expenses = _repository.getCompletedExpensesForUser(userId);
      if (expenses.isEmpty) return;

      await Future.wait([
        _logBQ2(userId, expenses),
        _logBQ4(userId, expenses),
        _logBQ5(userId, expenses),
        _logBQ6(userId, expenses),
        _logBQ7(userId),
        _logBQ8(userId, expenses),
        _logBQ9(userId, expenses),
      ]);
    } catch (_) {
      // Analytics is best-effort — must never interrupt app flow.
    }
  }

  // Backwards-compat alias — home_screen.dart calls this.
  Future<void> logAllBusinessQuestions({required int userId}) =>
      logAllBQs(userId);

  // ---------------------------------------------------------------------------
  // Private — BQ2 data computation
  // ---------------------------------------------------------------------------

  Future<void> _logBQ2(int userId, List<ExpenseModel> expenses) async {
    final last = expenses
        .map(ExpenseMomentService.expenseMoment)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    logDaysSinceLastExpense(userId, DateTime.now().difference(last).inDays);
  }

  // ---------------------------------------------------------------------------
  // Private — BQ4 data computation
  // ---------------------------------------------------------------------------

  Future<void> _logBQ4(int userId, List<ExpenseModel> expenses) async {
    final hourCounts = <int, int>{};
    for (final e in expenses) {
      final hour = ExpenseMomentService.expenseMoment(e).hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
    if (hourCounts.isEmpty) return;
    final mostActive =
        hourCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    logMostActiveHour(userId, mostActive);
  }

  // ---------------------------------------------------------------------------
  // Private — BQ5 data computation
  // ---------------------------------------------------------------------------

  Future<void> _logBQ5(int userId, List<ExpenseModel> expenses) async {
    final now = DateTime.now();
    final threeMonthsAgo = _addMonths(now, -3);
    final smallRecurring = expenses
        .where((e) => e.isRecurring)
        .where((e) {
          final m = ExpenseMomentService.expenseMoment(e);
          return !m.isBefore(threeMonthsAgo) &&
              !m.isAfter(now) &&
              e.amount < _smallRecurringExpenseThreshold;
        })
        .toList(growable: false);
    if (smallRecurring.isEmpty) return;
    final total = smallRecurring.fold<double>(0, (s, e) => s + e.amount);
    logSmallRecurringExpenses(userId, smallRecurring.length, total);
  }

  // ---------------------------------------------------------------------------
  // Private — BQ6 data computation
  // ---------------------------------------------------------------------------

  Future<void> _logBQ6(int userId, List<ExpenseModel> expenses) async {
    final manualCount = expenses.where((e) => e.source == 'MANUAL').length;
    final ocrCount = expenses.where((e) => e.source == 'OCR').length;
    final googlePayCount =
        expenses.where((e) => e.source == 'GOOGLE_PAY').length;
    final wearVoiceCount =
        expenses.where((e) => e.source == 'WEAR_VOICE').length;
    final wearManualCount =
        expenses.where((e) => e.source == 'WEAR_MANUAL').length;
    if (manualCount + ocrCount + googlePayCount +
            wearVoiceCount + wearManualCount ==
        0) return;
    logExpenseRegistrationMethods(
      userId,
      manualCount,
      ocrCount,
      googlePayCount,
      wearVoiceCount: wearVoiceCount,
      wearManualCount: wearManualCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Private — BQ7 data computation (savings goals → avg achieved %)
  // ---------------------------------------------------------------------------

  Future<void> _logBQ7(int userId) async {
    final goals = LocalStorageService.goalBox.values
        .where((g) => g.userId == userId)
        .toList();
    if (goals.isEmpty) return;

    final summary = DailyBudgetService.buildSummaryForUser(userId);
    double totalPct = 0;
    int validGoals = 0;

    for (final goal in goals) {
      final state = summary.stateFor(goal);
      if (state == null || goal.targetAmount <= 0) continue;
      totalPct +=
          ((state.currentAmount / goal.targetAmount) * 100).clamp(0.0, 100.0);
      validGoals++;
    }

    if (validGoals == 0) return;
    logSavingsGoalProgress(userId, totalPct / validGoals, validGoals);
  }

  // ---------------------------------------------------------------------------
  // Private — BQ8 data computation (budget midpoint)
  // ---------------------------------------------------------------------------

  Future<void> _logBQ8(int userId, List<ExpenseModel> allExpenses) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final monthExpenses = allExpenses.where((e) {
      final m = ExpenseMomentService.expenseMoment(e);
      return !m.isBefore(start) && !m.isAfter(now);
    }).toList();
    if (monthExpenses.isEmpty) return;

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final summary = DailyBudgetService.buildSummaryForUser(userId);
    final monthlyIncome = summary.internalDailyBudget * daysInMonth;
    if (monthlyIncome <= 0) return;

    final consumed = monthExpenses.fold<double>(0, (s, e) => s + e.amount);
    final consumedPct = (consumed / monthlyIncome * 100).clamp(0.0, 200.0);
    final evaluatedAtMidpoint = now.day >= (daysInMonth ~/ 2);

    logBudgetMidpointConsumption(userId, consumedPct, evaluatedAtMidpoint);
  }

  // ---------------------------------------------------------------------------
  // Private — BQ9 data computation (highest category growth)
  // ---------------------------------------------------------------------------

  Future<void> _logBQ9(int userId, List<ExpenseModel> allExpenses) async {
    final now = DateTime.now();
    final thisStart = DateTime(now.year, now.month, 1);
    final lastStart = DateTime(now.year, now.month - 1, 1);
    final lastEnd = DateTime(now.year, now.month - 1, now.day, 23, 59, 59);

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
      final prev = lastPeriod[entry.key] ?? 0;
      final growth = prev > 0
          ? ((entry.value - prev) / prev) * 100
          : entry.value > 0
          ? 100.0
          : 0.0;
      if (growth > topGrowthPct) {
        topGrowthPct = growth;
        topCategory = entry.key;
      }
    }

    if (topCategory == null) return;
    logCategoryHighestGrowth(
      userId,
      topCategory,
      thisPeriod[topCategory]!,
      lastPeriod[topCategory] ?? 0,
      topGrowthPct,
    );
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
  // Private — Mixpanel singleton resolution (lazy init fallback)
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
  // Private — helpers
  // ---------------------------------------------------------------------------

  String _sessionForHour(int hour) {
    if (hour >= 6 && hour <= 11) return 'morning';
    if (hour >= 12 && hour <= 17) return 'afternoon';
    if (hour >= 18 && hour <= 22) return 'evening';
    return 'night';
  }

  DateTime _addMonths(DateTime value, int monthsToAdd) {
    final totalMonths = (value.year * 12) + value.month - 1 + monthsToAdd;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = value.day > lastDay ? lastDay : value.day;
    return DateTime(
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
}
