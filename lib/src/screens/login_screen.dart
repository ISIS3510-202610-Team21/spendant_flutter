import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../models/user_model.dart';
import '../services/app_notification_service.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/firebase_uid_service.dart';
import '../services/post_auth_navigation.dart';
import '../widgets/auth_chrome.dart';
import '../theme/spendant_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final postAuthNavigationArgs = args is PostAuthNavigationArgs ? args : null;

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
  final AuthService _authService = AuthService();
  final BiometricAuthService _biometricAuthService = BiometricAuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordHidden = true;
  bool _isSubmitting = false;
  String? _errorText;

  bool get _isRegisterMode => widget.showEmail;

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordHidden = !_isPasswordHidden;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final validationError = _validateFields(
      username: username,
      email: email,
      password: password,
    );

    if (validationError != null) {
      setState(() {
        _errorText = validationError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final result = _isRegisterMode
        ? await _authService.register(
            username: username,
            email: email,
            password: password,
          )
        : await _authService.login(username: username, password: password);

    final user = result.user;
    if (user == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorText = result.errorMessage;
      });
      return;
    }

    final localUserId = user.key;
    if (localUserId is! int) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorText = 'This account could not be opened right now. Try again.';
      });
      return;
    }

    final savedAccess = await _resolveSavedAccessFor(user, localUserId);
    user.isFingerprintEnabled = savedAccess.fingerprintEnabled;
    await user.save();
    await FirebaseUidService.bindFirebaseUidToUser(user);

    await AuthMemoryStore.saveSession(
      userId: localUserId,
      username: user.username,
      rememberLogin: savedAccess.rememberLogin,
      fingerprintEnabled: savedAccess.fingerprintEnabled,
    );
    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      // Keep the local login flow responsive even if cloud sync fails.
    }
    await AppNotificationService.initialize();
    await AppNotificationService.refresh();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    final authState = await AuthMemoryStore.loadGreetingState();
    if (!mounted) {
      return;
    }

    final shouldShowPermissionsOnboarding =
        _isRegisterMode || authState.needsLocationPermissionPrompt;
    final redirect = widget.postAuthRedirect;
    if (shouldShowPermissionsOnboarding) {
      final navigationArgs = redirect == null
          ? null
          : PostAuthNavigationArgs(redirect: redirect);

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.registerIntro,
        (route) => false,
        arguments: navigationArgs,
      );
      return;
    }

    if (redirect != null) {
      await AppNavigationService.openRedirect(redirect);
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(widget.successRoute, (route) => false);
  }

  String? _validateFields({
    required String username,
    required String email,
    required String password,
  }) {
    if (username.isEmpty) {
      return _isRegisterMode
          ? 'Username is required.'
          : 'Incorrect username or password. Try again.';
    }

    if (_isRegisterMode && email.isEmpty) {
      return 'Email is required.';
    }

    if (password.trim().isEmpty) {
      return _isRegisterMode
          ? 'Password is required.'
          : 'Incorrect username or password. Try again.';
    }

    if (_isRegisterMode && password.length < 6) {
      return 'Password must be at least 6 characters.';
    }

    return null;
  }

  Future<_SavedAccessChoice> _resolveSavedAccessFor(
    UserModel user,
    int localUserId,
  ) async {
    final previousState = await AuthMemoryStore.loadGreetingState();
    if (previousState.hasSavedSession && previousState.userId == localUserId) {
      return _SavedAccessChoice(
        rememberLogin: true,
        fingerprintEnabled: previousState.isFingerprintEnabled,
      );
    }

    final rememberLogin = await _showChoiceDialog(
      title: 'Save this login on this device?',
      message:
          'If you save it, SpendAnt can keep this account ready on this phone.',
      confirmLabel: 'Save login',
      cancelLabel: 'Not now',
    );

    var fingerprintEnabled = false;
    if (!kIsWeb) {
      final availability = await _biometricAuthService.getAvailability();
      if (availability.isDeviceSupported &&
          availability.canCheckBiometrics &&
          availability.supportsFingerprintLogin) {
        final wantsFingerprint = await _showChoiceDialog(
          title: 'Enable fingerprint access?',
          message:
              'SpendAnt will use the saved local account for this phone and require the owner fingerprint to open it.',
          confirmLabel: 'Enable fingerprint',
          cancelLabel: 'Skip',
        );

        if (wantsFingerprint) {
          final authResult = await _biometricAuthService.authenticate(
            availability: availability,
          );
          if (authResult.didAuthenticate) {
            fingerprintEnabled = true;
          } else if (mounted && authResult.message != null) {
            await _showInfoDialog(
              title: 'Fingerprint not enabled',
              message: authResult.message!,
            );
          }
        }
      }
    }

    return _SavedAccessChoice(
      rememberLogin: rememberLogin || fingerprintEnabled,
      fingerprintEnabled: fingerprintEnabled,
    );
  }

  Future<bool> _showChoiceDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _SpendAntAuthDecisionDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
        );
      },
    );

    return result ?? false;
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return _SpendAntAuthDecisionDialog(
          title: title,
          message: message,
          confirmLabel: 'Continue',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      resizeToAvoidBottomInset: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mediaQuery = MediaQuery.of(context);
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          final antHeight = isLandscape
              ? (constraints.maxHeight * 0.62).clamp(220.0, widget.antHeight)
              : widget.antHeight;
          final antLeft = isLandscape ? 8.0 : widget.antLeft;
          final antBottom = isLandscape ? -18.0 : widget.antBottom;
          final horizontalPadding = isLandscape ? 28.0 : 38.0;
          final bottomSpacerFactor = isLandscape
              ? (widget.showEmail ? 0.12 : 0.16)
              : (widget.showEmail ? 0.29 : 0.34);

          return Stack(
            children: [
              Positioned(
                left: antLeft,
                bottom: antBottom,
                child: AntAsset(widget.antAssetPath, height: antHeight),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding +
                        (isLandscape ? mediaQuery.viewPadding.right : 0),
                    0,
                  ),
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
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            _isRegisterMode ? 'Username' : 'Username or email',
                          ),
                        ),
                        if (widget.showEmail) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration('Email'),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _isPasswordHidden,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
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
                        if (_errorText != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _errorText!,
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        BlackPrimaryButton(
                          label: widget.primaryLabel,
                          width: widget.showEmail ? 128 : 103,
                          height: 46,
                          isLoading: _isSubmitting,
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
                          height: constraints.maxHeight * bottomSpacerFactor,
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

class _SavedAccessChoice {
  const _SavedAccessChoice({
    required this.rememberLogin,
    required this.fingerprintEnabled,
  });

  final bool rememberLogin;
  final bool fingerprintEnabled;
}

class _SpendAntAuthDecisionDialog extends StatelessWidget {
  const _SpendAntAuthDecisionDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String? cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        decoration: BoxDecoration(
          color: AppPalette.field,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.fieldHint,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cancelLabel != null) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      cancelLabel!,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.fieldHint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    confirmLabel,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
