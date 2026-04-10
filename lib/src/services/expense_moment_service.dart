import '../models/expense_model.dart';
import 'app_time_format_service.dart';

abstract final class ExpenseMomentService {
  static DateTime expenseMoment(ExpenseModel expense) {
    final parsedTime = AppTimeFormatService.parseHourMinute(expense.time);

    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      parsedTime.hour.clamp(0, 23),
      parsedTime.minute.clamp(0, 59),
    );
  }

  static bool isFutureExpense(ExpenseModel expense, {DateTime? now}) {
    return expenseMoment(expense).isAfter(now ?? DateTime.now());
  }
}
