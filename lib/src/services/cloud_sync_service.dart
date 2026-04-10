import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../models/income_model.dart';
import '../models/label_model.dart';
import '../models/user_model.dart';
import 'app_time_format_service.dart';
import 'auth_memory_store.dart';
import 'firebase_uid_service.dart';
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
  static const Map<String, String> _detailLabelPrimaryCategories =
      <String, String>{
        'Food': 'Food',
        'Food Delivery': 'Food',
        'Groceries': 'Food',
        'Commute': 'Transport',
        'Transport': 'Transport',
        'Learning Materials': 'Services',
        'University Fees': 'Services',
        'Personal Care': 'Services',
        'Rent': 'Services',
        'Services': 'Services',
        'Utilities': 'Services',
        'Entertainment': 'Other',
        'Gifts': 'Other',
        'Group Hangouts': 'Other',
        'Subscriptions': 'Other',
        'Emergency': 'Other',
        'Impulse': 'Other',
        'Owed': 'Other',
      };

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

  Future<bool> deleteExpenseRecord(ExpenseModel expense) async {
    return _deleteRecord(
      collectionName: 'expenses',
      serverId: expense.serverId,
      fallbackDocumentId: _canonicalExpenseDocumentId(expense),
      deleteLocal: () => expense.delete(),
    );
  }

  Future<bool> deleteIncomeRecord(IncomeModel income) async {
    return _deleteRecord(
      collectionName: 'incomes',
      serverId: income.serverId,
      fallbackDocumentId: _canonicalIncomeDocumentId(income),
      deleteLocal: () => income.delete(),
    );
  }

  Future<bool> deleteGoalRecord(GoalModel goal) async {
    return _deleteRecord(
      collectionName: 'goals',
      serverId: goal.serverId,
      fallbackDocumentId: _canonicalGoalDocumentId(goal),
      deleteLocal: () => goal.delete(),
    );
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

    await FirebaseUidService.ensureFirebaseUid();
    try {
      await _mergeRemoteStateForCurrentUser();
    } catch (error) {
      debugPrint('Cloud sync remote merge failed: $error');
    }

    var uploadedExpenses = 0;
    var uploadedIncomes = 0;
    var uploadedGoals = 0;
    var uploadedLabels = 0;
    var uploadedUsers = 0;
    var failures = 0;

    final expenseBox = LocalStorageService.expenseBox;
    final expenseDocumentIds = _buildCanonicalExpenseDocumentIds();
    for (var index = 0; index < expenseBox.length; index++) {
      final expense = expenseBox.getAt(index);
      if (expense == null) {
        continue;
      }

      try {
        final localId = _localIdFor(expense, index);
        final firebaseUid = _firebaseUidForUserId(expense.userId);
        final canonicalDocumentId =
            expenseDocumentIds[_recordStorageKey(expense, index)];
        if (!_shouldSyncRecord(
          isSynced: expense.isSynced,
          serverId: expense.serverId,
          canonicalDocumentId: canonicalDocumentId,
        )) {
          continue;
        }

        final documentId = await _upsertDocument(
          collectionName: 'expenses',
          serverId: expense.serverId,
          fallbackDocumentId: canonicalDocumentId,
          includeSyncMetadata: false,
          preferFallbackDocumentId: true,
          deleteLegacyDocumentWhenMigrating: true,
          data: _expenseToMap(expense, localId, firebaseUid: firebaseUid),
        );
        await _localStorage.markExpenseAsSynced(index, documentId);
        uploadedExpenses++;
      } catch (_) {
        failures++;
      }
    }

    final incomeBox = LocalStorageService.incomeBox;
    final incomeDocumentIds = _buildCanonicalIncomeDocumentIds();
    for (var index = 0; index < incomeBox.length; index++) {
      final income = incomeBox.getAt(index);
      if (income == null) {
        continue;
      }

      try {
        final localId = _localIdFor(income, index);
        final firebaseUid = _firebaseUidForUserId(income.userId);
        final canonicalDocumentId =
            incomeDocumentIds[_recordStorageKey(income, index)];
        if (!_shouldSyncRecord(
          isSynced: income.isSynced,
          serverId: income.serverId,
          canonicalDocumentId: canonicalDocumentId,
        )) {
          continue;
        }

        final documentId = await _upsertDocument(
          collectionName: 'incomes',
          serverId: income.serverId,
          fallbackDocumentId: canonicalDocumentId,
          includeSyncMetadata: false,
          preferFallbackDocumentId: true,
          deleteLegacyDocumentWhenMigrating: true,
          data: _incomeToMap(income, localId, firebaseUid: firebaseUid),
        );
        await _localStorage.markIncomeAsSynced(index, documentId);
        uploadedIncomes++;
      } catch (_) {
        failures++;
      }
    }

    final goalBox = LocalStorageService.goalBox;
    final goalDocumentIds = _buildCanonicalGoalDocumentIds();
    for (var index = 0; index < goalBox.length; index++) {
      final goal = goalBox.getAt(index);
      if (goal == null) {
        continue;
      }

      try {
        final localId = _localIdFor(goal, index);
        final firebaseUid = _firebaseUidForUserId(goal.userId);
        final canonicalDocumentId =
            goalDocumentIds[_recordStorageKey(goal, index)];
        if (!_shouldSyncRecord(
          isSynced: goal.isSynced,
          serverId: goal.serverId,
          canonicalDocumentId: canonicalDocumentId,
        )) {
          continue;
        }

        final documentId = await _upsertDocument(
          collectionName: 'goals',
          serverId: goal.serverId,
          fallbackDocumentId: canonicalDocumentId,
          includeSyncMetadata: false,
          preferFallbackDocumentId: true,
          deleteLegacyDocumentWhenMigrating: true,
          data: _goalToMap(goal, localId, firebaseUid: firebaseUid),
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
      if (label == null ||
          !_shouldSyncRecord(
            isSynced: label.isSynced,
            serverId: label.serverId,
          )) {
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
      if (user == null || !_isUserReadyForCloudSync(user)) {
        continue;
      }

      try {
        final localId = _localIdFor(user, index);
        final uid = _firebaseUidForUser(user, localId);
        if (!_shouldSyncRecord(
          isSynced: user.isSynced,
          serverId: user.serverId,
        )) {
          continue;
        }

        final documentId = await _upsertDocument(
          collectionName: 'users',
          serverId: user.serverId,
          fallbackDocumentId: uid,
          includeSyncMetadata: false,
          preferFallbackDocumentId: true,
          deleteLegacyDocumentWhenMigrating: true,
          data: _userToMap(user, localId),
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

  Future<void> _mergeRemoteStateForCurrentUser() async {
    final activeUserId = AuthMemoryStore.currentUserId;
    if (activeUserId == null) {
      return;
    }

    final activeUser = _localStorage.getUserById(activeUserId);
    if (activeUser == null) {
      return;
    }

    final firebaseUid = _firebaseUidForUser(activeUser, activeUserId).trim();
    if (firebaseUid.isEmpty || firebaseUid.startsWith('user_')) {
      return;
    }

    final userSnapshot = await _firestore
        .collection('users')
        .doc(firebaseUid)
        .get(const GetOptions(source: Source.server));
    if (userSnapshot.exists) {
      await _mergeRemoteUser(userSnapshot, localUser: activeUser);
    }

    final remoteExpenses = await _firestore
        .collection('expenses')
        .where('firebaseUid', isEqualTo: firebaseUid)
        .get(const GetOptions(source: Source.server));
    await _mergeRemoteExpenses(remoteExpenses, localUserId: activeUserId);

    final remoteIncomes = await _firestore
        .collection('incomes')
        .where('firebaseUid', isEqualTo: firebaseUid)
        .get(const GetOptions(source: Source.server));
    await _mergeRemoteIncomes(remoteIncomes, localUserId: activeUserId);

    final remoteGoals = await _firestore
        .collection('goals')
        .where('firebaseUid', isEqualTo: firebaseUid)
        .get(const GetOptions(source: Source.server));
    await _mergeRemoteGoals(remoteGoals, localUserId: activeUserId);

    final remoteLabels = await _firestore
        .collection('labels')
        .where('firebaseUid', isEqualTo: firebaseUid)
        .get(const GetOptions(source: Source.server));
    await _mergeRemoteLabels(remoteLabels, localUserId: activeUserId);
  }

  Future<void> _mergeRemoteUser(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required UserModel localUser,
  }) async {
    final data = snapshot.data();
    if (data == null) {
      return;
    }

    final username = _stringValue(
      data['username'],
      fallback: _normalizedUsername(localUser),
    );
    localUser
      ..firebaseUid = _stringValue(data['uid'], fallback: snapshot.id)
      ..username = username
      ..email = _stringValue(data['email'], fallback: localUser.email)
      ..displayName =
          _stringOrNull(data['displayName'], fallback: localUser.displayName) ??
          username
      ..handle =
          _stringOrNull(data['handle'], fallback: localUser.handle) ??
          _normalizedHandle(localUser, username)
      ..createdAt = _dateTimeValue(data['createdAt']) ?? localUser.createdAt
      ..isSynced = true
      ..serverId = snapshot.id;
    await localUser.save();

    final currentUsername = AuthMemoryStore.currentState.username?.trim() ?? '';
    if (currentUsername != username) {
      await AuthMemoryStore.updateCurrentUsername(username);
    }
  }

  Future<void> _mergeRemoteExpenses(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int localUserId,
  }) async {
    for (final document in snapshot.docs) {
      final existingExpense = _findByServerId(
        LocalStorageService.expenseBox.values,
        document.id,
        readServerId: (expense) => expense.serverId,
      );
      if (existingExpense != null && !existingExpense.isSynced) {
        continue;
      }

      final data = document.data();
      final expense = existingExpense ?? ExpenseModel();
      final remoteIsRecurring = _boolValue(
        data['isRecurring'],
        fallback: expense.isRecurring,
      );
      final detailLabels = _expenseDetailLabelsValue(
        detailLabels: data['detailLabels'],
        labelNames: data['labelNames'],
        fallback: expense.detailLabels,
      );
      expense
        ..userId = localUserId
        ..name = _stringValue(data['name'], fallback: expense.name)
        ..amount = _doubleValue(data['amount'], fallback: expense.amount)
        ..date = _dateTimeValue(data['date']) ?? expense.date
        ..time = AppTimeFormatService.to24HourString(
          _stringValue(
            data['time'],
            fallback: expense.time.isNotEmpty ? expense.time : '00:00',
          ),
          fallback: expense.time.isNotEmpty ? expense.time : '00:00',
        )
        ..latitude = _doubleOrNull(data['latitude'], fallback: expense.latitude)
        ..longitude = _doubleOrNull(
          data['longitude'],
          fallback: expense.longitude,
        )
        ..locationName = _stringOrNull(
          data['locationName'],
          fallback: expense.locationName,
        )
        ..source = _stringValue(
          data['source'],
          fallback: expense.source.isNotEmpty ? expense.source : 'MANUAL',
        )
        ..receiptImagePath = _stringOrNull(
          data['receiptImagePath'],
          fallback: expense.receiptImagePath,
        )
        ..isPendingCategory = _boolValue(
          data['isPendingCategory'],
          fallback: expense.isPendingCategory,
        )
        ..isRecurring = remoteIsRecurring
        ..recurrenceInterval = _intOrNull(
          data['recurrenceInterval'],
          fallback: expense.recurrenceInterval,
        )
        ..recurrenceUnit = _stringOrNull(
          data['recurrenceUnit'],
          fallback: expense.recurrenceUnit,
        )
        ..nextOccurrenceDate =
            _dateTimeValue(data['nextOccurrenceDate']) ??
            expense.nextOccurrenceDate
        ..createdAt = _dateTimeValue(data['createdAt']) ?? expense.createdAt
        ..primaryCategory =
            _normalizePrimaryCategory(
              _stringOrNull(
                data['primaryCategory'],
                fallback: expense.primaryCategory,
              ),
            ) ??
            _derivePrimaryCategoryFromLabels(detailLabels) ??
            expense.primaryCategory
        ..detailLabels = detailLabels
        ..isRegretted = data.containsKey('isRegretted')
            ? _boolValue(data['isRegretted'], fallback: expense.isRegretted)
            : remoteIsRecurring
        ..wasAutoCategorized = _boolValue(
          data['wasAutoCategorized'],
          fallback: expense.wasAutoCategorized,
        )
        ..isSynced = true
        ..serverId = document.id;

      if (existingExpense == null) {
        await _localStorage.saveExpense(expense);
      } else {
        await expense.save();
      }
    }
  }

  Future<void> _mergeRemoteIncomes(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int localUserId,
  }) async {
    for (final document in snapshot.docs) {
      final existingIncome = _findByServerId(
        LocalStorageService.incomeBox.values,
        document.id,
        readServerId: (income) => income.serverId,
      );
      if (existingIncome != null && !existingIncome.isSynced) {
        continue;
      }

      final data = document.data();
      final income = existingIncome ?? IncomeModel();
      income
        ..userId = localUserId
        ..name = _stringValue(data['name'], fallback: income.name)
        ..amount = _doubleValue(data['amount'], fallback: income.amount)
        ..type = _stringValue(
          data['type'],
          fallback: income.type.isNotEmpty ? income.type : 'JUST_ONCE',
        )
        ..recurrenceInterval = _intOrNull(
          data['recurrenceInterval'],
          fallback: income.recurrenceInterval,
        )
        ..recurrenceUnit = _stringOrNull(
          data['recurrenceUnit'],
          fallback: income.recurrenceUnit,
        )
        ..nextOccurrenceDate =
            _dateTimeValue(data['nextOccurrenceDate']) ??
            income.nextOccurrenceDate
        ..startDate = _dateTimeValue(data['startDate']) ?? income.startDate
        ..createdAt = _dateTimeValue(data['createdAt']) ?? income.createdAt
        ..isSynced = true
        ..serverId = document.id;

      if (existingIncome == null) {
        await _localStorage.saveIncome(income);
      } else {
        await income.save();
      }
    }
  }

  Future<void> _mergeRemoteGoals(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int localUserId,
  }) async {
    for (final document in snapshot.docs) {
      final existingGoal = _findByServerId(
        LocalStorageService.goalBox.values,
        document.id,
        readServerId: (goal) => goal.serverId,
      );
      if (existingGoal != null && !existingGoal.isSynced) {
        continue;
      }

      final data = document.data();
      final goal = existingGoal ?? GoalModel();
      goal
        ..userId = localUserId
        ..name = _stringValue(data['name'], fallback: goal.name)
        ..targetAmount = _doubleValue(
          data['targetAmount'],
          fallback: goal.targetAmount,
        )
        ..currentAmount = _doubleValue(
          data['currentAmount'],
          fallback: goal.currentAmount,
        )
        ..deadline = _dateTimeValue(data['deadline']) ?? goal.deadline
        ..isCompleted = _boolValue(
          data['isCompleted'],
          fallback: goal.isCompleted,
        )
        ..createdAt = _dateTimeValue(data['createdAt']) ?? goal.createdAt
        ..isSynced = true
        ..serverId = document.id;

      if (existingGoal == null) {
        await _localStorage.saveGoal(goal);
      } else {
        await goal.save();
      }
    }
  }

  Future<void> _mergeRemoteLabels(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int localUserId,
  }) async {
    for (final document in snapshot.docs) {
      final existingLabel = _findByServerId(
        LocalStorageService.labelBox.values,
        document.id,
        readServerId: (label) => label.serverId,
      );
      if (existingLabel != null && !existingLabel.isSynced) {
        continue;
      }

      final data = document.data();
      final label = existingLabel ?? LabelModel();
      label
        ..userId = localUserId
        ..name = _stringValue(data['name'], fallback: label.name)
        ..iconEmoji = _stringOrNull(
          data['iconEmoji'],
          fallback: label.iconEmoji,
        )
        ..colorHex = _stringOrNull(data['colorHex'], fallback: label.colorHex)
        ..createdAt = _dateTimeValue(data['createdAt']) ?? label.createdAt
        ..isSynced = true
        ..serverId = document.id;

      if (existingLabel == null) {
        await _localStorage.saveLabel(label);
      } else {
        await label.save();
      }
    }
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

  bool _shouldSyncRecord({
    required bool isSynced,
    required String? serverId,
    String? canonicalDocumentId,
  }) {
    if (!isSynced) {
      return true;
    }

    final normalizedServerId = serverId?.trim();
    if (normalizedServerId == null || normalizedServerId.isEmpty) {
      return true;
    }

    final normalizedCanonicalId = canonicalDocumentId?.trim();
    if (normalizedCanonicalId != null &&
        normalizedCanonicalId.isNotEmpty &&
        normalizedCanonicalId != normalizedServerId) {
      return true;
    }

    return false;
  }

  Future<String> _upsertDocument({
    required String collectionName,
    required String? serverId,
    String? fallbackDocumentId,
    bool includeSyncMetadata = true,
    bool preferFallbackDocumentId = false,
    bool deleteLegacyDocumentWhenMigrating = false,
    required Map<String, Object?> data,
  }) async {
    final collection = _firestore.collection(collectionName);
    final resolvedDocumentId = _resolvedDocumentId(
      serverId: serverId,
      fallbackDocumentId: fallbackDocumentId,
      preferFallbackDocumentId: preferFallbackDocumentId,
    );
    final document = collection.doc(resolvedDocumentId);
    final payload = includeSyncMetadata
        ? <String, Object?>{...data, 'syncedAt': FieldValue.serverTimestamp()}
        : data;

    await document.set(payload);

    final remoteSnapshot = await document.get(
      const GetOptions(source: Source.server),
    );
    if (!remoteSnapshot.exists) {
      throw StateError(
        'Cloud sync could not confirm $collectionName/${document.id} on server.',
      );
    }

    final legacyServerId = serverId?.trim();
    if (deleteLegacyDocumentWhenMigrating &&
        legacyServerId != null &&
        legacyServerId.isNotEmpty &&
        legacyServerId != document.id) {
      await collection.doc(legacyServerId).delete();
    }

    return document.id;
  }

  Future<bool> _deleteRecord({
    required String collectionName,
    required String? serverId,
    required String fallbackDocumentId,
    required Future<void> Function() deleteLocal,
  }) async {
    var deletedFromCloud = true;

    if (isSupportedPlatform) {
      deletedFromCloud = await _deleteCloudDocumentVariants(
        collectionName: collectionName,
        serverId: serverId,
        fallbackDocumentId: fallbackDocumentId,
      );
    }

    await deleteLocal();
    return deletedFromCloud;
  }

  Future<bool> _deleteCloudDocumentVariants({
    required String collectionName,
    required String? serverId,
    required String fallbackDocumentId,
  }) async {
    var deletedFromCloud = true;
    final collection = _firestore.collection(collectionName);
    final documentIds = <String>{
      if (serverId != null && serverId.trim().isNotEmpty) serverId.trim(),
      fallbackDocumentId,
    };

    for (final documentId in documentIds) {
      try {
        await collection.doc(documentId).delete();
      } catch (_) {
        deletedFromCloud = false;
      }
    }

    return deletedFromCloud;
  }

  Map<String, Object?> _expenseToMap(
    ExpenseModel expense,
    int localId, {
    required String firebaseUid,
  }) {
    return <String, Object?>{
      'id': localId,
      'userId': expense.userId,
      'firebaseUid': firebaseUid,
      'name': expense.name,
      'amount': expense.amount,
      'date': _toEpochMillis(expense.date),
      'time': AppTimeFormatService.to24HourString(
        expense.time,
        fallback: expense.time.isNotEmpty ? expense.time : '00:00',
      ),
      'latitude': expense.latitude,
      'longitude': expense.longitude,
      'locationName': expense.locationName,
      'source': expense.source,
      'receiptImagePath': expense.receiptImagePath,
      'isPendingCategory': expense.isPendingCategory,
      'isRecurring': expense.isRecurring || expense.isRegretted,
      'recurrenceInterval': expense.recurrenceInterval,
      'recurrenceUnit': expense.recurrenceUnit,
      'nextOccurrenceDate': _toEpochMillis(expense.nextOccurrenceDate),
      'createdAt': _toEpochMillis(expense.createdAt),
      'primaryCategory': expense.primaryCategory,
      'detailLabels': expense.detailLabels,
      'labelNames': expense.detailLabels,
      'isRegretted': expense.isRegretted,
      'wasAutoCategorized': expense.wasAutoCategorized,
    };
  }

  Map<String, Object?> _incomeToMap(
    IncomeModel income,
    int localId, {
    required String firebaseUid,
  }) {
    return <String, Object?>{
      'id': localId,
      'userId': income.userId,
      'firebaseUid': firebaseUid,
      'name': income.name,
      'amount': income.amount,
      'type': income.type,
      'recurrenceInterval': income.recurrenceInterval,
      'recurrenceUnit': income.recurrenceUnit,
      'nextOccurrenceDate': _toEpochMillis(income.nextOccurrenceDate),
      'startDate': _toEpochMillis(income.startDate),
      'createdAt': _toEpochMillis(income.createdAt),
    };
  }

  Map<String, Object?> _goalToMap(
    GoalModel goal,
    int localId, {
    required String firebaseUid,
  }) {
    return <String, Object?>{
      'id': localId,
      'userId': goal.userId,
      'firebaseUid': firebaseUid,
      'name': goal.name,
      'targetAmount': goal.targetAmount,
      'currentAmount': goal.currentAmount,
      'deadline': _toEpochMillis(goal.deadline),
      'isCompleted': goal.isCompleted,
      'createdAt': _toEpochMillis(goal.createdAt),
    };
  }

  Map<String, Object?> _labelToMap(LabelModel label, int localIndex) {
    return <String, Object?>{
      'localIndex': localIndex,
      'userId': label.userId,
      'firebaseUid': _firebaseUidForEntity(),
      'name': label.name,
      'category': _derivePrimaryCategoryFromLabels(<String>[label.name]),
      'iconEmoji': label.iconEmoji,
      'colorHex': label.colorHex,
      'createdAt': _toEpochMillis(label.createdAt),
      'entityType': 'label',
    };
  }

  Map<String, Object?> _userToMap(UserModel user, int localId) {
    final username = _normalizedUsername(user);
    final uid = _firebaseUidForUser(user, localId);
    final displayName = _normalizedDisplayName(user, username);

    return <String, Object?>{
      'uid': uid,
      'username': username,
      'email': user.email.trim(),
      'displayName': displayName,
      'handle': _normalizedHandle(user, username),
      'createdAt': _toEpochMillis(user.createdAt),
    };
  }

  bool _isUserReadyForCloudSync(UserModel user) {
    final username = user.username.trim();
    final email = user.email.trim();
    final displayName = user.displayName?.trim() ?? '';
    final handle = user.handle?.trim() ?? '';
    final firebaseUid = _firebaseUidForUser(user, -1).trim();

    return username.isNotEmpty &&
        email.isNotEmpty &&
        displayName.isNotEmpty &&
        handle.isNotEmpty &&
        firebaseUid.isNotEmpty &&
        !firebaseUid.startsWith('user_');
  }

  int _localIdFor(HiveObject object, int fallbackIndex) {
    final key = object.key;
    if (key is int) {
      return key;
    }
    if (key is String) {
      return int.tryParse(key) ?? fallbackIndex;
    }
    return fallbackIndex;
  }

  String _recordStorageKey(HiveObject object, int fallbackIndex) {
    return object.key?.toString() ?? 'index_$fallbackIndex';
  }

  String _entityDocumentId({
    required String firebaseUid,
    required int counter,
  }) {
    return '${firebaseUid}_$counter';
  }

  String _canonicalExpenseDocumentId(ExpenseModel expense) {
    final recordKey = _recordStorageKey(expense, _localIdFor(expense, 0));
    return _buildCanonicalExpenseDocumentIds()[recordKey] ??
        _entityDocumentId(
          firebaseUid: _firebaseUidForUserId(expense.userId),
          counter: 1,
        );
  }

  String _canonicalIncomeDocumentId(IncomeModel income) {
    final recordKey = _recordStorageKey(income, _localIdFor(income, 0));
    return _buildCanonicalIncomeDocumentIds()[recordKey] ??
        _entityDocumentId(
          firebaseUid: _firebaseUidForUserId(income.userId),
          counter: 1,
        );
  }

  String _canonicalGoalDocumentId(GoalModel goal) {
    final recordKey = _recordStorageKey(goal, _localIdFor(goal, 0));
    return _buildCanonicalGoalDocumentIds()[recordKey] ??
        _entityDocumentId(
          firebaseUid: _firebaseUidForUserId(goal.userId),
          counter: 1,
        );
  }

  Map<String, String> _buildCanonicalExpenseDocumentIds() {
    return _buildCanonicalDocumentIds<ExpenseModel>(
      box: LocalStorageService.expenseBox,
      readUserId: (expense) => expense.userId,
      readServerId: (expense) => expense.serverId,
      readCreatedAt: (expense) => expense.createdAt,
    );
  }

  Map<String, String> _buildCanonicalIncomeDocumentIds() {
    return _buildCanonicalDocumentIds<IncomeModel>(
      box: LocalStorageService.incomeBox,
      readUserId: (income) => income.userId,
      readServerId: (income) => income.serverId,
      readCreatedAt: (income) => income.createdAt,
    );
  }

  Map<String, String> _buildCanonicalGoalDocumentIds() {
    return _buildCanonicalDocumentIds<GoalModel>(
      box: LocalStorageService.goalBox,
      readUserId: (goal) => goal.userId,
      readServerId: (goal) => goal.serverId,
      readCreatedAt: (goal) => goal.createdAt,
    );
  }

  Map<String, String> _buildCanonicalDocumentIds<T extends HiveObject>({
    required Box<T> box,
    required int Function(T value) readUserId,
    required String? Function(T value) readServerId,
    required DateTime Function(T value) readCreatedAt,
  }) {
    final candidatesByFirebaseUid =
        <String, List<_CanonicalDocumentCandidate<T>>>{};

    for (var index = 0; index < box.length; index++) {
      final value = box.getAt(index);
      if (value == null) {
        continue;
      }

      final firebaseUid = _firebaseUidForUserId(readUserId(value)).trim();
      if (firebaseUid.isEmpty) {
        continue;
      }

      candidatesByFirebaseUid
          .putIfAbsent(firebaseUid, () => <_CanonicalDocumentCandidate<T>>[])
          .add(
            _CanonicalDocumentCandidate<T>(
              value: value,
              recordKey: _recordStorageKey(value, index),
              firebaseUid: firebaseUid,
              serverId: readServerId(value),
              createdAt: readCreatedAt(value),
              localOrder: _localIdFor(value, index),
            ),
          );
    }

    final canonicalDocumentIds = <String, String>{};

    for (final entry in candidatesByFirebaseUid.entries) {
      final firebaseUid = entry.key;
      final candidates = entry.value
        ..sort((left, right) {
          final createdAtComparison = left.createdAt.compareTo(right.createdAt);
          if (createdAtComparison != 0) {
            return createdAtComparison;
          }
          return left.localOrder.compareTo(right.localOrder);
        });

      final usedCounters = <int>{};
      final unresolved = <_CanonicalDocumentCandidate<T>>[];

      for (final candidate in candidates) {
        final counter = _canonicalCounterFromDocumentId(
          candidate.serverId,
          firebaseUid,
        );
        if (counter == null || counter <= 0 || !usedCounters.add(counter)) {
          unresolved.add(candidate);
          continue;
        }

        canonicalDocumentIds[candidate.recordKey] = _entityDocumentId(
          firebaseUid: firebaseUid,
          counter: counter,
        );
      }

      var nextCounter = 1;
      for (final candidate in unresolved) {
        while (usedCounters.contains(nextCounter)) {
          nextCounter++;
        }

        usedCounters.add(nextCounter);
        canonicalDocumentIds[candidate.recordKey] = _entityDocumentId(
          firebaseUid: firebaseUid,
          counter: nextCounter,
        );
        nextCounter++;
      }
    }

    return canonicalDocumentIds;
  }

  int? _canonicalCounterFromDocumentId(String? documentId, String firebaseUid) {
    final normalizedDocumentId = documentId?.trim();
    if (normalizedDocumentId == null || normalizedDocumentId.isEmpty) {
      return null;
    }

    final match = RegExp(
      '^${RegExp.escape(firebaseUid)}_(\\d+)\$',
    ).firstMatch(normalizedDocumentId);
    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(1)!);
  }

  String _resolvedDocumentId({
    required String? serverId,
    required String? fallbackDocumentId,
    required bool preferFallbackDocumentId,
  }) {
    if (preferFallbackDocumentId &&
        fallbackDocumentId != null &&
        fallbackDocumentId.trim().isNotEmpty) {
      return fallbackDocumentId;
    }
    if (serverId != null && serverId.trim().isNotEmpty) {
      return serverId;
    }
    if (fallbackDocumentId != null && fallbackDocumentId.trim().isNotEmpty) {
      return fallbackDocumentId;
    }
    return _firestore.collection('_').doc().id;
  }

  int? _toEpochMillis(DateTime? value) {
    return value?.millisecondsSinceEpoch;
  }

  T? _findByServerId<T>(
    Iterable<T> values,
    String serverId, {
    required String? Function(T value) readServerId,
  }) {
    final normalizedServerId = serverId.trim();
    if (normalizedServerId.isEmpty) {
      return null;
    }

    for (final value in values) {
      final candidateServerId = readServerId(value)?.trim();
      if (candidateServerId == normalizedServerId) {
        return value;
      }
    }

    return null;
  }

  String _stringValue(Object? value, {String fallback = ''}) {
    return _stringOrNull(value, fallback: fallback) ?? fallback;
  }

  String? _stringOrNull(Object? value, {String? fallback}) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) {
      final normalizedFallback = fallback?.trim();
      if (normalizedFallback == null || normalizedFallback.isEmpty) {
        return null;
      }
      return normalizedFallback;
    }
    return normalized;
  }

  double _doubleValue(Object? value, {double fallback = 0}) {
    return _doubleOrNull(value, fallback: fallback) ?? fallback;
  }

  double? _doubleOrNull(Object? value, {double? fallback}) {
    if (value is num) {
      return value.toDouble();
    }

    final parsed = double.tryParse(value?.toString().trim() ?? '');
    return parsed ?? fallback;
  }

  int? _intOrNull(Object? value, {int? fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value?.toString().trim() ?? '');
    return parsed ?? fallback;
  }

  bool _boolValue(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
      default:
        return fallback;
    }
  }

  List<String> _stringListValue(Object? value, {List<String>? fallback}) {
    if (value is Iterable) {
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }

    return fallback == null
        ? const <String>[]
        : List<String>.from(fallback, growable: false);
  }

  List<String> _expenseDetailLabelsValue({
    required Object? detailLabels,
    required Object? labelNames,
    List<String>? fallback,
  }) {
    final primaryValues = _stringListValue(detailLabels);
    if (primaryValues.isNotEmpty) {
      return primaryValues;
    }

    final legacyValues = _stringListValue(labelNames);
    if (legacyValues.isNotEmpty) {
      return legacyValues;
    }

    return fallback == null
        ? const <String>[]
        : List<String>.from(fallback, growable: false);
  }

  DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }

    final millis = int.tryParse(normalized);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }

    return DateTime.tryParse(normalized);
  }

  String? _derivePrimaryCategoryFromLabels(Iterable<String> labels) {
    for (final label in labels) {
      final normalizedLabel = label.trim();
      if (normalizedLabel.isEmpty) {
        continue;
      }

      final category = _detailLabelPrimaryCategories[normalizedLabel];
      if (category != null) {
        return category;
      }
    }

    return labels.any((label) => label.trim().isNotEmpty) ? 'Other' : null;
  }

  String? _normalizePrimaryCategory(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    switch (trimmed) {
      case 'Food':
        return 'Food';
      case 'Transport':
        return 'Transport';
      case 'Services':
        return 'Services';
      default:
        return 'Other';
    }
  }

  String _firebaseUidForEntity() {
    final currentFirebaseUid = FirebaseUidService.currentFirebaseUid();
    if (currentFirebaseUid != null && currentFirebaseUid.isNotEmpty) {
      return currentFirebaseUid;
    }

    final box = LocalStorageService.userBox;
    for (var index = 0; index < box.length; index++) {
      final user = box.getAt(index);
      if (user == null) {
        continue;
      }

      return _firebaseUidForUser(user, _localIdFor(user, index));
    }
    return 'user_1';
  }

  String _firebaseUidForUserId(int userId) {
    final user = _localStorage.getUserById(userId);
    if (user != null) {
      return _firebaseUidForUser(user, userId);
    }

    return _firebaseUidForEntity();
  }

  String _firebaseUidForUser(UserModel user, int localId) {
    final firebaseUid = user.firebaseUid?.trim();
    if (firebaseUid != null && firebaseUid.isNotEmpty) {
      return firebaseUid;
    }

    final currentFirebaseUid = FirebaseUidService.currentFirebaseUid();
    if (currentFirebaseUid != null && currentFirebaseUid.isNotEmpty) {
      return currentFirebaseUid;
    }

    return 'user_$localId';
  }

  String _normalizedUsername(UserModel user) {
    final username = user.username.trim();
    if (username.isNotEmpty) {
      return username;
    }

    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    return 'User';
  }

  String _normalizedDisplayName(UserModel user, String username) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return username;
  }

  String _normalizedHandle(UserModel user, String username) {
    final handle = user.handle?.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle;
    }

    final normalized = username.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final safeValue = normalized.isEmpty ? 'spendant' : normalized;
    return '@$safeValue';
  }
}

class _CanonicalDocumentCandidate<T extends HiveObject> {
  const _CanonicalDocumentCandidate({
    required this.value,
    required this.recordKey,
    required this.firebaseUid,
    required this.serverId,
    required this.createdAt,
    required this.localOrder,
  });

  final T value;
  final String recordKey;
  final String firebaseUid;
  final String? serverId;
  final DateTime createdAt;
  final int localOrder;
}
