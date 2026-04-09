import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/services/permissions_review_service.dart';
import 'package:spendant/src/services/post_auth_navigation.dart';

void main() {
  group('PermissionsReviewService.planForState', () {
    test('prioritizes location screen when location is missing', () {
      const state = PermissionsReviewState(
        hasCalendarImport: false,
        hasPostingNotificationPermission: false,
        hasNotificationReaderAccess: false,
        hasLocationPermission: false,
      );

      final flow = PermissionsReviewService.planForState(state);

      expect(
        flow.destination,
        PermissionsReviewDestination.locationPermissionIntro,
      );
    });

    test(
      'starts at calendar and keeps notification step when both are missing',
      () {
        const state = PermissionsReviewState(
          hasCalendarImport: false,
          hasPostingNotificationPermission: false,
          hasNotificationReaderAccess: false,
          hasLocationPermission: true,
        );

        final flow = PermissionsReviewService.planForState(state);

        expect(flow.destination, PermissionsReviewDestination.registerIntro);
        expect(flow.initialStep, PermissionsIntroStep.calendar);
        expect(flow.showCalendarStep, isTrue);
        expect(flow.showNotificationStep, isTrue);
      },
    );

    test(
      'starts directly at notifications when only notifications are missing',
      () {
        const state = PermissionsReviewState(
          hasCalendarImport: true,
          hasPostingNotificationPermission: false,
          hasNotificationReaderAccess: true,
          hasLocationPermission: true,
        );

        final flow = PermissionsReviewService.planForState(state);

        expect(flow.destination, PermissionsReviewDestination.registerIntro);
        expect(flow.initialStep, PermissionsIntroStep.notifications);
        expect(flow.showCalendarStep, isFalse);
        expect(flow.showNotificationStep, isTrue);
      },
    );

    test(
      'falls back to the calendar step when everything is already in place',
      () {
        const state = PermissionsReviewState(
          hasCalendarImport: true,
          hasPostingNotificationPermission: true,
          hasNotificationReaderAccess: true,
          hasLocationPermission: true,
        );

        final flow = PermissionsReviewService.planForState(state);

        expect(flow.destination, PermissionsReviewDestination.registerIntro);
        expect(flow.initialStep, PermissionsIntroStep.calendar);
        expect(flow.showCalendarStep, isTrue);
        expect(flow.showNotificationStep, isFalse);
      },
    );
  });
}
