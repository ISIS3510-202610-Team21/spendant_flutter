import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import 'app_time_format_service.dart';

enum WeeklySmartInsightKind {
  microExpensesSummary,
  mostCommonSpendingTime,
  autoCategorizationUsage,
}

class WeeklySmartInsight {
  const WeeklySmartInsight({
    required this.signalId,
    required this.notificationId,
    required this.kind,
    required this.detectedAt,
    required this.title,
    required this.detailTitle,
    required this.detailMessage,
    this.subtitle,
    this.amount,
  });

  final String signalId;
  final String notificationId;
  final WeeklySmartInsightKind kind;
  final DateTime detectedAt;
  final String title;
  final String detailTitle;
  final String detailMessage;
  final String? subtitle;
  final double? amount;
}

abstract final class WeeklySmartInsightService {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static WeeklySmartInsight? buildInsight({
    required Iterable<ExpenseModel> expenses,
    required int userId,
    DateTime? now,
    math.Random? random,
  }) {
    final referenceNow = now ?? DateTime.now();
    if (referenceNow.weekday != DateTime.saturday) {
      return null;
    }

    final saturdayKey = _dayKey(_dateOnly(referenceNow));
    final windowStart = referenceNow.subtract(const Duration(days: 7));
    final weeklyExpenses =
        expenses.where((expense) {
          final expenseMoment = _expenseMoment(expense);
          return !expenseMoment.isBefore(windowStart) &&
              !expenseMoment.isAfter(referenceNow);
        }).toList()..sort(
          (left, right) =>
              _expenseMoment(left).compareTo(_expenseMoment(right)),
        );

    final candidates = <WeeklySmartInsight>[
      _buildMicroExpensesInsight(
        weeklyExpenses,
        now: referenceNow,
        saturdayKey: saturdayKey,
      ),
      _buildMostCommonSpendingTimeInsight(
        weeklyExpenses,
        now: referenceNow,
        saturdayKey: saturdayKey,
      ),
      _buildAutoCategorizationUsageInsight(
        weeklyExpenses,
        now: referenceNow,
        saturdayKey: saturdayKey,
      ),
    ];

    final selector = random ?? math.Random(_selectionSeed(userId, saturdayKey));
    return candidates[selector.nextInt(candidates.length)];
  }

  static WeeklySmartInsight _buildMicroExpensesInsight(
    List<ExpenseModel> expenses, {
    required DateTime now,
    required String saturdayKey,
  }) {
    final microExpenseTotal = expenses
        .where((expense) => expense.amount < 5000)
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    final amountLabel = _formatMoney(microExpenseTotal);

    return WeeklySmartInsight(
      signalId: 'weekly-smart:$saturdayKey',
      notificationId: 'weekly-smart-$saturdayKey',
      kind: WeeklySmartInsightKind.microExpensesSummary,
      detectedAt: now,
      title: 'Small purchases added up',
      subtitle: 'Weekly micro-expenses',
      amount: microExpenseTotal,
      detailTitle: 'Weekly micro-expenses summary',
      detailMessage:
          'This week you spent $amountLabel on small purchases. These can add up quickly.',
    );
  }

  static WeeklySmartInsight _buildMostCommonSpendingTimeInsight(
    List<ExpenseModel> expenses, {
    required DateTime now,
    required String saturdayKey,
  }) {
    if (expenses.isEmpty) {
      return WeeklySmartInsight(
        signalId: 'weekly-smart:$saturdayKey',
        notificationId: 'weekly-smart-$saturdayKey',
        kind: WeeklySmartInsightKind.mostCommonSpendingTime,
        detectedAt: now,
        title: 'No spending window stood out',
        subtitle: 'Weekly spending time',
        detailTitle: 'Weekly spending time summary',
        detailMessage:
            'You logged no expenses in the last 7 days, so no spending period stood out.',
      );
    }

    final countsByPeriod = <_SpendingPeriod, int>{
      for (final period in _SpendingPeriod.values) period: 0,
    };
    for (final expense in expenses) {
      final period = _periodForHour(_expenseMoment(expense).hour);
      countsByPeriod[period] = (countsByPeriod[period] ?? 0) + 1;
    }

    final mostCommonPeriod = countsByPeriod.entries.reduce((best, current) {
      if (current.value > best.value) {
        return current;
      }
      if (current.value == best.value &&
          current.key.startHour < best.key.startHour) {
        return current;
      }
      return best;
    }).key;

    return WeeklySmartInsight(
      signalId: 'weekly-smart:$saturdayKey',
      notificationId: 'weekly-smart-$saturdayKey',
      kind: WeeklySmartInsightKind.mostCommonSpendingTime,
      detectedAt: now,
      title: 'A spending window stands out',
      subtitle: 'Weekly spending time',
      detailTitle: 'Most common spending time',
      detailMessage:
          'You usually spend money in ${mostCommonPeriod.messageLabel}. Stay mindful during this period.',
    );
  }

  static WeeklySmartInsight _buildAutoCategorizationUsageInsight(
    List<ExpenseModel> expenses, {
    required DateTime now,
    required String saturdayKey,
  }) {
    final usageCount = expenses
        .where((expense) => expense.wasAutoCategorized)
        .length;

    return WeeklySmartInsight(
      signalId: 'weekly-smart:$saturdayKey',
      notificationId: 'weekly-smart-$saturdayKey',
      kind: WeeklySmartInsightKind.autoCategorizationUsage,
      detectedAt: now,
      title: 'Auto-categorization usage',
      subtitle: 'Weekly categorization habits',
      amount: usageCount.toDouble(),
      detailTitle: 'Weekly auto-categorization summary',
      detailMessage:
          'You relied on auto-categorization $usageCount ${usageCount == 1 ? 'time' : 'times'} this week.',
    );
  }

  static _SpendingPeriod _periodForHour(int hour) {
    for (final period in _SpendingPeriod.values) {
      if (hour >= period.startHour && hour <= period.endHour) {
        return period;
      }
    }
    return _SpendingPeriod.night;
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

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static int _selectionSeed(int userId, String saturdayKey) {
    return Object.hash(userId, saturdayKey) & 0x7fffffff;
  }

  static String _formatMoney(double amount) {
    return 'COP ${_currencyFormat.format(amount.round())}';
  }
}

enum _SpendingPeriod {
  night(startHour: 0, endHour: 5, messageLabel: 'the night'),
  morning(startHour: 6, endHour: 11, messageLabel: 'the morning'),
  afternoon(startHour: 12, endHour: 17, messageLabel: 'the afternoon'),
  evening(startHour: 18, endHour: 23, messageLabel: 'the evening');

  const _SpendingPeriod({
    required this.startHour,
    required this.endHour,
    required this.messageLabel,
  });

  final int startHour;
  final int endHour;
  final String messageLabel;
}
