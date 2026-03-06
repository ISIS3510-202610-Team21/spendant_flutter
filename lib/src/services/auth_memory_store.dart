import 'package:shared_preferences/shared_preferences.dart';

class AuthGreetingState {
  const AuthGreetingState({
    required this.hasLoggedInBefore,
    required this.username,
  });

  final bool hasLoggedInBefore;
  final String? username;
}

abstract final class AuthMemoryStore {
  static const _hasLoggedInBeforeKey = 'has_logged_in_before';
  static const _usernameKey = 'last_username';

  static Future<AuthGreetingState> loadGreetingState() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthGreetingState(
      hasLoggedInBefore: prefs.getBool(_hasLoggedInBeforeKey) ?? false,
      username: prefs.getString(_usernameKey),
    );
  }

  static Future<void> saveLogin(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasLoggedInBeforeKey, true);
    await prefs.setString(_usernameKey, username.trim());
  }
}
