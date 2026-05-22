package com.example.spendant_flutter

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Android-side handler for the `spendant_flutter/speech` MethodChannel.
 *
 * Stage 1 (Audio Capture) + Stage 2 (STT Transcription) of the voice
 * ingestion pipeline both happen here — Android's SpeechRecognizer runs
 * its own background service so the Flutter UI thread is never blocked.
 *
 * Flutter calls:
 *   - startListening  → starts SpeechRecognizer; result returned async
 *   - stopListening   → forces early flush + result delivery
 */
class SpeechRecognizerBridge(private val activity: Activity) : RecognitionListener {

    companion object {
        private const val CHANNEL = "spendant_flutter/speech"

        fun register(messenger: BinaryMessenger, activity: Activity) {
            val bridge = SpeechRecognizerBridge(activity)
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> bridge.startListening(result)
                    "stopListening"  -> bridge.stopListening(result)
                    else             -> result.notImplemented()
                }
            }
        }
    }

    private var recognizer: SpeechRecognizer? = null
    private var pendingResult: MethodChannel.Result? = null

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    fun startListening(result: MethodChannel.Result) {
        // Destroy any stale recognizer from a previous session.
        recognizer?.destroy()

        pendingResult = result

        recognizer = SpeechRecognizer.createSpeechRecognizer(activity).also {
            it.setRecognitionListener(this)
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        // SpeechRecognizer.startListening must be called on the main thread —
        // Flutter's platform thread satisfies this requirement.
        recognizer?.startListening(intent)
    }

    fun stopListening(result: MethodChannel.Result) {
        recognizer?.stopListening()
        result.success(null)
    }

    // -------------------------------------------------------------------------
    // RecognitionListener
    // -------------------------------------------------------------------------

    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: ""
        pendingResult?.success(text.ifBlank { null })
        pendingResult = null
        releaseRecognizer()
    }

    override fun onError(error: Int) {
        val msg = when (error) {
            SpeechRecognizer.ERROR_AUDIO          -> "Audio recording error"
            SpeechRecognizer.ERROR_CLIENT         -> "Client error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Missing RECORD_AUDIO permission"
            SpeechRecognizer.ERROR_NETWORK        -> "Network error"
            SpeechRecognizer.ERROR_NO_MATCH       -> "No speech recognized"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
            SpeechRecognizer.ERROR_SERVER         -> "Server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected"
            else -> "Unknown error ($error)"
        }
        // NO_MATCH / SPEECH_TIMEOUT return success(null) — not an exception.
        if (error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
            pendingResult?.success(null)
        } else {
            pendingResult?.error("STT_ERROR", msg, null)
        }
        pendingResult = null
        releaseRecognizer()
    }

    // Unused callbacks — required by the interface.
    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onPartialResults(partialResults: Bundle?) {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    private fun releaseRecognizer() {
        recognizer?.destroy()
        recognizer = null
    }
}
