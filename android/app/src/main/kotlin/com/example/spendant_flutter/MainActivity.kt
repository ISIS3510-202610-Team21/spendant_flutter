package com.example.spendant_flutter

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        NotificationReaderBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/platform_config"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasGoogleMapsApiKey" -> result.success(hasGoogleMapsApiKey())
                else -> result.notImplemented()
            }
        }
    }

    private fun hasGoogleMapsApiKey(): Boolean {
        val applicationInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA
        )
        val apiKey = applicationInfo.metaData?.getString("com.google.android.geo.API_KEY")
        return !apiKey.isNullOrBlank() && !apiKey.startsWith("YOUR_")
    }
}
