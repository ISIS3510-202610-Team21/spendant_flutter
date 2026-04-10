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
  static const String _weeklyInsightTitle = 'Weekly spending insight';
  static const String _weeklyInsightDetailTitle = 'Weekly spending insight';
  static const String _defaultTimeRange = '2pm to 3pm';

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

    final saturdayStart = _dateOnly(referenceNow);
    final saturdayKey = _dayKey(saturdayStart);
    final windowStart = saturdayStart.subtract(const Duration(days: 6));
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
      signalId: 'weekly_insight:$saturdayKey',
      notificationId: 'weekly_insight_${_dateOnly(now).millisecondsSinceEpoch}',
      kind: WeeklySmartInsightKind.microExpensesSummary,
      detectedAt: now,
      title: _weeklyInsightTitle,
      subtitle: 'Saturday summary',
      amount: microExpenseTotal,
      detailTitle: _weeklyInsightDetailTitle,
      detailMessage:
          'This week you spent $amountLabel on small purchases. These can add up quickly.',
    );
  }

  static WeeklySmartInsight _buildMostCommonSpendingTimeInsight(
    List<ExpenseModel> expenses, {
    required DateTime now,
    required String saturdayKey,
  }) {
    final countsByHour = <int, int>{};
    for (final expense in expenses) {
      final hour = _expenseMoment(expense).hour.clamp(0, 23);
      countsByHour[hour] = (countsByHour[hour] ?? 0) + 1;
    }

    final mostCommonHour = countsByHour.entries.isEmpty
        ? null
        : countsByHour.entries.reduce((best, current) {
            if (current.value > best.value) {
              return current;
            }
            if (current.value == best.value && current.key < best.key) {
              return current;
            }
            return best;
          }).key;
    final timeRange = mostCommonHour == null
        ? _defaultTimeRange
        : _hourRangeLabel(mostCommonHour);

    return WeeklySmartInsight(
      signalId: 'weekly_insight:$saturdayKey',
      notificationId: 'weekly_insight_${_dateOnly(now).millisecondsSinceEpoch}',
      kind: WeeklySmartInsightKind.mostCommonSpendingTime,
      detectedAt: now,
      title: _weeklyInsightTitle,
      subtitle: 'Saturday summary',
      detailTitle: _weeklyInsightDetailTitle,
      detailMessage:
          'You usually spend money around $timeRange. Stay mindful during this period.',
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
      signalId: 'weekly_insight:$saturdayKey',
      notificationId: 'weekly_insight_${_dateOnly(now).millisecondsSinceEpoch}',
      kind: WeeklySmartInsightKind.autoCategorizationUsage,
      detectedAt: now,
      title: _weeklyInsightTitle,
      subtitle: 'Saturday summary',
      amount: usageCount.toDouble(),
      detailTitle: _weeklyInsightDetailTitle,
      detailMessage:
          'You relied on auto-categorization $usageCount ${usageCount == 1 ? 'time' : 'times'} this week.',
    );
  }

  static String _hourRangeLabel(int hour24) {
    final startHour = _normalizeHour(hour24);
    final endHour = _normalizeHour(hour24 + 1);
    return '${_formatHour(startHour)} to ${_formatHour(endHour)}';
  }

  static int _normalizeHour(int hour) {
    return ((hour % 24) + 24) % 24;
  }

  static String _formatHour(int hour24) {
    final suffix = hour24 < 12 ? 'am' : 'pm';
    final hour12 = switch (hour24 % 12) {
      0 => 12,
      _ => hour24 % 12,
    };
    return '$hour12$suffix';
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
