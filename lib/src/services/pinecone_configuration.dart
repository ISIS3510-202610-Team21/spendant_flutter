import 'package:flutter_dotenv/flutter_dotenv.dart';

class PineconeConfiguration {
  const PineconeConfiguration({
    required this.apiKey,
    required this.indexHost,
    required this.namespace,
    required this.similarityThreshold,
    required this.embeddingModel,
    required this.embeddingDimension,
  });

  static const String apiVersion = '2025-10';
  static const double defaultSimilarityThreshold = 0.20;
  static const int defaultEmbeddingDimension = 384;
  static const String defaultEmbeddingModel = 'llama-text-embed-v2';

  final String apiKey;
  final Uri indexHost;
  final String namespace;
  final double similarityThreshold;
  final String embeddingModel;
  final int embeddingDimension;

  static PineconeConfiguration? fromEnvironment() {
    final apiKey = dotenv.maybeGet('PINECONE_API_KEY')?.trim();
    final rawIndexHost = dotenv.maybeGet('PINECONE_INDEX_HOST')?.trim();
    if (apiKey == null ||
        apiKey.isEmpty ||
        rawIndexHost == null ||
        rawIndexHost.isEmpty) {
      return null;
    }

    final parsedHost = Uri.tryParse(rawIndexHost);
    if (parsedHost == null || !parsedHost.hasScheme || parsedHost.host.isEmpty) {
      return null;
    }

    final normalizedHost = Uri.parse(
      rawIndexHost.endsWith('/')
          ? rawIndexHost.substring(0, rawIndexHost.length - 1)
          : rawIndexHost,
    );
    final namespace =
        dotenv.maybeGet('PINECONE_NAMESPACE')?.trim().isNotEmpty == true
        ? dotenv.maybeGet('PINECONE_NAMESPACE')!.trim()
        : '__default__';
    final similarityThreshold =
        double.tryParse(
          dotenv.maybeGet('PINECONE_SIMILARITY_THRESHOLD') ?? '',
        ) ??
        defaultSimilarityThreshold;
    final embeddingModel =
        dotenv.maybeGet('PINECONE_EMBED_MODEL')?.trim().isNotEmpty == true
        ? dotenv.maybeGet('PINECONE_EMBED_MODEL')!.trim()
        : defaultEmbeddingModel;
    final embeddingDimension =
        int.tryParse(dotenv.maybeGet('PINECONE_EMBED_DIMENSION') ?? '') ??
        defaultEmbeddingDimension;

    return PineconeConfiguration(
      apiKey: apiKey,
      indexHost: normalizedHost,
      namespace: namespace,
      similarityThreshold: similarityThreshold,
      embeddingModel: embeddingModel,
      embeddingDimension: embeddingDimension,
    );
  }
}
