import 'package:flutter_test/flutter_test.dart';

import 'package:spendant/src/services/auto_categorization_service.dart';
import 'package:spendant/src/services/connectivity_service.dart';
import 'package:spendant/src/services/embedding_service.dart';
import 'package:spendant/src/services/pinecone_configuration.dart';
import 'package:spendant/src/services/pinecone_repository.dart';

void main() {
  group('AutoCategorizationService', () {
    final configuration = PineconeConfiguration(
      apiKey: 'test-key',
      indexHost: Uri.parse('https://example.pinecone.io'),
      namespace: '__default__',
      similarityThreshold: 0.20,
      embeddingModel: 'llama-text-embed-v2',
      embeddingDimension: 384,
    );

    test('normalizes aliased labels when confidence is high enough', () async {
      final service = AutoCategorizationService(
        configuration: configuration,
        connectivityService: _FakeConnectivityService(hasInternet: true),
        embeddingService: const _FakeEmbeddingService(),
        repository: _FakePineconeRepository(
          match: const PineconeQueryMatch(
            id: 'label-education',
            score: 0.81,
            metadata: <String, dynamic>{'label': 'Education'},
          ),
        ),
      );

      final result = await service.categorizeExpense('Papeleria el Mono');

      expect(result.assigned, isTrue);
      expect(result.label, 'Learning Materials');
      expect(result.primaryCategory, 'Services');
      expect(result.detailLabels, <String>['Learning Materials']);
    });

    test('falls back to manual categorization when there is no internet', () async {
      final service = AutoCategorizationService(
        configuration: configuration,
        connectivityService: _FakeConnectivityService(hasInternet: false),
        embeddingService: const _FakeEmbeddingService(),
        repository: _FakePineconeRepository(
          match: const PineconeQueryMatch(
            id: 'label-food',
            score: 0.92,
            metadata: <String, dynamic>{'label': 'Food'},
          ),
        ),
      );

      final result = await service.categorizeExpense('Restaurante Dona Blanca');

      expect(result.assigned, isFalse);
      expect(
        result.fallbackReason,
        AutoCategorizationFallbackReason.noInternet,
      );
    });

    test('falls back to manual categorization on low confidence matches', () async {
      final service = AutoCategorizationService(
        configuration: configuration,
        connectivityService: _FakeConnectivityService(hasInternet: true),
        embeddingService: const _FakeEmbeddingService(),
        repository: _FakePineconeRepository(
          match: const PineconeQueryMatch(
            id: 'label-food',
            score: 0.14,
            metadata: <String, dynamic>{'label': 'Food'},
          ),
        ),
      );

      final result = await service.categorizeExpense('Restaurante Dona Blanca');

      expect(result.assigned, isFalse);
      expect(
        result.fallbackReason,
        AutoCategorizationFallbackReason.lowConfidence,
      );
    });

    test('upserts manual feedback with normalized metadata', () async {
      final repository = _FakePineconeRepository();
      final service = AutoCategorizationService(
        configuration: configuration,
        connectivityService: _FakeConnectivityService(hasInternet: true),
        embeddingService: const _FakeEmbeddingService(),
        repository: repository,
      );

      final learned = await service.learnFromManualCategory(
        merchantText: 'Papeleria el Mono',
        label: 'Education',
      );

      expect(learned, isTrue);
      expect(repository.upsertedId, startsWith('expense_'));
      expect(repository.upsertedValues, hasLength(3));
      expect(repository.upsertedMetadata, isNotNull);
      expect(
        repository.upsertedMetadata!['merchant'],
        'Papeleria el Mono',
      );
      expect(
        repository.upsertedMetadata!['label'],
        'Learning Materials',
      );
      expect(repository.upsertedMetadata!['category'], 'Services');
    });

    test('skips feedback learning when offline', () async {
      final repository = _FakePineconeRepository();
      final service = AutoCategorizationService(
        configuration: configuration,
        connectivityService: _FakeConnectivityService(hasInternet: false),
        embeddingService: const _FakeEmbeddingService(),
        repository: repository,
      );

      final learned = await service.learnFromManualCategory(
        merchantText: 'Papeleria el Mono',
        label: 'Education',
      );

      expect(learned, isFalse);
      expect(repository.upsertedId, isNull);
    });
  });
}

class _FakeConnectivityService implements ConnectivityService {
  const _FakeConnectivityService({required this.hasInternet});

  final bool hasInternet;

  @override
  Future<bool> hasInternetConnection() async => hasInternet;
}

class _FakeEmbeddingService implements EmbeddingService {
  const _FakeEmbeddingService();

  @override
  bool get isConfigured => true;

  @override
  Future<List<double>> embedPassage(String text) async {
    return const <double>[0.1, 0.2, 0.3];
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    return const <double>[0.1, 0.2, 0.3];
  }
}

class _FakePineconeRepository implements PineconeRepository {
  _FakePineconeRepository({this.match});

  final PineconeQueryMatch? match;

  String? upsertedId;
  List<double>? upsertedValues;
  Map<String, Object?>? upsertedMetadata;

  @override
  bool get isConfigured => true;

  @override
  Future<PineconeQueryMatch?> queryNearest({
    required List<double> vector,
    int topK = 1,
  }) async {
    return match;
  }

  @override
  Future<void> upsertVector({
    required String id,
    required List<double> values,
    required Map<String, Object?> metadata,
  }) async {
    upsertedId = id;
    upsertedValues = values;
    upsertedMetadata = metadata;
  }
}
