import 'dart:async';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import 'app_notification_service.dart';
import 'app_time_format_service.dart';
import 'auto_categorization_service.dart';
import 'auth_memory_store.dart';
import 'local_storage_service.dart';
import 'notification_expense_parser.dart';
import 'notification_reader_service.dart';

enum GooglePayImportStatus { imported, duplicate, ignored, unavailable }

class GooglePayImportResult {
  const GooglePayImportResult({required this.status, this.expense});

  final GooglePayImportStatus status;
  final ParsedNotificationExpense? expense;

  bool get imported => status == GooglePayImportStatus.imported;
}

abstract final class GooglePayExpenseImportService {
  static const String _processedEventIdsKey =
      'processed_notification_expense_event_ids_v2';
  static const int _maxProcessedEventIds = 240;
  static final NumberFormat _titleAmountFormat = NumberFormat('#,###', 'es_CO');
  static final NumberFormat _bodyAmountFormat = NumberFormat(
    '#,##0.00',
    'es_CO',
  );
  static int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;
  static final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;

  static StreamSubscription<NotificationReaderEvent>? _subscription;
  static Future<void>? _activeRefresh;
  static bool _isInitialized = false;
  static int _simulationCounter = 0;

  static const List<_GooglePaySimulationTemplate> _simulationTemplates =
      <_GooglePaySimulationTemplate>[
        _GooglePaySimulationTemplate(
          merchantName: 'CAFE QUINDIO EXPRESS TITAN PLAZA',
          baseAmount: 51600,
          cardDigits: '3141',
        ),
        _GooglePaySimulationTemplate(
          merchantName: 'UBER EATS',
          baseAmount: 28900,
          cardDigits: '3141',
        ),
        _GooglePaySimulationTemplate(
          merchantName: 'EXITO CHAPINERO',
          baseAmount: 43600,
          cardDigits: '3141',
        ),
        _GooglePaySimulationTemplate(
          merchantName: 'SPOTIFY',
          baseAmount: 24900,
          cardDigits: '3141',
        ),
      ];

  static Future<void> initialize() async {
    if (_isInitialized || _subscription != null) {
      return;
    }
    _isInitialized = true;

    if (!NotificationReaderService.isSupportedPlatform) {
      return;
    }

    _subscription = NotificationReaderService.events.listen((event) {
      unawaited(_importEventAndDiscard(event));
    });

    await refresh();
  }

  static Future<void> refresh({
    bool promptForNotificationPermission = true,
  }) async {
    if (!NotificationReaderService.isSupportedPlatform) {
      return;
    }

    final currentRefresh = _activeRefresh;
    if (currentRefresh != null) {
      return currentRefresh;
    }

    final refreshFuture = _refreshInternal(
      promptForNotificationPermission: promptForNotificationPermission,
    );
    _activeRefresh = refreshFuture;

    try {
      await refreshFuture;
    } finally {
      if (identical(_activeRefresh, refreshFuture)) {
        _activeRefresh = null;
      }
    }
  }

  static Future<void> _refreshInternal({
    required bool promptForNotificationPermission,
  }) async {
    final pendingEvents = await NotificationReaderService.drainPendingEvents();
    for (final event in pendingEvents) {
      await _importEvent(
        event,
        promptForNotificationPermission: promptForNotificationPermission,
      );
    }
  }

  static Future<GooglePayImportResult> importNotificationEvent(
    NotificationReaderEvent event, {
    bool promptForNotificationPermission = true,
  }) {
    return _importEvent(
      event,
      promptForNotificationPermission: promptForNotificationPermission,
    );
  }

  static Future<GooglePayImportResult> simulateExpenseImport() async {
    final now = DateTime.now();
    final sample =
        _simulationTemplates[_simulationCounter % _simulationTemplates.length];
    _simulationCounter++;

    final amountOffset = (now.millisecond % 17) * 100;
    final amount = sample.baseAmount + amountOffset;
    final titleAmount = _titleAmountFormat.format(amount);
    final bodyAmount = _bodyAmountFormat.format(amount);
    final event = NotificationReaderEvent(
      eventId: 'google-pay-sim-${now.microsecondsSinceEpoch}',
      packageName: 'com.google.android.apps.walletnfcrel',
      appName: 'Google Wallet',
      title: 'Compra aprobada por \$$titleAmount',
      text:
          'Tu compra en ${sample.merchantName} por \$$bodyAmount con tu tarjeta terminada en ${sample.cardDigits} ha sido APROBADA.',
      bigText:
          'Tu compra en ${sample.merchantName} por \$$bodyAmount con tu tarjeta terminada en ${sample.cardDigits} ha sido APROBADA.',
      subText: '',
      postedAtMillis: now.millisecondsSinceEpoch,
    );

    return _importEvent(event, promptForNotificationPermission: true);
  }

  static Future<GooglePayImportResult> _importEvent(
    NotificationReaderEvent event, {
    required bool promptForNotificationPermission,
  }) async {
    if (_currentUserId < 0) {
      return const GooglePayImportResult(
        status: GooglePayImportStatus.unavailable,
      );
    }

    final parsedExpense = NotificationExpenseParser.parse(event);
    if (parsedExpense == null) {
      return const GooglePayImportResult(status: GooglePayImportStatus.ignored);
    }

    final prefs = await SharedPreferences.getInstance();
    final processedIds =
        prefs.getStringList(_processedEventIdsKey) ?? <String>[];
    final dedupeKey = event.dedupeKey;
    if (processedIds.contains(dedupeKey)) {
      return GooglePayImportResult(
        status: GooglePayImportStatus.duplicate,
        expense: parsedExpense,
      );
    }

    if (_hasMatchingImportedExpense(parsedExpense)) {
      await _markEventAsProcessed(prefs, processedIds, dedupeKey);
      return GooglePayImportResult(
        status: GooglePayImportStatus.duplicate,
        expense: parsedExpense,
      );
    }

    final expenseDate = DateTime(
      parsedExpense.dateTime.year,
      parsedExpense.dateTime.month,
      parsedExpense.dateTime.day,
    );
    final categorization = await _autoCategorizationService.categorizeExpense(
      parsedExpense.name,
    );
    final detailLabels = categorization.assigned
        ? List<String>.from(categorization.detailLabels)
        : <String>[];

    final expense = ExpenseModel()
      ..userId = _currentUserId
      ..name = parsedExpense.name
      ..amount = parsedExpense.amount
      ..date = expenseDate
      ..time =
          '${parsedExpense.dateTime.hour.toString().padLeft(2, '0')}:${parsedExpense.dateTime.minute.toString().padLeft(2, '0')}'
      ..source = parsedExpense.source
      ..locationName = parsedExpense.locationName
      ..isPendingCategory = !categorization.assigned
      ..createdAt = parsedExpense.dateTime
      ..primaryCategory = categorization.primaryCategory
      ..detailLabels = detailLabels
      ..wasAutoCategorized = categorization.assigned;

    await LocalStorageService().saveExpense(expense);
    if (expense.isPendingCategory) {
      await _showImportedNeedsCategoryNotification(
        expense,
        parsedExpense,
        promptForNotificationPermission: promptForNotificationPermission,
      );
    } else {
      await _showImportedExpenseNotification(
        expense,
        parsedExpense,
        promptForNotificationPermission: promptForNotificationPermission,
      );
    }
    await _markEventAsProcessed(prefs, processedIds, dedupeKey);
    return GooglePayImportResult(
      status: GooglePayImportStatus.imported,
      expense: parsedExpense,
    );
  }

  static Future<void> _importEventAndDiscard(
    NotificationReaderEvent event,
  ) async {
    await _importEvent(event, promptForNotificationPermission: true);
  }

  static bool _hasMatchingImportedExpense(ParsedNotificationExpense candidate) {
    for (final expense in LocalStorageService.expenseBox.values) {
      if (expense.userId != _currentUserId) {
        continue;
      }
      if (!_merchantNamesLikelyMatch(expense.name, candidate.name)) {
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
      if (minuteDifference <= 5) {
        return true;
      }
    }

    return false;
  }

  static bool _merchantNamesLikelyMatch(String left, String right) {
    final normalizedLeft = _normalizeMerchantName(left);
    final normalizedRight = _normalizeMerchantName(right);
    if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
      return false;
    }

    return normalizedLeft == normalizedRight ||
        normalizedLeft.contains(normalizedRight) ||
        normalizedRight.contains(normalizedLeft);
  }

  static String _normalizeMerchantName(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(?:compra|pagaste|pago|transaccion|transacción|aprobada|aprobado|bold|nequi|gmail|google|pay|wallet)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static DateTime _expenseDateTime(ExpenseModel expense) {
    final parsedTime = AppTimeFormatService.parseHourMinute(expense.time);

    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      parsedTime.hour,
      parsedTime.minute,
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

  static Future<void> _showImportedExpenseNotification(
    ExpenseModel expense,
    ParsedNotificationExpense parsedExpense, {
    required bool promptForNotificationPermission,
  }) async {
    final sourceLabel = _sourceLabel(parsedExpense.source);
    final notification = AppNotificationModel()
      ..id = 'expense-imported-${expense.createdAt.microsecondsSinceEpoch}'
      ..type = AppNotificationTypes.expenseImported
      ..createdAt = DateTime.now()
      ..userId = expense.userId
      ..title = 'Imported from $sourceLabel'
      ..subtitle = expense.name
      ..amount = expense.amount
      ..category = expense.primaryCategory
      ..detailTitle = 'Expense imported automatically'
      ..detailMessage =
          'SpendAnt imported ${expense.name} for ${_formatCurrency(expense.amount)} from $sourceLabel and added it to your expenses.'
      ..routeName = '/notifications';
    await AppNotificationService.deliverNotification(
      notification,
      promptForNotificationPermission: promptForNotificationPermission,
    );
  }

  static Future<void> _showImportedNeedsCategoryNotification(
    ExpenseModel expense,
    ParsedNotificationExpense parsedExpense, {
    required bool promptForNotificationPermission,
  }) async {
    final sourceLabel = _sourceLabel(parsedExpense.source);
    final notification = AppNotificationModel()
      ..id = 'expense-import-review-${expense.createdAt.microsecondsSinceEpoch}'
      ..type = AppNotificationTypes.expenseImportedNeedsCategory
      ..createdAt = DateTime.now()
      ..userId = expense.userId
      ..title = 'Imported from $sourceLabel'
      ..subtitle = 'Needs category: ${expense.name}'
      ..amount = expense.amount
      ..detailTitle = 'Imported, but category is still missing'
      ..detailMessage =
          'SpendAnt imported ${expense.name} for ${_formatCurrency(expense.amount)} from $sourceLabel, but it still needs a category. Open Notifications and assign one.'
      ..routeName = '/notifications';
    await AppNotificationService.deliverNotification(
      notification,
      promptForNotificationPermission: promptForNotificationPermission,
    );
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case 'GOOGLE_PAY':
        return 'Google Pay';
      case 'GMAIL':
        return 'Gmail';
      case 'NEQUI':
        return 'Nequi';
      default:
        return 'notifications';
    }
  }

  static String _formatCurrency(double amount) {
    return 'COP ${_titleAmountFormat.format(amount.round())}';
  }
}

class _GooglePaySimulationTemplate {
  const _GooglePaySimulationTemplate({
    required this.merchantName,
    required this.baseAmount,
    required this.cardDigits,
  });

  final String merchantName;
  final int baseAmount;
  final String cardDigits;
}
