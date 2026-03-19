import 'package:hive/hive.dart';

part 'goal_model.g.dart';

@HiveType(typeId: 2)
class GoalModel extends HiveObject {
  @HiveField(0)
  int userId = 0;

  @HiveField(1)
  String name = '';

  @HiveField(2)
  double targetAmount = 0;

  @HiveField(3)
  double currentAmount = 0;

  @HiveField(4)
  DateTime deadline = DateTime.now();

  @HiveField(5)
  bool isCompleted = false;

  @HiveField(6)
  DateTime createdAt = DateTime.now();

  @HiveField(7)
  bool isSynced = false;

  @HiveField(8)
  String? serverId;

  /// Calcula el progreso como porcentaje (0-100)
  int getProgressPercent() {
    if (targetAmount > 0) {
      return ((currentAmount / targetAmount) * 100).toInt().clamp(0, 100);
    }
    return 0;
  }

  /// Calcula cuánto debe ahorrar por día para llegar a la meta
  double dailySavingsNeeded() {
    final remaining = targetAmount - currentAmount;
    final daysLeft = deadline.difference(DateTime.now()).inDays;
    return daysLeft > 0 ? remaining / daysLeft : remaining;
  }
}
