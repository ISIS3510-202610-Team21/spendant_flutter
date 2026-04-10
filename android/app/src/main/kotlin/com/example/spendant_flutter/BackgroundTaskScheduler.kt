package com.example.spendant_flutter

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import dev.fluttercommunity.workmanager.SharedPreferenceHelper
import dev.fluttercommunity.workmanager.WM
import org.json.JSONObject

object BackgroundTaskScheduler {
    private const val MAINTENANCE_TASK = "notification_maintenance"
    private const val IMPORT_TASK = "notification_event_import"
    private const val MAINTENANCE_UNIQUE_NAME = "spendant.notification_maintenance"
    private const val IMMEDIATE_MAINTENANCE_UNIQUE_NAME = "spendant.notification_maintenance.immediate"
    private const val IMPORT_UNIQUE_NAME = "spendant.notification_event_import"
    private const val REASON_KEY = "reason"
    private const val PERIODIC_FREQUENCY_SECONDS = 15L * 60L
    private const val PERIODIC_FLEX_SECONDS = 5L * 60L
    private const val PERIODIC_INITIAL_DELAY_SECONDS = 5L * 60L

    private val defaultConstraints: Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
            .build()

    fun ensurePeriodicMaintenance(context: Context) {
        val appContext = context.applicationContext
        if (!SharedPreferenceHelper.hasCallbackHandle(appContext)) {
            return
        }

        WM.enqueuePeriodicTask(
            context = appContext,
            uniqueName = MAINTENANCE_UNIQUE_NAME,
            dartTask = MAINTENANCE_TASK,
            payload = JSONObject(mapOf(REASON_KEY to "periodic_maintenance")).toString(),
            existingWorkPolicy = ExistingPeriodicWorkPolicy.UPDATE,
            frequencyInSeconds = PERIODIC_FREQUENCY_SECONDS,
            flexIntervalInSeconds = PERIODIC_FLEX_SECONDS,
            initialDelaySeconds = PERIODIC_INITIAL_DELAY_SECONDS,
            constraintsConfig = defaultConstraints,
            backoffPolicyConfig = null,
        )
    }

    fun enqueueNotificationImport(
        context: Context,
        payload: Map<String, Any?>,
    ) {
        val appContext = context.applicationContext
        if (!SharedPreferenceHelper.hasCallbackHandle(appContext)) {
            return
        }

        val fullPayload = LinkedHashMap<String, Any?>(payload)
        fullPayload[REASON_KEY] = "notification_posted"

        WM.enqueueOneOffTask(
            context = appContext,
            uniqueName = IMPORT_UNIQUE_NAME,
            dartTask = IMPORT_TASK,
            payload = JSONObject(fullPayload as Map<*, *>).toString(),
            existingWorkPolicy = ExistingWorkPolicy.APPEND,
            constraintsConfig = defaultConstraints,
            backoffPolicyConfig = null,
        )
    }

    fun enqueueMaintenance(
        context: Context,
        reason: String,
    ) {
        val appContext = context.applicationContext
        if (!SharedPreferenceHelper.hasCallbackHandle(appContext)) {
            return
        }

        WM.enqueueOneOffTask(
            context = appContext,
            uniqueName = IMMEDIATE_MAINTENANCE_UNIQUE_NAME,
            dartTask = MAINTENANCE_TASK,
            payload = JSONObject(mapOf(REASON_KEY to reason)).toString(),
            existingWorkPolicy = ExistingWorkPolicy.REPLACE,
            constraintsConfig = defaultConstraints,
            backoffPolicyConfig = null,
        )
    }
}
