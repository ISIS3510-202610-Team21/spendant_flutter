// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseModelAdapter extends TypeAdapter<ExpenseModel> {
  @override
  final int typeId = 0;

  @override
  ExpenseModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseModel()
      ..userId = fields[0] as int
      ..name = fields[1] as String
      ..amount = fields[2] as double
      ..date = fields[3] as DateTime
      ..time = fields[4] as String
      ..latitude = fields[5] as double?
      ..longitude = fields[6] as double?
      ..locationName = fields[7] as String?
      ..source = fields[8] as String
      ..receiptImagePath = fields[9] as String?
      ..isPendingCategory = fields[10] as bool
      ..isRecurring = fields[11] as bool
      ..recurrenceInterval = fields[12] as int?
      ..recurrenceUnit = fields[13] as String?
      ..nextOccurrenceDate = fields[14] as DateTime?
      ..createdAt = fields[15] as DateTime
      ..isSynced = fields[16] as bool
      ..serverId = fields[17] as String?
      ..primaryCategory = fields[18] as String?
      ..detailLabels = (fields[19] as List).cast<String>()
      ..isRegretted = fields[20] as bool? ?? false;
  }

  @override
  void write(BinaryWriter writer, ExpenseModel obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.time)
      ..writeByte(5)
      ..write(obj.latitude)
      ..writeByte(6)
      ..write(obj.longitude)
      ..writeByte(7)
      ..write(obj.locationName)
      ..writeByte(8)
      ..write(obj.source)
      ..writeByte(9)
      ..write(obj.receiptImagePath)
      ..writeByte(10)
      ..write(obj.isPendingCategory)
      ..writeByte(11)
      ..write(obj.isRecurring)
      ..writeByte(12)
      ..write(obj.recurrenceInterval)
      ..writeByte(13)
      ..write(obj.recurrenceUnit)
      ..writeByte(14)
      ..write(obj.nextOccurrenceDate)
      ..writeByte(15)
      ..write(obj.createdAt)
      ..writeByte(16)
      ..write(obj.isSynced)
      ..writeByte(17)
      ..write(obj.serverId)
      ..writeByte(18)
      ..write(obj.primaryCategory)
      ..writeByte(19)
      ..write(obj.detailLabels)
      ..writeByte(20)
      ..write(obj.isRegretted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
