import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/services/app_notification_service.dart';
import 'src/services/auth_memory_store.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/services/firebase_uid_service.dart';
import 'src/services/google_pay_expense_import_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      await LocalNotificationService.initialize();
      await AppNotificationService.initialize();
      await GooglePayExpenseImportService.initialize();
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
