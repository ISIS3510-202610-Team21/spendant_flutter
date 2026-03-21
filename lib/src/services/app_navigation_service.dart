import 'package:flutter/material.dart';

import 'auth_memory_store.dart';
import 'fingerprint_login_service.dart';
import 'post_auth_navigation.dart';

abstract final class AppNavigationService {
  static const String _loginRouteName = '/login';
  static const String _locationPermissionIntroRouteName =
      '/location-permission-intro';

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> openRedirect(
    AppRedirect redirect, {
    bool clearStack = true,
  }) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    if (clearStack) {
      navigator.pushNamedAndRemoveUntil(
        redirect.routeName,
        (route) => false,
        arguments: redirect.routeArgumentInt,
      );
      return;
    }

    navigator.pushNamed(
      redirect.routeName,
      arguments: redirect.routeArgumentInt,
    );
  }

  static Future<void> openColdStartRedirect(AppRedirect redirect) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    final authState = await AuthMemoryStore.loadGreetingState();
    if (authState.hasSavedSession && !authState.canUseFingerprintLogin) {
      if (authState.needsLocationPermissionPrompt) {
        final args = PostAuthNavigationArgs(redirect: redirect);
        navigator.pushNamedAndRemoveUntil(
          _locationPermissionIntroRouteName,
          (route) => false,
          arguments: args,
        );
        return;
      }

      navigator.pushNamedAndRemoveUntil(
        redirect.routeName,
        (route) => false,
        arguments: redirect.routeArgumentInt,
      );
      return;
    }

    if (authState.canUseFingerprintLogin) {
      final result = await FingerprintLoginService.authenticate(
        navigator,
        redirect: redirect,
      );
      if (result.didAuthenticate) {
        return;
      }
    }

    final args = PostAuthNavigationArgs(redirect: redirect);
    navigator.pushNamedAndRemoveUntil(
      _loginRouteName,
      (route) => false,
      arguments: args,
    );
  }
}
