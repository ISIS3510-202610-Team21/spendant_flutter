import 'package:flutter/material.dart';

import 'auth_memory_store.dart';

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
  static const String _fingerprintRouteName = '/fingerprint-auth';

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
    final args = PostAuthNavigationArgs(redirect: redirect);
    final initialRoute = authState.hasLoggedInBefore
        ? _fingerprintRouteName
        : _loginRouteName;

    navigator.pushNamedAndRemoveUntil(
      initialRoute,
      (route) => false,
      arguments: args,
    );
  }
}
