import 'package:shared_preferences/shared_preferences.dart';

class AuthGreetingState {
  const AuthGreetingState({
    required this.hasLoggedInBefore,
    required this.username,
    required this.avatarBase64,
  });

  final bool hasLoggedInBefore;
  final String? username;
  final String? avatarBase64;
}

abstract final class AuthMemoryStore {
  static const _hasLoggedInBeforeKey = 'has_logged_in_before';
  static const _usernameKey = 'last_username';
  static const _avatarBase64Key = 'profile_avatar_base64';

  static Future<AuthGreetingState> loadGreetingState() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthGreetingState(
      hasLoggedInBefore: prefs.getBool(_hasLoggedInBeforeKey) ?? false,
      username: prefs.getString(_usernameKey),
      avatarBase64: prefs.getString(_avatarBase64Key),
    );
  }

  static Future<void> saveLogin(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasLoggedInBeforeKey, true);
    await prefs.setString(_usernameKey, username.trim());
  }

  static Future<void> saveProfile({
    required String username,
    String? avatarBase64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasLoggedInBeforeKey, true);
    await prefs.setString(_usernameKey, username.trim());

    if (avatarBase64 == null || avatarBase64.trim().isEmpty) {
      await prefs.remove(_avatarBase64Key);
      return;
    }

    await prefs.setString(_avatarBase64Key, avatarBase64);
  }
}
