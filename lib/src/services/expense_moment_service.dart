import '../models/expense_model.dart';

abstract final class ExpenseMomentService {
  static DateTime expenseMoment(ExpenseModel expense) {
    final parts = expense.time.trim().split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
  }

  static bool isFutureExpense(ExpenseModel expense, {DateTime? now}) {
    return expenseMoment(expense).isAfter(now ?? DateTime.now());
  }
}
