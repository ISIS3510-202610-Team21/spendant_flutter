import 'package:flutter_test/flutter_test.dart';

import 'package:spendant/src/models/app_notification_model.dart';
import 'package:spendant/src/services/notification_feed_service.dart';

void main() {
  group('NotificationFeedService', () {
    test('buildFeed keeps only the current user generated notifications', () {
      final olderNotification = AppNotificationModel()
        ..id = 'goal-created-1'
        ..type = 'goal_created'
        ..userId = 7
        ..title = 'New goal created'
        ..detailTitle = 'Goal created'
        ..detailMessage = 'Track your new goal.'
        ..createdAt = DateTime(2026, 4, 7, 9, 0);
      final newerNotification = AppNotificationModel()
        ..id = 'budget-warning-2026-04-07'
        ..type = 'budget_warning'
        ..userId = 7
        ..title = 'Daily budget exhausted'
        ..detailTitle = 'Daily budget warning'
        ..detailMessage = 'Review your budget.'
        ..createdAt = DateTime(2026, 4, 7, 11, 0);
      final otherUserNotification = AppNotificationModel()
        ..id = 'income-created-1'
        ..type = 'income_created'
        ..userId = 8
        ..title = 'New income added'
        ..detailTitle = 'Income created'
        ..detailMessage = 'Another user notification.'
        ..createdAt = DateTime(2026, 4, 7, 12, 0);

      final feed = NotificationFeedService.buildFeed(
        appNotifications: <AppNotificationModel>[
          olderNotification,
          newerNotification,
          otherUserNotification,
        ],
        userId: 7,
      );

      expect(feed.map((item) => item.id), <String>[
        'budget-warning-2026-04-07',
        'goal-created-1',
      ]);
      expect(feed.first.type, NotificationFeedType.budgetWarning);
      expect(feed.last.type, NotificationFeedType.goalCreated);
    });

    test('maps generated notification categories into feed items', () {
      AppNotificationModel buildNotification(
        String id,
        String type,
        DateTime createdAt,
      ) {
        return AppNotificationModel()
          ..id = id
          ..type = type
          ..userId = 7
          ..title = id
          ..detailTitle = 'detail-$id'
          ..detailMessage = 'message-$id'
          ..createdAt = createdAt;
      }

      final feed = NotificationFeedService.buildFeed(
        appNotifications: <AppNotificationModel>[
          buildNotification(
            'goal-halfway',
            AppNotificationTypes.goalHalfway,
            DateTime(2026, 4, 7, 10, 0),
          ),
          buildNotification(
            'goal-achieved',
            AppNotificationTypes.goalAchieved,
            DateTime(2026, 4, 7, 9, 0),
          ),
          buildNotification(
            'income-due',
            AppNotificationTypes.incomeDue,
            DateTime(2026, 4, 7, 8, 0),
          ),
          buildNotification(
            'needs-category',
            AppNotificationTypes.expenseCategoryNeeded,
            DateTime(2026, 4, 7, 7, 0),
          ),
          buildNotification(
            'weekly-insight',
            AppNotificationTypes.weeklyInsight,
            DateTime(2026, 4, 7, 6, 0),
          ),
        ],
        userId: 7,
      );

      expect(feed[0].type, NotificationFeedType.goalHalfway);
      expect(feed[1].type, NotificationFeedType.goalAchieved);
      expect(feed[2].type, NotificationFeedType.incomeDue);
      expect(feed[3].type, NotificationFeedType.warning);
      expect(feed[4].type, NotificationFeedType.warning);
    });
  });
}
