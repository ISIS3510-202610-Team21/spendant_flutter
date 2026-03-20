import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../models/user_model.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_storage_service.dart';
import '../widgets/auth_chrome.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final postAuthNavigationArgs =
        args is PostAuthNavigationArgs ? args : null;

    return AuthCredentialsScreen(
      primaryLabel: 'Login',
      successRoute: AppRoutes.home,
      footerText: 'You got no account?',
      footerActionLabel: 'Register',
      antAssetPath: 'web/ant/ant_login.svg',
      antLeft: -28,
      antBottom: -56,
      antHeight: 460,
      onFooterPressed: () =>
          Navigator.of(context).pushNamed(AppRoutes.register),
      postAuthRedirect: postAuthNavigationArgs?.redirect,
    );
  }
}

class AuthCredentialsScreen extends StatefulWidget {
  const AuthCredentialsScreen({
    super.key,
    required this.primaryLabel,
    required this.successRoute,
    required this.footerText,
    required this.footerActionLabel,
    required this.antAssetPath,
    required this.antLeft,
    required this.antBottom,
    required this.antHeight,
    required this.onFooterPressed,
    this.postAuthRedirect,
    this.showEmail = false,
  });

  final String primaryLabel;
  final String successRoute;
  final String footerText;
  final String footerActionLabel;
  final String antAssetPath;
  final double antLeft;
  final double antBottom;
  final double antHeight;
  final VoidCallback onFooterPressed;
  final AppRedirect? postAuthRedirect;
  final bool showEmail;

  @override
  State<AuthCredentialsScreen> createState() => _AuthCredentialsScreenState();
}

class _AuthCredentialsScreenState extends State<AuthCredentialsScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isPasswordHidden = true;

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordHidden = !_isPasswordHidden;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _buildHandle(String username) {
    final normalized = username.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final safeValue = normalized.isEmpty ? 'spendant' : normalized;
    return '@$safeValue';
  }

  Future<void> _saveUserLocally(String username) async {
    final normalizedUsername = username.isEmpty ? 'there' : username;
    final userBox = LocalStorageService.userBox;
    final now = DateTime.now();

    if (userBox.isNotEmpty) {
      final existingUser = userBox.getAt(0);
      if (existingUser != null) {
        existingUser.username = normalizedUsername;
        existingUser.displayName = normalizedUsername;
        existingUser.handle = _buildHandle(normalizedUsername);
        existingUser.isSynced = false;
        if (existingUser.createdAt.millisecondsSinceEpoch <= 0) {
          existingUser.createdAt = now;
        }
        await existingUser.save();
        return;
      }
    }

    final user = UserModel()
      ..username = normalizedUsername
      ..displayName = normalizedUsername
      ..handle = _buildHandle(normalizedUsername)
      ..email = ''
      ..createdAt = now
      ..isSynced = false;

    await LocalStorageService().saveUser(user);
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    await AuthMemoryStore.saveLogin(username.isEmpty ? 'there' : username);
    await _saveUserLocally(username);
    unawaited(CloudSyncService().syncAllPendingData());
    if (!mounted) {
      return;
    }
    final redirect = widget.postAuthRedirect;
    if (redirect != null) {
      await AppNavigationService.openRedirect(redirect);
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(widget.successRoute, (route) => false);
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
                  widget.antAssetPath,
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
                        if (widget.showEmail) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _fieldDecoration('Email'),
                          ),
                        ],
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
                        const SizedBox(height: 20),
                        BlackPrimaryButton(
                          label: widget.primaryLabel,
                          width: widget.showEmail ? 128 : 103,
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
                              (widget.showEmail ? 0.29 : 0.34),
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
