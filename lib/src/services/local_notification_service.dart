import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification_model.dart';
import 'app_navigation_service.dart';
import 'post_auth_navigation.dart';

abstract final class LocalNotificationService {
  static const String _androidNotificationIcon = 'ic_stat_spendant';
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'spendant_alerts',
        'SpendAnt Alerts',
        description:
            'Goal, budget, and spending alerts generated locally by SpendAnt.',
        importance: Importance.max,
      );

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

  static Future<void> showTrackedNotification(
    AppNotificationModel notification,
  ) async {
    if (!_isInitialized) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        debugPrint(
          'LocalNotificationService initialization failed before show: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        return;
      }
    }

    final hasPermission = await ensurePermission(promptIfNeeded: true);
    if (!hasPermission) {
      debugPrint(
        'LocalNotificationService.showTrackedNotification skipped: notification permission not granted.',
      );
      return;
    }

    final payload = _payloadForNotification(notification);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        icon: _androidNotificationIcon,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(notification.detailMessage),
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
        notification.id.hashCode & 0x7fffffff,
        notification.title,
        notification.detailMessage,
        details,
        payload: payload,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'LocalNotificationService.showTrackedNotification failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
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
