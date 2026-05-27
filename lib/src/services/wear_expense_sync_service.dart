import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense_model.dart';
import '../theme/expense_visuals.dart';
import 'app_time_format_service.dart';
import 'currency_provider.dart';
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
  static const String _monthlyCategoriesKey = 'wear_monthly_categories';

  StreamSubscription<WearDataLayerEvent>? _eventsSubscription;
  Timer? _syncDebounce;
  ValueListenable<Box<ExpenseModel>>? _expensesListenable;
  bool _isApplyingRemoteChanges = false;
  bool _isInitialized = false;
  // Serial queue — ensures concurrent _handleWearEvent calls never interleave,
  // eliminating duplicate insertions and race conditions on both phone and watch.
  Future<void> _eventProcessingChain = Future<void>.value();
  int? _lastSyncedUserId;
  List<ExpenseCategoryTotal> _storedMonthlyCategories =
      const <ExpenseCategoryTotal>[];

  int? get syncedUserId => _lastSyncedUserId;

  /// Monthly category totals received from the phone side.
  /// Empty list means not yet received — fall back to local computation.
  List<ExpenseCategoryTotal> get storedMonthlyCategories =>
      _storedMonthlyCategories;

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
    _storedMonthlyCategories = _loadCategoriesFromPrefs(preferences);
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
        WearDataLayerService.instance.events.listen(_enqueueWearEvent);
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
      _enqueueWearEvent(event);
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

    // Phone computes monthly totals from ALL expenses so the watch chart is
    // accurate regardless of the 5-expense local cap.
    final monthlyCategoryMaps = _isPhoneSide
        ? ExpenseVisuals.topCategoryTotalsForMonth(
              LocalStorageService.expenseBox.values
                  .where((e) => e.userId == currentUserId),
              limit: 3,
            )
            .map((c) => <String, dynamic>{'label': c.label, 'amount': c.amount})
            .toList(growable: false)
        : null;

    await WearDataLayerService.instance.putJsonData(
      path: _recentExpensesPath,
      payload: <String, dynamic>{
        'userId': currentUserId,
        'generatedAt': DateTime.now().toIso8601String(),
        // Allows the receiving device to know the origin and apply the
        // correct strategy (REPLACE vs ADD).
        'senderIsPhone': _isPhoneSide,
        'expenses': expensesToSend.map(_expenseToMap).toList(growable: false),
        'monthlyCategoryTotals': ?monthlyCategoryMaps,
        // Phone sends its active currency so the watch can display amounts in
        // the same currency as the phone without needing the full rates DB.
        if (_isPhoneSide) 'activeCurrency': CurrencyProvider.instance.activeCurrency,
        if (_isPhoneSide) 'activeRate': CurrencyProvider.instance.activeRate,
      },
    );
    debugPrint('[WearSync] putJsonData done');
  }

  /// Enqueues [event] onto the serial processing chain so that concurrent
  /// Wear Data Layer callbacks (stream + existing-items replay) never interleave
  /// inside [_handleWearEvent] and cause duplicate insertions.
  void _enqueueWearEvent(WearDataLayerEvent event) {
    _eventProcessingChain = _eventProcessingChain
        .then((_) => _handleWearEvent(event))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[WearSync] _handleWearEvent error: $error\n$stackTrace');
        });
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

    // If phone sent data, apply currency + monthly totals before touching Hive
    // so that listeners already see fresh state when Hive changes fire.
    if (senderIsPhone && !_isPhoneSide) {
      // Sync active currency from phone so watch displays amounts in the same
      // currency without needing the full exchange-rate database.
      final activeCurrency = payload['activeCurrency']?.toString();
      final activeRate = (payload['activeRate'] as num?)?.toDouble();
      if (activeCurrency != null && activeRate != null && activeRate > 0) {
        CurrencyProvider.instance.setActiveCurrency(activeCurrency, activeRate);
      }

      final rawTotals = payload['monthlyCategoryTotals'];
      if (rawTotals is List) {
        final parsed = <ExpenseCategoryTotal>[];
        for (final item in rawTotals) {
          if (item is Map) {
            final label = item['label']?.toString();
            final amount = (item['amount'] as num?)?.toDouble();
            if (label != null && amount != null) {
              parsed.add(ExpenseCategoryTotal(label: label, amount: amount));
            }
          }
        }
        if (parsed.isNotEmpty) {
          await _persistMonthlyCategories(parsed);
        }
      }
    }

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
        // → ADD new WEAR_QUICK_ADD expenses only, with location enrichment.
        //
        // Expenses with any other source originated on the phone and were
        // merely reflected onto the watch. Re-adding them on the phone would
        // resurrect intentionally-deleted expenses, so they are skipped.
        for (final rawExpense in expenses) {
          if (rawExpense is! Map) continue;
          final normalized = rawExpense.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final incomingExpense = _expenseFromMap(normalized);
          if (incomingExpense == null) continue;
          // Only accept watch-created expenses; skip phone-originated ones.
          if (_isPhoneSide &&
              incomingExpense.source != 'WEAR_QUICK_ADD') {
            continue;
          }
          if (_hasEquivalentExpense(incomingExpense)) continue;
          if (_isPhoneSide) {
            await _enrichWithLocation(incomingExpense);
          }
          await LocalStorageService.expenseBox.add(incomingExpense);
        }
      }
    } finally {
      // Delay resetting the guard by one event-loop turn so that any async
      // Hive ValueListenable callbacks (which fire after the awaited add/delete
      // Futures resolve) still see the flag as true and skip re-triggering sync.
      await Future<void>.delayed(Duration.zero);
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

  Future<void> _persistMonthlyCategories(
    List<ExpenseCategoryTotal> categories,
  ) async {
    _storedMonthlyCategories = categories;
    final encoded = jsonEncode(
      categories
          .map((c) => <String, dynamic>{'label': c.label, 'amount': c.amount})
          .toList(),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_monthlyCategoriesKey, encoded);
  }

  static List<ExpenseCategoryTotal> _loadCategoriesFromPrefs(
    SharedPreferences preferences,
  ) {
    final raw = preferences.getString(_monthlyCategoriesKey);
    if (raw == null) return const <ExpenseCategoryTotal>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((item) {
            final label = item['label']?.toString();
            final amount = (item['amount'] as num?)?.toDouble();
            if (label == null || amount == null) return null;
            return ExpenseCategoryTotal(label: label, amount: amount);
          })
          .whereType<ExpenseCategoryTotal>()
          .toList();
    } catch (_) {
      return const <ExpenseCategoryTotal>[];
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
    // Use only the date portion (YYYY-MM-DD) + the HH:mm time string.
    // Full toIso8601String() includes sub-millisecond precision that is lost
    // when Hive round-trips the DateTime, causing fingerprint mismatches and
    // duplicate insertions on every sync cycle.
    final dateKey =
        '${expense.date.year.toString().padLeft(4, '0')}'
        '-${expense.date.month.toString().padLeft(2, '0')}'
        '-${expense.date.day.toString().padLeft(2, '0')}';
    return [
      expense.userId,
      expense.name.trim().toLowerCase(),
      expense.amount.round(),
      dateKey,
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
