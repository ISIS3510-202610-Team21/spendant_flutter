import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/expense_model.dart';

class SpendingAnomalyInsight {
  const SpendingAnomalyInsight({
    required this.signalId,
    required this.notificationId,
    required this.analyzedDay,
    required this.anomalousAmount,
    required this.baselineMean,
    required this.threshold,
  });

  final String signalId;
  final String notificationId;
  final DateTime analyzedDay;
  final double anomalousAmount;
  final double baselineMean;
  final double threshold;
}

abstract final class SpendingAnomalyService {
  static const int _minimumHistoryDays = 5;

  // Total closed days we look back: 1 analyzed (yesterday) + 5 baseline days.
  static const int _lookbackDays = _minimumHistoryDays + 1;

  static SpendingAnomalyInsight? buildInsight({
    required Iterable<ExpenseModel> expenses,
    required DateTime now,
  }) {
    final todayStart = DateUtils.dateOnly(now);

    // Count distinct past calendar days that have at least one recorded
    // expense with a positive amount. Days with $0 provide no statistical
    // signal and must not count toward the grace period threshold.
    final distinctPastSpendingDays = expenses
        .where(
          (e) =>
              e.amount > 0 &&
              DateUtils.dateOnly(e.date).isBefore(todayStart),
        )
        .map((e) => DateUtils.dateOnly(e.date))
        .toSet()
        .length;

    if (distinctPastSpendingDays < _minimumHistoryDays) {
      return null;
    }

    // Build exactly _lookbackDays closed-day totals (yesterday … 6 days ago).
    // Today is never included (offset starts at 1).
    final closedDays = <_DailyExpenseTotal>[
      for (var offset = 1; offset <= _lookbackDays; offset++)
        _DailyExpenseTotal(
          dayStart: todayStart.subtract(Duration(days: offset)),
          totalExpense: _sumExpensesForDay(
            expenses,
            todayStart.subtract(Duration(days: offset)),
          ),
        ),
    ];
    assert(closedDays.length == _lookbackDays);

    final analyzedDay = closedDays.first; // yesterday
    final baseline = closedDays.skip(1).take(_minimumHistoryDays).toList();
    if (baseline.length < _minimumHistoryDays) {
      return null;
    }

    final stats = _calculateStats(baseline);
    if (stats == null) {
      return null;
    }
    if (analyzedDay.totalExpense <= stats.threshold) {
      return null;
    }

    final dayKey = _dayKey(analyzedDay.dayStart);
    return SpendingAnomalyInsight(
      signalId: 'spending-anomaly:$dayKey',
      notificationId: 'spending-anomaly-$dayKey',
      analyzedDay: analyzedDay.dayStart,
      anomalousAmount: analyzedDay.totalExpense,
      baselineMean: stats.mean,
      threshold: stats.threshold,
    );
  }


  static double _sumExpensesForDay(
    Iterable<ExpenseModel> expenses,
    DateTime dayStart,
  ) {
    var total = 0.0;
    for (final expense in expenses) {
      if (DateUtils.isSameDay(expense.date, dayStart)) {
        total += expense.amount;
      }
    }
    return total;
  }

  static _SpendingAnomalyStats? _calculateStats(
    List<_DailyExpenseTotal> baseline,
  ) {
    if (baseline.length < _minimumHistoryDays) {
      return null;
    }

    final values = baseline.map((entry) => entry.totalExpense).toList();
    final mean = values.reduce((left, right) => left + right) / values.length;
    final variance =
        values
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((left, right) => left + right) /
        values.length;
    final standardDeviation = math.sqrt(variance);

    return _SpendingAnomalyStats(
      mean: mean,
      threshold: mean + (2 * standardDeviation),
    );
  }

  static String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _DailyExpenseTotal {
  const _DailyExpenseTotal({
    required this.dayStart,
    required this.totalExpense,
  });

  final DateTime dayStart;
  final double totalExpense;
}

class _SpendingAnomalyStats {
  const _SpendingAnomalyStats({required this.mean, required this.threshold});

  final double mean;
  final double threshold;
}
