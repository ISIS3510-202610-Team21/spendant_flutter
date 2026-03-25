import '../models/expense_model.dart';
import '../services/expense_moment_service.dart';
import '../services/local_storage_service.dart';

class ExpenseAnalyticsRepository {
  const ExpenseAnalyticsRepository();

  List<ExpenseModel> getCompletedExpensesForUser(int userId) {
    return LocalStorageService.expenseBox.values
        .where(
          (expense) =>
              expense.userId == userId &&
              !ExpenseMomentService.isFutureExpense(expense),
        )
        .toList(growable: false);
  }
}
