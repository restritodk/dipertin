package com.dipertin.app

import android.content.Context

/**
 * Persiste o motivo da última falha de aceite (callable
 * `aceitarOfertaCorrida` retornou aceito=false ou erro de rede)
 * para que o [com.dipertin.app.MainActivity] consiga expor o motivo
 * ao Flutter (via MethodChannel) e o EntregadorDashboardScreen mostre
 * SnackBar pro entregador entender por que a oferta sumiu.
 *
 * Sem essa ponte, o `handleAccept` da fullscreen executa a callable
 * em background e abre o radar imediatamente — qualquer falha do
 * servidor é silenciosa (apenas Log.w no logcat).
 *
 * Contrato:
 *   - `gravar` é chamado quando o callback do aceite retorna falha.
 *   - `consumir` é chamado pelo Flutter (via MethodChannel) e LIMPA
 *     o estado, evitando que a mesma mensagem reapareça em toda
 *     reabertura da tela.
 */
object UltimaFalhaAceiteStore {
    private const val PREFS = "incoming_delivery_flow"
    private const val KEY_PEDIDO_ID = "ultima_falha_aceite_pedido_id"
    private const val KEY_MOTIVO = "ultima_falha_aceite_motivo"
    private const val KEY_MENSAGEM = "ultima_falha_aceite_mensagem"
    private const val KEY_TIMESTAMP_MS = "ultima_falha_aceite_ts_ms"

    /**
     * TTL curto: se a falha aconteceu há mais de 5 minutos, descartamos.
     * Evita mostrar SnackBar com motivo antigo se o app ficou parado por
     * muito tempo no background.
     */
    private const val TTL_MS = 5L * 60L * 1000L

    fun gravar(
        context: Context,
        pedidoId: String,
        motivo: String,
        mensagem: String,
    ) {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_PEDIDO_ID, pedidoId)
            .putString(KEY_MOTIVO, motivo)
            .putString(KEY_MENSAGEM, mensagem)
            .putLong(KEY_TIMESTAMP_MS, System.currentTimeMillis())
            .apply()
    }

    /**
     * Lê e LIMPA o estado. Retorna null se vazio ou expirado pelo TTL.
     * Map devolvido tem chaves: `pedidoId`, `motivo`, `mensagem`,
     * `timestampMs` (Long).
     */
    fun consumir(context: Context): Map<String, Any?>? {
        val prefs = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val pedidoId = prefs.getString(KEY_PEDIDO_ID, null)
        val motivo = prefs.getString(KEY_MOTIVO, null)
        val mensagem = prefs.getString(KEY_MENSAGEM, null)
        val ts = prefs.getLong(KEY_TIMESTAMP_MS, 0L)

        if (pedidoId.isNullOrBlank() || mensagem.isNullOrBlank() || ts <= 0L) {
            return null
        }

        prefs.edit()
            .remove(KEY_PEDIDO_ID)
            .remove(KEY_MOTIVO)
            .remove(KEY_MENSAGEM)
            .remove(KEY_TIMESTAMP_MS)
            .apply()

        if (System.currentTimeMillis() - ts > TTL_MS) {
            return null
        }

        return mapOf(
            "pedidoId" to pedidoId,
            "motivo" to (motivo ?: ""),
            "mensagem" to mensagem,
            "timestampMs" to ts,
        )
    }
}
