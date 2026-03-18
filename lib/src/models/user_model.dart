import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 4)
class UserModel extends HiveObject {
  @HiveField(0)
  String username = '';

  @HiveField(1)
  String email = '';

  @HiveField(2)
  String passwordHash = '';

  @HiveField(3)
  String? firebaseUid;

  @HiveField(4)
  String? displayName;

  @HiveField(5)
  String? handle;

  @HiveField(6)
  String? avatarPath;

  @HiveField(7)
  bool isFingerprintEnabled = false;

  @HiveField(8)
  DateTime createdAt = DateTime.now();

  @HiveField(9)
  bool isSynced = false;

  @HiveField(10)
  String? serverId;
}
