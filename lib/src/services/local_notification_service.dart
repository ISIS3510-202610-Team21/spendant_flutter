import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification_model.dart';
import 'app_navigation_service.dart';

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
      iOS: DarwinInitializationSettings(),
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
    await androidImplementation?.requestNotificationsPermission();

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

    final routeName = notification.routeName;
    if (routeName == null || routeName.isEmpty) {
      return;
    }

    final payload = jsonEncode(
      AppRedirect(
        routeName: routeName,
        routeArgumentInt: notification.routeArgumentInt,
      ).toMap(),
    );

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
      iOS: const DarwinNotificationDetails(),
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
}
