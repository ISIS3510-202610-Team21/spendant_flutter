import 'package:geocoding/geocoding.dart';

typedef PlacemarkLookup =
    Future<List<Placemark>> Function(double latitude, double longitude);
typedef AddressLookup = Future<List<Location>> Function(String address);

class ExpenseLocationSearchResult {
  const ExpenseLocationSearchResult({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

class ExpenseLocationService {
  const ExpenseLocationService({
    PlacemarkLookup placemarkLookup = placemarkFromCoordinates,
    AddressLookup addressLookup = locationFromAddress,
  }) : _placemarkLookup = placemarkLookup,
       _addressLookup = addressLookup;

  final PlacemarkLookup _placemarkLookup;
  final AddressLookup _addressLookup;

  Future<String> resolveLabel({
    required double latitude,
    required double longitude,
  }) async {
    final fallbackLabel = formatCoordinates(latitude, longitude);

    try {
      final placemarks = await _placemarkLookup(latitude, longitude);
      if (placemarks.isEmpty) {
        return fallbackLabel;
      }

      return buildPlacemarkLabel(placemarks.first) ?? fallbackLabel;
    } catch (_) {
      return fallbackLabel;
    }
  }

  Future<ExpenseLocationSearchResult?> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return null;
    }

    try {
      final matches = await _addressLookup(query);
      if (matches.isEmpty) {
        return null;
      }

      final match = matches.first;
      return ExpenseLocationSearchResult(
        latitude: match.latitude,
        longitude: match.longitude,
        label: query,
      );
    } catch (_) {
      return null;
    }
  }

  static String? buildPlacemarkLabel(Placemark placemark) {
    final rawSegments = <String>[
      placemark.name ?? '',
      placemark.street ?? '',
      placemark.subLocality ?? '',
      placemark.locality ?? '',
      placemark.administrativeArea ?? '',
      placemark.country ?? '',
    ];

    final segments = <String>[];
    final seen = <String>{};

    for (final segment in rawSegments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final normalized = _normalizeSegment(trimmed);
      if (!seen.add(normalized)) {
        continue;
      }

      segments.add(trimmed);
    }

    if (segments.isEmpty) {
      return null;
    }

    return segments.join(', ');
  }

  static String formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }

  static bool looksLikeCoordinateLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }

    return RegExp(
      r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$',
    ).hasMatch(normalized);
  }

  static String _normalizeSegment(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
