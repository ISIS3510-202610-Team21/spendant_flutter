import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/auth_memory_store.dart';
import '../widgets/auth_chrome.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthCredentialsScreen(
      primaryLabel: 'Login',
      footerText: 'You got no account?',
      footerActionLabel: 'Register',
      antLeft: -20,
      antBottom: -60,
      antHeight: 300,
      onFooterPressed: () =>
          Navigator.of(context).pushNamed(AppRoutes.register),
    );
  }
}

class AuthCredentialsScreen extends StatefulWidget {
  const AuthCredentialsScreen({
    super.key,
    required this.primaryLabel,
    required this.footerText,
    required this.footerActionLabel,
    required this.antLeft,
    required this.antBottom,
    required this.antHeight,
    required this.onFooterPressed,
    this.showConfirmPassword = false,
  });

  final String primaryLabel;
  final String footerText;
  final String footerActionLabel;
  final double antLeft;
  final double antBottom;
  final double antHeight;
  final VoidCallback onFooterPressed;
  final bool showConfirmPassword;

  @override
  State<AuthCredentialsScreen> createState() => _AuthCredentialsScreenState();
}

class _AuthCredentialsScreenState extends State<AuthCredentialsScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isPasswordHidden = true;
  bool _isConfirmPasswordHidden = true;

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordHidden = !_isPasswordHidden;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _isConfirmPasswordHidden = !_isConfirmPasswordHidden;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    await AuthMemoryStore.saveLogin(username.isEmpty ? 'there' : username);
    if (!mounted) {
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      resizeToAvoidBottomInset: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned(
                left: widget.antLeft,
                bottom: widget.antBottom,
                child: AntAsset(
                  'web/ant/Standing.svg',
                  height: widget.antHeight,
                ),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 38),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 124),
                        const SpendAntWordmark(),
                        const SizedBox(height: 42),
                        TextField(
                          controller: _usernameController,
                          decoration: _fieldDecoration('Username'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          obscureText: _isPasswordHidden,
                          decoration: _fieldDecoration(
                            'Password',
                            suffixIcon: IconButton(
                              onPressed: _togglePasswordVisibility,
                              icon: Icon(
                                _isPasswordHidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        if (widget.showConfirmPassword) ...[
                          const SizedBox(height: 14),
                          TextField(
                            obscureText: _isConfirmPasswordHidden,
                            decoration: _fieldDecoration(
                              'Confirm password',
                              suffixIcon: IconButton(
                                onPressed: _toggleConfirmPasswordVisibility,
                                icon: Icon(
                                  _isConfirmPasswordHidden
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        BlackPrimaryButton(
                          label: widget.primaryLabel,
                          width: widget.showConfirmPassword ? 128 : 103,
                          height: 46,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            Text(
                              widget.footerText,
                              style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onFooterPressed,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              child: Text(widget.footerActionLabel),
                            ),
                          ],
                        ),
                        SizedBox(
                          height:
                              constraints.maxHeight *
                              (widget.showConfirmPassword ? 0.29 : 0.34),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration(String hintText, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF616161),
      ),
      suffixIcon: suffixIcon,
    );
  }
}
