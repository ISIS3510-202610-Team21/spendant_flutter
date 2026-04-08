import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/models/expense_model.dart';
import 'package:spendant/src/services/weekly_smart_insight_service.dart';

void main() {
  group('WeeklySmartInsightService', () {
    test('returns null when the current day is not Saturday', () {
      final insight = WeeklySmartInsightService.buildInsight(
        expenses: const <ExpenseModel>[],
        userId: 7,
        now: DateTime(2026, 3, 20, 12),
      );

      expect(insight, isNull);
    });

    test('builds the micro-expenses summary from the last 7 days', () {
      final insight = WeeklySmartInsightService.buildInsight(
        expenses: <ExpenseModel>[
          _expense(amount: 1800, dateTime: DateTime(2026, 3, 15, 8, 0)),
          _expense(amount: 1200, dateTime: DateTime(2026, 3, 20, 9, 0)),
          _expense(amount: 3100, dateTime: DateTime(2026, 3, 18, 13, 30)),
          _expense(amount: 8000, dateTime: DateTime(2026, 3, 17, 10, 0)),
          _expense(amount: 900, dateTime: DateTime(2026, 3, 10, 10, 0)),
        ],
        userId: 7,
        now: DateTime(2026, 3, 21, 12),
        random: const _FixedRandom(0),
      );

      expect(insight, isNotNull);
      expect(insight!.kind, WeeklySmartInsightKind.microExpensesSummary);
      expect(insight.title, 'Weekly spending insight');
      expect(insight.amount, 6100);
      expect(
        insight.detailMessage,
        'This week you spent COP 6,100 on small purchases. These can add up quickly.',
      );
    });

    test('builds the most common spending time insight from weekly expenses', () {
      final insight = WeeklySmartInsightService.buildInsight(
        expenses: <ExpenseModel>[
          _expense(amount: 12000, dateTime: DateTime(2026, 3, 20, 8, 15)),
          _expense(amount: 19000, dateTime: DateTime(2026, 3, 18, 9, 45)),
          _expense(amount: 15000, dateTime: DateTime(2026, 3, 17, 14, 0)),
        ],
        userId: 7,
        now: DateTime(2026, 3, 21, 12),
        random: const _FixedRandom(1),
      );

      expect(insight, isNotNull);
      expect(insight!.kind, WeeklySmartInsightKind.mostCommonSpendingTime);
      expect(insight.title, 'Weekly spending insight');
      expect(
        insight.detailMessage,
        'You usually spend money around 8am to 9am. Stay mindful during this period.',
      );
    });

    test('counts auto-categorized expenses from the last 7 days', () {
      final insight = WeeklySmartInsightService.buildInsight(
        expenses: <ExpenseModel>[
          _expense(
            amount: 12000,
            dateTime: DateTime(2026, 3, 20, 8, 15),
            wasAutoCategorized: true,
          ),
          _expense(
            amount: 19000,
            dateTime: DateTime(2026, 3, 18, 9, 45),
            wasAutoCategorized: true,
          ),
          _expense(
            amount: 15000,
            dateTime: DateTime(2026, 3, 17, 14, 0),
            wasAutoCategorized: false,
          ),
          _expense(
            amount: 15000,
            dateTime: DateTime(2026, 3, 12, 14, 0),
            wasAutoCategorized: true,
          ),
        ],
        userId: 7,
        now: DateTime(2026, 3, 21, 12),
        random: const _FixedRandom(2),
      );

      expect(insight, isNotNull);
      expect(insight!.kind, WeeklySmartInsightKind.autoCategorizationUsage);
      expect(insight.title, 'Weekly spending insight');
      expect(insight.amount, 2);
      expect(
        insight.detailMessage,
        'You relied on auto-categorization 2 times this week.',
      );
    });
  });
}

ExpenseModel _expense({
  required double amount,
  required DateTime dateTime,
  bool wasAutoCategorized = false,
}) {
  return ExpenseModel()
    ..userId = 7
    ..name = 'Expense'
    ..amount = amount
    ..date = DateTime(dateTime.year, dateTime.month, dateTime.day)
    ..time =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
    ..createdAt = dateTime
    ..wasAutoCategorized = wasAutoCategorized;
}

class _FixedRandom implements math.Random {
  const _FixedRandom(this.value);

  final int value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => value % max;
}
