package com.dipertin.app

import android.content.Context
import androidx.core.app.NotificationManagerCompat

object NotificationUtils {
    fun notificationIdForOrder(orderId: String): Int {
        return IncomingDeliveryContract.NOTIFICATION_ID_BASE + orderId.hashCode()
    }

    fun cancelIncomingNotification(context: Context, orderId: String) {
        val nm = NotificationManagerCompat.from(context)
        val notifId = notificationIdForOrder(orderId)
        nm.cancel(notifId)
        // Também cancela pela tag do payload híbrido — caso o SO tenha
        // desenhado a notif do sistema antes do serviço processar.
        val sysTag = "corrida_$orderId"
        nm.cancel(sysTag, notifId)
        nm.cancel(sysTag, 0)
    }
}

