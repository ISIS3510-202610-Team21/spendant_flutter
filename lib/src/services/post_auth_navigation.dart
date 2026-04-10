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

enum PermissionsIntroStep { welcome, calendar, notifications }

class PostAuthNavigationArgs {
  const PostAuthNavigationArgs({required this.redirect});

  final AppRedirect redirect;
}

class PermissionsIntroArgs {
  const PermissionsIntroArgs.fullOnboarding({this.redirect})
    : initialStep = PermissionsIntroStep.welcome,
      showWelcomeStep = true,
      showCalendarStep = true,
      showNotificationStep = true,
      showLocationStepAfterFlow = true;

  const PermissionsIntroArgs.review({
    required this.initialStep,
    required this.showCalendarStep,
    required this.showNotificationStep,
    this.redirect,
  }) : showWelcomeStep = false,
       showLocationStepAfterFlow = false;

  final AppRedirect? redirect;
  final PermissionsIntroStep initialStep;
  final bool showWelcomeStep;
  final bool showCalendarStep;
  final bool showNotificationStep;
  final bool showLocationStepAfterFlow;
}
