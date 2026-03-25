import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/models/expense_model.dart';
import 'package:spendant/src/models/goal_model.dart';
import 'package:spendant/src/models/income_model.dart';
import 'package:spendant/src/services/daily_budget_service.dart';

void main() {
  group('DailyBudgetService', () {
    test('spreads a just-once income across 120 days from its start date', () {
      final income = IncomeModel()
        ..amount = 120000
        ..type = 'JUST_ONCE'
        ..startDate = DateTime(2026, 3, 1);

      expect(
        DailyBudgetService.dailyIncomeContribution(
          income,
          onDay: DateTime(2026, 2, 28),
        ),
        0,
      );
      expect(
        DailyBudgetService.dailyIncomeContribution(
          income,
          onDay: DateTime(2026, 3, 1),
        ),
        1000,
      );
      expect(
        DailyBudgetService.dailyIncomeContribution(
          income,
          onDay: DateTime(2026, 6, 29),
        ),
        0,
      );
    });

    test(
      'computes dynamic goal progress from prior daily funding and expenses',
      () {
        final income = IncomeModel()
          ..amount = 12000
          ..type = 'JUST_ONCE'
          ..startDate = DateTime(2026, 3, 1);
        final goal = GoalModel()
          ..name = 'Laptop'
          ..targetAmount = 3000
          ..currentAmount = 0
          ..createdAt = DateTime(2026, 3, 1)
          ..deadline = DateTime(2026, 3, 31);
        final blockedDayOne = ExpenseModel()
          ..amount = 100
          ..date = DateTime(2026, 3, 5)
          ..time = '10:00';
        final blockedDayTwo = ExpenseModel()
          ..amount = 100
          ..date = DateTime(2026, 3, 6)
          ..time = '14:00';

        final states = DailyBudgetService.buildGoalStates(
          goals: <GoalModel>[goal],
          incomes: <IncomeModel>[income],
          expenses: <ExpenseModel>[blockedDayOne, blockedDayTwo],
          now: DateTime(2026, 3, 11, 9),
        );

        expect(states, hasLength(1));
        expect(states.single.currentAmount, 800);
        expect(states.single.dailyContribution, 100);
        expect(states.single.progressPercent, 27);
        expect(states.single.isCompleted, isFalse);
      },
    );

    test(
      'uses the stored current amount as the baseline for replanned goals',
      () {
        final goal = GoalModel()
          ..name = 'Trip'
          ..targetAmount = 1000
          ..currentAmount = 400
          ..createdAt = DateTime(2026, 3, 10)
          ..deadline = DateTime(2026, 3, 15);

        expect(
          DailyBudgetService.dailyGoalContribution(
            goal,
            today: DateTime(2026, 3, 12),
          ),
          120,
        );
      },
    );
  });
}
