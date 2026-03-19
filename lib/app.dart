import 'package:flutter/material.dart';

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
  static const budget = '/budget';
}

class SpendAntApp extends StatelessWidget {
  const SpendAntApp({super.key});

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
        AppRoutes.budget: (_) => const BudgetScreen(),
      },
    );
  }
}
