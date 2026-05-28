package com.example.spendant_flutter

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognizerIntent
import android.net.Uri
import android.view.InputDevice
import android.view.MotionEvent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    private var pendingVoiceResult: MethodChannel.Result? = null

    // Sink for streaming Wear OS rotary encoder deltas to Flutter.
    private var rotaryEventSink: EventChannel.EventSink? = null

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

        WearDataLayerBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        // Rotary encoder stream — Wear OS crown/bezel events forwarded to Flutter.
        // Flutter's PointerScrollEvent pipeline does NOT receive these on all
        // Wear OS devices because FlutterFragmentActivity.onGenericMotionEvent
        // is not automatically delegated.  We forward them explicitly here.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/rotary_input",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                rotaryEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                rotaryEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spendant_flutter/platform_config",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasGoogleMapsApiKey" -> result.success(hasGoogleMapsApiKey())
                "getDocumentsDir" -> {
                    try {
                        val dir = getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS)
                            ?: filesDir
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    } catch (e: Exception) {
                        result.error("DIR_FAILED", e.message, null)
                    }
                }
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

    // Forward Wear OS rotary encoder (crown / physical bezel) events to Flutter.
    // These arrive as GenericMotionEvent with SOURCE_ROTARY_ENCODER and
    // ACTION_SCROLL.  Negating AXIS_SCROLL converts the raw axis value to an
    // intuitive direction: positive delta = scroll down, negative = scroll up.
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
            val delta = -event.getAxisValue(MotionEvent.AXIS_SCROLL)
            rotaryEventSink?.success(delta.toDouble())
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    companion object {
        private const val VOICE_REQUEST_CODE = 47382
    }
}
