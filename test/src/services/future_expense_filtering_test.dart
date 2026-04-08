import 'package:flutter_test/flutter_test.dart';

import 'package:spendant/src/models/app_notification_model.dart';
import 'package:spendant/src/models/expense_model.dart';
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

    test('notification feed only includes generated app notifications', () {
      final generatedNotification = AppNotificationModel()
        ..id = 'budget-warning-2026-04-07'
        ..type = 'budget_warning'
        ..userId = 7
        ..title = 'Daily budget exhausted'
        ..detailTitle = 'Daily budget warning'
        ..detailMessage = 'Review today\'s budget.'
        ..createdAt = DateTime(2026, 4, 7, 9, 0);
      final otherUserNotification = AppNotificationModel()
        ..id = 'goal-created-1'
        ..type = 'goal_created'
        ..userId = 8
        ..title = 'New goal created'
        ..detailTitle = 'Goal created'
        ..detailMessage = 'Another user notification.'
        ..createdAt = DateTime(2026, 4, 7, 10, 0);

      final feed = NotificationFeedService.buildFeed(
        appNotifications: <AppNotificationModel>[
          generatedNotification,
          otherUserNotification,
        ],
        userId: 7,
      );

      expect(feed, hasLength(1));
      expect(feed.single.title, 'Daily budget exhausted');
      expect(feed.single.type, NotificationFeedType.budgetWarning);
    });
  });
}
