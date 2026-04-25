package com.example.spendant_flutter

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object SmsReaderBridge {
    private const val METHOD_CHANNEL_NAME = "spendant_flutter/sms_reader"
    private const val EVENT_CHANNEL_NAME = "spendant_flutter/sms_reader/events"
    private const val MAX_TEXT_LENGTH = 900
    private const val LOOKBACK_MILLIS = 48L * 60 * 60 * 1000 // 48 hours

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "drainRecentSms" -> result.success(drainRecentSms(activity))
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    fun handleIncomingSms(sender: String, body: String, timestampMillis: Long) {
        val truncatedBody = truncateText(body)
        if (truncatedBody.isBlank()) return
        if (!looksLikeExpenseSms(truncatedBody)) return

        val payload = hashMapOf<String, Any?>(
            "eventId" to "sms-$sender-$timestampMillis",
            "packageName" to "sms",
            "appName" to "SMS",
            "title" to sender.trim().ifBlank { "SMS" },
            "text" to truncatedBody,
            "bigText" to truncatedBody,
            "subText" to "",
            "postedAtMillis" to timestampMillis,
        )
        emit(payload)
    }

    private fun drainRecentSms(context: Context): List<Map<String, Any?>> {
        val sinceMillis = System.currentTimeMillis() - LOOKBACK_MILLIS
        val results = mutableListOf<Map<String, Any?>>()
        try {
            val cursor = context.contentResolver.query(
                Uri.parse("content://sms/inbox"),
                arrayOf("_id", "address", "body", "date"),
                "date > ?",
                arrayOf(sinceMillis.toString()),
                "date DESC",
            ) ?: return results

            cursor.use {
                val idCol = it.getColumnIndexOrThrow("_id")
                val addressCol = it.getColumnIndexOrThrow("address")
                val bodyCol = it.getColumnIndexOrThrow("body")
                val dateCol = it.getColumnIndexOrThrow("date")

                while (it.moveToNext()) {
                    val rawBody = it.getString(bodyCol) ?: continue
                    val body = truncateText(rawBody)
                    if (!looksLikeExpenseSms(body)) continue

                    results.add(
                        hashMapOf(
                            "eventId" to "sms-${it.getLong(idCol)}",
                            "packageName" to "sms",
                            "appName" to "SMS",
                            "title" to (it.getString(addressCol)?.trim() ?: "SMS"),
                            "text" to body,
                            "bigText" to body,
                            "subText" to "",
                            "postedAtMillis" to it.getLong(dateCol),
                        )
                    )
                }
            }
        } catch (_: Exception) {
            // READ_SMS permission not granted or ContentProvider unavailable.
        }
        return results
    }

    private fun looksLikeExpenseSms(body: String): Boolean {
        val lower = body.lowercase()
        val ignoreSignals = listOf(
            "otp", "codigo de verificacion", "clave dinamica", "password", "contrasena",
        )
        if (ignoreSignals.any(lower::contains)) return false
        val expenseSignals = listOf(
            "pagaste", "compra", "pago aprobado", "transaccion aprobada",
            "te cobraron", "debito", "cobro aprobado", "retiro aprobado",
        )
        return expenseSignals.any(lower::contains)
    }

    private fun truncateText(value: String): String =
        if (value.length <= MAX_TEXT_LENGTH) value else value.take(MAX_TEXT_LENGTH)

    private fun emit(payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(payload) }
    }
}
