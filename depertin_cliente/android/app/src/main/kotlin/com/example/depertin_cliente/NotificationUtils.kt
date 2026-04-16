package com.example.depertin_cliente

import android.content.Context
import androidx.core.app.NotificationManagerCompat

object NotificationUtils {
    fun notificationIdForOrder(orderId: String): Int {
        return IncomingDeliveryContract.NOTIFICATION_ID_BASE + orderId.hashCode()
    }

    fun cancelIncomingNotification(context: Context, orderId: String) {
        NotificationManagerCompat.from(context).cancel(notificationIdForOrder(orderId))
    }
}

