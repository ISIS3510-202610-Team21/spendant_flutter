// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserModelAdapter extends TypeAdapter<UserModel> {
  @override
  final int typeId = 4;

  @override
  UserModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserModel()
      ..username = fields[0] as String
      ..email = fields[1] as String
      ..passwordHash = fields[2] as String
      ..firebaseUid = fields[3] as String?
      ..displayName = fields[4] as String?
      ..handle = fields[5] as String?
      ..avatarPath = fields[6] as String?
      ..isFingerprintEnabled = fields[7] as bool
      ..createdAt = fields[8] as DateTime
      ..isSynced = fields[9] as bool
      ..serverId = fields[10] as String?;
  }

  @override
  void write(BinaryWriter writer, UserModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.username)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.passwordHash)
      ..writeByte(3)
      ..write(obj.firebaseUid)
      ..writeByte(4)
      ..write(obj.displayName)
      ..writeByte(5)
      ..write(obj.handle)
      ..writeByte(6)
      ..write(obj.avatarPath)
      ..writeByte(7)
      ..write(obj.isFingerprintEnabled)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.isSynced)
      ..writeByte(10)
      ..write(obj.serverId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
