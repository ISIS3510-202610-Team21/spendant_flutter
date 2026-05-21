import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense_model.dart';
import 'app_time_format_service.dart';
import 'auth_memory_store.dart';
import 'expense_location_service.dart';
import 'local_storage_service.dart';
import 'wear_data_layer_service.dart';

class WearExpenseSyncService {
  WearExpenseSyncService._();

  static final WearExpenseSyncService instance = WearExpenseSyncService._();
  static const String _recentExpensesPath = '/spendant/expenses/recent';
  static const String _requestRecentExpensesPath =
      '/spendant/expenses/request_recent';
  static const int _recentExpensesLimit = 5;
  static const String _lastSyncedUserIdKey = 'wear_last_synced_user_id';

  StreamSubscription<WearDataLayerEvent>? _eventsSubscription;
  Timer? _syncDebounce;
  ValueListenable<Box<ExpenseModel>>? _expensesListenable;
  bool _isApplyingRemoteChanges = false;
  bool _isInitialized = false;
  int? _lastSyncedUserId;

  int? get syncedUserId => _lastSyncedUserId;

  int? get effectiveUserId {
    final signedInUserId = AuthMemoryStore.currentUserId;
    if (signedInUserId != null) return signedInUserId;
    if (_lastSyncedUserId != null) return _lastSyncedUserId;
    final expenses = LocalStorageService.expenseBox.values.toList()
      ..sort(
        (left, right) =>
            _expenseDateTime(right).compareTo(_expenseDateTime(left)),
      );
    return expenses.isEmpty ? null : expenses.first.userId;
  }

  // True when this process is the phone app (user is signed in).
  bool get _isPhoneSide => AuthMemoryStore.currentUserId != null;

  Future<void> initialize() async {
    debugPrint('[WearSync] initialize called');
    if (_isInitialized || !WearDataLayerService.isSupportedPlatform) {
      debugPrint(
        '[WearSync] skipped: _isInitialized=$_isInitialized '
        'isSupportedPlatform=${WearDataLayerService.isSupportedPlatform}',
      );
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    _lastSyncedUserId = preferences.getInt(_lastSyncedUserIdKey);
    debugPrint(
      '[WearSync] lastSyncedUserId=$_lastSyncedUserId '
      'effectiveUserId=$effectiveUserId',
    );

    await WearDataLayerService.instance.initialize();
    if (!WearDataLayerService.instance.isAvailable) {
      debugPrint('[WearSync] WearDataLayer not available — aborting');
      return;
    }

    _expensesListenable = LocalStorageService.expensesListenable;
    _expensesListenable!.addListener(_handleLocalExpensesChanged);
    _eventsSubscription =
        WearDataLayerService.instance.events.listen(_handleWearEvent);
    _isInitialized = true;
    debugPrint('[WearSync] initialized OK — scheduling first push');
    _scheduleRecentExpensesSync();

    // Read data items already in the Data Layer (pushed before this session
    // started). onDataChanged only fires for new changes, so without this the
    // watch would miss any payload the phone synced while this app was closed.
    final existing = await WearDataLayerService.instance
        .getExistingJsonData(_recentExpensesPath);
    debugPrint('[WearSync] existing data items found: ${existing.length}');
    for (final event in existing) {
      await _handleWearEvent(event);
    }

    unawaited(requestRecentExpenses());
  }

  Future<void> dispose() async {
    _syncDebounce?.cancel();
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _expensesListenable?.removeListener(_handleLocalExpensesChanged);
    _expensesListenable = null;
    _isInitialized = false;
  }

  void _handleLocalExpensesChanged() {
    if (_isApplyingRemoteChanges) return;
    _scheduleRecentExpensesSync();
  }

  void _scheduleRecentExpensesSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(
      const Duration(milliseconds: 450),
      _pushRecentExpensesToWearDataLayer,
    );
  }

  Future<void> requestRecentExpenses() async {
    debugPrint(
      '[WearSync] requestRecentExpenses → effectiveUserId=$effectiveUserId',
    );
    final nodeCount = await WearDataLayerService.instance.sendJsonMessage(
      path: _requestRecentExpensesPath,
      payload: <String, dynamic>{
        'userId': effectiveUserId,
        'requestedAt': DateTime.now().toIso8601String(),
      },
    );
    debugPrint('[WearSync] requestRecentExpenses sent to $nodeCount node(s)');
  }

  Future<void> _pushRecentExpensesToWearDataLayer() async {
    final currentUserId = effectiveUserId;
    debugPrint(
      '[WearSync] _pushRecentExpenses → effectiveUserId=$currentUserId',
    );
    if (currentUserId == null) {
      debugPrint('[WearSync] _pushRecentExpenses aborted — no userId');
      return;
    }

    await _persistSyncedUserId(currentUserId);

    final recentExpenses = LocalStorageService.expenseBox.values
        .where((expense) => expense.userId == currentUserId)
        .toList()
      ..sort(
        (left, right) =>
            _expenseDateTime(right).compareTo(_expenseDateTime(left)),
      );

    final expensesToSend = recentExpenses.take(_recentExpensesLimit).toList();
    debugPrint(
      '[WearSync] pushing ${expensesToSend.length} expenses for '
      'userId=$currentUserId',
    );
    await WearDataLayerService.instance.putJsonData(
      path: _recentExpensesPath,
      payload: <String, dynamic>{
        'userId': currentUserId,
        'generatedAt': DateTime.now().toIso8601String(),
        // Allows the receiving device to know the origin and apply the
        // correct strategy (REPLACE vs ADD).
        'senderIsPhone': _isPhoneSide,
        'expenses': expensesToSend.map(_expenseToMap).toList(growable: false),
      },
    );
    debugPrint('[WearSync] putJsonData done');
  }

  Future<void> _handleWearEvent(WearDataLayerEvent event) async {
    debugPrint(
      '[WearSync] event received: type=${event.type} path=${event.path}',
    );
    if (event.path == _requestRecentExpensesPath) {
      await _pushRecentExpensesToWearDataLayer();
      return;
    }

    if (event.path != _recentExpensesPath) return;

    final payload = event.payload;
    if (payload == null) return;

    final payloadUserId = payload['userId'];
    if (payloadUserId is! int) return;

    final currentUserId = effectiveUserId;
    if (currentUserId != null && payloadUserId != currentUserId) return;

    await _persistSyncedUserId(payloadUserId);

    final expenses = payload['expenses'];
    if (expenses is! List) return;

    // senderIsPhone tells us who pushed this data item.
    final senderIsPhone = payload['senderIsPhone'] == true;

    _isApplyingRemoteChanges = true;
    try {
      if (senderIsPhone && !_isPhoneSide) {
        // Watch receiving phone data → REPLACE all non-watch expenses so
        // deletions on the phone are reflected here too.
        final keysToDelete = LocalStorageService.expenseBox
            .toMap()
            .entries
            .where(
              (e) =>
                  e.value.userId == payloadUserId &&
                  e.value.source != 'WEAR_QUICK_ADD',
            )
            .map((e) => e.key)
            .toList();
        await LocalStorageService.expenseBox.deleteAll(keysToDelete);

        for (final rawExpense in expenses) {
          if (rawExpense is! Map) continue;
          final normalized = rawExpense.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final incomingExpense = _expenseFromMap(normalized);
          if (incomingExpense == null) continue;
          await LocalStorageService.expenseBox.add(incomingExpense);
        }
      } else {
        // Phone receiving watch data (or legacy payload without senderIsPhone)
        // → ADD new expenses only, with location enrichment for watch-created ones.
        for (final rawExpense in expenses) {
          if (rawExpense is! Map) continue;
          final normalized = rawExpense.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final incomingExpense = _expenseFromMap(normalized);
          if (incomingExpense == null || _hasEquivalentExpense(incomingExpense)) {
            continue;
          }
          if (_isPhoneSide && incomingExpense.source == 'WEAR_QUICK_ADD') {
            await _enrichWithLocation(incomingExpense);
          }
          await LocalStorageService.expenseBox.add(incomingExpense);
        }
      }
    } finally {
      _isApplyingRemoteChanges = false;
    }
  }

  // Attempts to set lat/lng/locationName on a watch-created expense when
  // received on the phone. Fails silently if location is unavailable.
  Future<void> _enrichWithLocation(ExpenseModel expense) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      expense.latitude = position.latitude;
      expense.longitude = position.longitude;
      try {
        const locationService = ExpenseLocationService();
        expense.locationName = await locationService.resolveLabel(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (_) {
        expense.locationName = ExpenseLocationService.formatCoordinates(
          position.latitude,
          position.longitude,
        );
      }
    } catch (_) {
      // Location unavailable — proceed without it.
    }
  }

  Future<void> _persistSyncedUserId(int userId) async {
    if (_lastSyncedUserId == userId) return;
    _lastSyncedUserId = userId;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_lastSyncedUserIdKey, userId);
  }

  bool _hasEquivalentExpense(ExpenseModel incomingExpense) {
    final incomingFingerprint = _expenseFingerprint(incomingExpense);
    return LocalStorageService.expenseBox.values.any(
      (existingExpense) =>
          _expenseFingerprint(existingExpense) == incomingFingerprint,
    );
  }

  Map<String, dynamic> _expenseToMap(ExpenseModel expense) {
    return <String, dynamic>{
      'userId': expense.userId,
      'name': expense.name,
      'amount': expense.amount,
      'date': expense.date.toIso8601String(),
      'time': expense.time,
      'source': expense.source,
      'createdAt': expense.createdAt.toIso8601String(),
      'primaryCategory': expense.primaryCategory,
      'detailLabels': expense.detailLabels,
    };
  }

  ExpenseModel? _expenseFromMap(Map<String, dynamic> rawExpense) {
    final date = DateTime.tryParse(rawExpense['date']?.toString() ?? '');
    final createdAt =
        DateTime.tryParse(rawExpense['createdAt']?.toString() ?? '');
    final amount = (rawExpense['amount'] as num?)?.toDouble();
    final userId = rawExpense['userId'] as int?;
    if (date == null || createdAt == null || amount == null || userId == null) {
      return null;
    }

    final expense = ExpenseModel()
      ..userId = userId
      ..name = rawExpense['name']?.toString() ?? 'Expense'
      ..amount = amount
      ..date = date
      ..time = rawExpense['time']?.toString() ?? '00:00'
      ..source = rawExpense['source']?.toString() ?? 'WEAR_SYNC'
      ..createdAt = createdAt
      ..primaryCategory = rawExpense['primaryCategory']?.toString();

    final rawLabels = rawExpense['detailLabels'];
    if (rawLabels is List) {
      expense.detailLabels = rawLabels
          .map((label) => label.toString().trim())
          .where((label) => label.isNotEmpty)
          .toList();
    }

    return expense;
  }

  String _expenseFingerprint(ExpenseModel expense) {
    final normalizedLabel = expense.detailLabels.isEmpty
        ? (expense.primaryCategory ?? '')
        : expense.detailLabels.first;
    return [
      expense.userId,
      expense.name.trim().toLowerCase(),
      expense.amount.round(),
      expense.date.toIso8601String(),
      expense.time.trim(),
      normalizedLabel.trim().toLowerCase(),
    ].join('|');
  }

  DateTime _expenseDateTime(ExpenseModel expense) {
    final parsedTime = AppTimeFormatService.parseHourMinute(expense.time);
    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      parsedTime.hour.clamp(0, 23),
      math.max(0, parsedTime.minute.clamp(0, 59)),
    );
  }
}
