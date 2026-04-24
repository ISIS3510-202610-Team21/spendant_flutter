import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notification_reader_service.dart';

/// Reads bank/payment SMS messages and surfaces them as [NotificationReaderEvent]s
/// so the rest of the import pipeline (parser, dedup, import service) can treat
/// them identically to notification-based events.
///
/// Requires [Permission.sms] at runtime (READ_SMS + RECEIVE_SMS in the manifest).
/// All methods return empty/false silently when permission is denied, so callers
/// do not need to guard against exceptions.
abstract final class SmsReaderService {
  static const MethodChannel _methodChannel = MethodChannel(
    'spendant_flutter/sms_reader',
  );
  static const EventChannel _eventChannel = EventChannel(
    'spendant_flutter/sms_reader/events',
  );

  static Stream<NotificationReaderEvent>? _events;

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<bool> hasPermission() async {
    if (!isSupportedPlatform) return false;
    return Permission.sms.isGranted;
  }

  /// Asks the OS for READ_SMS + RECEIVE_SMS. Returns true if granted.
  static Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// Queries the SMS inbox for the last 48 hours and returns events whose body
  /// contains expense-related keywords. Returns [] if permission is denied.
  static Future<List<NotificationReaderEvent>> drainRecentSms() async {
    if (!isSupportedPlatform) return const <NotificationReaderEvent>[];
    if (!await hasPermission()) return const <NotificationReaderEvent>[];

    try {
      final values = await _methodChannel.invokeMethod<List<dynamic>>(
        'drainRecentSms',
      );
      if (values == null) return const <NotificationReaderEvent>[];
      return values
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (v) => NotificationReaderEvent.fromMap(
              Map<Object?, Object?>.from(v),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <NotificationReaderEvent>[];
    }
  }

  /// Live stream of incoming SMS events forwarded by [SmsBroadcastReceiver].
  /// Only fires when [Permission.sms] (RECEIVE_SMS) is granted on the device.
  static Stream<NotificationReaderEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          return NotificationReaderEvent.fromMap(
            Map<Object?, Object?>.from(event as Map<dynamic, dynamic>),
          );
        })
        .asBroadcastStream();
  }
}
