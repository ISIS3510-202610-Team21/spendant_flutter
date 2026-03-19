import 'package:hive/hive.dart';

part 'label_model.g.dart';

@HiveType(typeId: 3)
class LabelModel extends HiveObject {
  @HiveField(0)
  int userId = 0;

  @HiveField(1)
  String name = '';

  @HiveField(2)
  String? iconEmoji;

  @HiveField(3)
  String? colorHex;

  @HiveField(4)
  DateTime createdAt = DateTime.now();

  @HiveField(5)
  bool isSynced = false;

  @HiveField(6)
  String? serverId;
}
