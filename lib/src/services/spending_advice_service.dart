import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import 'app_time_format_service.dart';

enum SpendingAdviceKind {
  expenseSpike,
  categoryAcceleration,
  habitCluster,
  regretHotspot,
}

class SpendingAdvice {
  const SpendingAdvice({
    required this.signalId,
    required this.notificationId,
    required this.kind,
    required this.detectedAt,
    required this.title,
    required this.detailTitle,
    required this.detailMessage,
    this.subtitle,
    this.amount,
    this.category,
  });

  final String signalId;
  final String notificationId;
  final SpendingAdviceKind kind;
  final DateTime detectedAt;
  final String title;
  final String detailTitle;
  final String detailMessage;
  final String? subtitle;
  final double? amount;
  final String? category;
}

abstract final class SpendingAdviceService {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static const Map<String, String> _detailLabelPrimaryCategories =
      <String, String>{
        'Food': 'Food',
        'Food Delivery': 'Food',
        'Groceries': 'Food',
        'Commute': 'Transport',
        'Transport': 'Transport',
        'Learning Materials': 'Services',
        'University Fees': 'Services',
        'Personal Care': 'Services',
        'Rent': 'Services',
        'Services': 'Services',
        'Utilities': 'Services',
        'Entertainment': 'Other',
        'Gifts': 'Other',
        'Group Hangouts': 'Other',
        'Subscriptions': 'Other',
        'Emergency': 'Other',
        'Impulse': 'Other',
        'Owed': 'Other',
      };

  static const Map<String, String> _habitTitles = <String, String>{
    'Impulse': 'Impulse purchases are stacking up',
    'Food Delivery': 'Food delivery is becoming a weekly habit',
    'Entertainment': 'Entertainment spending is clustering',
    'Group Hangouts': 'Group hangouts are piling up',
  };

  static List<SpendingAdvice> buildInsights({
    required Iterable<ExpenseModel> expenses,
    DateTime? now,
  }) {
    final referenceNow = now ?? DateTime.now();
    final orderedExpenses =
        expenses
            .where((expense) => expense.amount > 0)
            .where((expense) => !_expenseMoment(expense).isAfter(referenceNow))
            .toList()
          ..sort(
            (left, right) =>
                _expenseMoment(left).compareTo(_expenseMoment(right)),
          );

    final insights = <SpendingAdvice>[
      ..._buildExpenseSpikeInsights(orderedExpenses),
      ..._buildCategoryAccelerationInsights(orderedExpenses),
      ..._buildHabitClusterInsights(orderedExpenses),
    ]..sort((left, right) => right.detectedAt.compareTo(left.detectedAt));

    return insights;
  }

  static Set<String> collectSatisfiedSignalIds({
    required Iterable<ExpenseModel> expenses,
    DateTime? now,
  }) {
    return buildInsights(
      expenses: expenses,
      now: now,
    ).map((advice) => advice.signalId).toSet();
  }

  static List<SpendingAdvice> _buildExpenseSpikeInsights(
    List<ExpenseModel> expenses,
  ) {
    final insights = <SpendingAdvice>[];

    for (var index = 0; index < expenses.length; index++) {
      final expense = expenses[index];
      if (expense.amount < 35000) {
        continue;
      }

      final category = _normalizedCategoryForExpense(expense);
      final comparableHistory = _selectComparisonHistory(
        expense,
        expenses.take(index),
      );
      if (comparableHistory == null || comparableHistory.expenses.length < 3) {
        continue;
      }

      final amounts =
          comparableHistory.expenses
              .map((candidate) => candidate.amount)
              .toList()
            ..sort();
      final median = _median(amounts);
      final upperQuartile = _percentile(amounts, 0.75);
      final threshold = math.max(
        math.max(median * 1.85, upperQuartile * 1.45),
        median + 20000,
      );

      if (expense.amount < threshold || (expense.amount - median) < 15000) {
        continue;
      }

      final delta = expense.amount - median;
      insights.add(
        SpendingAdvice(
          signalId: 'advice:spike:${_expenseIdentity(expense)}',
          notificationId: 'advice-spike-${_expenseIdentity(expense)}',
          kind: SpendingAdviceKind.expenseSpike,
          detectedAt: _expenseMoment(expense),
          title: 'Unusual ${comparableHistory.label} expense',
          subtitle: expense.name,
          amount: expense.amount,
          category: category,
          detailTitle:
              'This looks higher than your usual ${comparableHistory.label} spending',
          detailMessage:
              '${expense.name} was ${_formatMoney(expense.amount)}. Your typical ${comparableHistory.label} expense is around ${_formatMoney(median)}, so this landed ${_formatMoney(delta)} above your normal pattern.',
        ),
      );
    }

    return insights;
  }

  static List<SpendingAdvice> _buildCategoryAccelerationInsights(
    List<ExpenseModel> expenses,
  ) {
    final insights = <SpendingAdvice>[];
    final emittedSignalIds = <String>{};

    for (final expense in expenses) {
      final expenseMoment = _expenseMoment(expense);
      final category = _normalizedCategoryForExpense(expense);
      final currentMonthExpenses = expenses.where((candidate) {
        final candidateMoment = _expenseMoment(candidate);
        return candidateMoment.year == expenseMoment.year &&
            candidateMoment.month == expenseMoment.month &&
            _normalizedCategoryForExpense(candidate) == category &&
            !candidateMoment.isAfter(expenseMoment);
      }).toList();

      if (currentMonthExpenses.length < 3) {
        continue;
      }

      final baselineTotals = <double>[];
      for (var offset = 1; offset <= 3; offset++) {
        final previousMonth = _addMonths(
          DateTime(expenseMoment.year, expenseMoment.month, 1),
          -offset,
        );
        final previousMonthTotal = expenses
            .where((candidate) {
              final candidateMoment = _expenseMoment(candidate);
              return candidateMoment.year == previousMonth.year &&
                  candidateMoment.month == previousMonth.month &&
                  _normalizedCategoryForExpense(candidate) == category &&
                  _isWithinComparableMonthCutoff(
                    candidateMoment,
                    expenseMoment,
                  );
            })
            .fold<double>(0, (sum, candidate) => sum + candidate.amount);
        if (previousMonthTotal > 0) {
          baselineTotals.add(previousMonthTotal);
        }
      }

      if (baselineTotals.length < 2) {
        continue;
      }

      final currentTotal = currentMonthExpenses.fold<double>(
        0,
        (sum, candidate) => sum + candidate.amount,
      );
      final baselineAverage =
          baselineTotals.reduce((sum, amount) => sum + amount) /
          baselineTotals.length;
      final overshoot = currentTotal - baselineAverage;
      if (currentTotal < baselineAverage * 1.55 || overshoot < 30000) {
        continue;
      }

      final signalId =
          'advice:pace:${_slugify(category)}:${_monthKey(expenseMoment)}';
      if (!emittedSignalIds.add(signalId)) {
        continue;
      }

      insights.add(
        SpendingAdvice(
          signalId: signalId,
          notificationId:
              'advice-pace-${_slugify(category)}-${_monthKey(expenseMoment)}',
          kind: SpendingAdviceKind.categoryAcceleration,
          detectedAt: expenseMoment,
          title: '$category spending is moving too fast',
          subtitle: '$category this month',
          amount: currentTotal,
          category: category,
          detailTitle: 'You are spending faster than usual in $category',
          detailMessage:
              'By ${_dayMonthLabel(expenseMoment)} you already spent ${_formatMoney(currentTotal)} on $category. Your normal pace for this point in the month is about ${_formatMoney(baselineAverage)}.',
        ),
      );
    }

    return insights;
  }

  static List<SpendingAdvice> _buildHabitClusterInsights(
    List<ExpenseModel> expenses,
  ) {
    final insights = <SpendingAdvice>[];
    final emittedSignalIds = <String>{};

    for (final expense in expenses) {
      final expenseMoment = _expenseMoment(expense);
      final expenseDay = _dateOnly(expenseMoment);
      final recentWindowStart = expenseDay.subtract(const Duration(days: 6));
      final priorWindowStart = recentWindowStart.subtract(
        const Duration(days: 28),
      );

      for (final label in expense.detailLabels.toSet()) {
        final title = _habitTitles[label];
        if (title == null) {
          continue;
        }

        final recentMatches = expenses.where((candidate) {
          final candidateMoment = _expenseMoment(candidate);
          final candidateDay = _dateOnly(_expenseMoment(candidate));
          return !candidateDay.isBefore(recentWindowStart) &&
              !candidateDay.isAfter(expenseDay) &&
              !candidateMoment.isAfter(expenseMoment) &&
              candidate.detailLabels.contains(label);
        }).toList();

        if (recentMatches.length < 3) {
          continue;
        }

        final recentTotal = recentMatches.fold<double>(
          0,
          (sum, candidate) => sum + candidate.amount,
        );
        if (recentTotal < 40000) {
          continue;
        }

        final priorMatches = expenses.where((candidate) {
          final candidateDay = _dateOnly(_expenseMoment(candidate));
          return !candidateDay.isBefore(priorWindowStart) &&
              candidateDay.isBefore(recentWindowStart) &&
              candidate.detailLabels.contains(label);
        }).toList();
        final priorWeeklyAverage = priorMatches.length / 4;
        if (priorMatches.isNotEmpty &&
            recentMatches.length <
                math.max(3, (priorWeeklyAverage * 2.2).ceil())) {
          continue;
        }

        final signalId =
            'advice:habit:${_slugify(label)}:${_dayKey(_startOfWeek(expenseMoment))}';
        if (!emittedSignalIds.add(signalId)) {
          continue;
        }

        final category = _primaryCategoryForLabel(label);
        insights.add(
          SpendingAdvice(
            signalId: signalId,
            notificationId:
                'advice-habit-${_slugify(label)}-${_dayKey(_startOfWeek(expenseMoment))}',
            kind: SpendingAdviceKind.habitCluster,
            detectedAt: expenseMoment,
            title: title,
            subtitle: '$label in the last 7 days',
            amount: recentTotal,
            category: category,
            detailTitle: 'A new $label pattern showed up this week',
            detailMessage:
                'You logged ${recentMatches.length} $label expenses in the last 7 days for ${_formatMoney(recentTotal)}. Your previous four weeks averaged ${priorWeeklyAverage.toStringAsFixed(1)} per week.',
          ),
        );
      }
    }

    return insights;
  }

  static _ComparisonHistory? _selectComparisonHistory(
    ExpenseModel expense,
    Iterable<ExpenseModel> previousExpenses,
  ) {
    final expenseMoment = _expenseMoment(expense);
    final category = _normalizedCategoryForExpense(expense);
    final segment = _comparisonSegment(expense);

    var comparableExpenses = previousExpenses.where((candidate) {
      return _comparisonSegment(candidate) == segment &&
          expenseMoment.difference(_expenseMoment(candidate)).inDays <= 90;
    }).toList();
    if (comparableExpenses.length >= 3) {
      return _ComparisonHistory(label: segment, expenses: comparableExpenses);
    }

    if (segment == category) {
      return null;
    }

    comparableExpenses = previousExpenses.where((candidate) {
      return _normalizedCategoryForExpense(candidate) == category &&
          expenseMoment.difference(_expenseMoment(candidate)).inDays <= 90;
    }).toList();
    if (comparableExpenses.length < 3) {
      return null;
    }

    return _ComparisonHistory(label: category, expenses: comparableExpenses);
  }

  static String _comparisonSegment(ExpenseModel expense) {
    for (final label in expense.detailLabels) {
      final trimmed = label.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return _normalizedCategoryForExpense(expense);
  }

  static String _normalizedCategoryForExpense(ExpenseModel expense) {
    final primaryCategory = expense.primaryCategory?.trim();
    if (primaryCategory != null && primaryCategory.isNotEmpty) {
      return _normalizeCategory(primaryCategory);
    }

    for (final label in expense.detailLabels) {
      final derivedCategory = _detailLabelPrimaryCategories[label.trim()];
      if (derivedCategory != null) {
        return derivedCategory;
      }
    }

    return 'Other';
  }

  static String _normalizeCategory(String category) {
    switch (category) {
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

  static String _primaryCategoryForLabel(String label) {
    return _detailLabelPrimaryCategories[label.trim()] ?? 'Other';
  }

  static String _formatMoney(double amount) {
    return 'COP ${_currencyFormat.format(amount.round())}';
  }

  static double _median(List<double> sortedValues) {
    if (sortedValues.isEmpty) {
      return 0;
    }

    final middle = sortedValues.length ~/ 2;
    if (sortedValues.length.isOdd) {
      return sortedValues[middle];
    }

    return (sortedValues[middle - 1] + sortedValues[middle]) / 2;
  }

  static double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) {
      return 0;
    }

    final constrainedPercentile = percentile.clamp(0, 1);
    final position = (sortedValues.length - 1) * constrainedPercentile;
    final lowerIndex = position.floor();
    final upperIndex = position.ceil();
    if (lowerIndex == upperIndex) {
      return sortedValues[lowerIndex];
    }

    final fraction = position - lowerIndex;
    return sortedValues[lowerIndex] +
        (sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction;
  }

  static DateTime _expenseMoment(ExpenseModel expense) {
    final parsedTime = _parseTime(expense.time);
    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      parsedTime.$1,
      parsedTime.$2,
    );
  }

  static (int, int) _parseTime(String value) {
    final parsed = AppTimeFormatService.parseHourMinute(value);
    return (parsed.hour.clamp(0, 23), parsed.minute.clamp(0, 59));
  }

  static bool _isWithinComparableMonthCutoff(
    DateTime candidate,
    DateTime cutoff,
  ) {
    final candidateMinutes = _minutesSinceMidnight(candidate);
    final cutoffMinutes = _minutesSinceMidnight(cutoff);

    return candidate.day < cutoff.day ||
        (candidate.day == cutoff.day && candidateMinutes <= cutoffMinutes);
  }

  static int _minutesSinceMidnight(DateTime value) {
    return value.hour * 60 + value.minute;
  }

  static DateTime _startOfWeek(DateTime value) {
    final day = _dateOnly(value);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _expenseIdentity(ExpenseModel expense) {
    final key = expense.serverId ?? expense.key?.toString();
    if (key != null && key.isNotEmpty) {
      return key;
    }

    return expense.createdAt.microsecondsSinceEpoch.toString();
  }

  static String _slugify(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  static String _monthKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    return '${value.year}-$month';
  }

  static String _dayKey(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _dayMonthLabel(DateTime value) {
    return '${value.day}/${value.month}';
  }

  static DateTime _addMonths(DateTime value, int monthsToAdd) {
    final targetMonth = value.month + monthsToAdd;
    final year = value.year + ((targetMonth - 1) ~/ 12);
    final month = ((targetMonth - 1) % 12) + 1;
    return DateTime(year, month, 1);
  }
}

class _ComparisonHistory {
  const _ComparisonHistory({required this.label, required this.expenses});

  final String label;
  final List<ExpenseModel> expenses;
}
