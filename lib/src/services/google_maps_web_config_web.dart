// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

const String _googleMapsApiKeyStorageKey = 'GOOGLE_MAPS_API_KEY';
const String _fallbackGoogleMapsApiKey =
    'AIzaSyBw9W_7GwOntgGVTqYpnSj8k7_9_W-7zWU';
const String _googleMapsScriptId = 'spendant-google-maps-js';
const String _googleMapsLoadedFlag = 'spendantGoogleMapsLoaded';

Completer<bool>? _googleMapsLoader;

bool hasConfiguredGoogleMapsApiKeyOnWeb() {
  return _configuredGoogleMapsApiKey().isNotEmpty;
}

Future<bool> ensureGoogleMapsApiKeyOnWebLoaded() {
  final configuredKey = _configuredGoogleMapsApiKey();
  if (configuredKey.isEmpty) {
    return Future<bool>.value(false);
  }

  if (_hasLoadedGoogleMapsJavaScript()) {
    return Future<bool>.value(true);
  }

  final existingLoader = _googleMapsLoader;
  if (existingLoader != null) {
    return existingLoader.future;
  }

  final loader = Completer<bool>();
  _googleMapsLoader = loader;

  final existingScript = html.document.getElementById(_googleMapsScriptId);
  if (existingScript is html.ScriptElement) {
    existingScript.onError.first.then((_) {
      if (!loader.isCompleted) {
        loader.complete(false);
      }
    });
    existingScript.onLoad.first.then((_) {
      if (!loader.isCompleted) {
        loader.complete(_hasLoadedGoogleMapsJavaScript());
      }
    });
    return loader.future;
  }

  final script = html.ScriptElement()
    ..id = _googleMapsScriptId
    ..async = true
    ..defer = true
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(configuredKey)}&libraries=places&loading=async';

  script.onError.first.then((_) {
    html.document.documentElement?.dataset.remove(_googleMapsLoadedFlag);
    if (!loader.isCompleted) {
      loader.complete(false);
    }
  });
  script.onLoad.first.then((_) {
    html.document.documentElement?.dataset[_googleMapsLoadedFlag] = 'true';
    if (!loader.isCompleted) {
      loader.complete(_hasLoadedGoogleMapsJavaScript());
    }
  });

  html.document.head?.append(script);
  return loader.future;
}

String _configuredGoogleMapsApiKey() {
  final queryKey = Uri.base.queryParameters['gmapsKey']?.trim() ?? '';
  if (queryKey.isNotEmpty) {
    html.window.localStorage[_googleMapsApiKeyStorageKey] = queryKey;
    return queryKey;
  }

  final storedKey =
      html.window.localStorage[_googleMapsApiKeyStorageKey]?.trim() ?? '';
  if (storedKey.isNotEmpty) {
    return storedKey;
  }

  return _fallbackGoogleMapsApiKey.trim();
}

bool _hasLoadedGoogleMapsJavaScript() {
  return html.document.documentElement?.dataset[_googleMapsLoadedFlag] ==
      'true';
}
