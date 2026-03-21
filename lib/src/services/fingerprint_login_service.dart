import 'package:flutter/material.dart';

import '../../app.dart';
import 'app_navigation_service.dart';
import 'app_notification_service.dart';
import 'auth_memory_store.dart';
import 'biometric_auth_service.dart';

class FingerprintLoginResult {
  const FingerprintLoginResult({required this.didAuthenticate, this.message});

  final bool didAuthenticate;
  final String? message;
}

abstract final class FingerprintLoginService {
  static final BiometricAuthService _biometricAuthService =
      BiometricAuthService();

  static Future<FingerprintLoginResult> authenticate(
    NavigatorState navigator, {
    AppRedirect? redirect,
  }) async {
    final authState = await AuthMemoryStore.loadGreetingState();
    if (!authState.canUseFingerprintLogin) {
      return const FingerprintLoginResult(
        didAuthenticate: false,
        message:
            'Log in once, save that session locally, and enable fingerprint access first.',
      );
    }

    final availability = await _biometricAuthService.getAvailability();
    if (!availability.isDeviceSupported || !availability.canCheckBiometrics) {
      return const FingerprintLoginResult(
        didAuthenticate: false,
        message: 'This device does not support fingerprint authentication.',
      );
    }

    if (!availability.supportsFingerprintLogin) {
      return const FingerprintLoginResult(
        didAuthenticate: false,
        message: 'Fingerprint login is not available on this device right now.',
      );
    }

    final result = await _biometricAuthService.authenticate(
      availability: availability,
    );
    if (!result.didAuthenticate) {
      return FingerprintLoginResult(
        didAuthenticate: false,
        message: result.message,
      );
    }

    await AppNotificationService.initialize();
    await AppNotificationService.refresh();

    if (redirect != null) {
      await AppNavigationService.openRedirect(redirect);
      return const FingerprintLoginResult(didAuthenticate: true);
    }

    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    return const FingerprintLoginResult(didAuthenticate: true);
  }
}
