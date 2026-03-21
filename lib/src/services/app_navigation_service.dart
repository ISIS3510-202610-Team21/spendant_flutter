import 'package:flutter/material.dart';

import 'auth_memory_store.dart';
import 'fingerprint_login_service.dart';

class AppRedirect {
  const AppRedirect({required this.routeName, this.routeArgumentInt});

  final String routeName;
  final int? routeArgumentInt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'routeName': routeName,
      'routeArgumentInt': routeArgumentInt,
    };
  }

  static AppRedirect? fromMap(Map<String, Object?>? map) {
    if (map == null) {
      return null;
    }

    final routeName = map['routeName'];
    if (routeName is! String || routeName.isEmpty) {
      return null;
    }

    final routeArgumentInt = map['routeArgumentInt'];
    return AppRedirect(
      routeName: routeName,
      routeArgumentInt: routeArgumentInt is int ? routeArgumentInt : null,
    );
  }
}

class PostAuthNavigationArgs {
  const PostAuthNavigationArgs({required this.redirect});

  final AppRedirect redirect;
}

abstract final class AppNavigationService {
  static const String _loginRouteName = '/login';

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
