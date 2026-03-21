import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'connectivity_service.dart';
import 'embedding_service.dart';
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
      connectivityService:
          connectivityService ?? DefaultConnectivityService(),
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

  final PineconeConfiguration? _configuration;
  final PineconeRepository _repository;
  final EmbeddingService _embeddingService;
  final ConnectivityService _connectivityService;

  bool get isConfigured =>
      _configuration != null &&
      _repository.isConfigured &&
      _embeddingService.isConfigured;

  Future<AutoCategorizationResult> categorizeExpense(String merchantText) async {
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

    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!hasInternet) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.noInternet,
      );
    }

    try {
      final embedding = await _embeddingService.embedQuery(normalizedMerchant);
      final match = await _repository.queryNearest(vector: embedding);
      if (match == null) {
        return const AutoCategorizationResult.manualRequired(
          fallbackReason: AutoCategorizationFallbackReason.noMatch,
        );
      }

      final rawLabel = match.metadata['label']?.toString().trim();
      if (rawLabel == null || rawLabel.isEmpty) {
        return AutoCategorizationResult.manualRequired(
          fallbackReason: AutoCategorizationFallbackReason.missingLabelMetadata,
          score: match.score,
        );
      }

      final label = _normalizeLabel(rawLabel) ?? rawLabel;
      if (match.score < _similarityThreshold) {
        return AutoCategorizationResult.manualRequired(
          fallbackReason: AutoCategorizationFallbackReason.lowConfidence,
          score: match.score,
        );
      }

      final detailLabels = _detailLabelsFor(label);
      return AutoCategorizationResult.autoAssigned(
        label: label,
        detailLabels: detailLabels,
        primaryCategory: _primaryCategoryForLabel(label),
        score: match.score,
      );
    } catch (_) {
      return const AutoCategorizationResult.manualRequired(
        fallbackReason: AutoCategorizationFallbackReason.requestFailed,
      );
    }
  }

  Future<bool> learnFromManualCategory({
    required String merchantText,
    required String label,
  }) async {
    final normalizedMerchant = merchantText.trim();
    final normalizedLabel = (_normalizeLabel(label) ?? label).trim();
    if (normalizedMerchant.isEmpty || normalizedLabel.isEmpty || !isConfigured) {
      return false;
    }

    final hasInternet = await _connectivityService.hasInternetConnection();
    if (!hasInternet) {
      return false;
    }

    try {
      final embedding = await _embeddingService.embedPassage(normalizedMerchant);
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
    final directMatch = _detailLabelPrimaryCategories[normalizedLabel];
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

    for (final knownLabel in _detailLabelPrimaryCategories.keys) {
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

  String _buildVectorId({
    required String merchantText,
    required String label,
  }) {
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
}
