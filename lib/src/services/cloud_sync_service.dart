import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import '../models/label_model.dart';
import '../models/user_model.dart';
import 'local_storage_service.dart';

class CloudSyncSummary {
  const CloudSyncSummary({
    this.uploadedExpenses = 0,
    this.uploadedIncomes = 0,
    this.uploadedGoals = 0,
    this.uploadedLabels = 0,
    this.uploadedUsers = 0,
    this.failures = 0,
  });

  final int uploadedExpenses;
  final int uploadedIncomes;
  final int uploadedGoals;
  final int uploadedLabels;
  final int uploadedUsers;
  final int failures;

  int get uploadedTotal =>
      uploadedExpenses +
      uploadedIncomes +
      uploadedGoals +
      uploadedLabels +
      uploadedUsers;
}

class CloudVerificationSummary {
  const CloudVerificationSummary({
    required this.remoteExpenses,
    required this.remoteIncomes,
    required this.remoteGoals,
    required this.remoteLabels,
    required this.remoteUsers,
    required this.pendingExpenses,
    required this.pendingIncomes,
    required this.pendingGoals,
    required this.pendingLabels,
    required this.pendingUsers,
    required this.missingExpenses,
    required this.missingIncomes,
    required this.missingGoals,
    required this.missingLabels,
    required this.missingUsers,
  });

  final int remoteExpenses;
  final int remoteIncomes;
  final int remoteGoals;
  final int remoteLabels;
  final int remoteUsers;
  final int pendingExpenses;
  final int pendingIncomes;
  final int pendingGoals;
  final int pendingLabels;
  final int pendingUsers;
  final int missingExpenses;
  final int missingIncomes;
  final int missingGoals;
  final int missingLabels;
  final int missingUsers;

  int get remoteTotal =>
      remoteExpenses + remoteIncomes + remoteGoals + remoteLabels + remoteUsers;

  int get pendingTotal =>
      pendingExpenses +
      pendingIncomes +
      pendingGoals +
      pendingLabels +
      pendingUsers;

  int get missingTotal =>
      missingExpenses +
      missingIncomes +
      missingGoals +
      missingLabels +
      missingUsers;
}

class CloudSyncService {
  CloudSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static Future<CloudSyncSummary>? _ongoingSync;
  static bool _syncRequestedWhileRunning = false;

  final FirebaseFirestore _firestore;
  final LocalStorageService _localStorage = LocalStorageService();

  static bool get isSupportedPlatform {
    if (kIsWeb) {
      return true;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
        return false;
    }
  }

  Future<CloudSyncSummary> syncAllPendingData() async {
    final ongoingSync = _ongoingSync;
    if (ongoingSync != null) {
      _syncRequestedWhileRunning = true;
      return ongoingSync;
    }

    final syncFuture = _runSyncQueue();
    _ongoingSync = syncFuture;

    try {
      return await syncFuture;
    } finally {
      if (identical(_ongoingSync, syncFuture)) {
        _ongoingSync = null;
      }
    }
  }

  Future<CloudSyncSummary> _runSyncQueue() async {
    CloudSyncSummary latestSummary = const CloudSyncSummary();

    do {
      _syncRequestedWhileRunning = false;
      latestSummary = await _syncAllPendingDataInternal();
    } while (_syncRequestedWhileRunning);

    return latestSummary;
  }

  Future<CloudSyncSummary> _syncAllPendingDataInternal() async {
    if (!isSupportedPlatform) {
      return const CloudSyncSummary();
    }

    var uploadedExpenses = 0;
    var uploadedIncomes = 0;
    var uploadedGoals = 0;
    var uploadedLabels = 0;
    var uploadedUsers = 0;
    var failures = 0;

    final expenseBox = LocalStorageService.expenseBox;
    for (var index = 0; index < expenseBox.length; index++) {
      final expense = expenseBox.getAt(index);
      if (expense == null || expense.isSynced) {
        continue;
      }

      try {
        final documentId = await _upsertDocument(
          collectionName: 'expenses',
          serverId: expense.serverId,
          data: _expenseToMap(expense, index),
        );
        await _localStorage.markExpenseAsSynced(index, documentId);
        uploadedExpenses++;
      } catch (_) {
        failures++;
      }
    }

    final incomeBox = LocalStorageService.incomeBox;
    for (var index = 0; index < incomeBox.length; index++) {
      final income = incomeBox.getAt(index);
      if (income == null || income.isSynced) {
        continue;
      }

      try {
        final documentId = await _upsertDocument(
          collectionName: 'incomes',
          serverId: income.serverId,
          data: _incomeToMap(income, index),
        );
        await _localStorage.markIncomeAsSynced(index, documentId);
        uploadedIncomes++;
      } catch (_) {
        failures++;
      }
    }

    final goalBox = LocalStorageService.goalBox;
    for (var index = 0; index < goalBox.length; index++) {
      final goal = goalBox.getAt(index);
      if (goal == null || goal.isSynced) {
        continue;
      }

      try {
        final documentId = await _upsertDocument(
          collectionName: 'goals',
          serverId: goal.serverId,
          data: _goalToMap(goal, index),
        );
        await _localStorage.markGoalAsSynced(index, documentId);
        uploadedGoals++;
      } catch (_) {
        failures++;
      }
    }

    final labelBox = LocalStorageService.labelBox;
    for (var index = 0; index < labelBox.length; index++) {
      final label = labelBox.getAt(index);
      if (label == null || label.isSynced) {
        continue;
      }

      try {
        final documentId = await _upsertDocument(
          collectionName: 'labels',
          serverId: label.serverId,
          data: _labelToMap(label, index),
        );
        await _localStorage.markLabelAsSynced(index, documentId);
        uploadedLabels++;
      } catch (_) {
        failures++;
      }
    }

    final userBox = LocalStorageService.userBox;
    for (var index = 0; index < userBox.length; index++) {
      final user = userBox.getAt(index);
      if (user == null || user.isSynced) {
        continue;
      }

      try {
        final documentId = await _upsertDocument(
          collectionName: 'users',
          serverId: user.serverId,
          data: _userToMap(user, index),
        );
        await _localStorage.markUserAsSynced(index, documentId);
        uploadedUsers++;
      } catch (_) {
        failures++;
      }
    }

    return CloudSyncSummary(
      uploadedExpenses: uploadedExpenses,
      uploadedIncomes: uploadedIncomes,
      uploadedGoals: uploadedGoals,
      uploadedLabels: uploadedLabels,
      uploadedUsers: uploadedUsers,
      failures: failures,
    );
  }

  Future<CloudVerificationSummary> verifyCloudState() async {
    if (!isSupportedPlatform) {
      return CloudVerificationSummary(
        remoteExpenses: 0,
        remoteIncomes: 0,
        remoteGoals: 0,
        remoteLabels: 0,
        remoteUsers: 0,
        pendingExpenses: LocalStorageService.expenseBox.values
            .where((expense) => !expense.isSynced)
            .length,
        pendingIncomes: LocalStorageService.incomeBox.values
            .where((income) => !income.isSynced)
            .length,
        pendingGoals: LocalStorageService.goalBox.values
            .where((goal) => !goal.isSynced)
            .length,
        pendingLabels: LocalStorageService.labelBox.values
            .where((label) => !label.isSynced)
            .length,
        pendingUsers: LocalStorageService.userBox.values
            .where((user) => !user.isSynced)
            .length,
        missingExpenses: 0,
        missingIncomes: 0,
        missingGoals: 0,
        missingLabels: 0,
        missingUsers: 0,
      );
    }

    final remoteExpenses =
        (await _firestore.collection('expenses').get()).docs.length;
    final remoteIncomes =
        (await _firestore.collection('incomes').get()).docs.length;
    final remoteGoals =
        (await _firestore.collection('goals').get()).docs.length;
    final remoteLabels =
        (await _firestore.collection('labels').get()).docs.length;
    final remoteUsers =
        (await _firestore.collection('users').get()).docs.length;

    final pendingExpenses = LocalStorageService.expenseBox.values
        .where((expense) => !expense.isSynced)
        .length;
    final pendingIncomes = LocalStorageService.incomeBox.values
        .where((income) => !income.isSynced)
        .length;
    final pendingGoals = LocalStorageService.goalBox.values
        .where((goal) => !goal.isSynced)
        .length;
    final pendingLabels = LocalStorageService.labelBox.values
        .where((label) => !label.isSynced)
        .length;
    final pendingUsers = LocalStorageService.userBox.values
        .where((user) => !user.isSynced)
        .length;

    final missingExpenses = await _countMissingSyncedExpenses();
    final missingIncomes = await _countMissingSyncedIncomes();
    final missingGoals = await _countMissingSyncedGoals();
    final missingLabels = await _countMissingSyncedLabels();
    final missingUsers = await _countMissingSyncedUsers();

    return CloudVerificationSummary(
      remoteExpenses: remoteExpenses,
      remoteIncomes: remoteIncomes,
      remoteGoals: remoteGoals,
      remoteLabels: remoteLabels,
      remoteUsers: remoteUsers,
      pendingExpenses: pendingExpenses,
      pendingIncomes: pendingIncomes,
      pendingGoals: pendingGoals,
      pendingLabels: pendingLabels,
      pendingUsers: pendingUsers,
      missingExpenses: missingExpenses,
      missingIncomes: missingIncomes,
      missingGoals: missingGoals,
      missingLabels: missingLabels,
      missingUsers: missingUsers,
    );
  }

  Future<int> _countMissingSyncedExpenses() async {
    var missing = 0;
    final box = LocalStorageService.expenseBox;

    for (var index = 0; index < box.length; index++) {
      final expense = box.getAt(index);
      final serverId = expense?.serverId;
      if (expense == null || !expense.isSynced || serverId == null) {
        continue;
      }

      final snapshot = await _firestore
          .collection('expenses')
          .doc(serverId)
          .get();
      if (!snapshot.exists) {
        missing++;
      }
    }

    return missing;
  }

  Future<int> _countMissingSyncedIncomes() async {
    var missing = 0;
    final box = LocalStorageService.incomeBox;

    for (var index = 0; index < box.length; index++) {
      final income = box.getAt(index);
      final serverId = income?.serverId;
      if (income == null || !income.isSynced || serverId == null) {
        continue;
      }

      final snapshot = await _firestore
          .collection('incomes')
          .doc(serverId)
          .get();
      if (!snapshot.exists) {
        missing++;
      }
    }

    return missing;
  }

  Future<int> _countMissingSyncedGoals() async {
    var missing = 0;
    final box = LocalStorageService.goalBox;

    for (var index = 0; index < box.length; index++) {
      final goal = box.getAt(index);
      final serverId = goal?.serverId;
      if (goal == null || !goal.isSynced || serverId == null) {
        continue;
      }

      final snapshot = await _firestore.collection('goals').doc(serverId).get();
      if (!snapshot.exists) {
        missing++;
      }
    }

    return missing;
  }

  Future<int> _countMissingSyncedLabels() async {
    var missing = 0;
    final box = LocalStorageService.labelBox;

    for (var index = 0; index < box.length; index++) {
      final label = box.getAt(index);
      final serverId = label?.serverId;
      if (label == null || !label.isSynced || serverId == null) {
        continue;
      }

      final snapshot = await _firestore
          .collection('labels')
          .doc(serverId)
          .get();
      if (!snapshot.exists) {
        missing++;
      }
    }

    return missing;
  }

  Future<int> _countMissingSyncedUsers() async {
    var missing = 0;
    final box = LocalStorageService.userBox;

    for (var index = 0; index < box.length; index++) {
      final user = box.getAt(index);
      final serverId = user?.serverId;
      if (user == null || !user.isSynced || serverId == null) {
        continue;
      }

      final snapshot = await _firestore.collection('users').doc(serverId).get();
      if (!snapshot.exists) {
        missing++;
      }
    }

    return missing;
  }

  Future<String> _upsertDocument({
    required String collectionName,
    required String? serverId,
    required Map<String, Object?> data,
  }) async {
    final collection = _firestore.collection(collectionName);
    final document = serverId != null && serverId.trim().isNotEmpty
        ? collection.doc(serverId)
        : collection.doc();

    await document.set(<String, Object?>{
      ...data,
      'syncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final remoteSnapshot = await document.get(
      const GetOptions(source: Source.server),
    );
    if (!remoteSnapshot.exists) {
      throw StateError(
        'Cloud sync could not confirm $collectionName/${document.id} on server.',
      );
    }

    return document.id;
  }

  Map<String, Object?> _expenseToMap(ExpenseModel expense, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'userId': expense.userId,
      'name': expense.name,
      'amount': expense.amount,
      'date': expense.date,
      'time': expense.time,
      'latitude': expense.latitude,
      'longitude': expense.longitude,
      'locationName': expense.locationName,
      'source': expense.source,
      'receiptImagePath': expense.receiptImagePath,
      'isPendingCategory': expense.isPendingCategory,
      'isRecurring': expense.isRecurring,
      'recurrenceInterval': expense.recurrenceInterval,
      'recurrenceUnit': expense.recurrenceUnit,
      'nextOccurrenceDate': expense.nextOccurrenceDate,
      'createdAt': expense.createdAt,
      'primaryCategory': expense.primaryCategory,
      'detailLabels': expense.detailLabels,
      'entityType': 'expense',
    };
  }

  Map<String, Object?> _incomeToMap(IncomeModel income, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'userId': income.userId,
      'name': income.name,
      'amount': income.amount,
      'type': income.type,
      'recurrenceInterval': income.recurrenceInterval,
      'recurrenceUnit': income.recurrenceUnit,
      'nextOccurrenceDate': income.nextOccurrenceDate,
      'startDate': income.startDate,
      'createdAt': income.createdAt,
      'entityType': 'income',
    };
  }

  Map<String, Object?> _goalToMap(GoalModel goal, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'userId': goal.userId,
      'name': goal.name,
      'targetAmount': goal.targetAmount,
      'currentAmount': goal.currentAmount,
      'deadline': goal.deadline,
      'isCompleted': goal.isCompleted,
      'createdAt': goal.createdAt,
      'entityType': 'goal',
    };
  }

  Map<String, Object?> _labelToMap(LabelModel label, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'userId': label.userId,
      'name': label.name,
      'iconEmoji': label.iconEmoji,
      'colorHex': label.colorHex,
      'createdAt': label.createdAt,
      'entityType': 'label',
    };
  }

  Map<String, Object?> _userToMap(UserModel user, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'username': user.username,
      'email': user.email,
      'passwordHash': user.passwordHash,
      'firebaseUid': user.firebaseUid,
      'displayName': user.displayName,
      'handle': user.handle,
      'avatarPath': user.avatarPath,
      'isFingerprintEnabled': user.isFingerprintEnabled,
      'createdAt': user.createdAt,
      'entityType': 'user',
    };
  }
}
