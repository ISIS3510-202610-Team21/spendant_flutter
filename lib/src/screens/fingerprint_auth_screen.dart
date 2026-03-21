import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/app_notification_service.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../services/biometric_auth_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class FingerprintAuthScreen extends StatefulWidget {
  const FingerprintAuthScreen({super.key});

  @override
  State<FingerprintAuthScreen> createState() => _FingerprintAuthScreenState();
}

class _FingerprintAuthScreenState extends State<FingerprintAuthScreen> {
  final BiometricAuthService _biometricAuthService = BiometricAuthService();

  bool _didLoadRedirect = false;
  AuthGreetingState? _authState;
  BiometricAvailability? _availability;
  PostAuthNavigationArgs? _postAuthNavigationArgs;
  String? _statusMessage;
  bool _isLoading = true;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didLoadRedirect) {
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is PostAuthNavigationArgs) {
      _postAuthNavigationArgs = args;
    }
    _didLoadRedirect = true;
  }

  Future<void> _loadBiometricState() async {
    final authState = await AuthMemoryStore.loadGreetingState();
    BiometricAvailability? availability;
    String? statusMessage;

    if (authState.canUseFingerprintLogin) {
      availability = await _biometricAuthService.getAvailability();

      if (!availability.isDeviceSupported || !availability.canCheckBiometrics) {
        statusMessage =
            'This device does not support fingerprint authentication.';
      } else if (!availability.supportsFingerprintLogin) {
        statusMessage =
            'Fingerprint login is not available on this device right now.';
      } else {
        statusMessage = null;
      }
    } else {
      statusMessage =
          'Log in once, save that session locally, and enable fingerprint access first.';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _authState = authState;
      _availability = availability;
      _statusMessage = statusMessage;
      _isLoading = false;
    });
  }

  Future<void> _handlePrimaryAction() async {
    if (_isLoading || _isAuthenticating) {
      return;
    }

    final authState = _authState;
    final availability = _availability;

    if (authState == null || !authState.canUseFingerprintLogin) {
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.login,
        arguments: _postAuthNavigationArgs,
      );
      return;
    }

    if (availability == null ||
        !availability.isDeviceSupported ||
        !availability.canCheckBiometrics ||
        !availability.supportsFingerprintLogin) {
      setState(() {
        _statusMessage =
            'Fingerprint login is not ready on this device. Use your password instead.';
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _statusMessage = null;
    });

    final result = await _biometricAuthService.authenticate(
      availability: availability,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isAuthenticating = false;
      _statusMessage = result.message;
    });

    if (result.didAuthenticate) {
      await AppNotificationService.initialize();
      await AppNotificationService.refresh();
      if (!mounted) {
        return;
      }

      final redirect = _postAuthNavigationArgs?.redirect;
      if (redirect != null) {
        await AppNavigationService.openRedirect(redirect);
        return;
      }

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUseFingerprintLogin = _authState?.canUseFingerprintLogin ?? false;
    final availability = _availability;
    final title = _isLoading
        ? 'Checking device'
        : !canUseFingerprintLogin
        ? 'Login required'
        : 'Touch the sensor';
    final subtitle = _statusMessage ?? 'Use your fingerprint to log in safely.';
    final buttonLabel = !canUseFingerprintLogin
        ? 'Go to Login'
        : _isAuthenticating
        ? 'Authenticating...'
        : 'Continue';

    return GreenScreenScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned(
                left: -28,
                bottom: -56,
                child: AntAsset('web/ant/ant_login.svg', height: 460),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 120),
                        const SpendAntWordmark(),
                        const SizedBox(height: 88),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 34),
                        GestureDetector(
                          onTap: _handlePrimaryAction,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppPalette.field,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppPalette.ink,
                                width: 2,
                              ),
                            ),
                            child: _isLoading || _isAuthenticating
                                ? const Center(
                                    child: SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: AppPalette.ink,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.fingerprint,
                                    size: 78,
                                    color: AppPalette.ink,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              color: AppPalette.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        BlackPrimaryButton(
                          label: buttonLabel,
                          width: 170,
                          onPressed: _isLoading ? () {} : _handlePrimaryAction,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pushReplacementNamed(
                                AppRoutes.login,
                                arguments: _postAuthNavigationArgs,
                              ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppPalette.ink,
                          ),
                          child: Text(
                            canUseFingerprintLogin
                                ? 'Use password instead'
                                : 'Open login screen',
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (canUseFingerprintLogin &&
                            !_isLoading &&
                            availability != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            availability.supportsFingerprint ||
                                    availability.supportsFingerprintLogin
                                ? 'Detected method: fingerprint'
                                : 'Detected method: unavailable',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.ink.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                        SizedBox(height: constraints.maxHeight * 0.20),
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
}
