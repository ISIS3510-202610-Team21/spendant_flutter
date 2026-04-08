package com.example.spendant_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationTimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent?,
    ) {
        val action = intent?.action ?: return
        BackgroundTaskScheduler.ensurePeriodicMaintenance(context)

        val reason =
            when (action) {
                Intent.ACTION_BOOT_COMPLETED -> "boot_completed"
                Intent.ACTION_MY_PACKAGE_REPLACED -> "package_replaced"
                Intent.ACTION_TIMEZONE_CHANGED -> "timezone_changed"
                Intent.ACTION_TIME_CHANGED -> "time_changed"
                Intent.ACTION_DATE_CHANGED -> "date_changed"
                else -> "system_change"
            }
        BackgroundTaskScheduler.enqueueMaintenance(context, reason)
    }
}
