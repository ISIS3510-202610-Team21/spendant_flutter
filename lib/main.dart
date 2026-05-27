import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/services/app_analytics_service.dart';
import 'src/services/app_notification_service.dart';
import 'src/services/auth_memory_store.dart';
import 'src/services/background_task_service.dart';
import 'src/services/calendar_availability_service.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/services/currency_provider.dart';
import 'src/services/exchange_rate_db_service.dart';
import 'src/services/exchange_rate_sync_service.dart';
import 'src/services/report_cache_service.dart';
import 'src/services/voice_pattern_cache_service.dart';
import 'src/services/firebase_uid_service.dart';
import 'src/services/google_pay_expense_import_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_storage_service.dart';
import 'src/services/sync_log_service.dart';
import 'src/services/wear_expense_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/fonts/ — disable network fetching to guarantee
  // offline availability and eliminate any latency on first paint.
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  FlutterError.onError = (details) {
    AppAnalyticsService.instance.logModuleCrash(
      details.library ?? 'flutter',
      details.exceptionAsString(),
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    AppAnalyticsService.instance.logModuleCrash('platform', error.toString());
    return false;
  };

  unawaited(BackgroundTaskService.initialize());
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<Object?> _startupFuture = _initializeCriticalServices();

  Future<Object?> _initializeCriticalServices() async {
    try {
      await _loadLocalConfiguration();
      await LocalStorageService.init();
      await AuthMemoryStore.initialize();
      debugPrint('LocalStorageService initialized');
      unawaited(_initializeOptionalServices());
      return null;
    } catch (error) {
      debugPrint('Error initializing LocalStorageService: $error');
      return error;
    }
  }

  Future<void> _loadLocalConfiguration() async {
    try {
      await dotenv.load(fileName: '.env');
      debugPrint('Local .env configuration loaded');
    } catch (error) {
      debugPrint('Local .env configuration was not loaded: $error');
    }
  }

  Future<void> _initializeOptionalServices() async {
    try {
      await BackgroundTaskService.initialize();
    } catch (error) {
      debugPrint('Error initializing background tasks: $error');
    }

    try {
      await SyncLogService.init();
      debugPrint('SyncLogService initialized');
    } catch (error) {
      debugPrint('Error initializing SyncLogService: $error');
    }

    try {
      // Exchange rate DB must be ready before the sync check and before
      // CurrencyProvider.loadFromDb() so the in-memory cache is populated.
      await ExchangeRateDbService.init();
      await VoicePatternCacheService.init();
      await ReportCacheService.init();
      await CurrencyProvider.instance.loadFromDb();
      // Background sync runs in a separate Isolate — never blocks UI.
      // When the sync completes (writes new rates to DB), reload the
      // in-memory cache so CurrencyProvider reflects the fresh rates
      // without requiring an app restart.
      unawaited(
        ExchangeRateSyncService.runOnAppLaunch().then((_) async {
          await CurrencyProvider.instance.loadFromDb();
          debugPrint('ExchangeRateService: cache reloaded after sync.');
        }),
      );
      debugPrint('ExchangeRateService initialized');
    } catch (error) {
      debugPrint('Error initializing ExchangeRateService: $error');
    }

    try {
      await CalendarAvailabilityService.instance.initialize();
      await LocalNotificationService.initialize();
      await AppNotificationService.initialize();
      await GooglePayExpenseImportService.initialize();
      await WearExpenseSyncService.instance.initialize();
      debugPrint('Notification services initialized');
    } catch (error) {
      debugPrint('Error initializing notifications: $error');
    }

    if (!CloudSyncService.isSupportedPlatform) {
      debugPrint('Firebase is not available on this platform');
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseUidService.ensureFirebaseUid();
      debugPrint('Firebase initialized');
    } catch (error) {
      debugPrint('Error initializing Firebase: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Object?>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupLoadingApp();
        }

        final error = snapshot.data;
        if (error != null) {
          return _StartupErrorApp(message: 'Storage startup failed: $error');
        }

        return const SpendAntApp();
      },
    );
  }
}

class _StartupLoadingApp extends StatelessWidget {
  const _StartupLoadingApp();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF44C669),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF8B0000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFF176),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
