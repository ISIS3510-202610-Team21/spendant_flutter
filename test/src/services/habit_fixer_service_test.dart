import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/models/expense_model.dart';
import 'package:spendant/src/services/habit_fixer_service.dart';
import 'package:spendant/src/services/spending_advice_service.dart';

void main() {
  group('HabitFixerService', () {
    test('triggers when the user returns to a regret hotspot while free', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Cafe',
          amount: 17000,
          date: DateTime(2026, 3, 3),
          time: '12:05',
          latitude: 4.6098,
          longitude: -74.0819,
          locationName: 'Cafe Solaris',
          isRegretted: true,
          primaryCategory: 'Food',
        ),
        _expense(
          name: 'Cafe',
          amount: 19000,
          date: DateTime(2026, 3, 10),
          time: '12:20',
          latitude: 4.6099,
          longitude: -74.0818,
          locationName: 'Cafe Solaris',
          isRegretted: true,
          primaryCategory: 'Food',
        ),
      ];

      final advice = HabitFixerService.buildTriggeredAdvice(
        expenses: expenses,
        now: DateTime(2026, 3, 20, 12, 15),
        currentLatitude: 4.60985,
        currentLongitude: -74.08185,
        isCalendarAvailable: true,
      );

      expect(advice, isNotNull);
      expect(advice!.kind, SpendingAdviceKind.regretHotspot);
      expect(advice.title, 'Pause before spending at Cafe Solaris');
      expect(advice.category, 'Food');
      expect(advice.detailMessage, contains('calendar looks free'));
    });

    test('does not trigger when the calendar says the user is busy', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Impulse snack',
          amount: 12000,
          date: DateTime(2026, 3, 2),
          time: '18:10',
          latitude: 4.6501,
          longitude: -74.0552,
          locationName: 'Corner Store',
          isRegretted: true,
          primaryCategory: 'Food',
        ),
        _expense(
          name: 'Impulse snack',
          amount: 14000,
          date: DateTime(2026, 3, 9),
          time: '18:25',
          latitude: 4.6500,
          longitude: -74.0553,
          locationName: 'Corner Store',
          isRegretted: true,
          primaryCategory: 'Food',
        ),
      ];

      final advice = HabitFixerService.buildTriggeredAdvice(
        expenses: expenses,
        now: DateTime(2026, 3, 20, 18, 20),
        currentLatitude: 4.65005,
        currentLongitude: -74.05525,
        isCalendarAvailable: false,
      );

      expect(advice, isNull);
    });

    test('does not trigger outside the hotspot time window', () {
      final expenses = <ExpenseModel>[
        _expense(
          name: 'Mall stop',
          amount: 65000,
          date: DateTime(2026, 3, 1),
          time: '11:30',
          latitude: 4.711,
          longitude: -74.072,
          locationName: 'Andino Mall',
          isRegretted: true,
          primaryCategory: 'Other',
        ),
        _expense(
          name: 'Mall stop',
          amount: 72000,
          date: DateTime(2026, 3, 8),
          time: '12:00',
          latitude: 4.7111,
          longitude: -74.0721,
          locationName: 'Andino Mall',
          isRegretted: true,
          primaryCategory: 'Other',
        ),
      ];

      final advice = HabitFixerService.buildTriggeredAdvice(
        expenses: expenses,
        now: DateTime(2026, 3, 20, 16, 30),
        currentLatitude: 4.71105,
        currentLongitude: -74.07205,
        isCalendarAvailable: true,
      );

      expect(advice, isNull);
    });
  });
}

ExpenseModel _expense({
  required String name,
  required double amount,
  required DateTime date,
  required String time,
  required double latitude,
  required double longitude,
  required String locationName,
  required bool isRegretted,
  required String primaryCategory,
}) {
  return ExpenseModel()
    ..name = name
    ..amount = amount
    ..date = date
    ..time = time
    ..latitude = latitude
    ..longitude = longitude
    ..locationName = locationName
    ..isRegretted = isRegretted
    ..createdAt = date
    ..primaryCategory = primaryCategory;
}
