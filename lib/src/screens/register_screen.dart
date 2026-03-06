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
      onFooterPressed: () =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.login),
    );
  }
}
