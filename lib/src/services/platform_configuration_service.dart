import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class PlatformConfigurationService {
  static const MethodChannel _channel = MethodChannel(
    'spendant_flutter/platform_config',
  );

  static Future<bool> hasGoogleMapsApiKey() async {
    if (kIsWeb) {
      return false;
    }

    final hasKey = await _channel.invokeMethod<bool>('hasGoogleMapsApiKey');
    return hasKey ?? false;
  }
}
