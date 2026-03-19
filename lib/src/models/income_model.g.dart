// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'income_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class IncomeModelAdapter extends TypeAdapter<IncomeModel> {
  @override
  final int typeId = 1;

  @override
  IncomeModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return IncomeModel()
      ..userId = fields[0] as int
      ..name = fields[1] as String
      ..amount = fields[2] as double
      ..type = fields[3] as String
      ..recurrenceInterval = fields[4] as int?
      ..recurrenceUnit = fields[5] as String?
      ..nextOccurrenceDate = fields[6] as DateTime?
      ..startDate = fields[7] as DateTime
      ..createdAt = fields[8] as DateTime
      ..isSynced = fields[9] as bool
      ..serverId = fields[10] as String?;
  }

  @override
  void write(BinaryWriter writer, IncomeModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.recurrenceInterval)
      ..writeByte(5)
      ..write(obj.recurrenceUnit)
      ..writeByte(6)
      ..write(obj.nextOccurrenceDate)
      ..writeByte(7)
      ..write(obj.startDate)
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
      other is IncomeModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
