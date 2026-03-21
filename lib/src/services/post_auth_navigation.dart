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
