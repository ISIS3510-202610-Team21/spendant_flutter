import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pinecone_configuration.dart';

class PineconeQueryMatch {
  const PineconeQueryMatch({
    required this.id,
    required this.score,
    required this.metadata,
  });

  final String id;
  final double score;
  final Map<String, dynamic> metadata;
}

abstract interface class PineconeRepository {
  bool get isConfigured;

  Future<PineconeQueryMatch?> queryNearest({
    required List<double> vector,
    int topK = 1,
  });

  Future<void> upsertVector({
    required String id,
    required List<double> values,
    required Map<String, Object?> metadata,
  });
}

class HttpPineconeRepository implements PineconeRepository {
  HttpPineconeRepository({
    PineconeConfiguration? configuration,
    http.Client? client,
  }) : _configuration = configuration,
       _client = client ?? http.Client();

  final PineconeConfiguration? _configuration;
  final http.Client _client;

  @override
  bool get isConfigured => _configuration != null;

  @override
  Future<PineconeQueryMatch?> queryNearest({
    required List<double> vector,
    int topK = 1,
  }) async {
    final configuration = _configuration;
    if (configuration == null) {
      throw StateError('Pinecone repository configuration is missing.');
    }

    final response = await _client.post(
      configuration.indexHost.resolve('/query'),
      headers: _headers(configuration),
      body: jsonEncode(<String, Object?>{
        'namespace': configuration.namespace,
        'vector': vector,
        'topK': topK,
        'includeMetadata': true,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Pinecone query failed with ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Pinecone query returned an invalid response.');
    }

    final matches = decoded['matches'];
    if (matches is! List || matches.isEmpty) {
      return null;
    }

    final match = matches.first;
    if (match is! Map<String, dynamic>) {
      return null;
    }

    final metadata = match['metadata'];
    return PineconeQueryMatch(
      id: match['id']?.toString() ?? '',
      score: (match['score'] as num?)?.toDouble() ?? 0,
      metadata: metadata is Map<String, dynamic>
          ? metadata
          : <String, dynamic>{},
    );
  }

  @override
  Future<void> upsertVector({
    required String id,
    required List<double> values,
    required Map<String, Object?> metadata,
  }) async {
    final configuration = _configuration;
    if (configuration == null) {
      throw StateError('Pinecone repository configuration is missing.');
    }

    final response = await _client.post(
      configuration.indexHost.resolve('/vectors/upsert'),
      headers: _headers(configuration),
      body: jsonEncode(<String, Object?>{
        'namespace': configuration.namespace,
        'vectors': <Map<String, Object?>>[
          <String, Object?>{
            'id': id,
            'values': values,
            'metadata': metadata,
          },
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Pinecone upsert failed with ${response.statusCode}: ${response.body}',
      );
    }
  }

  Map<String, String> _headers(PineconeConfiguration configuration) {
    return <String, String>{
      'Api-Key': configuration.apiKey,
      'Content-Type': 'application/json',
      'X-Pinecone-Api-Version': PineconeConfiguration.apiVersion,
    };
  }
}
