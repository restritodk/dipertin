package com.dipertin.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Campanhas push do painel web: garante [largeIcon] com o launcher do app
 * (o FCM automático só usa o smallIcon monocromático [ic_stat_notify]).
 */
object CampanhaNotificationHelper {
    private const val CHANNEL_ID = "high_importance_channel"
    private const val CHANNEL_NAME = "Alertas DiPertin"
    private var channelCreated = false

    fun show(
        context: Context,
        title: String,
        body: String,
        campanhaId: String?,
    ) {
        val appCtx = context.applicationContext
        ensureChannel(appCtx)

        val launchIntent = Intent(appCtx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("tipoNotificacao", "campanha_marketing")
            if (!campanhaId.isNullOrBlank()) {
                putExtra("campanhaId", campanhaId)
            }
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            })
        val contentPending = PendingIntent.getActivity(
            appCtx,
            910_001,
            launchIntent,
            piFlags,
        )

        val largeIcon = BitmapFactory.decodeResource(
            appCtx.resources,
            R.mipmap.ic_launcher,
        )

        val notifId = campanhaId?.hashCode()?.and(0x7FFFFFFF) ?: 910_002

        val builder = NotificationCompat.Builder(appCtx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setLargeIcon(largeIcon)
            .setColor(appCtx.getColor(R.color.notification_color))
            .setContentTitle(title.ifBlank { "DiPertin" })
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(contentPending)

        NotificationManagerCompat.from(appCtx).notify(notifId, builder.build())
    }

    private fun ensureChannel(context: Context) {
        if (channelCreated) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            channelCreated = true
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Pedidos, entregas, campanhas e central de ajuda"
            enableVibration(true)
        }
        val nm = context.getSystemService(NotificationManager::class.java)
        nm?.createNotificationChannel(channel)
        channelCreated = true
    }
}
