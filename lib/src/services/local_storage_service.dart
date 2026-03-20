import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import '../models/label_model.dart';
import '../models/user_model.dart';

class LocalStorageService {
  static const String _expensesBox = 'expenses';
  static const String _incomesBox = 'incomes';
  static const String _goalsBox = 'goals';
  static const String _notificationsBox = 'notifications';
  static const String _labelsBox = 'labels';
  static const String _usersBox = 'users';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters only once to avoid hot-restart collisions.
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ExpenseModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(IncomeModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(GoalModelAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(LabelModelAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(UserModelAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(AppNotificationModelAdapter());
    }

    // Open boxes
    if (!Hive.isBoxOpen(_expensesBox)) {
      await Hive.openBox<ExpenseModel>(_expensesBox);
    }
    if (!Hive.isBoxOpen(_incomesBox)) {
      await Hive.openBox<IncomeModel>(_incomesBox);
    }
    if (!Hive.isBoxOpen(_goalsBox)) {
      await Hive.openBox<GoalModel>(_goalsBox);
    }
    if (!Hive.isBoxOpen(_notificationsBox)) {
      await Hive.openBox<AppNotificationModel>(_notificationsBox);
    }
    if (!Hive.isBoxOpen(_labelsBox)) {
      await Hive.openBox<LabelModel>(_labelsBox);
    }
    if (!Hive.isBoxOpen(_usersBox)) {
      await Hive.openBox<UserModel>(_usersBox);
    }
  }

  static Box<ExpenseModel> get expenseBox =>
      Hive.box<ExpenseModel>(_expensesBox);
  static Box<IncomeModel> get incomeBox => Hive.box<IncomeModel>(_incomesBox);
  static Box<GoalModel> get goalBox => Hive.box<GoalModel>(_goalsBox);
  static Box<AppNotificationModel> get notificationBox =>
      Hive.box<AppNotificationModel>(_notificationsBox);
  static Box<LabelModel> get labelBox => Hive.box<LabelModel>(_labelsBox);
  static Box<UserModel> get userBox => Hive.box<UserModel>(_usersBox);

  static ValueListenable<Box<ExpenseModel>> get expensesListenable =>
      expenseBox.listenable();
  static ValueListenable<Box<GoalModel>> get goalsListenable =>
      goalBox.listenable();
  static ValueListenable<Box<AppNotificationModel>>
  get notificationsListenable => notificationBox.listenable();
  static ValueListenable<Box<IncomeModel>> get incomesListenable =>
      incomeBox.listenable();
  static ValueListenable<Box<LabelModel>> get labelsListenable =>
      labelBox.listenable();
  static ValueListenable<Box<UserModel>> get usersListenable =>
      userBox.listenable();

  // ─────────────────────────────────────────────────────────
  // EXPENSES
  // ─────────────────────────────────────────────────────────

  Future<void> saveExpense(ExpenseModel expense) async {
    await expenseBox.add(expense);
  }

  Future<List<ExpenseModel>> getAllExpenses() async {
    return expenseBox.values.toList();
  }

  Future<List<ExpenseModel>> getExpensesByUserId(int userId) async {
    return expenseBox.values.where((e) => e.userId == userId).toList();
  }

  Future<List<ExpenseModel>> getUnsyncedExpenses() async {
    return expenseBox.values.where((e) => !e.isSynced).toList();
  }

  Future<void> updateExpense(int index, ExpenseModel expense) async {
    await expenseBox.putAt(index, expense);
  }

  Future<void> deleteExpense(int index) async {
    await expenseBox.deleteAt(index);
  }

  Future<void> markExpenseAsSynced(int index, String serverId) async {
    final expense = expenseBox.getAt(index);
    if (expense != null) {
      expense.isSynced = true;
      expense.serverId = serverId;
      await expense.save();
    }
  }

  // ─────────────────────────────────────────────────────────
  // INCOMES
  // ─────────────────────────────────────────────────────────

  Future<void> saveIncome(IncomeModel income) async {
    await incomeBox.add(income);
  }

  Future<List<IncomeModel>> getAllIncomes() async {
    return incomeBox.values.toList();
  }

  Future<List<IncomeModel>> getIncomesByUserId(int userId) async {
    return incomeBox.values.where((i) => i.userId == userId).toList();
  }

  Future<List<IncomeModel>> getUnsyncedIncomes() async {
    return incomeBox.values.where((i) => !i.isSynced).toList();
  }

  Future<void> updateIncome(int index, IncomeModel income) async {
    await incomeBox.putAt(index, income);
  }

  Future<void> deleteIncome(int index) async {
    await incomeBox.deleteAt(index);
  }

  Future<void> markIncomeAsSynced(int index, String serverId) async {
    final income = incomeBox.getAt(index);
    if (income != null) {
      income.isSynced = true;
      income.serverId = serverId;
      await income.save();
    }
  }

  // ─────────────────────────────────────────────────────────
  // GOALS
  // ─────────────────────────────────────────────────────────

  Future<void> saveGoal(GoalModel goal) async {
    await goalBox.add(goal);
  }

  Future<List<GoalModel>> getAllGoals() async {
    return goalBox.values.toList();
  }

  Future<List<GoalModel>> getGoalsByUserId(int userId) async {
    return goalBox.values.where((g) => g.userId == userId).toList();
  }

  Future<List<GoalModel>> getUnsyncedGoals() async {
    return goalBox.values.where((g) => !g.isSynced).toList();
  }

  Future<void> updateGoal(int index, GoalModel goal) async {
    await goalBox.putAt(index, goal);
  }

  Future<void> deleteGoal(int index) async {
    await goalBox.deleteAt(index);
  }

  Future<void> markGoalAsSynced(int index, String serverId) async {
    final goal = goalBox.getAt(index);
    if (goal != null) {
      goal.isSynced = true;
      goal.serverId = serverId;
      await goal.save();
    }
  }

  // ─────────────────────────────────────────────────────────
  // LABELS
  // ─────────────────────────────────────────────────────────

  Future<void> saveLabel(LabelModel label) async {
    await labelBox.add(label);
  }

  Future<List<LabelModel>> getAllLabels() async {
    return labelBox.values.toList();
  }

  Future<List<LabelModel>> getLabelsByUserId(int userId) async {
    return labelBox.values.where((l) => l.userId == userId).toList();
  }

  Future<List<LabelModel>> getUnsyncedLabels() async {
    return labelBox.values.where((l) => !l.isSynced).toList();
  }

  Future<void> updateLabel(int index, LabelModel label) async {
    await labelBox.putAt(index, label);
  }

  Future<void> deleteLabel(int index) async {
    await labelBox.deleteAt(index);
  }

  Future<void> markLabelAsSynced(int index, String serverId) async {
    final label = labelBox.getAt(index);
    if (label != null) {
      label.isSynced = true;
      label.serverId = serverId;
      await label.save();
    }
  }

  // ─────────────────────────────────────────────────────────
  // USERS
  // ─────────────────────────────────────────────────────────

  Future<void> saveUser(UserModel user) async {
    await userBox.add(user);
  }

  Future<UserModel?> findUserByUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    for (final user in userBox.values) {
      if (user.username.trim().toLowerCase() == normalized) {
        return user;
      }
    }

    return null;
  }

  Future<UserModel?> findUserByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    for (final user in userBox.values) {
      if (user.email.trim().toLowerCase() == normalized) {
        return user;
      }
    }

    return null;
  }

  Future<UserModel?> findUserByFirebaseUid(String firebaseUid) async {
    final normalized = firebaseUid.trim();
    for (final user in userBox.values) {
      if ((user.firebaseUid?.trim() ?? '') == normalized) {
        return user;
      }
    }

    return null;
  }

  UserModel? getUserById(int userId) {
    return userBox.get(userId);
  }

  Future<UserModel?> getUser(int index) async {
    return userBox.getAt(index);
  }

  Future<List<UserModel>> getAllUsers() async {
    return userBox.values.toList();
  }

  Future<List<UserModel>> getUnsyncedUsers() async {
    return userBox.values.where((u) => !u.isSynced).toList();
  }

  Future<void> updateUser(int index, UserModel user) async {
    await userBox.putAt(index, user);
  }

  Future<void> markUserAsSynced(int index, String serverId) async {
    final user = userBox.getAt(index);
    if (user != null) {
      user.isSynced = true;
      user.serverId = serverId;
      await user.save();
    }
  }

  // ─────────────────────────────────────────────────────────
  // SYNC HELPERS
  // ─────────────────────────────────────────────────────────

  /// Obtiene todos los datos no sincronizados
  Future<Map<String, List>> getAllUnsyncedData() async {
    return {
      'expenses': await getUnsyncedExpenses(),
      'incomes': await getUnsyncedIncomes(),
      'goals': await getUnsyncedGoals(),
      'labels': await getUnsyncedLabels(),
      'users': await getUnsyncedUsers(),
    };
  }

  /// Limpia todas las boxes (uso en logout o reset)
  Future<void> clearAllData() async {
    await expenseBox.clear();
    await incomeBox.clear();
    await goalBox.clear();
    await notificationBox.clear();
    await labelBox.clear();
    await userBox.clear();
  }
}
