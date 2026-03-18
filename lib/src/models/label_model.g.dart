// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'label_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LabelModelAdapter extends TypeAdapter<LabelModel> {
  @override
  final int typeId = 3;

  @override
  LabelModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LabelModel()
      ..userId = fields[0] as int
      ..name = fields[1] as String
      ..iconEmoji = fields[2] as String?
      ..colorHex = fields[3] as String?
      ..createdAt = fields[4] as DateTime
      ..isSynced = fields[5] as bool
      ..serverId = fields[6] as String?;
  }

  @override
  void write(BinaryWriter writer, LabelModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.iconEmoji)
      ..writeByte(3)
      ..write(obj.colorHex)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.isSynced)
      ..writeByte(6)
      ..write(obj.serverId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabelModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
