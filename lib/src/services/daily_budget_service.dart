import 'package:flutter/material.dart';

import '../models/goal_model.dart';
import '../models/income_model.dart';
import 'local_storage_service.dart';

class DailyBudgetSummary {
  const DailyBudgetSummary({
    required this.incomes,
    required this.goals,
    required this.todayExpenses,
    required this.internalDailyBudget,
    required this.totalGoalDailyCommitment,
    required this.spendableDailyBudget,
    required this.remainingInternalBudget,
    required this.remainingSpendableBudget,
  });

  final List<IncomeModel> incomes;
  final List<GoalModel> goals;
  final double todayExpenses;
  final double internalDailyBudget;
  final double totalGoalDailyCommitment;
  final double spendableDailyBudget;
  final double remainingInternalBudget;
  final double remainingSpendableBudget;

  double get totalDailyIncome => internalDailyBudget;
  bool get hasIncome => incomes.isNotEmpty && internalDailyBudget > 0;
  bool get hasGoals => goals.isNotEmpty;
  bool get isSpendableBudgetExhausted => remainingSpendableBudget <= 0;
  bool get isInternalBudgetExhausted => remainingInternalBudget <= 0;
  double get goalHeadroom => internalDailyBudget - totalGoalDailyCommitment;
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
              DateUtils.isSameDay(DateUtils.dateOnly(expense.date), today),
        )
        .toList();

    final internalDailyBudget = incomes.fold<double>(
      0,
      (total, income) => total + dailyIncomeContribution(income, onDay: today),
    );
    final totalGoalDailyCommitment = goals.fold<double>(
      0,
      (total, goal) => total + dailyGoalContribution(goal, today: today),
    );
    final todayExpensesTotal = expenses.fold<double>(
      0,
      (total, expense) => total + expense.amount,
    );
    final spendableDailyBudget = internalDailyBudget - totalGoalDailyCommitment;

    return DailyBudgetSummary(
      incomes: incomes,
      goals: goals,
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
      return DateUtils.isSameDay(startDay, day) ? income.amount : 0;
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
    return projectedGoalDailyContribution(
      targetAmount: goal.targetAmount,
      currentAmount: goal.currentAmount,
      deadline: goal.deadline,
      isCompleted: goal.isCompleted,
      today: today,
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
}
