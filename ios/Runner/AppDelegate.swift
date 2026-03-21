import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func googleMapsApiKeyFromDotEnv() -> String? {
    let flutterAssetsPath = Bundle.main.resourcePath?.appending("/flutter_assets/.env")
    guard
      let flutterAssetsPath,
      let fileContents = try? String(contentsOfFile: flutterAssetsPath, encoding: .utf8)
    else {
      return nil
    }

    let lines = fileContents.components(separatedBy: .newlines)
    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#") {
        continue
      }

      guard let separatorIndex = line.firstIndex(of: "=") else {
        continue
      }

      let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
      guard key == "GOOGLE_MAPS_API_KEY" || key == "MAPS_API_KEY" else {
        continue
      }

      let value = line[line.index(after: separatorIndex)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        return value
      }
    }

    return nil
  }

  private func googleMapsApiKey() -> String? {
    let bundleApiKey = Bundle.main.object(
      forInfoDictionaryKey: "GMSApiKey"
    ) as? String
    let environmentApiKey =
      ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ??
      ProcessInfo.processInfo.environment["MAPS_API_KEY"]
    let dotEnvApiKey = googleMapsApiKeyFromDotEnv()

    let candidates = [bundleApiKey, environmentApiKey, dotEnvApiKey]
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
