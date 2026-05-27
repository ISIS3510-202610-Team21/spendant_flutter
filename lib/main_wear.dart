import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

import 'src/screens/expense_watch_screen.dart';
import 'src/services/auth_memory_store.dart';
import 'src/services/currency_provider.dart';
import 'src/services/local_storage_service.dart';
import 'src/services/wear_expense_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const _WearBootstrapApp());
}

class _WearBootstrapApp extends StatefulWidget {
  const _WearBootstrapApp();

  @override
  State<_WearBootstrapApp> createState() => _WearBootstrapAppState();
}

class _WearBootstrapAppState extends State<_WearBootstrapApp> {
  late final Future<Object?> _startupFuture = _initializeWearServices();

  Future<Object?> _initializeWearServices() async {
    try {
      await _loadLocalConfiguration();
      await LocalStorageService.init();
      await AuthMemoryStore.initialize();
      // Restore persisted ISO before sync arrives so voice parsing uses the
      // correct defaultCurrency from the very first frame.
      await CurrencyProvider.instance.restoreFromPrefs();
      await WearExpenseSyncService.instance.initialize();
      return null;
    } catch (error) {
      return error;
    }
  }

  Future<void> _loadLocalConfiguration() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Wear builds can run without local .env configuration.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Object?>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _WearLoadingApp();
        }

        final error = snapshot.data;
        if (error != null) {
          return _WearErrorApp(message: 'Wear startup failed: $error');
        }

        return const _SpendAntWearApp();
      },
    );
  }
}

class _SpendAntWearApp extends StatelessWidget {
  const _SpendAntWearApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpendAnt Watch',
      home: ExpenseWatchScreen(),
    );
  }
}

class _WearLoadingApp extends StatelessWidget {
  const _WearLoadingApp();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _WearErrorApp extends StatelessWidget {
  const _WearErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
