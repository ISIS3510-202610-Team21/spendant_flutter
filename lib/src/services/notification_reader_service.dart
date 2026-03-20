import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationReaderEvent {
  const NotificationReaderEvent({
    required this.eventId,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.bigText,
    required this.subText,
    required this.postedAtMillis,
  });

  factory NotificationReaderEvent.fromMap(Map<Object?, Object?> values) {
    return NotificationReaderEvent(
      eventId: _readString(values['eventId']),
      packageName: _readString(values['packageName']),
      appName: _readString(values['appName']),
      title: _readString(values['title']),
      text: _readString(values['text']),
      bigText: _readString(values['bigText']),
      subText: _readString(values['subText']),
      postedAtMillis: _readInt(values['postedAtMillis']),
    );
  }

  final String eventId;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final String bigText;
  final String subText;
  final int postedAtMillis;

  String get dedupeKey {
    if (eventId.trim().isNotEmpty) {
      return eventId.trim();
    }

    return [
      packageName.trim(),
      appName.trim(),
      postedAtMillis.toString(),
      title.trim(),
      text.trim(),
      bigText.trim(),
      subText.trim(),
    ].join('|');
  }

  static String _readString(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

abstract final class NotificationReaderService {
  static const MethodChannel _methodChannel = MethodChannel(
    'spendant_flutter/notification_reader',
  );
  static const EventChannel _eventChannel = EventChannel(
    'spendant_flutter/notification_reader/events',
  );

  static Stream<NotificationReaderEvent>? _events;

  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<bool> isAccessEnabled() async {
    if (!isSupportedPlatform) {
      return false;
    }

    final enabled = await _methodChannel.invokeMethod<bool>(
      'isNotificationListenerEnabled',
    );
    return enabled ?? false;
  }

  static Future<void> openAccessSettings() async {
    if (!isSupportedPlatform) {
      return;
    }

    await _methodChannel.invokeMethod<void>('openNotificationListenerSettings');
  }

  static Future<List<NotificationReaderEvent>> drainPendingEvents() async {
    if (!isSupportedPlatform) {
      return const <NotificationReaderEvent>[];
    }

    final values = await _methodChannel.invokeMethod<List<dynamic>>(
      'drainPendingEvents',
    );
    if (values == null) {
      return const <NotificationReaderEvent>[];
    }

    return values
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (value) => NotificationReaderEvent.fromMap(
            Map<Object?, Object?>.from(value),
          ),
        )
        .toList(growable: false);
  }

  static Stream<NotificationReaderEvent> get events {
    return _events ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<Object?, Object?>.from(event as Map<dynamic, dynamic>);
      return NotificationReaderEvent.fromMap(map);
    }).asBroadcastStream();
  }
}
