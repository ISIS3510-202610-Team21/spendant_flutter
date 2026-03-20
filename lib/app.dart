import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'src/models/expense_model.dart';
import 'src/models/goal_model.dart';
import 'src/models/income_model.dart';
import 'src/screens/debug_storage_screen.dart';
import 'src/screens/budget_screen.dart';
import 'src/screens/fingerprint_auth_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/loading_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/new_expense_screen.dart';
import 'src/screens/notifications_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/post_register_intro_screen.dart';
import 'src/screens/register_screen.dart';
import 'src/screens/set_goal_screen.dart';
import 'src/services/app_navigation_service.dart';
import 'src/services/app_notification_service.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/services/google_pay_expense_import_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_storage_service.dart';
import 'src/theme/spendant_theme.dart';

abstract final class AppRoutes {
  static const onboarding = '/';
  static const loading = '/loading';
  static const login = '/login';
  static const register = '/register';
  static const registerIntro = '/register-intro';
  static const fingerprintAuth = '/fingerprint-auth';
  static const home = '/home';
  static const notifications = '/notifications';
  static const setGoal = '/set-goal';
  static const newExpense = '/new-expense';
  static const budget = '/budget';
}

class SpendAntApp extends StatelessWidget {
  const SpendAntApp({super.key});

  @override
  State<SpendAntApp> createState() => _SpendAntAppState();
}

class _SpendAntAppState extends State<SpendAntApp> {
  static const Duration _syncInterval = Duration(seconds: 20);

  Timer? _syncTimer;
  Timer? _notificationRefreshTimer;
  AppLifecycleListener? _appLifecycleListener;
  late final ValueListenable<Box<ExpenseModel>> _expensesListenable;
  late final ValueListenable<Box<GoalModel>> _goalsListenable;
  late final ValueListenable<Box<IncomeModel>> _incomesListenable;

  @override
  void initState() {
    super.initState();
    _expensesListenable = LocalStorageService.expensesListenable;
    _goalsListenable = LocalStorageService.goalsListenable;
    _incomesListenable = LocalStorageService.incomesListenable;
    _expensesListenable.addListener(_scheduleAppNotificationRefresh);
    _goalsListenable.addListener(_scheduleAppNotificationRefresh);
    _incomesListenable.addListener(_scheduleAppNotificationRefresh);
    _startPendingSyncLoop();
    _scheduleAppNotificationRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleColdStartNotificationNavigation();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _notificationRefreshTimer?.cancel();
    _appLifecycleListener?.dispose();
    _expensesListenable.removeListener(_scheduleAppNotificationRefresh);
    _goalsListenable.removeListener(_scheduleAppNotificationRefresh);
    _incomesListenable.removeListener(_scheduleAppNotificationRefresh);
    super.dispose();
  }

  void _startPendingSyncLoop() {
    if (!CloudSyncService.isSupportedPlatform) {
      return;
    }

    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(GooglePayExpenseImportService.refresh());
        _syncPendingDataInBackground();
        _scheduleAppNotificationRefresh();
      },
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

  void _scheduleAppNotificationRefresh() {
    _notificationRefreshTimer?.cancel();
    _notificationRefreshTimer = Timer(const Duration(milliseconds: 180), () {
      unawaited(AppNotificationService.refresh());
    });
  }

  Future<void> _handleColdStartNotificationNavigation() async {
    final launchRedirect = LocalNotificationService.takeLaunchRedirect();
    if (launchRedirect == null) {
      return;
    }

    await AppNavigationService.openColdStartRedirect(launchRedirect);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpendAnt',
      theme: SpendAntTheme.light(),
      navigatorKey: AppNavigationService.navigatorKey,
      initialRoute: AppRoutes.onboarding,
      routes: {
        AppRoutes.onboarding: (_) => const OnboardingScreen(),
        AppRoutes.loading: (_) => const LoadingScreen(),
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.register: (_) => const RegisterScreen(),
        AppRoutes.registerIntro: (_) => const PostRegisterIntroScreen(),
        AppRoutes.fingerprintAuth: (_) => const FingerprintAuthScreen(),
        AppRoutes.home: (_) => const HomeScreen(),
        AppRoutes.notifications: (_) => const NotificationsScreen(),
        AppRoutes.setGoal: (_) => const SetGoalScreen(),
        AppRoutes.newExpense: (_) => const NewExpenseScreen(),
        AppRoutes.budget: (_) => const BudgetScreen(),
      },
    );
  }
}
