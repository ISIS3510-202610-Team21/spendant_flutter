import 'package:hive/hive.dart';

part 'income_model.g.dart';

@HiveType(typeId: 1)
class IncomeModel extends HiveObject {
  @HiveField(0)
  int userId = 0;

  @HiveField(1)
  String name = '';

  @HiveField(2)
  double amount = 0;

  @HiveField(3)
  String type = 'JUST_ONCE'; // JUST_ONCE o FREQUENTLY

  @HiveField(4)
  int? recurrenceInterval;

  @HiveField(5)
  String? recurrenceUnit; // DAYS, WEEKS, MONTHS

  @HiveField(6)
  DateTime? nextOccurrenceDate;

  @HiveField(7)
  DateTime startDate = DateTime.now();

  @HiveField(8)
  DateTime createdAt = DateTime.now();

  @HiveField(9)
  bool isSynced = false;

  @HiveField(10)
  String? serverId;
}
