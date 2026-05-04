import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'cloud_sync_service.dart';
import 'connectivity_service.dart';
import 'local_notification_service.dart';

/// Monitors internet connectivity and exposes it as a [ValueNotifier].
/// Also fires a persistent system notification when the device goes offline,
/// and cancels it automatically when connectivity is restored.
abstract final class ConnectivityMonitor {
  static const int _offlineNotificationId = 0x4F464C4E; // 'OFLN'

  static final ValueNotifier<bool> _isOnline = ValueNotifier<bool>(true);

  static ValueListenable<bool> get isOnlineListenable => _isOnline;
  static bool get isOnline => _isOnline.value;

  static StreamSubscription<bool>? _subscription;
  static bool _offlineNotificationShown = false;

  static Future<void> initialize({
    ConnectivityService? connectivityService,
  }) async {
    final service = connectivityService ?? DefaultConnectivityService();

    // Seed initial state.
    final initialState = await service.hasInternetConnection();
    _isOnline.value = initialState;

    // Listen to changes.
    _subscription?.cancel();
    _subscription = service.connectivityStream.listen(_handleConnectivityChange);
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  static void _handleConnectivityChange(bool isConnected) {
    if (_isOnline.value == isConnected) {
      return;
    }

    _isOnline.value = isConnected;

    if (!isConnected) {
      _showOfflineNotification();
    } else {
      _cancelOfflineNotification();
      _syncOnReconnect();
    }
  }

  static void _syncOnReconnect() {
    unawaited(CloudSyncService().syncAllPendingData());
  }

  static void _showOfflineNotification() {
    if (_offlineNotificationShown) {
      return;
    }
    _offlineNotificationShown = true;
    unawaited(_sendOfflineNotification());
  }

  static void _cancelOfflineNotification() {
    if (!_offlineNotificationShown) {
      return;
    }
    _offlineNotificationShown = false;
    unawaited(LocalNotificationService.cancelNotification(_offlineNotificationId));
  }

  static Future<void> _sendOfflineNotification() async {
    try {
      final hasPermission = await LocalNotificationService.ensurePermission(
        promptIfNeeded: false,
      );
      if (!hasPermission) {
        return;
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'spendant_alerts',
          'SpendAnt Alerts',
          channelDescription:
              'Goal, budget, and spending alerts generated locally by SpendAnt.',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: false,
          icon: 'ic_stat_spendant',
          color: const Color(0xFF44C669),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      );

      await LocalNotificationService.showRawNotification(
        notificationId: _offlineNotificationId,
        title: 'Working offline',
        body:
            'Expenses and other data will be created locally and sent to the cloud when internet connection is available.',
        details: details,
      );
    } catch (error) {
      debugPrint('ConnectivityMonitor: failed to show offline notification: $error');
    }
  }
}
