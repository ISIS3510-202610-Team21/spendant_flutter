import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../models/user_model.dart';
import 'local_storage_service.dart';

class AuthResult {
  const AuthResult({this.user, this.errorMessage});

  final UserModel? user;
  final String? errorMessage;

  bool get isSuccess => user != null;
}

class AuthService {
  AuthService({
    LocalStorageService? localStorage,
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _localStorage = localStorage ?? LocalStorageService(),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final LocalStorageService _localStorage;
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final trimmedIdentifier = username.trim();
    final passwordHash = hashPassword(password);
    UserModel? localUser;

    try {
      await _ensureFirebaseReady();
      localUser = await _localStorage.findUserByUsername(trimmedIdentifier);

      if (localUser == null) {
        final resolvedEmail = trimmedIdentifier.contains('@')
            ? trimmedIdentifier.toLowerCase()
            : await _findEmailByUsernameInFirestore(trimmedIdentifier);
        if (resolvedEmail == null || resolvedEmail.isEmpty) {
          return const AuthResult(
            errorMessage: 'Incorrect username or password. Try again.',
          );
        }

        final authResult = await _firebaseAuth.signInWithEmailAndPassword(
          email: resolvedEmail,
          password: password,
        );
        final firebaseUid = authResult.user?.uid.trim();
        if (firebaseUid == null || firebaseUid.isEmpty) {
          return const AuthResult(
            errorMessage: 'Incorrect username or password. Try again.',
          );
        }

        final remoteProfile =
            await _findRemoteUserProfileByUid(firebaseUid) ??
            _RemoteUserProfile(
              uid: firebaseUid,
              username: trimmedIdentifier,
              email: resolvedEmail,
              displayName: trimmedIdentifier,
              handle: _buildHandle(trimmedIdentifier),
              createdAtMillis: DateTime.now().millisecondsSinceEpoch,
            );

        final cachedUser = await _upsertLocalUser(
          remoteProfile,
          passwordHash: passwordHash,
        );
        return AuthResult(user: cachedUser);
      }

      final authResult = await _firebaseAuth.signInWithEmailAndPassword(
        email: localUser.email.trim(),
        password: password,
      );
      final firebaseUid = authResult.user?.uid.trim();
      if (firebaseUid == null || firebaseUid.isEmpty) {
        return const AuthResult(
          errorMessage: 'Incorrect username or password. Try again.',
        );
      }

      if (localUser.firebaseUid?.trim() != firebaseUid ||
          localUser.passwordHash.trim() != passwordHash) {
        localUser
          ..firebaseUid = firebaseUid
          ..passwordHash = passwordHash
          ..isSynced = false;
        await localUser.save();
      }

      return AuthResult(user: localUser);
    } on FirebaseAuthException catch (error) {
      final offlineUser =
          localUser ??
          await _localStorage.findUserByUsername(trimmedIdentifier);
      if (_matchesStoredPassword(offlineUser, passwordHash)) {
        return AuthResult(user: offlineUser);
      }

      return AuthResult(errorMessage: _mapFirebaseError(error));
    } on FirebaseException catch (error) {
      debugPrint(
        'AuthService.login Firebase error: ${error.code} ${error.message}',
      );
      final offlineUser =
          localUser ??
          await _localStorage.findUserByUsername(trimmedIdentifier);
      if (_matchesStoredPassword(offlineUser, passwordHash)) {
        return AuthResult(user: offlineUser);
      }

      return AuthResult(errorMessage: _mapFirebaseDataError(error));
    } catch (error) {
      final offlineUser =
          localUser ??
          await _localStorage.findUserByUsername(trimmedIdentifier);
      if (_matchesStoredPassword(offlineUser, passwordHash)) {
        return AuthResult(user: offlineUser);
      }

      return AuthResult(
        errorMessage: error.toString().trim().isEmpty
            ? 'Incorrect username or password. Try again.'
            : 'Incorrect username or password. Try again.',
      );
    }
  }

  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final trimmedUsername = username.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final passwordHash = hashPassword(password);

    if (await _localStorage.findUserByUsername(trimmedUsername) != null) {
      return const AuthResult(errorMessage: 'That username is already in use.');
    }

    try {
      await _ensureFirebaseReady();

      final authResult = await _firebaseAuth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final firebaseUid = authResult.user?.uid.trim();
      if (firebaseUid == null || firebaseUid.isEmpty) {
        return const AuthResult(
          errorMessage: 'This account could not be created right now.',
        );
      }

      final profile = _RemoteUserProfile(
        uid: firebaseUid,
        username: trimmedUsername,
        email: normalizedEmail,
        displayName: trimmedUsername,
        handle: _buildHandle(trimmedUsername),
        createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      );

      final user = await _upsertLocalUser(profile, passwordHash: passwordHash);
      await _saveUserToFirestore(profile);
      return AuthResult(user: user);
    } on FirebaseAuthException catch (error) {
      return AuthResult(errorMessage: _mapFirebaseError(error));
    } on FirebaseException catch (error) {
      debugPrint(
        'AuthService.register Firebase error: ${error.code} ${error.message}',
      );
      return AuthResult(errorMessage: _mapFirebaseDataError(error));
    } catch (error) {
      return AuthResult(
        errorMessage: error.toString().trim().isEmpty
            ? 'This account could not be created right now.'
            : 'This account could not be created right now.',
      );
    }
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  String _buildHandle(String username) {
    final normalized = username.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '');
    final safeValue = normalized.isEmpty ? 'SpendAnt' : normalized;
    return '@$safeValue';
  }

  Future<void> _ensureFirebaseReady() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> _saveUserToFirestore(_RemoteUserProfile profile) async {
    try {
      await _firestore
          .collection('users')
          .doc(profile.uid)
          .set(profile.toMap());
    } catch (error) {
      debugPrint('AuthService.saveUserToFirestore failed: $error');
    }
  }

  Future<String?> _findEmailByUsernameInFirestore(String username) async {
    try {
      final result = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      return result.docs.firstOrNull?.data()['email'] as String?;
    } catch (error) {
      debugPrint('AuthService.findEmailByUsernameInFirestore failed: $error');
      return null;
    }
  }

  Future<_RemoteUserProfile?> _findRemoteUserProfileByUid(
    String firebaseUid,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(firebaseUid)
          .get();
      if (!snapshot.exists) {
        return null;
      }

      return _RemoteUserProfile.fromMap(
        snapshot.data() ?? const <String, Object?>{},
      );
    } catch (error) {
      debugPrint('AuthService.findRemoteUserProfileByUid failed: $error');
      return null;
    }
  }

  Future<UserModel> _upsertLocalUser(
    _RemoteUserProfile profile, {
    required String passwordHash,
  }) async {
    final existingUser =
        await _localStorage.findUserByFirebaseUid(profile.uid) ??
        await _localStorage.findUserByEmail(profile.email) ??
        await _localStorage.findUserByUsername(profile.username);

    if (existingUser != null) {
      existingUser
        ..firebaseUid = profile.uid
        ..username = profile.username
        ..email = profile.email
        ..passwordHash = passwordHash
        ..displayName = profile.displayName
        ..handle = profile.handle
        ..createdAt = DateTime.fromMillisecondsSinceEpoch(
          profile.createdAtMillis,
        )
        ..isSynced = false
        ..serverId = profile.uid;
      await existingUser.save();
      return existingUser;
    }

    final user = UserModel()
      ..firebaseUid = profile.uid
      ..username = profile.username
      ..email = profile.email
      ..passwordHash = passwordHash
      ..displayName = profile.displayName
      ..handle = profile.handle
      ..createdAt = DateTime.fromMillisecondsSinceEpoch(profile.createdAtMillis)
      ..isSynced = false
      ..serverId = profile.uid;
    await _localStorage.saveUser(user);
    return user;
  }

  bool _matchesStoredPassword(UserModel? user, String passwordHash) {
    if (user == null) {
      return false;
    }

    return user.passwordHash.trim() == passwordHash;
  }

  String _mapFirebaseError(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'That email is already registered.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Incorrect username or password. Try again.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled in Firebase Auth.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Unknown authentication error.';
    }
  }

  String _mapFirebaseDataError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firebase blocked access to user profiles. Check Firestore rules.';
      case 'unavailable':
        return 'No internet connection.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Unknown data error.';
    }
  }
}

class _RemoteUserProfile {
  const _RemoteUserProfile({
    required this.uid,
    required this.username,
    required this.email,
    required this.displayName,
    required this.handle,
    required this.createdAtMillis,
  });

  final String uid;
  final String username;
  final String email;
  final String displayName;
  final String handle;
  final int createdAtMillis;

  factory _RemoteUserProfile.fromMap(Map<String, Object?> data) {
    return _RemoteUserProfile(
      uid: (data['uid'] as String? ?? '').trim(),
      username: (data['username'] as String? ?? '').trim(),
      email: (data['email'] as String? ?? '').trim().toLowerCase(),
      displayName: (data['displayName'] as String? ?? '').trim(),
      handle: (data['handle'] as String? ?? '').trim(),
      createdAtMillis:
          (data['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'uid': uid,
      'username': username,
      'email': email,
      'displayName': displayName,
      'handle': handle,
      'createdAt': createdAtMillis,
    };
  }
}
