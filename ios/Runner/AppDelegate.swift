import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func googleMapsApiKey() -> String? {
    let bundleApiKey = Bundle.main.object(
      forInfoDictionaryKey: "GMSApiKey"
    ) as? String
    let environmentApiKey =
      ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ??
      ProcessInfo.processInfo.environment["MAPS_API_KEY"]

    let candidates = [bundleApiKey, environmentApiKey]
    for candidate in candidates {
      let trimmed = candidate?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? ""
      if trimmed.isEmpty || trimmed.hasPrefix("YOUR_") || trimmed.contains("$(") {
        continue
      }

      return trimmed
    }

    return nil
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = googleMapsApiKey() {
      GMSServices.provideAPIKey(apiKey)
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "spendant_flutter/platform_config",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "hasGoogleMapsApiKey":
          result(self.googleMapsApiKey() != nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
