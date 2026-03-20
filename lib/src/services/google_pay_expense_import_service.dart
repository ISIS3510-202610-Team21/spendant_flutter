import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense_model.dart';
import 'auth_memory_store.dart';
import 'google_pay_notification_parser.dart';
import 'local_storage_service.dart';
import 'notification_reader_service.dart';

abstract final class GooglePayExpenseImportService {
  static const String _processedEventIdsKey =
      'processed_google_pay_notification_event_ids_v1';
  static const int _maxProcessedEventIds = 240;
  static int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  static StreamSubscription<NotificationReaderEvent>? _subscription;
  static Future<void>? _activeRefresh;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized || _subscription != null) {
      return;
    }
    _isInitialized = true;

    if (!NotificationReaderService.isSupportedPlatform) {
      return;
    }

    _subscription = NotificationReaderService.events.listen((event) {
      unawaited(_importEvent(event));
    });

    await refresh();
  }

  static Future<void> refresh() async {
    if (!NotificationReaderService.isSupportedPlatform) {
      return;
    }

    final currentRefresh = _activeRefresh;
    if (currentRefresh != null) {
      return currentRefresh;
    }

    final refreshFuture = _refreshInternal();
    _activeRefresh = refreshFuture;

    try {
      await refreshFuture;
    } finally {
      if (identical(_activeRefresh, refreshFuture)) {
        _activeRefresh = null;
      }
    }
  }

  static Future<void> _refreshInternal() async {
    final pendingEvents = await NotificationReaderService.drainPendingEvents();
    for (final event in pendingEvents) {
      await _importEvent(event);
    }
  }

  static Future<void> _importEvent(NotificationReaderEvent event) async {
    if (_currentUserId < 0) {
      return;
    }

    final parsedExpense = GooglePayNotificationParser.parse(event);
    if (parsedExpense == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final processedIds =
        prefs.getStringList(_processedEventIdsKey) ?? <String>[];
    final dedupeKey = event.dedupeKey;
    if (processedIds.contains(dedupeKey)) {
      return;
    }

    if (_hasMatchingImportedExpense(parsedExpense)) {
      await _markEventAsProcessed(prefs, processedIds, dedupeKey);
      return;
    }

    final expenseDate = DateTime(
      parsedExpense.dateTime.year,
      parsedExpense.dateTime.month,
      parsedExpense.dateTime.day,
    );

    final expense = ExpenseModel()
      ..userId = _currentUserId
      ..name = parsedExpense.name
      ..amount = parsedExpense.amount
      ..date = expenseDate
      ..time =
          '${parsedExpense.dateTime.hour.toString().padLeft(2, '0')}:${parsedExpense.dateTime.minute.toString().padLeft(2, '0')}'
      ..source = 'GOOGLE_PAY'
      ..isPendingCategory = parsedExpense.detailLabels.isEmpty
      ..createdAt = parsedExpense.dateTime
      ..primaryCategory = parsedExpense.primaryCategory
      ..detailLabels = List<String>.from(parsedExpense.detailLabels);

    await LocalStorageService().saveExpense(expense);
    await _markEventAsProcessed(prefs, processedIds, dedupeKey);
  }

  static bool _hasMatchingImportedExpense(ParsedGooglePayExpense candidate) {
    for (final expense in LocalStorageService.expenseBox.values) {
      if (expense.source != 'GOOGLE_PAY') {
        continue;
      }
      if (expense.name.trim().toLowerCase() !=
          candidate.name.trim().toLowerCase()) {
        continue;
      }
      if ((expense.amount - candidate.amount).abs() > 0.01) {
        continue;
      }

      final storedDateTime = _expenseDateTime(expense);
      final minuteDifference = storedDateTime
          .difference(candidate.dateTime)
          .inMinutes
          .abs();
      if (minuteDifference <= 2) {
        return true;
      }
    }

    return false;
  }

  static DateTime _expenseDateTime(ExpenseModel expense) {
    final parts = expense.time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      hour,
      minute,
    );
  }

  static Future<void> _markEventAsProcessed(
    SharedPreferences prefs,
    List<String> currentProcessedIds,
    String dedupeKey,
  ) async {
    final updatedIds = <String>[
      ...currentProcessedIds.where((value) => value != dedupeKey),
      dedupeKey,
    ];

    if (updatedIds.length > _maxProcessedEventIds) {
      updatedIds.removeRange(0, updatedIds.length - _maxProcessedEventIds);
    }

    await prefs.setStringList(_processedEventIdsKey, updatedIds);
  }
}
