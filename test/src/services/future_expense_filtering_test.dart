import 'package:flutter_test/flutter_test.dart';

import 'package:spendant/src/models/app_notification_model.dart';
import 'package:spendant/src/models/expense_model.dart';
import 'package:spendant/src/models/goal_model.dart';
import 'package:spendant/src/services/expense_moment_service.dart';
import 'package:spendant/src/services/notification_feed_service.dart';
import 'package:spendant/src/theme/expense_visuals.dart';

void main() {
  group('Future expense filtering', () {
    test('expense moment service flags future-dated expenses', () {
      final expense = ExpenseModel()
        ..date = DateTime(2026, 3, 20)
        ..time = '18:45';

      final isFuture = ExpenseMomentService.isFutureExpense(
        expense,
        now: DateTime(2026, 3, 20, 12),
      );

      expect(isFuture, isTrue);
    });

    test('top category totals for month ignore future expenses', () {
      final currentExpense = ExpenseModel()
        ..name = 'Lunch'
        ..amount = 200
        ..date = DateTime(2026, 3, 20)
        ..time = '10:15'
        ..detailLabels = <String>['Food'];
      final futureExpense = ExpenseModel()
        ..name = 'Shoes'
        ..amount = 1000
        ..date = DateTime(2026, 3, 25)
        ..time = '09:00'
        ..detailLabels = <String>['Food'];

      final totals = ExpenseVisuals.topCategoryTotalsForMonth(<ExpenseModel>[
        currentExpense,
        futureExpense,
      ], now: DateTime(2026, 3, 20, 12));

      expect(totals, hasLength(1));
      expect(totals.first.label, 'Food');
      expect(totals.first.amount, 200);
    });

    test('notification feed ignores future expenses', () {
      final currentExpense = ExpenseModel()
        ..userId = 7
        ..name = 'Lunch'
        ..amount = 200
        ..date = DateTime(2020, 3, 20)
        ..time = '10:15'
        ..createdAt = DateTime(2020, 3, 20, 10, 15)
        ..detailLabels = <String>['Food'];
      final futureExpense = ExpenseModel()
        ..userId = 7
        ..name = 'Shoes'
        ..amount = 1000
        ..date = DateTime(2099, 3, 25)
        ..time = '09:00'
        ..createdAt = DateTime(2020, 3, 20, 10, 30)
        ..detailLabels = <String>['Other'];

      final feed = NotificationFeedService.buildFeed(
        expenses: <ExpenseModel>[currentExpense, futureExpense],
        goals: <GoalModel>[],
        appNotifications: <AppNotificationModel>[],
        userId: 7,
      );

      expect(feed, hasLength(1));
      expect(feed.single.title, 'Lunch');
    });
  });
}
