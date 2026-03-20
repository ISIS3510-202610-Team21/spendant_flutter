import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'google_maps_web_config_stub.dart'
    if (dart.library.html) 'google_maps_web_config_web.dart';

abstract final class PlatformConfigurationService {
  static const MethodChannel _channel = MethodChannel(
    'spendant_flutter/platform_config',
  );

  static Future<bool> hasGoogleMapsApiKey() async {
    if (kIsWeb) {
      return hasConfiguredGoogleMapsApiKeyOnWeb();
    }

    try {
      final hasKey = await _channel.invokeMethod<bool>('hasGoogleMapsApiKey');
      return hasKey ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> ensureGoogleMapsIsReady() async {
    if (kIsWeb) {
      return ensureGoogleMapsApiKeyOnWebLoaded();
    }

    return hasGoogleMapsApiKey();
  }
}
