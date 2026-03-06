import 'package:flutter/material.dart';

import 'src/screens/loading_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/register_screen.dart';
import 'src/theme/spendant_theme.dart';

abstract final class AppRoutes {
  static const onboarding = '/';
  static const loading = '/loading';
  static const login = '/login';
  static const register = '/register';
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
      },
    );
  }
}
