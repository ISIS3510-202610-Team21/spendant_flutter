import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
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

  AuthGreetingState? _authState;
  BiometricAvailability? _availability;
  String? _statusMessage;
  bool _isLoading = true;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final authState = await AuthMemoryStore.loadGreetingState();
    BiometricAvailability? availability;
    String? statusMessage;

    if (authState.hasLoggedInBefore) {
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
          'Log in with your account first before enabling biometric access.';
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

    if (authState == null || !authState.hasLoggedInBefore) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
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
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLoggedInBefore = _authState?.hasLoggedInBefore ?? false;
    final availability = _availability;
    final title = _isLoading
        ? 'Checking device'
        : !hasLoggedInBefore
        ? 'Login required'
        : 'Touch the sensor';
    final subtitle = _statusMessage ?? 'Use your fingerprint to log in safely.';
    final buttonLabel = !hasLoggedInBefore
        ? 'Go to Login'
        : _isAuthenticating
        ? 'Authenticating...'
        : 'Continue';

    return GreenScreenScaffold(
      resizeToAvoidBottomInset: false,
      child: LayoutBuilder(
        builder: (context, _) {
          return Stack(
            children: [
              Positioned(
                left: -24,
                bottom: -18,
                child: IgnorePointer(
                  child: AntAsset('web/ant/Standing.svg', height: 210),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 28, 30, 32),
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      const SpendAntWordmark(),
                      const SizedBox(height: 108),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 38),
                      GestureDetector(
                        onTap: _handlePrimaryAction,
                        child: Container(
                          width: 182,
                          height: 182,
                          decoration: BoxDecoration(
                            color: AppPalette.field,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppPalette.ink, width: 2),
                          ),
                          child: _isLoading || _isAuthenticating
                              ? const Center(
                                  child: SizedBox(
                                    width: 38,
                                    height: 38,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AppPalette.ink,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.fingerprint,
                                  size: 92,
                                  color: AppPalette.ink,
                                ),
                        ),
                      ),
                      const SizedBox(height: 42),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            color: AppPalette.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      BlackPrimaryButton(
                        label: buttonLabel,
                        width: 190,
                        height: 50,
                        onPressed: _isLoading ? () {} : _handlePrimaryAction,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoutes.login),
                        style: TextButton.styleFrom(
                          foregroundColor: AppPalette.ink,
                        ),
                        child: Text(
                          hasLoggedInBefore
                              ? 'Use password instead'
                              : 'Open login screen',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (hasLoggedInBefore &&
                          !_isLoading &&
                          availability != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          availability.supportsFingerprint ||
                                  availability.supportsFingerprintLogin
                              ? 'Detected method: fingerprint'
                              : 'Detected method: unavailable',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.ink.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                      const Spacer(),
                    ],
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
