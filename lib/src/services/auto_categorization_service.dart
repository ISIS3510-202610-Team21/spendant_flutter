import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../theme/expense_visuals.dart';
import 'connectivity_service.dart';
import 'embedding_service.dart';
import 'local_storage_service.dart';
import 'pinecone_configuration.dart';
import 'pinecone_repository.dart';

enum AutoCategorizationFallbackReason {
  missingText,
  notConfigured,
  noInternet,
  requestFailed,
  noMatch,
  lowConfidence,
  missingLabelMetadata,
}

class AutoCategorizationResult {
  const AutoCategorizationResult.autoAssigned({
    required this.label,
    required this.detailLabels,
    required this.primaryCategory,
    this.score,
  }) : assigned = true,
       fallbackReason = null;

  const AutoCategorizationResult.manualRequired({
    required AutoCategorizationFallbackReason this.fallbackReason,
    this.score,
  }) : assigned = false,
       label = null,
       primaryCategory = null,
       detailLabels = const <String>[];

  final bool assigned;
  final String? label;
  final String? primaryCategory;
  final List<String> detailLabels;
  final double? score;
  final AutoCategorizationFallbackReason? fallbackReason;
}

class AutoCategorizationService {
  factory AutoCategorizationService({
    PineconeConfiguration? configuration,
    PineconeRepository? repository,
    EmbeddingService? embeddingService,
    ConnectivityService? connectivityService,
  }) {
    final resolvedConfiguration =
        configuration ?? PineconeConfiguration.fromEnvironment();
    return AutoCategorizationService._(
      configuration: resolvedConfiguration,
      repository:
          repository ??
          HttpPineconeRepository(configuration: resolvedConfiguration),
      embeddingService:
          embeddingService ??
          PineconeEmbeddingService(configuration: resolvedConfiguration),
      connectivityService: connectivityService ?? DefaultConnectivityService(),
    );
  }

  AutoCategorizationService._({
    required PineconeConfiguration? configuration,
    required PineconeRepository repository,
    required EmbeddingService embeddingService,
    required ConnectivityService connectivityService,
  }) : _configuration = configuration,
       _repository = repository,
       _embeddingService = embeddingService,
       _connectivityService = connectivityService;

  static final AutoCategorizationService instance = AutoCategorizationService();


  static const Map<String, String> _labelAliases = <String, String>{
    'academic essentials': 'Learning Materials',
    'commute': 'Commute',
    'delivery': 'Food Delivery',
    'education': 'Learning Materials',
    'emergency': 'Emergency',
    'entertainment': 'Entertainment',
    'food': 'Food',
    'food delivery': 'Food Delivery',
    'gift': 'Gifts',
    'gifts': 'Gifts',
    'grocery': 'Groceries',
    'groceries': 'Groceries',
    'group hangouts': 'Group Hangouts',
    'hangouts': 'Group Hangouts',
    'impulse': 'Impulse',
    'learning materials': 'Learning Materials',
    'lifestyle & social': 'Entertainment',
    'living expenses': 'Services',
    'other': 'Other',
    'owed': 'Owed',
    'personal care': 'Personal Care',
    'rent': 'Rent',
    'service': 'Services',
    'services': 'Services',
    'strategic & utility tags': 'Emergency',
    'subscription': 'Subscriptions',
    'subscriptions': 'Subscriptions',
    'transport': 'Transport',
    'transportation': 'Transport',
    'tuition': 'University Fees',
    'university fees': 'University Fees',
    'utilities': 'Utilities',
    'utility': 'Utilities',
  };

  static const int _cacheCapacity = 100;

  final PineconeConfiguration? _configuration;
  final PineconeRepository _repository;
  final EmbeddingService _embeddingService;
  final ConnectivityService _connectivityService;
  final LinkedHashMap<String, AutoCategorizationResult> _cache =
      LinkedHashMap<String, AutoCategorizationResult>();
  Future<int>? _activeBackfill;

  String _cacheKey(String expenseName) => expenseName.trim().toLowerCase();

  bool get isConfigured =>
      _configuration != null &&
      _repository.isConfigured &&
      _embeddingService.isConfigured;

  Future<AutoCategorizationResult> categorizeExpense(
    String merchantText,
  ) async {
    final normalizedMerchant = merchantText.trim();
    if (normalizedMerchant.isEmpty) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.missingText,
      );
    }

    if (!isConfigured) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.notConfigured,
      );
    }

    return _categorizeNormalizedMerchant(normalizedMerchant);
  }

  Future<int> backfillPendingExpenseCategories({
    Iterable<ExpenseModel>? expenses,
  }) async {
    if (!isConfigured) {
      return 0;
    }

    final candidates =
        (expenses ?? LocalStorageService.expenseBox.values)
            .where(_expenseNeedsCategory)
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    if (candidates.isEmpty) {
      return 0;
    }

    final runningBackfill = _activeBackfill;
    if (runningBackfill != null) {
      return runningBackfill;
    }

    final backfillFuture = _backfillPendingExpenseCategoriesInternal(
      candidates,
    );
    _activeBackfill = backfillFuture;

    try {
      return await backfillFuture;
    } finally {
      if (identical(_activeBackfill, backfillFuture)) {
        _activeBackfill = null;
      }
    }
  }

  Future<AutoCategorizationResult> _categorizeNormalizedMerchant(
    String normalizedMerchant,
  ) async {
    final key = _cacheKey(normalizedMerchant);
    final cached = _cache[key];
    if (cached != null) {
      _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!hasInternet) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.noInternet,
      );
    }

    try {
      final embedding = await _embeddingService.embedQuery(normalizedMerchant);
      final match = await _repository.queryNearest(vector: embedding);

      final AutoCategorizationResult result;
      if (match == null) {
        result = const AutoCategorizationResult.manualRequired(
          fallbackReason: AutoCategorizationFallbackReason.noMatch,
        );
      } else {
        final rawLabel = match.metadata['label']?.toString().trim();
        if (rawLabel == null || rawLabel.isEmpty) {
          result = AutoCategorizationResult.manualRequired(
            fallbackReason:
                AutoCategorizationFallbackReason.missingLabelMetadata,
            score: match.score,
          );
        } else {
          final label = _normalizeLabel(rawLabel) ?? rawLabel;
          if (match.score < _similarityThreshold) {
            result = AutoCategorizationResult.manualRequired(
              fallbackReason: AutoCategorizationFallbackReason.lowConfidence,
              score: match.score,
            );
          } else {
            result = AutoCategorizationResult.autoAssigned(
              label: label,
              detailLabels: _detailLabelsFor(label),
              primaryCategory: _primaryCategoryForLabel(label),
              score: match.score,
            );
          }
        }
      }

      if (_cache.length >= _cacheCapacity) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = result;
      return result;
    } catch (_) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.requestFailed,
      );
    }
  }

  Future<int> _backfillPendingExpenseCategoriesInternal(
    List<ExpenseModel> expenses,
  ) async {
    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!hasInternet) {
      return 0;
    }

    var updatedCount = 0;
    for (final expense in expenses) {
      if (!_expenseNeedsCategory(expense)) {
        continue;
      }

      final merchantText = expense.name.trim();
      if (merchantText.isEmpty) {
        continue;
      }

      final categorization = await _categorizeNormalizedMerchant(merchantText);
      final didApply = await _applyCategorizationToExpense(
        expense,
        categorization,
      );
      if (didApply) {
        updatedCount++;
      }
    }

    return updatedCount;
  }

  Future<bool> _applyCategorizationToExpense(
    ExpenseModel expense,
    AutoCategorizationResult categorization,
  ) async {
    if (!categorization.assigned) {
      return false;
    }

    final primaryCategory = categorization.primaryCategory?.trim();
    final detailLabels = categorization.detailLabels
        .map((label) => (_normalizeLabel(label) ?? label).trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    if (primaryCategory == null ||
        primaryCategory.isEmpty ||
        detailLabels.isEmpty) {
      return false;
    }

    final didChange =
        expense.isPendingCategory ||
        expense.primaryCategory?.trim() != primaryCategory ||
        !_listContentsEqual(expense.detailLabels, detailLabels) ||
        !expense.wasAutoCategorized;
    if (!didChange) {
      return false;
    }

    expense
      ..primaryCategory = primaryCategory
      ..detailLabels = detailLabels
      ..isPendingCategory = false
      ..wasAutoCategorized = true
      ..isSynced = false;

    if (expense.isInBox) {
      await expense.save();
    }
    await _clearPendingCategoryNotifications(expense);
    return true;
  }

  Future<void> _clearPendingCategoryNotifications(ExpenseModel expense) async {
    final notificationIds = <String>{
      'expense-category-${expense.key ?? expense.createdAt.microsecondsSinceEpoch}',
      'expense-category-${expense.createdAt.microsecondsSinceEpoch}',
    };

    try {
      for (final notification
          in LocalStorageService.notificationBox.values.toList()) {
        if (notification.userId != expense.userId ||
            notification.type != AppNotificationTypes.expenseCategoryNeeded ||
            !notificationIds.contains(notification.id) ||
            !notification.isInBox) {
          continue;
        }

        await notification.delete();
      }
    } catch (_) {
      // Notification cleanup should not block category repair.
    }
  }

  bool _expenseNeedsCategory(ExpenseModel expense) {
    return expense.isPendingCategory ||
        (expense.detailLabels.isEmpty &&
            (expense.primaryCategory?.trim().isEmpty ?? true));
  }

  Future<bool> learnFromManualCategory({
    required String merchantText,
    required String label,
  }) async {
    final normalizedMerchant = merchantText.trim();
    final normalizedLabel = (_normalizeLabel(label) ?? label).trim();
    if (normalizedMerchant.isEmpty ||
        normalizedLabel.isEmpty ||
        !isConfigured) {
      return false;
    }

    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!hasInternet) {
      return false;
    }

    try {
      final embedding = await _embeddingService.embedPassage(
        normalizedMerchant,
      );
      await _repository.upsertVector(
        id: _buildVectorId(
          merchantText: normalizedMerchant,
          label: normalizedLabel,
        ),
        values: embedding,
        metadata: <String, Object?>{
          'merchant': normalizedMerchant,
          'text': normalizedMerchant,
          'label': normalizedLabel,
          'category': _primaryCategoryForLabel(normalizedLabel),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  double get _similarityThreshold =>
      _configuration?.similarityThreshold ??
      PineconeConfiguration.defaultSimilarityThreshold;

  List<String> _detailLabelsFor(String label) {
    final normalizedLabel = _normalizeLabel(label) ?? label.trim();
    if (normalizedLabel.isEmpty) {
      return const <String>[];
    }

    return <String>[normalizedLabel];
  }

  String _primaryCategoryForLabel(String label) {
    final normalizedLabel = _normalizeLabel(label) ?? label.trim();
    final directMatch = ExpenseVisuals.detailLabelPrimaryCategories[normalizedLabel];
    if (directMatch != null) {
      return directMatch;
    }

    switch (normalizedLabel.toLowerCase()) {
      case 'food':
        return 'Food';
      case 'transport':
        return 'Transport';
      case 'services':
        return 'Services';
      default:
        return 'Other';
    }
  }

  String? _normalizeLabel(String? rawLabel) {
    if (rawLabel == null) {
      return null;
    }

    final trimmed = rawLabel.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final knownLabel in ExpenseVisuals.detailLabelPrimaryCategories.keys) {
      if (knownLabel.toLowerCase() == trimmed.toLowerCase()) {
        return knownLabel;
      }
    }

    if (trimmed.toLowerCase() == 'other') {
      return 'Other';
    }

    final alias = _labelAliases[_slugify(trimmed)];
    if (alias != null) {
      return alias;
    }

    return trimmed;
  }

  String _buildVectorId({required String merchantText, required String label}) {
    final digest = sha1.convert(
      utf8.encode('${merchantText.toLowerCase()}::$label'),
    );
    return 'expense_${digest.toString()}';
  }

  String _slugify(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _listContentsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }
}
