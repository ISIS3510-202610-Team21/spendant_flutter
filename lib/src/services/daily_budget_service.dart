import 'package:flutter/material.dart';

import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import 'expense_moment_service.dart';
import 'local_storage_service.dart';

class GoalComputedState {
  const GoalComputedState({
    required this.goal,
    required this.baselineAmount,
    required this.currentAmount,
    required this.dailyContribution,
    required this.isCompleted,
  });

  final GoalModel goal;
  final double baselineAmount;
  final double currentAmount;
  final double dailyContribution;
  final bool isCompleted;

  double get progress => goal.targetAmount <= 0
      ? 0
      : (currentAmount / goal.targetAmount).clamp(0.0, 1.0).toDouble();

  int get progressPercent => (progress * 100).round().clamp(0, 100).toInt();
}

class DailyBudgetSummary {
  const DailyBudgetSummary({
    required this.incomes,
    required this.goals,
    required this.goalStates,
    required this.todayExpenses,
    required this.internalDailyBudget,
    required this.totalGoalDailyCommitment,
    required this.spendableDailyBudget,
    required this.remainingInternalBudget,
    required this.remainingSpendableBudget,
  });

  final List<IncomeModel> incomes;
  final List<GoalModel> goals;
  final List<GoalComputedState> goalStates;
  final double todayExpenses;
  final double internalDailyBudget;
  final double totalGoalDailyCommitment;
  final double spendableDailyBudget;
  final double remainingInternalBudget;
  final double remainingSpendableBudget;

  double get totalDailyIncome => internalDailyBudget;
  bool get hasIncome => incomes.isNotEmpty && internalDailyBudget > 0;
  bool get hasGoals => goals.isNotEmpty;
  bool get isSpendableBudgetExhausted => remainingSpendableBudget < 0;
  bool get isInternalBudgetExhausted => remainingInternalBudget <= 0;
  double get goalHeadroom => internalDailyBudget - totalGoalDailyCommitment;

  GoalComputedState? stateFor(GoalModel goal) {
    for (final state in goalStates) {
      if (DailyBudgetService.sameGoal(state.goal, goal)) {
        return state;
      }
    }

    return null;
  }
}

class GoalBudgetValidationResult {
  const GoalBudgetValidationResult({
    required this.hasIncome,
    required this.dailyGoalAmount,
    required this.currentGoalDailyCommitment,
    required this.projectedGoalDailyCommitment,
    required this.availableInternalDailyBudget,
    required this.goalFitsOnItsOwn,
    required this.goalFitsWithAllGoals,
  });

  final bool hasIncome;
  final double dailyGoalAmount;
  final double currentGoalDailyCommitment;
  final double projectedGoalDailyCommitment;
  final double availableInternalDailyBudget;
  final bool goalFitsOnItsOwn;
  final bool goalFitsWithAllGoals;

  bool get canCreateGoal =>
      hasIncome && goalFitsOnItsOwn && goalFitsWithAllGoals;
}

abstract final class DailyBudgetService {
  static const int _justOnceIncomeSpreadDays = 120;
  static const double _epsilon = 0.0001;

  static DailyBudgetSummary buildSummaryForUser(int userId, {DateTime? now}) {
    final currentMoment = now ?? DateTime.now();
    final today = DateUtils.dateOnly(currentMoment);

    final incomes =
        LocalStorageService.incomeBox.values
            .where((income) => income.userId == userId)
            .toList()
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    final goals =
        LocalStorageService.goalBox.values
            .where((goal) => goal.userId == userId)
            .toList()
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

    final expenses = LocalStorageService.expenseBox.values
        .where(
          (expense) =>
              expense.userId == userId &&
              !ExpenseMomentService.isFutureExpense(
                expense,
                now: currentMoment,
              ),
        )
        .toList();

    final goalStates = buildGoalStates(
      goals: goals,
      incomes: incomes,
      expenses: expenses,
      now: currentMoment,
    );
    final internalDailyBudget = incomes.fold<double>(
      0,
      (total, income) => total + dailyIncomeContribution(income, onDay: today),
    );
    final totalGoalDailyCommitment = goalStates.fold<double>(
      0,
      (total, state) => total + state.dailyContribution,
    );
    final todayExpensesTotal = expenses.fold<double>(0, (total, expense) {
      final expenseDay = DateUtils.dateOnly(expense.date);
      if (!DateUtils.isSameDay(expenseDay, today)) {
        return total;
      }
      return total + expense.amount;
    });
    final spendableDailyBudget =
        (internalDailyBudget - totalGoalDailyCommitment)
            .clamp(0.0, double.infinity)
            .toDouble();

    return DailyBudgetSummary(
      incomes: incomes,
      goals: goals,
      goalStates: goalStates,
      todayExpenses: todayExpensesTotal,
      internalDailyBudget: internalDailyBudget,
      totalGoalDailyCommitment: totalGoalDailyCommitment,
      spendableDailyBudget: spendableDailyBudget,
      remainingInternalBudget: internalDailyBudget - todayExpensesTotal,
      remainingSpendableBudget: spendableDailyBudget - todayExpensesTotal,
    );
  }

  static GoalBudgetValidationResult validateNewGoal({
    required int userId,
    required double targetAmount,
    required double currentAmount,
    required DateTime deadline,
    DateTime? now,
  }) {
    final currentMoment = now ?? DateTime.now();
    final today = DateUtils.dateOnly(currentMoment);
    final summary = buildSummaryForUser(userId, now: today);
    final dailyGoalAmount = projectedGoalDailyContribution(
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      deadline: deadline,
      today: today,
    );
    final projectedGoalDailyCommitment =
        summary.totalGoalDailyCommitment + dailyGoalAmount;
    final goalFitsOnItsOwn =
        dailyGoalAmount <= summary.internalDailyBudget + 0.0001;
    final goalFitsWithAllGoals =
        projectedGoalDailyCommitment <= summary.internalDailyBudget + 0.0001;

    return GoalBudgetValidationResult(
      hasIncome: summary.hasIncome,
      dailyGoalAmount: dailyGoalAmount,
      currentGoalDailyCommitment: summary.totalGoalDailyCommitment,
      projectedGoalDailyCommitment: projectedGoalDailyCommitment,
      availableInternalDailyBudget: summary.internalDailyBudget,
      goalFitsOnItsOwn: goalFitsOnItsOwn,
      goalFitsWithAllGoals: goalFitsWithAllGoals,
    );
  }

  static double dailyIncomeContribution(IncomeModel income, {DateTime? onDay}) {
    final day = DateUtils.dateOnly(onDay ?? DateTime.now());
    final startDay = DateUtils.dateOnly(income.startDate);

    if (startDay.isAfter(day)) {
      return 0;
    }

    if (income.type == 'JUST_ONCE') {
      final elapsedDays = day.difference(startDay).inDays;
      if (elapsedDays >= _justOnceIncomeSpreadDays) {
        return 0;
      }
      return income.amount / _justOnceIncomeSpreadDays;
    }

    final interval = income.recurrenceInterval ?? 1;
    final normalizedInterval = interval < 1 ? 1 : interval;
    final daysPerCycle = switch (income.recurrenceUnit) {
      'DAYS' => normalizedInterval.toDouble(),
      'WEEKS' => normalizedInterval * 7.0,
      'MONTHS' => normalizedInterval * 30.0,
      _ => normalizedInterval * 30.0,
    };

    return income.amount / daysPerCycle;
  }

  static double dailyGoalContribution(GoalModel goal, {DateTime? today}) {
    final currentDay = DateUtils.dateOnly(today ?? DateTime.now());
    if (DateUtils.dateOnly(goal.createdAt).isAfter(currentDay) ||
        DateUtils.dateOnly(goal.deadline).isBefore(currentDay) ||
        _goalBaselineAmount(goal) + _epsilon >= goal.targetAmount ||
        goal.isCompleted) {
      return 0;
    }

    return projectedGoalDailyContribution(
      targetAmount: goal.targetAmount,
      currentAmount: _goalBaselineAmount(goal),
      deadline: goal.deadline,
      isCompleted: goal.isCompleted,
      today: currentDay,
    );
  }

  static double projectedGoalDailyContribution({
    required double targetAmount,
    required double currentAmount,
    required DateTime deadline,
    bool isCompleted = false,
    DateTime? today,
  }) {
    if (isCompleted) {
      return 0;
    }

    final remainingAmount = targetAmount - currentAmount;
    if (remainingAmount <= 0) {
      return 0;
    }

    final currentDay = DateUtils.dateOnly(today ?? DateTime.now());
    final deadlineDay = DateUtils.dateOnly(deadline);
    final daysLeft = deadlineDay.difference(currentDay).inDays;

    if (daysLeft <= 0) {
      return remainingAmount;
    }

    return remainingAmount / daysLeft;
  }

  static List<GoalComputedState> buildGoalStatesForUser(
    int userId, {
    DateTime? now,
  }) {
    final currentMoment = now ?? DateTime.now();

    final incomes = LocalStorageService.incomeBox.values
        .where((income) => income.userId == userId)
        .toList();
    final goals = LocalStorageService.goalBox.values
        .where((goal) => goal.userId == userId)
        .toList();
    final expenses = LocalStorageService.expenseBox.values
        .where(
          (expense) =>
              expense.userId == userId &&
              !ExpenseMomentService.isFutureExpense(
                expense,
                now: currentMoment,
              ),
        )
        .toList();

    return buildGoalStates(
      goals: goals,
      incomes: incomes,
      expenses: expenses,
      now: currentMoment,
    );
  }

  static List<GoalComputedState> buildGoalStates({
    required Iterable<GoalModel> goals,
    required Iterable<IncomeModel> incomes,
    required Iterable<ExpenseModel> expenses,
    DateTime? now,
  }) {
    final currentMoment = now ?? DateTime.now();
    final today = DateUtils.dateOnly(currentMoment);
    final orderedGoals = goals.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (orderedGoals.isEmpty) {
      return const <GoalComputedState>[];
    }

    final currentAmounts = <GoalModel, double>{
      for (final goal in orderedGoals) goal: _goalBaselineAmount(goal),
    };
    final expensesByDay = <DateTime, double>{};
    for (final expense in expenses) {
      final expenseDay = DateUtils.dateOnly(expense.date);
      if (!expenseDay.isBefore(today)) {
        continue;
      }
      expensesByDay.update(
        expenseDay,
        (current) => current + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }

    final earliestPlanDay = orderedGoals
        .map((goal) => DateUtils.dateOnly(goal.createdAt))
        .reduce(_earliestDay);
    for (
      var dayCursor = earliestPlanDay;
      dayCursor.isBefore(today);
      dayCursor = dayCursor.add(const Duration(days: 1))
    ) {
      final activeGoals = orderedGoals.where((goal) {
        final currentAmount = currentAmounts[goal] ?? 0;
        if (currentAmount + _epsilon >= goal.targetAmount) {
          return false;
        }

        final planStart = DateUtils.dateOnly(goal.createdAt);
        final deadline = DateUtils.dateOnly(goal.deadline);
        return !planStart.isAfter(dayCursor) && !deadline.isBefore(dayCursor);
      }).toList();
      if (activeGoals.isEmpty) {
        continue;
      }

      final totalDailyIncome = incomes.fold<double>(
        0,
        (total, income) =>
            total + dailyIncomeContribution(income, onDay: dayCursor),
      );
      final expensesForDay = expensesByDay[dayCursor] ?? 0;
      final availableForGoals = (totalDailyIncome - expensesForDay)
          .clamp(0.0, double.infinity)
          .toDouble();
      if (availableForGoals <= _epsilon) {
        continue;
      }

      final goalTargets = <GoalModel, double>{
        for (final goal in activeGoals)
          goal: _plannedGoalDailyContribution(goal),
      };
      final totalGoalTargets = goalTargets.values.fold<double>(
        0,
        (total, target) => total + target,
      );
      if (totalGoalTargets <= _epsilon) {
        continue;
      }

      final contributionFactor = availableForGoals >= totalGoalTargets
          ? 1.0
          : availableForGoals / totalGoalTargets;
      for (final goal in activeGoals) {
        final targetContribution = goalTargets[goal] ?? 0;
        if (targetContribution <= _epsilon) {
          continue;
        }

        final currentAmount = currentAmounts[goal] ?? 0;
        final remainingAmount = goal.targetAmount - currentAmount;
        if (remainingAmount <= _epsilon) {
          continue;
        }

        final contributedAmount = (targetContribution * contributionFactor)
            .clamp(0.0, remainingAmount)
            .toDouble();
        currentAmounts[goal] = currentAmount + contributedAmount;
      }
    }

    return orderedGoals
        .map((goal) {
          final currentAmount =
              (currentAmounts[goal] ?? _goalBaselineAmount(goal))
                  .clamp(0.0, goal.targetAmount)
                  .toDouble();
          final plannedDailyContribution = _plannedGoalDailyContribution(goal);
          final isCompleted = currentAmount + _epsilon >= goal.targetAmount;
          final isActiveToday =
              !goal.isCompleted &&
              !isCompleted &&
              !DateUtils.dateOnly(goal.createdAt).isAfter(today) &&
              !DateUtils.dateOnly(goal.deadline).isBefore(today) &&
              plannedDailyContribution > _epsilon;

          // Use remaining-days contribution so the displayed daily reserve
          // reflects how much must be saved per day from TODAY, not from the
          // original creation date. This prevents stale goals from showing an
          // artificially low daily saving (e.g. 500 instead of 2,000).
          final todayDailyContribution = isActiveToday
              ? projectedGoalDailyContribution(
                  targetAmount: goal.targetAmount,
                  currentAmount: currentAmount,
                  deadline: goal.deadline,
                  isCompleted: isCompleted,
                  today: today,
                )
              : 0.0;

          return GoalComputedState(
            goal: goal,
            baselineAmount: _goalBaselineAmount(goal),
            currentAmount: currentAmount,
            dailyContribution: todayDailyContribution,
            isCompleted: isCompleted,
          );
        })
        .toList(growable: false);
  }

  static bool sameGoal(GoalModel left, GoalModel right) {
    if (identical(left, right)) {
      return true;
    }

    final leftServerId = left.serverId;
    final rightServerId = right.serverId;
    if (leftServerId != null &&
        rightServerId != null &&
        leftServerId.isNotEmpty &&
        leftServerId == rightServerId) {
      return true;
    }

    final leftKey = left.key;
    final rightKey = right.key;
    if (leftKey != null && rightKey != null && leftKey == rightKey) {
      return true;
    }

    return left.createdAt == right.createdAt &&
        left.name == right.name &&
        left.targetAmount == right.targetAmount;
  }

  static double _goalBaselineAmount(GoalModel goal) {
    return goal.currentAmount.clamp(0.0, goal.targetAmount).toDouble();
  }

  static double _plannedGoalDailyContribution(GoalModel goal) {
    if (goal.isCompleted) {
      return 0;
    }

    final baselineAmount = _goalBaselineAmount(goal);
    final remainingAmount = goal.targetAmount - baselineAmount;
    if (remainingAmount <= _epsilon) {
      return 0;
    }

    final startDay = DateUtils.dateOnly(goal.createdAt);
    final deadlineDay = DateUtils.dateOnly(goal.deadline);
    final totalDays = deadlineDay.difference(startDay).inDays;
    if (totalDays <= 0) {
      return remainingAmount;
    }

    return remainingAmount / totalDays;
  }

  static DateTime _earliestDay(DateTime left, DateTime right) {
    return left.isBefore(right) ? left : right;
  }
}
