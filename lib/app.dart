import 'dart:async';

import 'package:flutter/material.dart';

import 'src/screens/debug_storage_screen.dart';
import 'src/screens/budget_screen.dart';
import 'src/screens/fingerprint_auth_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/loading_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/new_expense_screen.dart';
import 'src/screens/notifications_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/register_screen.dart';
import 'src/screens/set_goal_screen.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/theme/spendant_theme.dart';

abstract final class AppRoutes {
  static const onboarding = '/';
  static const loading = '/loading';
  static const login = '/login';
  static const register = '/register';
  static const fingerprintAuth = '/fingerprint-auth';
  static const home = '/home';
  static const notifications = '/notifications';
  static const setGoal = '/set-goal';
  static const newExpense = '/new-expense';
  static const debugStorage = '/debug-storage';
  static const budget = '/budget';
}

class SpendAntApp extends StatefulWidget {
  const SpendAntApp({super.key});

  @override
  State<SpendAntApp> createState() => _SpendAntAppState();
}

class _SpendAntAppState extends State<SpendAntApp> {
  static const Duration _syncInterval = Duration(seconds: 20);

  Timer? _syncTimer;
  AppLifecycleListener? _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _startPendingSyncLoop();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _appLifecycleListener?.dispose();
    super.dispose();
  }

  void _startPendingSyncLoop() {
    if (!CloudSyncService.isSupportedPlatform) {
      return;
    }

    _appLifecycleListener = AppLifecycleListener(
      onResume: _syncPendingDataInBackground,
    );

    _syncPendingDataInBackground();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _syncPendingDataInBackground();
    });
  }

  void _syncPendingDataInBackground() {
    unawaited(_runPendingCloudSync());
  }

  Future<void> _runPendingCloudSync() async {
    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      // Keep local data pending until a later retry succeeds.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpendAnt',
      theme: SpendAntTheme.light(),
      initialRoute: AppRoutes.onboarding,
      routes: {
        AppRoutes.onboarding: (_) => const OnboardingScreen(),
        AppRoutes.loading: (_) => const LoadingScreen(),
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.register: (_) => const RegisterScreen(),
        AppRoutes.fingerprintAuth: (_) => const FingerprintAuthScreen(),
        AppRoutes.home: (_) => const HomeScreen(),
        AppRoutes.notifications: (_) => const NotificationsScreen(),
        AppRoutes.setGoal: (_) => const SetGoalScreen(),
        AppRoutes.newExpense: (_) => const NewExpenseScreen(),
        AppRoutes.debugStorage: (_) => const DebugStorageScreen(),
        AppRoutes.budget: (_) => const BudgetScreen(),
      },
    );
  }
}
