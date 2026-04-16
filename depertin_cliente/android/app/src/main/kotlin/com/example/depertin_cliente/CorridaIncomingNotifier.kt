package com.example.depertin_cliente

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Notificação nativa com [NotificationCompat.setFullScreenIntent] para oferta de corrida
 * (app em background / encerrado). Alinhado ao canal [corrida_chamada] e som raw.
 */
object CorridaIncomingNotifier {
    private const val TAG = "IncomingDeliveryFlow"
    private var channelCreated = false
    private val recentlyShown = HashMap<String, Long>()

    /** Base estável por pedido — evita colisão de PendingIntent entre “Abrir” e “Aceitar”. */
    private fun stableRequestBase(orderId: String, messageId: String?): Int {
        val seed = "${orderId.trim()}:${messageId.orEmpty().trim()}"
        var h = seed.fold(0) { acc, ch -> 31 * acc + ch.code }
        if (h == Int.MIN_VALUE) h = 0
        return (IncomingDeliveryContract.NOTIFICATION_ID_BASE * 4096 + (h and 0x000FFFFF)) and 0x6FFFFFFF
    }

    fun show(context: Context, payload: Map<String, String>, messageId: String?) {
        val appCtx = context.applicationContext
        ensureChannel(appCtx)

        val title = payload["notif_title"]?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Nova corrida disponível"
        val text = payload["notif_body"]?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Toque para aceitar."
        val orderId = payload["orderId"] ?: payload["order_id"] ?: payload["pedido_id"] ?: ""
        if (orderId.isBlank()) {
            Log.w(TAG, "Notificação ignorada: orderId ausente no payload")
            return
        }
        val requestId = IncomingDeliveryContract.requestIdFromPayload(payload)
        if (!IncomingDeliveryFlowState.shouldShowNotification(requestId)) {
            Log.i(TAG, "Notificação suprimida: requestId já em tela/estado terminal ($requestId)")
            return
        }
        if (shouldSkipDuplicate(orderId, messageId)) {
            Log.d(TAG, "Notificação duplicada ignorada: orderId=$orderId messageId=$messageId")
            return
        }

        val chamadaIntent = Intent(appCtx, IncomingDeliveryActivity::class.java).apply {
            action = IncomingDeliveryContract.ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            for (e in payload.entries) {
                putExtra(e.key, e.value)
            }
            putExtra(IncomingDeliveryContract.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID, requestId)
            putExtra(IncomingDeliveryContract.EXTRA_EVENTO, payload["evento"].orEmpty())
            putExtra(IncomingDeliveryContract.EXTRA_TIPO, payload["tipoNotificacao"] ?: payload["type"].orEmpty())
        }

        val base = stableRequestBase(orderId, messageId)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val contentPending = PendingIntent.getActivity(
            appCtx,
            base + 11,
            chamadaIntent,
            piFlags,
        )
        val fullScreenIntent = Intent(chamadaIntent).apply {
            action = "${IncomingDeliveryContract.ACTION_OPEN}.FULLSCREEN"
        }
        val fullScreenPending = PendingIntent.getActivity(
            appCtx,
            base + 22,
            fullScreenIntent,
            piFlags,
        )

        val acceptIntent = Intent(appCtx, IncomingDeliveryActionReceiver::class.java).apply {
            action = IncomingDeliveryContract.ACTION_ACCEPT
            putExtra(IncomingDeliveryContract.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID, requestId)
        }
        val rejectIntent = Intent(appCtx, IncomingDeliveryActionReceiver::class.java).apply {
            action = IncomingDeliveryContract.ACTION_REJECT
            putExtra(IncomingDeliveryContract.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID, requestId)
        }
        val acceptPending = PendingIntent.getBroadcast(
            appCtx,
            base + 33,
            acceptIntent,
            piFlags,
        )
        val rejectPending = PendingIntent.getBroadcast(
            appCtx,
            base + 44,
            rejectIntent,
            piFlags,
        )
        val openPending = PendingIntent.getActivity(
            appCtx,
            base + 55,
            chamadaIntent,
            piFlags,
        )

        val soundUri = Uri.parse(
            "android.resource://${appCtx.packageName}/raw/chamada_entregador",
        )

        val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val canFullScreen = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                nm.canUseFullScreenIntent()
            } else {
                true
            }
        } catch (e: Exception) {
            Log.w(TAG, "Falha ao consultar canUseFullScreenIntent, fallback=true", e)
            true
        }
        val notificationsEnabled = NotificationManagerCompat.from(appCtx).areNotificationsEnabled()
        val postNotificationsGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.checkSelfPermission(appCtx, Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val appForeground = AppForegroundHelper.isForeground(appCtx)
        Log.i(
            TAG,
            "Emitindo chamada orderId=$orderId msgId=$messageId foreground=$appForeground " +
                "canFullScreen=$canFullScreen notifEnabled=$notificationsEnabled postNotifGranted=$postNotificationsGranted",
        )
        logOemDiagnostics()

        val builder = NotificationCompat.Builder(appCtx, IncomingDeliveryContract.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setTimeoutAfter(20_000L)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 400, 200, 400))
            .setLights(Color.parseColor("#6A1B9A"), 1000, 1000)
            .setContentIntent(contentPending)
            .addAction(0, "Aceitar", acceptPending)
            .addAction(0, "Abrir", openPending)
            .addAction(0, "Recusar", rejectPending)
        if (canFullScreen) {
            builder.setFullScreenIntent(fullScreenPending, true)
            Log.i(TAG, "fullScreenIntent configurado para orderId=$orderId")
        } else {
            builder.setFullScreenIntent(fullScreenPending, false)
            Log.w(TAG, "Sistema bloqueou fullScreenIntent (canUseFullScreenIntent=false), mantendo heads-up")
        }
        val notification = builder.build()
        tryWakeScreen(appCtx)
        nm.notify(NotificationUtils.notificationIdForOrder(orderId), notification)
        IncomingDeliveryFlowState.markNotificationShown(requestId)
        Log.i(TAG, "Notificação de corrida publicada orderId=$orderId canal=${IncomingDeliveryContract.CHANNEL_ID}")
    }

    private fun ensureChannel(context: Context) {
        if (channelCreated) {
            Log.d(TAG, "Canal já inicializado: ${IncomingDeliveryContract.CHANNEL_ID}")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = Uri.parse(
                "android.resource://${context.packageName}/raw/chamada_entregador",
            )
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val ch = NotificationChannel(
                IncomingDeliveryContract.CHANNEL_ID,
                IncomingDeliveryContract.CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = IncomingDeliveryContract.CHANNEL_DESC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
                setSound(soundUri, attrs)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(ch)
            Log.i(TAG, "Canal criado/atualizado: ${IncomingDeliveryContract.CHANNEL_ID}")
        }
        channelCreated = true
    }

    private fun shouldSkipDuplicate(orderId: String, messageId: String?): Boolean {
        val key = "$orderId:${messageId.orEmpty()}"
        val now = System.currentTimeMillis()
        synchronized(recentlyShown) {
            val last = recentlyShown[key]
            recentlyShown.entries.removeIf { now - it.value > 60_000L }
            if (last != null && now - last < 4_000L) {
                return true
            }
            recentlyShown[key] = now
        }
        return false
    }

    private fun tryWakeScreen(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            val wakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "${context.packageName}:incoming_delivery",
            )
            wakeLock.acquire(2500L)
            Log.d(TAG, "WakeLock curto adquirido para alerta de corrida")
        } catch (e: Exception) {
            Log.w(TAG, "Falha ao adquirir WakeLock (seguindo com notificação)", e)
        }
    }

    private fun logOemDiagnostics() {
        val manufacturer = Build.MANUFACTURER.lowercase()
        when {
            manufacturer.contains("xiaomi") -> {
                Log.w(TAG, "OEM Xiaomi/MIUI/HyperOS detectado: verificar autostart, lockscreen e bateria")
            }
            manufacturer.contains("oppo") || manufacturer.contains("oneplus") -> {
                Log.w(TAG, "OEM Oppo/OnePlus detectado: verificar auto-launch e execução em segundo plano")
            }
            manufacturer.contains("vivo") -> {
                Log.w(TAG, "OEM Vivo detectado: verificar permissões de inicialização e lockscreen")
            }
            manufacturer.contains("realme") -> {
                Log.w(TAG, "OEM Realme detectado: verificar proteção de bateria e notificações em tela bloqueada")
            }
        }
    }
}
