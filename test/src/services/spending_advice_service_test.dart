import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/models/expense_model.dart';
import 'package:spendant/src/services/spending_advice_service.dart';

void main() {
  group('SpendingAdviceService', () {
    test('flags an expense that is far above its recent pattern', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Rappi',
          amount: 18000,
          date: DateTime(2026, 1, 3),
          time: '12:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 22000,
          date: DateTime(2026, 1, 8),
          time: '12:30',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 20000,
          date: DateTime(2026, 1, 14),
          time: '13:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 65000,
          date: DateTime(2026, 1, 20),
          time: '13:15',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
      ];

      final insights = SpendingAdviceService.buildInsights(
        expenses: expenses,
        now: DateTime(2026, 1, 20, 18),
      );

      final spikeAdvice = insights.where(
        (advice) => advice.kind == SpendingAdviceKind.expenseSpike,
      );

      expect(spikeAdvice, isNotEmpty);
      expect(spikeAdvice.first.title, 'Unusual Food Delivery expense');
      expect(spikeAdvice.first.amount, 65000);
      expect(spikeAdvice.first.category, 'Food');
    });

    test('flags a category when the monthly pace outruns recent months', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Exito',
          amount: 25000,
          date: DateTime(2026, 1, 4),
          time: '10:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Groceries'],
        ),
        _expense(
          name: 'Exito',
          amount: 20000,
          date: DateTime(2026, 1, 9),
          time: '10:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Groceries'],
        ),
        _expense(
          name: 'D1',
          amount: 30000,
          date: DateTime(2026, 2, 5),
          time: '10:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Groceries'],
        ),
        _expense(
          name: 'D1',
          amount: 18000,
          date: DateTime(2026, 2, 11),
          time: '10:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Groceries'],
        ),
        _expense(
          name: 'Rappi',
          amount: 28000,
          date: DateTime(2026, 3, 3),
          time: '10:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 34000,
          date: DateTime(2026, 3, 7),
          time: '11:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Exito',
          amount: 42000,
          date: DateTime(2026, 3, 10),
          time: '12:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Groceries'],
        ),
      ];

      final insights = SpendingAdviceService.buildInsights(
        expenses: expenses,
        now: DateTime(2026, 3, 10, 18),
      );

      final paceAdvice = insights.where(
        (advice) => advice.kind == SpendingAdviceKind.categoryAcceleration,
      );

      expect(paceAdvice, isNotEmpty);
      expect(paceAdvice.first.category, 'Food');
      expect(paceAdvice.first.title, 'Food spending is moving too fast');
    });

    test('flags repeated discretionary labels as a weekly pattern', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Rappi',
          amount: 19000,
          date: DateTime(2026, 2, 15),
          time: '20:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 21000,
          date: DateTime(2026, 3, 15),
          time: '20:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 22000,
          date: DateTime(2026, 3, 17),
          time: '20:30',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
        _expense(
          name: 'Rappi',
          amount: 24000,
          date: DateTime(2026, 3, 20),
          time: '21:00',
          primaryCategory: 'Food',
          detailLabels: const <String>['Food Delivery'],
        ),
      ];

      final insights = SpendingAdviceService.buildInsights(
        expenses: expenses,
        now: DateTime(2026, 3, 20, 23),
      );

      final habitAdvice = insights.where(
        (advice) => advice.kind == SpendingAdviceKind.habitCluster,
      );

      expect(habitAdvice, isNotEmpty);
      expect(
        habitAdvice.first.title,
        'Food delivery is becoming a weekly habit',
      );
      expect(habitAdvice.first.category, 'Food');
    });
  });
}

ExpenseModel _expense({
  required String name,
  required double amount,
  required DateTime date,
  required String time,
  required String primaryCategory,
  required List<String> detailLabels,
}) {
  return ExpenseModel()
    ..name = name
    ..amount = amount
    ..date = date
    ..time = time
    ..createdAt = date
    ..primaryCategory = primaryCategory
    ..detailLabels = List<String>.from(detailLabels);
}
