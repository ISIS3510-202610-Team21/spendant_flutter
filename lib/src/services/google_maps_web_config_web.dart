// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const String _fallbackGoogleMapsApiKey =
    'AIzaSyBw9W_7GwOntgGVTqYpnSj8k7_9_W-7zWU';

bool hasConfiguredGoogleMapsApiKeyOnWeb() {
  final queryKey = Uri.base.queryParameters['gmapsKey']?.trim();
  if (queryKey != null && queryKey.isNotEmpty) {
    return true;
  }

  final storedKey = html.window.localStorage['GOOGLE_MAPS_API_KEY']?.trim();
  if (storedKey != null && storedKey.isNotEmpty) {
    return true;
  }

  return _fallbackGoogleMapsApiKey.trim().isNotEmpty;
}
