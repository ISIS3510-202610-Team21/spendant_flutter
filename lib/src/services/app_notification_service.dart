import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import 'auth_memory_store.dart';
import 'daily_budget_service.dart';
import 'local_notification_service.dart';
import 'local_storage_service.dart';

abstract final class AppNotificationService {
  static const String _bootstrapKeyPrefix = 'app_notification_bootstrap_v1';
  static const String _trackedSignalIdsKeyPrefix =
      'app_notification_tracked_signal_ids_v1';
  static const String _goalRouteName = '/set-goal';
  static const String _budgetRouteName = '/budget';

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
    final goals = LocalStorageService.goalBox.values
        .where((goal) => goal.userId == _currentUserId)
        .toList();
    final incomes = LocalStorageService.incomeBox.values
        .where((income) => income.userId == _currentUserId)
        .toList();

    for (final goal in goals) {
      final halfwaySignalId = _goalSignalId(goal, '50');
      if (_goalProgress(goal) >= 0.5 &&
          !trackedSignals.contains(halfwaySignalId)) {
        trackedSignals.add(halfwaySignalId);
        shouldPersistTrackedSignals = true;
        await _upsertNotification(
          _buildGoalHalfwayNotification(goal, now: now),
          notifySystem: true,
        );
      }

      final completedSignalId = _goalSignalId(goal, '100');
      if (_goalProgress(goal) >= 1 &&
          !trackedSignals.contains(completedSignalId)) {
        trackedSignals.add(completedSignalId);
        shouldPersistTrackedSignals = true;
        await _upsertNotification(
          _buildGoalAchievedNotification(goal, now: now),
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

    final goals = LocalStorageService.goalBox.values.where(
      (goal) => goal.userId == _currentUserId,
    );
    final incomes = LocalStorageService.incomeBox.values.where(
      (income) => income.userId == _currentUserId,
    );
    for (final goal in goals) {
      final progress = _goalProgress(goal);
      if (progress >= 0.5) {
        trackedSignals.add(_goalSignalId(goal, '50'));
      }
      if (progress >= 1) {
        trackedSignals.add(_goalSignalId(goal, '100'));
      }
    }
    for (final income in incomes) {
      final dueOccurrence = _latestDueIncomeOccurrence(income, now: now);
      if (dueOccurrence != null) {
        trackedSignals.add(_incomeDueSignalId(income, dueOccurrence));
      }
    }

    final summary = DailyBudgetService.buildSummaryForUser(
      _currentUserId,
      now: now,
    );
    if (summary.isSpendableBudgetExhausted) {
      trackedSignals.add(_budgetSignalId(now));
    }

    return trackedSignals;
  }

  static double _goalProgress(GoalModel goal) {
    if (goal.targetAmount <= 0) {
      return 0;
    }

    return (goal.currentAmount / goal.targetAmount).clamp(0.0, 1.0);
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
    GoalModel goal, {
    required DateTime now,
  }) {
    return AppNotificationModel()
      ..id = _goalNotificationId(goal, '50')
      ..type = AppNotificationTypes.goalHalfway
      ..createdAt = now
      ..userId = _currentUserId
      ..title = 'Goal at 50%'
      ..subtitle = goal.name
      ..amount = goal.currentAmount
      ..detailTitle = 'Halfway there'
      ..detailMessage =
          'Your goal ${goal.name} already reached 50%. You have saved COP ${_currencyFormat.format(goal.currentAmount.round())} out of COP ${_currencyFormat.format(goal.targetAmount.round())}.'
      ..routeName = _goalRouteName
      ..routeArgumentInt = 1;
  }

  static AppNotificationModel _buildGoalAchievedNotification(
    GoalModel goal, {
    required DateTime now,
  }) {
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
          'Your recurring income ${income.name} reached its next cycle on ${DateFormat('d/M/y').format(dueOccurrence)}. Review Budget and Income to plan around it.'
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
