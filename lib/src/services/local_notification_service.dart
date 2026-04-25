import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification_model.dart';
import 'app_navigation_service.dart';
import 'auth_memory_store.dart';
import 'local_storage_service.dart';
import 'notification_feed_service.dart';
import 'post_auth_navigation.dart';

class LocalNotificationAttemptResult {
  const LocalNotificationAttemptResult({
    required this.wasShown,
    this.errorMessage,
  });

  final bool wasShown;
  final String? errorMessage;
}

abstract final class LocalNotificationService {
  static const String _androidNotificationIcon = 'ic_stat_spendant';
  static const Color _androidNotificationColor = Color(0xFF44C669);
  static const DrawableResourceAndroidBitmap _androidLargeIcon =
      DrawableResourceAndroidBitmap('spendant_notification_large_icon');
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'spendant_alerts',
        'SpendAnt Alerts',
        description:
            'Goal, budget, and spending alerts generated locally by SpendAnt.',
        importance: Importance.max,
      );
  static const String _androidNotificationGroupKey = 'spendant_alerts_group';
  static const String _androidTestNotificationGroupKey =
      'spendant_alerts_test_group';
  static const int _androidSummaryNotificationId = 0x53414D;
  static const int _androidTestSummaryNotificationId = 0x534154;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static AppRedirect? _launchRedirect;
  static bool _isInitialized = false;
  static Future<void>? _initializing;
  static Future<bool>? _permissionRequest;

  static Future<void> initialize() async {
    final runningInitialization = _initializing;
    if (runningInitialization != null) {
      await runningInitialization;
      return;
    }

    final initialization = _initializeInternal();
    _initializing = initialization;

    try {
      await initialization;
    } finally {
      if (identical(_initializing, initialization)) {
        _initializing = null;
      }
    }
  }

  static Future<void> _initializeInternal() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings(_androidNotificationIcon),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      ),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(_androidChannel);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _launchRedirect = _redirectFromPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }

    _isInitialized = true;
  }

  static AppRedirect? takeLaunchRedirect() {
    final redirect = _launchRedirect;
    _launchRedirect = null;
    return redirect;
  }

  static Future<bool> ensurePermission({bool promptIfNeeded = false}) async {
    if (kIsWeb) {
      return false;
    }

    if (!_isInitialized) {
      await initialize();
    }

    final currentRequest = _permissionRequest;
    if (currentRequest != null) {
      return currentRequest;
    }

    final requestFuture = _ensurePermissionInternal(
      promptIfNeeded: promptIfNeeded,
    );
    _permissionRequest = requestFuture;

    try {
      return await requestFuture;
    } finally {
      if (identical(_permissionRequest, requestFuture)) {
        _permissionRequest = null;
      }
    }
  }

  static Future<LocalNotificationAttemptResult> showTrackedNotification(
    AppNotificationModel notification, {
    bool promptIfNeeded = true,
  }) async {
    if (!_isInitialized) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        debugPrint(
          'LocalNotificationService initialization failed before show: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        return LocalNotificationAttemptResult(
          wasShown: false,
          errorMessage: '$error',
        );
      }
    }

    final hasPermission = await ensurePermission(
      promptIfNeeded: promptIfNeeded,
    );
    if (!hasPermission) {
      debugPrint(
        'LocalNotificationService.showTrackedNotification skipped: notification permission not granted.',
      );
      return const LocalNotificationAttemptResult(wasShown: false);
    }

    final payload = _payloadForNotification(notification);
    final notificationId = notification.id.hashCode & 0x7fffffff;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _showAndroidGroupedNotification(
        childNotificationId: notificationId,
        summaryNotificationId: _androidSummaryNotificationId,
        groupKey: _androidNotificationGroupKey,
        title: notification.title,
        body: notification.detailMessage,
        payload: payload,
        summaryLines: _buildStoredSummaryLines(),
      );
    }

    return _showNotification(
      notificationId: notificationId,
      title: notification.title,
      body: notification.detailMessage,
      payload: payload,
    );
  }

  static Future<LocalNotificationAttemptResult> showTestNotification({
    required String title,
    required String body,
    bool promptIfNeeded = true,
  }) async {
    if (!_isInitialized) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        debugPrint(
          'LocalNotificationService initialization failed before test show: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        return LocalNotificationAttemptResult(
          wasShown: false,
          errorMessage: '$error',
        );
      }
    }

    final hasPermission = await ensurePermission(
      promptIfNeeded: promptIfNeeded,
    );
    if (!hasPermission) {
      debugPrint(
        'LocalNotificationService.showTestNotification skipped: notification permission not granted.',
      );
      return const LocalNotificationAttemptResult(wasShown: false);
    }

    final notificationId = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _showAndroidGroupedNotification(
        childNotificationId: notificationId,
        summaryNotificationId: _androidTestSummaryNotificationId,
        groupKey: _androidTestNotificationGroupKey,
        title: title,
        body: body,
        summaryLines: <String>[title],
      );
    }

    return _showNotification(
      notificationId: notificationId,
      title: title,
      body: body,
    );
  }

  static Future<LocalNotificationAttemptResult> _showNotification({
    required int notificationId,
    required String title,
    required String body,
    String? payload,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        icon: _androidNotificationIcon,
        color: _androidNotificationColor,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    try {
      await _plugin.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );
      return const LocalNotificationAttemptResult(wasShown: true);
    } catch (error, stackTrace) {
      debugPrint('LocalNotificationService._showNotification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return LocalNotificationAttemptResult(
        wasShown: false,
        errorMessage: '$error',
      );
    }
  }

  static Future<LocalNotificationAttemptResult> _showAndroidGroupedNotification({
    required int childNotificationId,
    required int summaryNotificationId,
    required String groupKey,
    required String title,
    required String body,
    String? payload,
    required List<String> summaryLines,
  }) async {
    final childDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        icon: _androidNotificationIcon,
        color: _androidNotificationColor,
        largeIcon: _androidLargeIcon,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(body),
        groupKey: groupKey,
        groupAlertBehavior: GroupAlertBehavior.children,
      ),
    );

    final normalizedSummaryLines = summaryLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(5)
        .toList(growable: false);
    final resolvedSummaryLines = normalizedSummaryLines.isEmpty
        ? <String>[title]
        : normalizedSummaryLines;
    final summaryCount = resolvedSummaryLines.length;
    final summaryBody = summaryCount == 1
        ? '1 alert from SpendAnt'
        : '$summaryCount alerts from SpendAnt';
    final summaryDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        icon: _androidNotificationIcon,
        color: _androidNotificationColor,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        styleInformation: InboxStyleInformation(
          resolvedSummaryLines,
          contentTitle: 'SpendAnt',
          summaryText: summaryBody,
        ),
        groupKey: groupKey,
        setAsGroupSummary: true,
        groupAlertBehavior: GroupAlertBehavior.summary,
      ),
    );

    try {
      await _plugin.show(
        childNotificationId,
        title,
        body,
        childDetails,
        payload: payload,
      );
      await _plugin.show(
        summaryNotificationId,
        'SpendAnt',
        summaryBody,
        summaryDetails,
      );
      return const LocalNotificationAttemptResult(wasShown: true);
    } catch (error, stackTrace) {
      debugPrint(
        'LocalNotificationService._showAndroidGroupedNotification failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return LocalNotificationAttemptResult(
        wasShown: false,
        errorMessage: '$error',
      );
    }
  }

  static List<String> _buildStoredSummaryLines() {
    final currentUserId = AuthMemoryStore.currentUserIdOrGuest;
    if (currentUserId < 0) {
      return const <String>[];
    }

    final notifications = LocalStorageService.notificationBox.values
        .where((notification) => notification.userId == currentUserId)
        .where(
          (notification) =>
              NotificationFeedService.isVisibleInFeedType(notification.type),
        )
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    return notifications.take(5).map((notification) {
      final subtitle = notification.subtitle?.trim();
      if (subtitle != null && subtitle.isNotEmpty) {
        return '${notification.title} - $subtitle';
      }
      return notification.title.trim();
    }).where((line) => line.isNotEmpty).toList(growable: false);
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final redirect = _redirectFromPayload(response.payload);
    if (redirect == null) {
      return;
    }

    AppNavigationService.openRedirect(redirect);
  }

  static AppRedirect? _redirectFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return AppRedirect.fromMap(
        decoded.map((key, value) => MapEntry<String, Object?>(key, value)),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _payloadForNotification(AppNotificationModel notification) {
    final routeName = notification.routeName;
    if (routeName == null || routeName.isEmpty) {
      return null;
    }

    return jsonEncode(
      AppRedirect(
        routeName: routeName,
        routeArgumentInt: notification.routeArgumentInt,
      ).toMap(),
    );
  }

  static Future<void> cancelNotification(int notificationId) async {
    if (!_isInitialized) {
      return;
    }
    try {
      await _plugin.cancel(notificationId);
    } catch (error) {
      debugPrint('LocalNotificationService.cancelNotification failed: $error');
    }
  }

  static Future<LocalNotificationAttemptResult> showRawNotification({
    required int notificationId,
    required String title,
    required String body,
    required NotificationDetails details,
    String? payload,
  }) async {
    if (!_isInitialized) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        debugPrint(
          'LocalNotificationService initialization failed before showRaw: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        return LocalNotificationAttemptResult(
          wasShown: false,
          errorMessage: '$error',
        );
      }
    }

    try {
      await _plugin.show(notificationId, title, body, details, payload: payload);
      return const LocalNotificationAttemptResult(wasShown: true);
    } catch (error, stackTrace) {
      debugPrint('LocalNotificationService.showRawNotification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return LocalNotificationAttemptResult(
        wasShown: false,
        errorMessage: '$error',
      );
    }
  }

  static Future<bool> _ensurePermissionInternal({
    required bool promptIfNeeded,
  }) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _ensureAndroidPermission(promptIfNeeded: promptIfNeeded);
      case TargetPlatform.iOS:
        return _ensureIosPermission(promptIfNeeded: promptIfNeeded);
      case TargetPlatform.macOS:
        return _ensureMacOsPermission(promptIfNeeded: promptIfNeeded);
      default:
        return true;
    }
  }

  static Future<bool> _ensureAndroidPermission({
    required bool promptIfNeeded,
  }) async {
    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation == null) {
      return false;
    }

    final notificationsEnabled =
        await androidImplementation.areNotificationsEnabled() ?? false;
    if (notificationsEnabled) {
      return true;
    }

    if (!promptIfNeeded) {
      return false;
    }

    return await androidImplementation.requestNotificationsPermission() ??
        false;
  }

  static Future<bool> _ensureIosPermission({
    required bool promptIfNeeded,
  }) async {
    final iOSImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iOSImplementation == null) {
      return false;
    }

    final currentPermissions = await iOSImplementation.checkPermissions();
    if (_darwinPermissionsAllowAlerts(currentPermissions)) {
      return true;
    }

    if (!promptIfNeeded) {
      return false;
    }

    return await iOSImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  static Future<bool> _ensureMacOsPermission({
    required bool promptIfNeeded,
  }) async {
    final macOSImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macOSImplementation == null) {
      return false;
    }

    final currentPermissions = await macOSImplementation.checkPermissions();
    if (_darwinPermissionsAllowAlerts(currentPermissions)) {
      return true;
    }

    if (!promptIfNeeded) {
      return false;
    }

    return await macOSImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  static bool _darwinPermissionsAllowAlerts(
    NotificationsEnabledOptions? permissions,
  ) {
    if (permissions == null || !permissions.isEnabled) {
      return false;
    }

    return permissions.isAlertEnabled || permissions.isProvisionalEnabled;
  }
}
