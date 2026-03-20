import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../firebase_options.dart';
import '../models/user_model.dart';
import 'auth_memory_store.dart';
import 'local_storage_service.dart';

abstract final class FirebaseUidService {
  static String? currentFirebaseUid() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim();
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
    } catch (_) {
      // Firebase Auth may not be initialized yet on this platform/session.
    }

    return _localFirebaseUid();
  }

  static Future<String?> ensureFirebaseUid() async {
    try {
      final isFirebaseReady = await _ensureFirebaseInitialized();
      if (!isFirebaseReady) {
        return _localFirebaseUid();
      }

      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;
      user ??= (await auth.signInAnonymously()).user;
      final uid = user?.uid.trim();
      if (uid == null || uid.isEmpty) {
        return _localFirebaseUid();
      }

      await _persistFirebaseUid(uid);
      return uid;
    } catch (_) {
      return _localFirebaseUid();
    }
  }

  static Future<String?> bindFirebaseUidToUser(UserModel user) async {
    final uid = currentFirebaseUid() ?? await ensureFirebaseUid();
    final trimmedUid = uid?.trim() ?? '';
    if (trimmedUid.isEmpty) {
      return null;
    }

    if (user.firebaseUid?.trim() == trimmedUid) {
      return trimmedUid;
    }

    user
      ..firebaseUid = trimmedUid
      ..isSynced = false;
    await user.save();
    return trimmedUid;
  }

  static Future<bool> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _localFirebaseUid() {
    final box = LocalStorageService.userBox;
    for (var index = 0; index < box.length; index++) {
      final user = box.getAt(index);
      final uid = user?.firebaseUid?.trim();
      if (uid != null && uid.isNotEmpty) {
        return uid;
      }
    }
    return null;
  }

  static Future<void> _persistFirebaseUid(String uid) async {
    final activeUserId = AuthMemoryStore.currentUserId;
    if (activeUserId == null) {
      return;
    }

    final user = LocalStorageService().getUserById(activeUserId);
    if (user == null) {
      return;
    }

    if (user.firebaseUid?.trim() == uid) {
      return;
    }

    user
      ..firebaseUid = uid
      ..isSynced = false;
    await user.save();
  }
}
