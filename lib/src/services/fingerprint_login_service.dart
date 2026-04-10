import 'package:flutter/material.dart';

import '../../app.dart';
import 'app_notification_service.dart';
import 'auth_memory_store.dart';
import 'biometric_auth_service.dart';
import 'cloud_sync_service.dart';
import 'post_auth_navigation.dart';

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
    final unavailableMessage = _availabilityMessage(availability);
    if (unavailableMessage != null) {
      return FingerprintLoginResult(
        didAuthenticate: false,
        message: unavailableMessage,
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

    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      // Keep fingerprint login available even when cloud sync is offline.
    }

    await AppNotificationService.initialize();
    await AppNotificationService.refresh();

    final refreshedState = await AuthMemoryStore.loadGreetingState();
    if (refreshedState.needsLocationPermissionPrompt) {
      final navigationArgs = redirect == null
          ? null
          : PostAuthNavigationArgs(redirect: redirect);
      navigator.pushNamedAndRemoveUntil(
        AppRoutes.registerIntro,
        (route) => false,
        arguments: navigationArgs,
      );
      return const FingerprintLoginResult(didAuthenticate: true);
    }

    if (redirect != null) {
      navigator.pushNamedAndRemoveUntil(
        redirect.routeName,
        (route) => false,
        arguments: redirect.routeArgumentInt,
      );
      return const FingerprintLoginResult(didAuthenticate: true);
    }

    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
    return const FingerprintLoginResult(didAuthenticate: true);
  }

  static String? _availabilityMessage(BiometricAvailability availability) {
    if (!availability.isDeviceSupported || !availability.canCheckBiometrics) {
      return 'This device does not support fingerprint authentication.';
    }

    if (!availability.supportsFingerprintLogin) {
      return 'Fingerprint login is not available on this device right now.';
    }

    return null;
  }
}
