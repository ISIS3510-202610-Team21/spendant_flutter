import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WearDataLayerEvent {
  const WearDataLayerEvent({
    required this.type,
    required this.path,
    this.payload,
  });

  final String type;
  final String path;
  final Map<String, dynamic>? payload;
}

class WearDataLayerService {
  WearDataLayerService._();

  static final WearDataLayerService instance = WearDataLayerService._();
  static const MethodChannel _methodChannel = MethodChannel(
    'spendant_flutter/wear_data_layer',
  );
  static const EventChannel _eventChannel = EventChannel(
    'spendant_flutter/wear_data_layer/events',
  );

  final StreamController<WearDataLayerEvent> _eventsController =
      StreamController<WearDataLayerEvent>.broadcast();

  StreamSubscription<dynamic>? _nativeEventsSubscription;
  bool _isInitialized = false;
  bool _isAvailable = false;

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isAvailable => _isAvailable;

  Stream<WearDataLayerEvent> get events => _eventsController.stream;

  Future<void> initialize() async {
    if (_isInitialized || !isSupportedPlatform) {
      debugPrint('[WearDL] initialize skipped: _isInitialized=$_isInitialized isSupportedPlatform=$isSupportedPlatform');
      return;
    }

    _isInitialized = true;
    _isAvailable =
        await _methodChannel.invokeMethod<bool>('isAvailable') ?? false;
    debugPrint('[WearDL] isAvailable=$_isAvailable');
    if (!_isAvailable) {
      return;
    }

    _nativeEventsSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[WearDL] stream error: $error');
      },
    );
    debugPrint('[WearDL] event stream subscribed');
  }

  Future<void> dispose() async {
    await _nativeEventsSubscription?.cancel();
    _nativeEventsSubscription = null;
    _isInitialized = false;
    _isAvailable = false;
  }

  Future<void> putJsonData({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    if (!_isAvailable) {
      return;
    }

    await _methodChannel.invokeMethod<void>('putDataItem', <String, dynamic>{
      'path': path,
      'payload': jsonEncode(payload),
    });
  }

  Future<List<WearDataLayerEvent>> getExistingJsonData(String path) async {
    if (!_isAvailable) return [];

    try {
      final rawItems = await _methodChannel.invokeMethod<List<dynamic>>(
            'getDataItems',
            <String, dynamic>{'path': path},
          ) ??
          [];

      return rawItems.whereType<Map<Object?, Object?>>().map((rawItem) {
        final item = rawItem.map((k, v) => MapEntry(k.toString(), v));
        final rawPayload = item['payload']?.toString();
        Map<String, dynamic>? payload;
        if (rawPayload != null && rawPayload.isNotEmpty) {
          final decoded = jsonDecode(rawPayload);
          if (decoded is Map<String, dynamic>) payload = decoded;
        }
        return WearDataLayerEvent(
          type: 'data',
          path: item['path']?.toString() ?? path,
          payload: payload,
        );
      }).toList();
    } catch (error) {
      debugPrint('WearDataLayerService getExistingJsonData error: $error');
      return [];
    }
  }

  Future<int> sendJsonMessage({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    if (!_isAvailable) {
      return 0;
    }

    final connectedNodes =
        await _methodChannel.invokeMethod<int>('sendMessage', <String, dynamic>{
          'path': path,
          'payload': jsonEncode(payload),
        }) ??
        0;
    return connectedNodes;
  }

  void _handleNativeEvent(dynamic rawEvent) {
    if (rawEvent is! Map<Object?, Object?>) {
      return;
    }

    final normalizedEvent = rawEvent.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawPayload = normalizedEvent['payload']?.toString();
    Map<String, dynamic>? payload;
    if (rawPayload != null && rawPayload.isNotEmpty) {
      final decodedPayload = jsonDecode(rawPayload);
      if (decodedPayload is Map<String, dynamic>) {
        payload = decodedPayload;
      }
    }

    _eventsController.add(
      WearDataLayerEvent(
        type: normalizedEvent['type']?.toString() ?? 'unknown',
        path: normalizedEvent['path']?.toString() ?? '',
        payload: payload,
      ),
    );
  }
}
