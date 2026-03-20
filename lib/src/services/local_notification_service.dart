import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification_model.dart';
import 'app_navigation_service.dart';

abstract final class LocalNotificationService {
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'spendant_alerts',
        'SpendAnt Alerts',
        description: 'Goal and budget alerts generated locally by SpendAnt.',
        importance: Importance.max,
      );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static AppRedirect? _launchRedirect;

  static Future<void> initialize() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(_androidChannel);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _launchRedirect = _redirectFromPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }
  }

  static AppRedirect? takeLaunchRedirect() {
    final redirect = _launchRedirect;
    _launchRedirect = null;
    return redirect;
  }

  static Future<void> showTrackedNotification(
    AppNotificationModel notification,
  ) async {
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
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(notification.detailMessage),
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      notification.id.hashCode & 0x7fffffff,
      notification.title,
      notification.detailMessage,
      details,
      payload: payload,
    );
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
        decoded.map(
          (key, value) => MapEntry<String, Object?>(key, value),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
