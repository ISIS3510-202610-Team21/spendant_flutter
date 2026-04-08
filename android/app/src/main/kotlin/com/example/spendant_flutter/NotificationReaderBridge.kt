package com.example.spendant_flutter

import android.app.Activity
import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

object NotificationReaderBridge {
    private const val METHOD_CHANNEL_NAME = "spendant_flutter/notification_reader"
    private const val EVENT_CHANNEL_NAME = "spendant_flutter/notification_reader/events"
    private const val PREFS_NAME = "spendant_notification_reader"
    private const val PENDING_EVENTS_KEY = "pending_events_v1"
    private const val MAX_PENDING_EVENTS = 40
    private const val MAX_TEXT_LENGTH = 900

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun register(
        messenger: BinaryMessenger,
        activity: Activity,
    ) {
        MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler { call, result ->
            handleMethodCall(activity, call, result)
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

    fun handlePostedNotification(
        context: Context,
        statusBarNotification: StatusBarNotification,
    ) {
        val payload = buildPayload(context, statusBarNotification) ?: return
        storePendingEvent(context, payload)
        if (eventSink == null) {
            BackgroundTaskScheduler.enqueueNotificationImport(context, payload)
        }
        emit(payload)
    }

    private fun handleMethodCall(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "isNotificationListenerEnabled" -> {
                result.success(isNotificationListenerEnabled(activity))
            }

            "openNotificationListenerSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error(
                        "open_settings_failed",
                        error.message,
                        null,
                    )
                }
            }

            "drainPendingEvents" -> {
                result.success(drainPendingEvents(activity))
            }

            else -> result.notImplemented()
        }
    }

    private fun buildPayload(
        context: Context,
        statusBarNotification: StatusBarNotification,
    ): Map<String, Any?>? {
        val notification = statusBarNotification.notification ?: return null
        val packageName = statusBarNotification.packageName ?: return null
        val appName = resolveApplicationName(context, packageName)

        if (!isSupportedExpenseCandidate(packageName, appName)) {
            return null
        }

        val extras = notification.extras
        val title = truncateText(
            extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        )
        val text = truncateText(
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        )
        val bigText = truncateText(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        )
        val subText = truncateText(
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim().orEmpty()
        )

        if (title.isBlank() && text.isBlank() && bigText.isBlank() && subText.isBlank()) {
            return null
        }

        return hashMapOf<String, Any?>(
            "eventId" to statusBarNotification.key,
            "packageName" to packageName,
            "appName" to appName,
            "title" to title,
            "text" to text,
            "bigText" to bigText,
            "subText" to subText,
            "postedAtMillis" to statusBarNotification.postTime,
        )
    }

    private fun resolveApplicationName(
        context: Context,
        packageName: String,
    ): String {
        return try {
            val packageManager = context.packageManager
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    private fun isSupportedExpenseCandidate(
        packageName: String,
        appName: String,
    ): Boolean {
        return isGooglePayCandidate(packageName, appName) ||
            isGmailCandidate(packageName, appName) ||
            isNequiCandidate(packageName, appName)
    }

    private fun isGooglePayCandidate(
        packageName: String,
        appName: String,
    ): Boolean {
        val normalizedPackage = packageName.lowercase()
        val normalizedAppName = appName.lowercase()
        val isGooglePackage =
            normalizedPackage.contains("google") &&
                (normalizedPackage.contains("wallet") || normalizedPackage.contains("paisa"))
        return isGooglePackage ||
            normalizedAppName.contains("google pay") ||
            normalizedAppName.contains("google wallet")
    }

    private fun isGmailCandidate(
        packageName: String,
        appName: String,
    ): Boolean {
        val normalizedSource = "$packageName $appName".lowercase()
        return normalizedSource.contains("gmail") ||
            normalizedSource.contains("com.google.android.gm")
    }

    private fun isNequiCandidate(
        packageName: String,
        appName: String,
    ): Boolean {
        val normalizedSource = "$packageName $appName".lowercase()
        return normalizedSource.contains("nequi")
    }

    private fun truncateText(value: String): String {
        if (value.length <= MAX_TEXT_LENGTH) {
            return value
        }

        return value.take(MAX_TEXT_LENGTH)
    }

    private fun isNotificationListenerEnabled(context: Context): Boolean {
        val enabledListeners = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val expectedComponent = ComponentName(context, SpendAntNotificationListenerService::class.java)

        return enabledListeners
            .split(':')
            .mapNotNull(ComponentName::unflattenFromString)
            .any { component ->
                component.packageName == expectedComponent.packageName &&
                    component.className == expectedComponent.className
            }
    }

    private fun emit(payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post {
            sink.success(payload)
        }
    }

    private fun storePendingEvent(
        context: Context,
        payload: Map<String, Any?>,
    ) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pendingArray = readPendingEventsArray(prefs.getString(PENDING_EVENTS_KEY, null))
            val eventId = payload["eventId"] as? String
            var replaced = false

            if (!eventId.isNullOrBlank()) {
                for (index in 0 until pendingArray.length()) {
                    val existing = pendingArray.optJSONObject(index) ?: continue
                    if (existing.optString("eventId") == eventId) {
                        pendingArray.put(index, JSONObject(payload))
                        replaced = true
                        break
                    }
                }
            }

            if (!replaced) {
                pendingArray.put(JSONObject(payload))
            }

            prefs.edit()
                .putString(PENDING_EVENTS_KEY, trimPendingEvents(pendingArray).toString())
                .apply()
        }
    }

    private fun drainPendingEvents(context: Context): List<Map<String, Any?>> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pendingArray = readPendingEventsArray(prefs.getString(PENDING_EVENTS_KEY, null))
            prefs.edit().remove(PENDING_EVENTS_KEY).apply()

            return buildList {
                for (index in 0 until pendingArray.length()) {
                    val item = pendingArray.optJSONObject(index) ?: continue
                    add(
                        hashMapOf<String, Any?>(
                            "eventId" to item.optString("eventId"),
                            "packageName" to item.optString("packageName"),
                            "appName" to item.optString("appName"),
                            "title" to item.optString("title"),
                            "text" to item.optString("text"),
                            "bigText" to item.optString("bigText"),
                            "subText" to item.optString("subText"),
                            "postedAtMillis" to item.optLong("postedAtMillis"),
                        )
                    )
                }
            }
        }
    }

    private fun readPendingEventsArray(rawValue: String?): JSONArray {
        if (rawValue.isNullOrBlank()) {
            return JSONArray()
        }

        return try {
            JSONArray(rawValue)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun trimPendingEvents(pendingArray: JSONArray): JSONArray {
        if (pendingArray.length() <= MAX_PENDING_EVENTS) {
            return pendingArray
        }

        val trimmedArray = JSONArray()
        val startIndex = pendingArray.length() - MAX_PENDING_EVENTS
        for (index in startIndex until pendingArray.length()) {
            trimmedArray.put(pendingArray.get(index))
        }
        return trimmedArray
    }
}
