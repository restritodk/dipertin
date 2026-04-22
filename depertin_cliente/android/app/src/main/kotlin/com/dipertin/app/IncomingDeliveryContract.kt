package com.dipertin.app

object IncomingDeliveryContract {
    const val CHANNEL_ID = "corrida_chamada"
    const val CHANNEL_NAME = "Nova solicitação de entrega"
    const val CHANNEL_DESC = "Alertas de novas corridas e entregas"
    const val NOTIFICATION_ID_BASE = 7000

    const val EXTRA_ORDER_ID = "order_id"
    const val EXTRA_REQUEST_ID = "request_id"
    const val EXTRA_EXPIRES_AT = "despacho_expira_em_ms"
    const val EXTRA_EVENTO = "evento"
    const val EXTRA_TIPO = "tipoNotificacao"

    const val ACTION_ACCEPT = "com.dipertin.app.ACTION_ACCEPT_DELIVERY"
    const val ACTION_REJECT = "com.dipertin.app.ACTION_REJECT_DELIVERY"
    const val ACTION_OPEN = "com.dipertin.app.ACTION_OPEN_DELIVERY"

    fun requestId(orderId: String, offerSeq: String?): String {
        val oid = orderId.trim()
        if (oid.isEmpty()) return ""
        val seq = offerSeq?.trim().orEmpty()
        return if (seq.isNotEmpty()) "$oid:$seq" else oid
    }

    fun requestIdFromPayload(payload: Map<String, String>): String {
        val orderId = payload["request_order_id"]
            ?: payload["orderId"]
            ?: payload["order_id"]
            ?: payload["pedido_id"]
            ?: ""
        val explicitRequestId = payload[EXTRA_REQUEST_ID].orEmpty().trim()
        if (explicitRequestId.isNotEmpty()) return explicitRequestId
        val seq = payload["despacho_oferta_seq"]
        return requestId(orderId, seq)
    }
}

