import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import 'app_date_format_service.dart';
import 'auth_memory_store.dart';
import 'daily_budget_service.dart';
import 'expense_moment_service.dart';
import 'habit_fixer_monitor_service.dart';
import 'local_notification_service.dart';
import 'local_storage_service.dart';
import 'spending_advice_service.dart';
import 'weekly_smart_insight_service.dart';

abstract final class AppNotificationService {
  static const String _bootstrapKeyPrefix = 'app_notification_bootstrap_v2';
  static const String _trackedSignalIdsKeyPrefix =
      'app_notification_tracked_signal_ids_v2';
  static const String _goalRouteName = '/set-goal';
  static const String _budgetRouteName = '/budget';
  static const String _notificationsRouteName = '/notifications';

  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');
  static int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;
  static String get _bootstrapKey => '$_bootstrapKeyPrefix-$_currentUserId';
  static String get _trackedSignalIdsKey =>
      '$_trackedSignalIdsKeyPrefix-$_currentUserId';

  static Future<void>? _activeRefresh;

  static Future<void> initialize() async {
    if (_currentUserId < 0) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final didBootstrap = prefs.getBool(_bootstrapKey) ?? false;
    if (didBootstrap) {
      return;
    }

    final trackedSignals = _collectSatisfiedSignalIds(now: DateTime.now());
    await prefs.setStringList(
      _trackedSignalIdsKey,
      trackedSignals.toList(growable: false),
    );
    await prefs.setBool(_bootstrapKey, true);
  }

  static Future<void> refresh() async {
    final runningRefresh = _activeRefresh;
    if (runningRefresh != null) {
      return runningRefresh;
    }

    final refreshFuture = _refreshInternal();
    _activeRefresh = refreshFuture;

    try {
      await refreshFuture;
    } finally {
      if (identical(_activeRefresh, refreshFuture)) {
        _activeRefresh = null;
      }
    }
  }

  static Future<void> _refreshInternal() async {
    if (_currentUserId < 0) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final trackedSignals = {
      ...(prefs.getStringList(_trackedSignalIdsKey) ?? const <String>[]),
    };
    var shouldPersistTrackedSignals = false;

    final now = DateTime.now();
    final expenses = LocalStorageService.expenseBox.values
        .where(
          (expense) =>
              expense.userId == _currentUserId &&
              !ExpenseMomentService.isFutureExpense(expense, now: now),
        )
        .toList();
    final goals = LocalStorageService.goalBox.values
        .where((goal) => goal.userId == _currentUserId)
        .toList();
    final incomes = LocalStorageService.incomeBox.values
        .where((income) => income.userId == _currentUserId)
        .toList();
    final goalStates = DailyBudgetService.buildGoalStates(
      goals: goals,
      incomes: incomes,
      expenses: expenses,
      now: now,
    );

    for (final goalState in goalStates) {
      final halfwaySignalId = _goalSignalId(goalState.goal, '50');
      if (_goalProgress(goalState) >= 0.5 &&
          !trackedSignals.contains(halfwaySignalId)) {
        trackedSignals.add(halfwaySignalId);
        shouldPersistTrackedSignals = true;
        await _upsertNotification(
          _buildGoalHalfwayNotification(goalState, now: now),
          notifySystem: true,
        );
      }

      final completedSignalId = _goalSignalId(goalState.goal, '100');
      if (_goalProgress(goalState) >= 1 &&
          !trackedSignals.contains(completedSignalId)) {
        trackedSignals.add(completedSignalId);
        shouldPersistTrackedSignals = true;
        await _upsertNotification(
          _buildGoalAchievedNotification(goalState, now: now),
          notifySystem: true,
        );
      }
    }

    for (final income in incomes) {
      final dueOccurrence = _latestDueIncomeOccurrence(income, now: now);
      if (dueOccurrence == null) {
        continue;
      }

      final dueSignalId = _incomeDueSignalId(income, dueOccurrence);
      if (trackedSignals.contains(dueSignalId)) {
        continue;
      }

      trackedSignals.add(dueSignalId);
      shouldPersistTrackedSignals = true;
      await _upsertNotification(
        _buildIncomeDueNotification(
          income,
          now: now,
          dueOccurrence: dueOccurrence,
        ),
        notifySystem: true,
      );
    }

    final spendingAdvices = SpendingAdviceService.buildInsights(
      expenses: expenses,
      now: now,
    );
    for (final advice in spendingAdvices) {
      if (trackedSignals.contains(advice.signalId)) {
        continue;
      }

      trackedSignals.add(advice.signalId);
      shouldPersistTrackedSignals = true;
      await _upsertNotification(
        _buildSpendingAdviceNotification(advice, now: now),
        notifySystem: true,
      );
    }

    final habitFixerAdvice = await HabitFixerMonitorService.instance
        .buildTriggeredAdvice(expenses: expenses, now: now);
    if (habitFixerAdvice != null &&
        !trackedSignals.contains(habitFixerAdvice.signalId)) {
      trackedSignals.add(habitFixerAdvice.signalId);
      shouldPersistTrackedSignals = true;
      await _upsertNotification(
        _buildSpendingAdviceNotification(habitFixerAdvice, now: now),
        notifySystem: true,
      );
    }

    final weeklyInsight = WeeklySmartInsightService.buildInsight(
      expenses: expenses,
      userId: _currentUserId,
      now: now,
    );
    if (weeklyInsight != null &&
        !trackedSignals.contains(weeklyInsight.signalId)) {
      trackedSignals.add(weeklyInsight.signalId);
      shouldPersistTrackedSignals = true;
      await _upsertNotification(
        _buildWeeklyInsightNotification(weeklyInsight, now: now),
        notifySystem: true,
      );
    }

    final summary = DailyBudgetService.buildSummaryForUser(
      _currentUserId,
      now: now,
    );
    if (summary.isSpendableBudgetExhausted) {
      final budgetSignalId = _budgetSignalId(now);
      final shouldNotify = !trackedSignals.contains(budgetSignalId);
      if (shouldNotify) {
        trackedSignals.add(budgetSignalId);
        shouldPersistTrackedSignals = true;
      }

      await _upsertNotification(
        _buildBudgetWarningNotification(summary, now: now),
        notifySystem: shouldNotify,
      );
    }

    if (!shouldPersistTrackedSignals) {
      return;
    }

    await prefs.setStringList(
      _trackedSignalIdsKey,
      trackedSignals.toList(growable: false),
    );
  }

  static Set<String> _collectSatisfiedSignalIds({required DateTime now}) {
    final trackedSignals = <String>{};

    final expenses = LocalStorageService.expenseBox.values.where(
      (expense) =>
          expense.userId == _currentUserId &&
          !ExpenseMomentService.isFutureExpense(expense, now: now),
    );
    final goals = LocalStorageService.goalBox.values.where(
      (goal) => goal.userId == _currentUserId,
    );
    final incomes = LocalStorageService.incomeBox.values.where(
      (income) => income.userId == _currentUserId,
    );
    final goalStates = DailyBudgetService.buildGoalStates(
      goals: goals,
      incomes: incomes,
      expenses: expenses,
      now: now,
    );
    for (final goalState in goalStates) {
      final progress = _goalProgress(goalState);
      if (progress >= 0.5) {
        trackedSignals.add(_goalSignalId(goalState.goal, '50'));
      }
      if (progress >= 1) {
        trackedSignals.add(_goalSignalId(goalState.goal, '100'));
      }
    }
    for (final income in incomes) {
      final dueOccurrence = _latestDueIncomeOccurrence(income, now: now);
      if (dueOccurrence != null) {
        trackedSignals.add(_incomeDueSignalId(income, dueOccurrence));
      }
    }
    trackedSignals.addAll(
      SpendingAdviceService.collectSatisfiedSignalIds(
        expenses: expenses,
        now: now,
      ),
    );

    final summary = DailyBudgetService.buildSummaryForUser(
      _currentUserId,
      now: now,
    );
    if (summary.isSpendableBudgetExhausted) {
      trackedSignals.add(_budgetSignalId(now));
    }

    return trackedSignals;
  }

  static double _goalProgress(GoalComputedState goalState) {
    return goalState.progress;
  }

  static String _goalSignalId(GoalModel goal, String milestone) {
    return 'goal:$milestone:${_goalIdentity(goal)}';
  }

  static String _goalNotificationId(GoalModel goal, String milestone) {
    return 'goal-$milestone-${_goalIdentity(goal)}';
  }

  static String _incomeSignalId(IncomeModel income, String signal) {
    return 'income:$signal:${_incomeIdentity(income)}';
  }

  static String _incomeNotificationId(IncomeModel income, String signal) {
    return 'income-$signal-${_incomeIdentity(income)}';
  }

  static String _incomeDueSignalId(IncomeModel income, DateTime occurrence) {
    return 'income:due:${_incomeIdentity(income)}:${_dayKey(occurrence)}';
  }

  static String _incomeDueNotificationId(
    IncomeModel income,
    DateTime occurrence,
  ) {
    return 'income-due-${_incomeIdentity(income)}-${_dayKey(occurrence)}';
  }

  static String _goalIdentity(GoalModel goal) {
    final key = goal.serverId ?? goal.key?.toString();
    if (key != null && key.isNotEmpty) {
      return key;
    }

    return goal.createdAt.microsecondsSinceEpoch.toString();
  }

  static String _incomeIdentity(IncomeModel income) {
    final key = income.serverId ?? income.key?.toString();
    if (key != null && key.isNotEmpty) {
      return key;
    }

    return income.createdAt.microsecondsSinceEpoch.toString();
  }

  static String _budgetSignalId(DateTime now) {
    return 'budget:${_dayKey(now)}';
  }

  static String _budgetNotificationId(DateTime now) {
    return 'budget-warning-${_dayKey(now)}';
  }

  static String _dayKey(DateTime value) {
    final day = DateUtils.dateOnly(value);
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }

  static AppNotificationModel _buildGoalCreatedNotification(
    GoalModel goal, {
    required DateTime now,
  }) {
    return AppNotificationModel()
      ..id = _goalNotificationId(goal, 'created')
      ..type = AppNotificationTypes.goalCreated
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'New goal created'
      ..subtitle = goal.name
      ..amount = goal.targetAmount
      ..detailTitle = 'Goal created'
      ..detailMessage =
          'Your goal ${goal.name} was created for COP ${_currencyFormat.format(goal.targetAmount.round())}. Open Goals to track it and keep saving.'
      ..routeName = _goalRouteName
      ..routeArgumentInt = 1;
  }

  static AppNotificationModel _buildGoalHalfwayNotification(
    GoalComputedState goalState, {
    required DateTime now,
  }) {
    final goal = goalState.goal;
    return AppNotificationModel()
      ..id = _goalNotificationId(goal, '50')
      ..type = AppNotificationTypes.goalHalfway
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'Goal at 50%'
      ..subtitle = goal.name
      ..amount = goalState.currentAmount
      ..detailTitle = 'Halfway there'
      ..detailMessage =
          'Your goal ${goal.name} already reached 50%. You have saved COP ${_currencyFormat.format(goalState.currentAmount.round())} out of COP ${_currencyFormat.format(goal.targetAmount.round())}.'
      ..routeName = _goalRouteName
      ..routeArgumentInt = 1;
  }

  static AppNotificationModel _buildGoalAchievedNotification(
    GoalComputedState goalState, {
    required DateTime now,
  }) {
    final goal = goalState.goal;
    return AppNotificationModel()
      ..id = _goalNotificationId(goal, '100')
      ..type = AppNotificationTypes.goalAchieved
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'Goal completed'
      ..subtitle = goal.name
      ..amount = goal.targetAmount
      ..detailTitle = 'Goal completed'
      ..detailMessage =
          'You hit COP ${_currencyFormat.format(goal.targetAmount.round())} for ${goal.name}. Review the goal screen to decide your next move.'
      ..routeName = _goalRouteName
      ..routeArgumentInt = 1;
  }

  static AppNotificationModel _buildIncomeCreatedNotification(
    IncomeModel income, {
    required DateTime now,
  }) {
    return AppNotificationModel()
      ..id = _incomeNotificationId(income, 'created')
      ..type = AppNotificationTypes.incomeCreated
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'New income added'
      ..subtitle = income.name
      ..amount = income.amount
      ..detailTitle = 'Income created'
      ..detailMessage =
          'Your income ${income.name} was added for COP ${_currencyFormat.format(income.amount.round())}. Open Budget and Income to review it.'
      ..routeName = _budgetRouteName;
  }

  static AppNotificationModel _buildIncomeDueNotification(
    IncomeModel income, {
    required DateTime now,
    required DateTime dueOccurrence,
  }) {
    return AppNotificationModel()
      ..id = _incomeDueNotificationId(income, dueOccurrence)
      ..type = AppNotificationTypes.incomeDue
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'Income available'
      ..subtitle = income.name
      ..amount = income.amount
      ..detailTitle = 'Income arrived'
      ..detailMessage =
          'Your recurring income ${income.name} reached its next cycle on ${AppDateFormatService.longDate(dueOccurrence)}. Review Budget and Income to plan around it.'
      ..routeName = _budgetRouteName;
  }

  static AppNotificationModel _buildBudgetWarningNotification(
    DailyBudgetSummary summary, {
    required DateTime now,
  }) {
    final overspentAmount = (-summary.remainingSpendableBudget).clamp(
      0.0,
      double.infinity,
    );
    final goalImpactAmount = overspentAmount > summary.totalGoalDailyCommitment
        ? summary.totalGoalDailyCommitment
        : overspentAmount;
    final overspentLabel =
        'COP ${_currencyFormat.format(overspentAmount.round())}';
    final goalImpactLabel =
        'COP ${_currencyFormat.format(goalImpactAmount.round())}';
    final detailMessage = goalImpactAmount > 0
        ? 'You already passed today\'s spendable budget by $overspentLabel. That overspend can reduce the money reserved for your goals by up to $goalImpactLabel today.'
        : 'You already passed today\'s spendable budget by $overspentLabel. Open your budget screen and rebalance today\'s spending.';

    return AppNotificationModel()
      ..id = _budgetNotificationId(now)
      ..type = AppNotificationTypes.budgetWarning
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'Daily budget exhausted'
      ..subtitle = goalImpactAmount > 0
          ? 'Goals at risk: $goalImpactLabel'
          : 'Review your daily budget'
      ..amount = overspentAmount
      ..detailTitle = 'Daily budget warning'
      ..detailMessage = detailMessage
      ..routeName = _budgetRouteName;
  }

  static AppNotificationModel _buildSpendingAdviceNotification(
    SpendingAdvice advice, {
    required DateTime now,
  }) {
    return AppNotificationModel()
      ..id = advice.notificationId
      ..type = _notificationTypeForAdvice(advice.kind)
      ..createdAt = now
      ..userId = _currentUserId
      ..title = advice.title
      ..subtitle = advice.subtitle
      ..amount = advice.amount
      ..category = advice.category
      ..detailTitle = advice.detailTitle
      ..detailMessage = advice.detailMessage
      ..routeName = _notificationsRouteName;
  }

  static AppNotificationModel _buildWeeklyInsightNotification(
    WeeklySmartInsight insight, {
    required DateTime now,
  }) {
    return AppNotificationModel()
      ..id = insight.notificationId
      ..type = AppNotificationTypes.weeklyInsight
      ..createdAt = now
      ..userId = _currentUserId
      ..title = insight.title
      ..subtitle = insight.subtitle
      ..amount = insight.amount
      ..detailTitle = insight.detailTitle
      ..detailMessage = insight.detailMessage
      ..routeName = _notificationsRouteName;
  }

  static String _notificationTypeForAdvice(SpendingAdviceKind kind) {
    switch (kind) {
      case SpendingAdviceKind.expenseSpike:
        return AppNotificationTypes.spendingSpike;
      case SpendingAdviceKind.categoryAcceleration:
        return AppNotificationTypes.spendingPace;
      case SpendingAdviceKind.habitCluster:
        return AppNotificationTypes.spendingPattern;
      case SpendingAdviceKind.regretHotspot:
        return AppNotificationTypes.habitFixerWarning;
    }
  }

  static DateTime? _latestDueIncomeOccurrence(
    IncomeModel income, {
    required DateTime now,
  }) {
    if (income.type != 'FREQUENTLY') {
      return null;
    }

    final interval = income.recurrenceInterval ?? 1;
    if (interval < 1) {
      return null;
    }

    final start = DateUtils.dateOnly(income.startDate);
    final today = DateUtils.dateOnly(now);
    if (today.isBefore(start)) {
      return null;
    }

    switch (income.recurrenceUnit ?? 'WEEKS') {
      case 'DAYS':
        final elapsedDays = today.difference(start).inDays;
        final cycle = elapsedDays ~/ interval;
        if (cycle < 1) {
          return null;
        }
        return start.add(Duration(days: cycle * interval));
      case 'WEEKS':
        final cycleDays = interval * 7;
        final elapsedDays = today.difference(start).inDays;
        final cycle = elapsedDays ~/ cycleDays;
        if (cycle < 1) {
          return null;
        }
        return start.add(Duration(days: cycle * cycleDays));
      case 'MONTHS':
        final rawMonths =
            (today.year - start.year) * 12 + (today.month - start.month);
        var elapsedMonths = rawMonths;
        if (today.day < start.day) {
          elapsedMonths--;
        }
        if (elapsedMonths < interval) {
          return null;
        }
        final cycle = elapsedMonths ~/ interval;
        return _addMonths(start, cycle * interval);
      default:
        return null;
    }
  }

  static DateTime _addMonths(DateTime date, int monthsToAdd) {
    final targetMonth = date.month + monthsToAdd;
    final year = date.year + ((targetMonth - 1) ~/ 12);
    final month = ((targetMonth - 1) % 12) + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = math.min(date.day, lastDayOfMonth);
    return DateTime(year, month, day);
  }

  static Future<void> notifyGoalCreated(GoalModel goal) async {
    if (_currentUserId < 0) {
      return;
    }

    final signalId = _goalSignalId(goal, 'created');
    final prefs = await SharedPreferences.getInstance();
    final trackedSignals = {
      ...(prefs.getStringList(_trackedSignalIdsKey) ?? const <String>[]),
    };
    if (trackedSignals.contains(signalId)) {
      return;
    }

    trackedSignals.add(signalId);
    await prefs.setStringList(
      _trackedSignalIdsKey,
      trackedSignals.toList(growable: false),
    );
    await _upsertNotification(
      _buildGoalCreatedNotification(goal, now: DateTime.now()),
      notifySystem: true,
    );
  }

  static Future<void> notifyIncomeCreated(IncomeModel income) async {
    if (_currentUserId < 0) {
      return;
    }

    final signalId = _incomeSignalId(income, 'created');
    final prefs = await SharedPreferences.getInstance();
    final trackedSignals = {
      ...(prefs.getStringList(_trackedSignalIdsKey) ?? const <String>[]),
    };
    if (trackedSignals.contains(signalId)) {
      return;
    }

    trackedSignals.add(signalId);
    await prefs.setStringList(
      _trackedSignalIdsKey,
      trackedSignals.toList(growable: false),
    );
    await _upsertNotification(
      _buildIncomeCreatedNotification(income, now: DateTime.now()),
      notifySystem: true,
    );
  }

  static Future<void> deliverNotification(
    AppNotificationModel notification, {
    bool notifySystem = true,
  }) async {
    if (_currentUserId < 0 || notification.userId != _currentUserId) {
      return;
    }

    await _upsertNotification(notification, notifySystem: notifySystem);
  }

  static Future<void> _upsertNotification(
    AppNotificationModel incomingNotification, {
    required bool notifySystem,
  }) async {
    final storedNotification = _findStoredNotification(incomingNotification.id);
    if (storedNotification == null) {
      await LocalStorageService.notificationBox.add(incomingNotification);
    } else {
      storedNotification
        ..type = incomingNotification.type
        ..createdAt = incomingNotification.createdAt
        ..title = incomingNotification.title
        ..subtitle = incomingNotification.subtitle
        ..amount = incomingNotification.amount
        ..detailTitle = incomingNotification.detailTitle
        ..detailMessage = incomingNotification.detailMessage
        ..category = incomingNotification.category
        ..routeName = incomingNotification.routeName
        ..routeArgumentInt = incomingNotification.routeArgumentInt;
      await storedNotification.save();
    }

    if (!notifySystem) {
      return;
    }

    await LocalNotificationService.showTrackedNotification(
      incomingNotification,
    );
  }

  static AppNotificationModel? _findStoredNotification(String id) {
    for (final notification in LocalStorageService.notificationBox.values) {
      if (notification.id == id && notification.userId == _currentUserId) {
        return notification;
      }
    }

    return null;
  }
}
