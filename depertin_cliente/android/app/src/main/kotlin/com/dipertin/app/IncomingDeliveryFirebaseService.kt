package com.dipertin.app

import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class IncomingDeliveryFirebaseService : FlutterFirebaseMessagingService() {
    private val tag = "IncomingDeliveryFlow"

    private fun openIncomingDeliveryScreen(data: Map<String, String>) {
        val appCtx = applicationContext
        val intent = Intent(appCtx, IncomingDeliveryActivity::class.java).apply {
            action = IncomingDeliveryContract.ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            for ((k, v) in data) {
                putExtra(k, v)
            }
            val orderId = data["orderId"] ?: data["order_id"] ?: data["pedido_id"] ?: ""
            val requestId = IncomingDeliveryContract.requestIdFromPayload(data)
            putExtra(IncomingDeliveryContract.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID, requestId)
        }
        startActivity(intent)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        try {
            val data = message.data
            val notificationPayload = message.notification
            Log.i(
                tag,
                "Push recebido id=${message.messageId} from=${message.from} " +
                    "dataKeys=${data.keys} hasNotificationPayload=${notificationPayload != null}",
            )
            if (data.isEmpty()) {
                Log.w(
                    tag,
                    "Push sem data payload. Em background o Android pode mostrar apenas notificação padrão sem abrir tela de corrida.",
                )
            }
            val type = data["type"]?.toString()
                ?: data["event"]?.toString()
                ?: data["tipoNotificacao"]?.toString()
                ?: ""
            val evento = data["evento"]?.toString().orEmpty()
            val orderId = data["orderId"]?.toString()
                ?: data["order_id"]?.toString()
                ?: data["pedido_id"]?.toString()
                ?: ""

            val isIncoming = type == "nova_corrida" ||
                type == "nova_entrega" ||
                type == "delivery_request" ||
                evento == "dispatch_request"
            val segmento = data["segmento"]?.toString().orEmpty()
            val isEntregadorSegment = segmento.isBlank() || segmento == "entregador"
            Log.i(
                tag,
                "Payload parseado: type=$type evento=$evento segmento=$segmento orderId=$orderId isIncoming=$isIncoming",
            )
            val canFullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val nm = getSystemService(NotificationManager::class.java)
                nm?.canUseFullScreenIntent() == true
            } else {
                true
            }
            Log.i(tag, "canUseFullScreenIntent=$canFullScreen sdk=${Build.VERSION.SDK_INT}")

            val corridaEntregador =
                isIncoming && isEntregadorSegment && orderId.isNotBlank()

            if (corridaEntregador) {
                val requestId = IncomingDeliveryContract.requestIdFromPayload(data)
                if (!IncomingDeliveryFlowState.shouldShowNotification(requestId)) {
                    Log.i(tag, "Corrida suprimida por estado requestId=$requestId")
                    return
                }
                // Sempre UI nativa (heads-up + fullScreenIntent + ecrã bloqueado).
                // Em foreground, abre diretamente a tela oficial de chamada para evitar
                // duplicidade visual com notificação interativa.
                // Em background/lockscreen, mantém notificação interativa como ponto de entrada.
                val appForeground = AppForegroundHelper.isForeground(this)
                Log.i(
                    tag,
                    "Corrida entregador requestId=$requestId foreground=$appForeground hostResumed=${MainActivity.isFlutterHostResumed}",
                )
                if (appForeground) {
                    NotificationUtils.cancelIncomingNotification(this, orderId)
                    openIncomingDeliveryScreen(data)
                } else {
                    CorridaIncomingNotifier.show(this, data, message.messageId)
                }
                Log.i(tag, "FCM corrida — fim (plugin Flutter não recebe este push).")
                return
            }

            if (!isIncoming || !isEntregadorSegment) {
                Log.d(tag, "Evento ignorado para fluxo de corrida")
            } else if (orderId.isBlank()) {
                Log.w(tag, "Evento de corrida ignorado por falta de orderId")
            }
        } catch (e: Exception) {
            Log.e(tag, "Erro no IncomingDeliveryFirebaseService", e)
        }
        // Mantém fallback do plugin Flutter para evitar perda de notificações
        // em cenários onde o caminho nativo seja restringido pelo SO/OEM.
        super.onMessageReceived(message)
    }
}

