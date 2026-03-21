import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pinecone_configuration.dart';

abstract interface class EmbeddingService {
  bool get isConfigured;

  Future<List<double>> embedQuery(String text);

  Future<List<double>> embedPassage(String text);
}

class PineconeEmbeddingService implements EmbeddingService {
  PineconeEmbeddingService({
    PineconeConfiguration? configuration,
    http.Client? client,
  }) : _configuration = configuration,
       _client = client ?? http.Client();

  final PineconeConfiguration? _configuration;
  final http.Client _client;

  @override
  bool get isConfigured => _configuration != null;

  @override
  Future<List<double>> embedQuery(String text) {
    return _embed(text, inputType: 'query');
  }

  @override
  Future<List<double>> embedPassage(String text) {
    return _embed(text, inputType: 'passage');
  }

  Future<List<double>> _embed(String text, {required String inputType}) async {
    final configuration = _configuration;
    if (configuration == null) {
      throw StateError('Pinecone embedding configuration is missing.');
    }

    final response = await _client.post(
      Uri.parse('https://api.pinecone.io/embed'),
      headers: <String, String>{
        'Api-Key': configuration.apiKey,
        'Content-Type': 'application/json',
        'X-Pinecone-Api-Version': PineconeConfiguration.apiVersion,
      },
      body: jsonEncode(<String, Object?>{
        'model': configuration.embeddingModel,
        'parameters': <String, Object?>{
          'input_type': inputType,
          'dimension': configuration.embeddingDimension,
        },
        'inputs': <Map<String, String>>[
          <String, String>{'text': text},
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Pinecone embed failed with ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Pinecone embed returned an invalid response.');
    }

    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw StateError('Pinecone embed returned no vectors.');
    }

    final first = data.first;
    if (first is! Map<String, dynamic>) {
      throw StateError('Pinecone embed returned a malformed vector payload.');
    }

    final values = first['values'];
    if (values is! List) {
      throw StateError('Pinecone embed returned no vector values.');
    }

    return values
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList(growable: false);
  }
}
