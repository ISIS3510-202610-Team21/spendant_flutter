package com.example.spendant_flutter

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var pendingVoiceResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        NotificationReaderBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        SmsReaderBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        WearDataLayerBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/platform_config",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasGoogleMapsApiKey" -> result.success(hasGoogleMapsApiKey())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/voice_input",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSpeechRecognition" -> {
                    val pm = packageManager
                    val activities = pm.queryIntentActivities(
                        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH), 0,
                    )
                    if (activities.isEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    pendingVoiceResult = result
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, VOICE_REQUEST_CODE)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VOICE_REQUEST_CODE) {
            val text = if (resultCode == Activity.RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            } else {
                null
            }
            pendingVoiceResult?.success(text)
            pendingVoiceResult = null
        }
    }

    private fun hasGoogleMapsApiKey(): Boolean {
        val applicationInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA,
        )
        val apiKey = applicationInfo.metaData?.getString("com.google.android.geo.API_KEY")
        return !apiKey.isNullOrBlank() && !apiKey.startsWith("YOUR_")
    }

    companion object {
        private const val VOICE_REQUEST_CODE = 47382
    }
}
