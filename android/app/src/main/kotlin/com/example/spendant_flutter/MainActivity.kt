package com.example.spendant_flutter

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        NotificationReaderBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        SpeechRecognizerBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        SmsReaderBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/platform_config"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasGoogleMapsApiKey" -> result.success(hasGoogleMapsApiKey())
                "openFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri: Uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                            FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                        } else {
                            Uri.fromFile(file)
                        }
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/pdf")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(Intent.createChooser(intent, "Open PDF with"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }
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
