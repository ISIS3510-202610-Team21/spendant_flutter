import 'package:hive/hive.dart';

part 'expense_model.g.dart';

@HiveType(typeId: 0)
class ExpenseModel extends HiveObject {
  @HiveField(0)
  int userId = 0;

  @HiveField(1)
  String name = '';

  @HiveField(2)
  double amount = 0;

  @HiveField(3)
  DateTime date = DateTime.now();

  @HiveField(4)
  String time = '';

  @HiveField(5)
  double? latitude;

  @HiveField(6)
  double? longitude;

  @HiveField(7)
  String? locationName;

  @HiveField(8)
  String source = 'MANUAL'; // MANUAL, OCR, GOOGLE_PAY

  @HiveField(9)
  String? receiptImagePath;

  @HiveField(10)
  bool isPendingCategory = false;

  @HiveField(11)
  bool isRecurring = false;

  @HiveField(12)
  int? recurrenceInterval;

  @HiveField(13)
  String? recurrenceUnit; // DAYS, WEEKS, MONTHS

  @HiveField(14)
  DateTime? nextOccurrenceDate;

  @HiveField(15)
  DateTime createdAt = DateTime.now();

  @HiveField(16)
  bool isSynced = false;

  @HiveField(17)
  String? serverId;

  @HiveField(18)
  String? primaryCategory;

  @HiveField(19)
  List<String> detailLabels = <String>[];

  @HiveField(20)
  bool isRegretted = false;
}
