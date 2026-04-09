import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'calendar_availability_service.dart';
import 'local_notification_service.dart';
import 'notification_reader_service.dart';
import 'post_auth_navigation.dart';

enum PermissionsReviewDestination { registerIntro, locationPermissionIntro }

class PermissionsReviewState {
  const PermissionsReviewState({
    required this.hasCalendarImport,
    required this.hasPostingNotificationPermission,
    required this.hasNotificationReaderAccess,
    required this.hasLocationPermission,
  });

  final bool hasCalendarImport;
  final bool hasPostingNotificationPermission;
  final bool hasNotificationReaderAccess;
  final bool hasLocationPermission;

  bool get needsNotificationReview {
    return !hasPostingNotificationPermission || !hasNotificationReaderAccess;
  }
}

class PermissionsReviewFlow {
  const PermissionsReviewFlow.locationPermissionIntro()
    : destination = PermissionsReviewDestination.locationPermissionIntro,
      initialStep = null,
      showCalendarStep = false,
      showNotificationStep = false;

  const PermissionsReviewFlow.registerIntro({
    required this.initialStep,
    required this.showCalendarStep,
    required this.showNotificationStep,
  }) : destination = PermissionsReviewDestination.registerIntro;

  final PermissionsReviewDestination destination;
  final PermissionsIntroStep? initialStep;
  final bool showCalendarStep;
  final bool showNotificationStep;
}

abstract final class PermissionsReviewService {
  static Future<PermissionsReviewFlow> planForNormalLogin() async {
    final state = await _loadState();
    return planForState(state);
  }

  @visibleForTesting
  static PermissionsReviewFlow planForState(PermissionsReviewState state) {
    if (!state.hasLocationPermission) {
      return const PermissionsReviewFlow.locationPermissionIntro();
    }

    if (!state.hasCalendarImport) {
      return PermissionsReviewFlow.registerIntro(
        initialStep: PermissionsIntroStep.calendar,
        showCalendarStep: true,
        showNotificationStep: state.needsNotificationReview,
      );
    }

    if (state.needsNotificationReview) {
      return const PermissionsReviewFlow.registerIntro(
        initialStep: PermissionsIntroStep.notifications,
        showCalendarStep: false,
        showNotificationStep: true,
      );
    }

    return const PermissionsReviewFlow.registerIntro(
      initialStep: PermissionsIntroStep.calendar,
      showCalendarStep: true,
      showNotificationStep: false,
    );
  }

  static Future<PermissionsReviewState> _loadState() async {
    final results = await Future.wait<bool>(<Future<bool>>[
      _hasCalendarImport(),
      _hasPostingNotificationPermission(),
      _hasNotificationReaderAccess(),
      _hasLocationPermission(),
    ]);

    return PermissionsReviewState(
      hasCalendarImport: results[0],
      hasPostingNotificationPermission: results[1],
      hasNotificationReaderAccess: results[2],
      hasLocationPermission: results[3],
    );
  }

  static Future<bool> _hasCalendarImport() async {
    try {
      final snapshot = await CalendarAvailabilityService.instance
          .snapshotForMoment(DateTime.now());
      return snapshot.hasSchedule;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hasPostingNotificationPermission() async {
    if (kIsWeb) {
      return true;
    }

    try {
      return await LocalNotificationService.ensurePermission(
        promptIfNeeded: false,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hasNotificationReaderAccess() async {
    if (!NotificationReaderService.isSupportedPlatform) {
      return true;
    }

    try {
      return await NotificationReaderService.isAccessEnabled();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hasLocationPermission() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}
