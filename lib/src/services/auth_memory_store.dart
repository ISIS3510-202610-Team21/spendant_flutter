import 'package:shared_preferences/shared_preferences.dart';

class AuthGreetingState {
  const AuthGreetingState({
    required this.hasSavedSession,
    required this.username,
    required this.userId,
    required this.isFingerprintEnabled,
    required this.avatarBase64,
  });

  final bool hasSavedSession;
  final String? username;
  final int? userId;
  final bool isFingerprintEnabled;
  final String? avatarBase64;

  bool get hasActiveSession => userId != null;
  bool get canUseFingerprintLogin =>
      hasSavedSession && isFingerprintEnabled && userId != null;
}

abstract final class AuthMemoryStore {
  static const _hasSavedSessionKey = 'has_saved_session';
  static const _usernameKey = 'last_username';
  static const _userIdKey = 'authenticated_user_id';
  static const _fingerprintEnabledKey = 'fingerprint_enabled_for_saved_login';
  static const _avatarBase64Key = 'profile_avatar_base64';

  static const AuthGreetingState _emptyState = AuthGreetingState(
    hasSavedSession: false,
    username: null,
    userId: null,
    isFingerprintEnabled: false,
    avatarBase64: null,
  );

  static AuthGreetingState _currentState = _emptyState;
  static bool _didInitialize = false;

  static Future<void> initialize() async {
    _currentState = await _loadPersistedState();
    _didInitialize = true;
  }

  static Future<AuthGreetingState> loadGreetingState() async {
    if (!_didInitialize) {
      await initialize();
    }

    return _currentState;
  }

  static AuthGreetingState get currentState => _currentState;

  static int? get currentUserId => _currentState.userId;

  static int get currentUserIdOrGuest => _currentState.userId ?? -1;

  static Future<void> saveSession({
    required int userId,
    required String username,
    required bool rememberLogin,
    required bool fingerprintEnabled,
  }) async {
    final trimmedUsername = username.trim();
    final shouldPersistSession = rememberLogin || fingerprintEnabled;
    final prefs = await SharedPreferences.getInstance();

    if (shouldPersistSession) {
      await prefs.setBool(_hasSavedSessionKey, true);
      await prefs.setString(_usernameKey, trimmedUsername);
      await prefs.setInt(_userIdKey, userId);
      await prefs.setBool(_fingerprintEnabledKey, fingerprintEnabled);
    } else {
      await prefs.remove(_hasSavedSessionKey);
      await prefs.remove(_usernameKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_fingerprintEnabledKey);
    }

    _currentState = AuthGreetingState(
      hasSavedSession: shouldPersistSession,
      username: trimmedUsername,
      userId: userId,
      isFingerprintEnabled: shouldPersistSession && fingerprintEnabled,
      avatarBase64: _currentState.avatarBase64,
    );
    _didInitialize = true;
  }

  static Future<void> updateCurrentUsername(String username) async {
    final trimmedUsername = username.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_currentState.hasSavedSession) {
      await prefs.setString(_usernameKey, trimmedUsername);
    }

    _currentState = AuthGreetingState(
      hasSavedSession: _currentState.hasSavedSession,
      username: trimmedUsername,
      userId: _currentState.userId,
      isFingerprintEnabled: _currentState.isFingerprintEnabled,
      avatarBase64: _currentState.avatarBase64,
    );
    _didInitialize = true;
  }

  static Future<void> saveProfile({
    required String username,
    String? avatarBase64,
  }) async {
    final trimmedUsername = username.trim();
    final normalizedAvatar = avatarBase64?.trim();
    final prefs = await SharedPreferences.getInstance();

    if (_currentState.hasSavedSession) {
      await prefs.setString(_usernameKey, trimmedUsername);
    }

    if (normalizedAvatar == null || normalizedAvatar.isEmpty) {
      await prefs.remove(_avatarBase64Key);
    } else {
      await prefs.setString(_avatarBase64Key, normalizedAvatar);
    }

    _currentState = AuthGreetingState(
      hasSavedSession: _currentState.hasSavedSession,
      username: trimmedUsername,
      userId: _currentState.userId,
      isFingerprintEnabled: _currentState.isFingerprintEnabled,
      avatarBase64: normalizedAvatar == null || normalizedAvatar.isEmpty
          ? null
          : normalizedAvatar,
    );
    _didInitialize = true;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasSavedSessionKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_fingerprintEnabledKey);
    await prefs.remove(_avatarBase64Key);
    _currentState = _emptyState;
    _didInitialize = true;
  }

  static Future<AuthGreetingState> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSavedSession = prefs.getBool(_hasSavedSessionKey) ?? false;
    final userId = prefs.getInt(_userIdKey);

    return AuthGreetingState(
      hasSavedSession: hasSavedSession,
      username: prefs.getString(_usernameKey),
      userId: hasSavedSession ? userId : null,
      isFingerprintEnabled:
          hasSavedSession && (prefs.getBool(_fingerprintEnabledKey) ?? false),
      avatarBase64: prefs.getString(_avatarBase64Key),
    );
  }
}
