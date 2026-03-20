package com.example.spendant_flutter

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class SpendAntNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(statusBarNotification: StatusBarNotification) {
        NotificationReaderBridge.handlePostedNotification(this, statusBarNotification)
    }
}
