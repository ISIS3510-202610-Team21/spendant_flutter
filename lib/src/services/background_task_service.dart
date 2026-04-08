import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'app_notification_service.dart';
import 'app_runtime_state_service.dart';
import 'auth_memory_store.dart';
import 'auto_categorization_service.dart';
import 'calendar_availability_service.dart';
import 'google_pay_expense_import_service.dart';
import 'local_notification_service.dart';
import 'local_storage_service.dart';
import 'notification_reader_service.dart';

@pragma('vm:entry-point')
void spendAntBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      return await BackgroundTaskService.handleTask(
        taskName,
        inputData: inputData,
      );
    } catch (error, stackTrace) {
      debugPrint('Background task failed for $taskName: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  });
}

abstract final class BackgroundTaskService {
  static const String maintenanceTaskName = 'notification_maintenance';
  static const String importTaskName = 'notification_event_import';
  static const String maintenanceUniqueName =
      'spendant.notification_maintenance';
  static const String importUniqueName = 'spendant.notification_event_import';
  static const String reasonKey = 'reason';

  static Future<void>? _initializing;
  static bool _didInitialize = false;

  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<void> initialize() async {
    if (!isSupportedPlatform) {
      return;
    }

    final runningInitialization = _initializing;
    if (runningInitialization != null) {
      await runningInitialization;
      return;
    }

    if (_didInitialize) {
      await ensureScheduled();
      return;
    }

    final initialization = _initializeInternal();
    _initializing = initialization;

    try {
      await initialization;
      _didInitialize = true;
    } finally {
      if (identical(_initializing, initialization)) {
        _initializing = null;
      }
    }
  }

  static Future<void> _initializeInternal() async {
    await Workmanager().initialize(spendAntBackgroundDispatcher);
    await ensureScheduled();
  }

  static Future<void> ensureScheduled() async {
    if (!isSupportedPlatform) {
      return;
    }

    await Workmanager().registerPeriodicTask(
      maintenanceUniqueName,
      maintenanceTaskName,
      frequency: const Duration(minutes: 15),
      flexInterval: const Duration(minutes: 5),
      initialDelay: const Duration(minutes: 5),
      existingWorkPolicy: ExistingWorkPolicy.update,
      inputData: const <String, dynamic>{reasonKey: 'periodic_maintenance'},
    );
  }

  static Future<bool> handleTask(
    String taskName, {
    Map<String, dynamic>? inputData,
  }) async {
    if (!isSupportedPlatform) {
      return true;
    }
    if (await AppRuntimeStateService.isForeground()) {
      return true;
    }

    await _ensureBackgroundServicesReady();

    switch (taskName) {
      case importTaskName:
        await _runImportTask(inputData);
        return true;
      case maintenanceTaskName:
        await _runMaintenanceTask();
        return true;
      default:
        return true;
    }
  }

  static Future<void> _ensureBackgroundServicesReady() async {
    await LocalStorageService.init();
    await AuthMemoryStore.initialize();

    try {
      await CalendarAvailabilityService.instance.initialize();
    } catch (error) {
      debugPrint('Background calendar initialization skipped: $error');
    }

    try {
      await LocalNotificationService.initialize();
    } catch (error) {
      debugPrint(
        'Background local notifications initialization skipped: $error',
      );
    }

    await AppNotificationService.initialize();
  }

  static Future<void> _runImportTask(Map<String, dynamic>? inputData) async {
    final event = _eventFromInputData(inputData);
    if (event != null) {
      await GooglePayExpenseImportService.importNotificationEvent(
        event,
        promptForNotificationPermission: false,
      );
    }

    await _runMaintenanceTask();
  }

  static Future<void> _runMaintenanceTask() async {
    await AutoCategorizationService.instance.backfillPendingExpenseCategories();
    await AppNotificationService.refresh(
      promptForNotificationPermission: false,
    );
  }

  static NotificationReaderEvent? _eventFromInputData(
    Map<String, dynamic>? inputData,
  ) {
    if (inputData == null || inputData.isEmpty) {
      return null;
    }
    if ((inputData['eventId']?.toString().trim().isEmpty ?? true) &&
        (inputData['title']?.toString().trim().isEmpty ?? true) &&
        (inputData['text']?.toString().trim().isEmpty ?? true) &&
        (inputData['bigText']?.toString().trim().isEmpty ?? true)) {
      return null;
    }

    return NotificationReaderEvent.fromMap(
      inputData.map<Object?, Object?>(
        (key, value) => MapEntry<Object?, Object?>(key, value),
      ),
    );
  }
}
