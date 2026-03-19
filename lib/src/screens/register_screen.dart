import 'package:flutter/material.dart';

import '../../app.dart';
import 'login_screen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthCredentialsScreen(
      primaryLabel: 'Register',
      showConfirmPassword: true,
      footerText: 'Already got an account?',
      footerActionLabel: 'Login',
      antAssetPath: 'web/ant/ant_login.svg',
      antLeft: -28,
      antBottom: -56,
      antHeight: 460,
      onFooterPressed: () =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.login),
    );
  }
}
