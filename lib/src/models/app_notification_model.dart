import 'package:hive/hive.dart';

abstract final class AppNotificationTypes {
  static const goalCreated = 'goal_created';
  static const goalHalfway = 'goal_halfway';
  static const goalAchieved = 'goal_achieved';
  static const incomeCreated = 'income_created';
  static const incomeDue = 'income_due';
  static const budgetWarning = 'budget_warning';
}

class AppNotificationModel extends HiveObject {
  String id = '';
  String type = '';
  DateTime createdAt = DateTime.now();
  String title = '';
  String detailTitle = '';
  String detailMessage = '';
  String? subtitle;
  double? amount;
  String? category;
  String? routeName;
  int? routeArgumentInt;
}

class AppNotificationModelAdapter extends TypeAdapter<AppNotificationModel> {
  @override
  final int typeId = 5;

  @override
  AppNotificationModel read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, Object?>{
      for (var index = 0; index < fieldCount; index++) reader.readByte(): reader.read(),
    };

    return AppNotificationModel()
      ..id = fields[0] as String
      ..type = fields[1] as String
      ..createdAt = fields[2] as DateTime
      ..title = fields[3] as String
      ..detailTitle = fields[4] as String
      ..detailMessage = fields[5] as String
      ..subtitle = fields[6] as String?
      ..amount = fields[7] as double?
      ..category = fields[8] as String?
      ..routeName = fields[9] as String?
      ..routeArgumentInt = fields[10] as int?;
  }

  @override
  void write(BinaryWriter writer, AppNotificationModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.detailTitle)
      ..writeByte(5)
      ..write(obj.detailMessage)
      ..writeByte(6)
      ..write(obj.subtitle)
      ..writeByte(7)
      ..write(obj.amount)
      ..writeByte(8)
      ..write(obj.category)
      ..writeByte(9)
      ..write(obj.routeName)
      ..writeByte(10)
      ..write(obj.routeArgumentInt);
  }
}
