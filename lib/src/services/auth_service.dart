import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/user_model.dart';
import 'local_storage_service.dart';

class AuthResult {
  const AuthResult({this.user, this.errorMessage});

  final UserModel? user;
  final String? errorMessage;

  bool get isSuccess => user != null;
}

class AuthService {
  AuthService({LocalStorageService? localStorage})
    : _localStorage = localStorage ?? LocalStorageService();

  final LocalStorageService _localStorage;

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = _normalizeUsername(username);
    final user = await _localStorage.findUserByUsername(normalizedUsername);
    if (user == null) {
      return const AuthResult(
        errorMessage: 'Incorrect username or password. Try again.',
      );
    }

    if (!_matchesStoredPassword(user, password)) {
      return const AuthResult(
        errorMessage: 'Incorrect username or password. Try again.',
      );
    }

    return AuthResult(user: user);
  }

  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalizedUsername = _normalizeUsername(username);
    final normalizedEmail = email.trim().toLowerCase();

    if (await _localStorage.findUserByUsername(normalizedUsername) != null) {
      return const AuthResult(errorMessage: 'That username is already in use.');
    }

    if (await _localStorage.findUserByEmail(normalizedEmail) != null) {
      return const AuthResult(
        errorMessage: 'That email is already registered.',
      );
    }

    final user = UserModel()
      ..username = username.trim()
      ..email = normalizedEmail
      ..passwordHash = hashPassword(password)
      ..displayName = username.trim()
      ..handle = _buildHandle(username)
      ..isFingerprintEnabled = false
      ..createdAt = DateTime.now()
      ..isSynced = false;

    await _localStorage.saveUser(user);
    return AuthResult(user: user);
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  String _normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }

  String _buildHandle(String username) {
    final normalized = username.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final safeValue = normalized.isEmpty ? 'spendant' : normalized;
    return '@$safeValue';
  }

  bool _matchesStoredPassword(UserModel user, String rawPassword) {
    final hashedPassword = hashPassword(rawPassword);
    final storedPassword = user.passwordHash.trim();
    final didMatch =
        storedPassword == hashedPassword || storedPassword == rawPassword;

    if (didMatch && storedPassword != hashedPassword) {
      user.passwordHash = hashedPassword;
      user.save();
    }

    return didMatch;
  }
}
