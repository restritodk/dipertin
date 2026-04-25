package com.dipertin.app

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.functions.FirebaseFunctionsException

object IncomingDeliveryRepository {
    private val auth by lazy { FirebaseAuth.getInstance() }
    private val functions by lazy { FirebaseFunctions.getInstance("us-central1") }

    /** Nunca assumir `true` por omissão — evita “aceite fantasma” se o SDK serializar diferente. */
    private fun coagirBoolean(v: Any?): Boolean? {
        return when (v) {
            is Boolean -> v
            is java.lang.Boolean -> v.booleanValue()
            is Number -> v.toInt() != 0
            is String -> when (v.trim().lowercase()) {
                "true", "1", "yes" -> true
                "false", "0", "no" -> false
                else -> null
            }
            else -> null
        }
    }

    /**
     * Resultado estruturado do aceite. `mensagem` é humanizada, pronta
     * pra exibir; `motivo` é o código bruto retornado pelo backend
     * (ex.: `corrida_ja_aceita`) — útil pra disparar UX específica
     * (ex.: levar o usuário pra "Meus veículos" no caso de
     * `veiculo_nao_configurado`).
     */
    data class AceiteResultado(
        val ok: Boolean,
        val mensagem: String?,
        val motivo: String,
    )

    fun aceitar(orderId: String, onDone: (AceiteResultado) -> Unit) {
        val uid = auth.currentUser?.uid
        if (uid.isNullOrBlank() || orderId.isBlank()) {
            onDone(AceiteResultado(false, "Sessão inválida.", "sessao_invalida"))
            return
        }
        val payload = hashMapOf("pedidoId" to orderId)
        functions
            .getHttpsCallable("aceitarOfertaCorrida")
            .call(payload)
            .addOnSuccessListener { result ->
                val map = result.data as? Map<*, *>
                val aceito = coagirBoolean(map?.get("aceito"))
                if (aceito == true) {
                    onDone(AceiteResultado(true, null, ""))
                    return@addOnSuccessListener
                }
                if (aceito == false) {
                    val motivo = map?.get("motivo")?.toString().orEmpty()
                    onDone(AceiteResultado(false, mensagemMotivoAceite(motivo), motivo))
                    return@addOnSuccessListener
                }
                onDone(
                    AceiteResultado(
                        false,
                        "Resposta inválida do servidor ao aceitar.",
                        "resposta_invalida",
                    ),
                )
            }
            .addOnFailureListener { e ->
                onDone(
                    AceiteResultado(
                        false,
                        mensagemErroCallable(e),
                        codigoErroCallable(e),
                    ),
                )
            }
    }

    fun recusar(orderId: String, onDone: (Boolean, String?) -> Unit) {
        val uid = auth.currentUser?.uid
        if (uid.isNullOrBlank() || orderId.isBlank()) {
            onDone(false, "Sessão inválida.")
            return
        }
        val payload = hashMapOf("pedidoId" to orderId)
        functions
            .getHttpsCallable("recusarOfertaCorrida")
            .call(payload)
            .addOnSuccessListener { result ->
                val map = result.data as? Map<*, *>
                val recusado = coagirBoolean(map?.get("recusado"))
                if (recusado == true) {
                    onDone(true, null)
                    return@addOnSuccessListener
                }
                if (recusado == false) {
                    val motivo = map?.get("motivo")?.toString().orEmpty()
                    onDone(false, mensagemMotivoRecusa(motivo))
                    return@addOnSuccessListener
                }
                onDone(false, "Resposta inválida do servidor ao recusar.")
            }
            .addOnFailureListener { e ->
                onDone(false, mensagemErroCallable(e))
            }
    }

    private fun mensagemMotivoAceite(motivo: String): String {
        return when (motivo) {
            "corrida_ja_aceita" -> "Corrida já foi aceita por outro entregador."
            "oferta_nao_pertence_ao_entregador" -> "Oferta não pertence ao seu perfil."
            "oferta_expirada_ou_invalida" -> "Oferta expirou. Aguarde uma nova corrida."
            "pedido_indisponivel" -> "Pedido não está mais disponível."
            "veiculo_incompativel_loja" ->
                "Esta loja não aceita seu tipo de veículo. A corrida foi " +
                    "redirecionada para outro entregador compatível."
            "veiculo_nao_configurado" ->
                "Seu veículo ativo não está cadastrado. Abra Meus veículos e " +
                    "defina o veículo em uso."
            "bloqueado_por_estado_operacional" ->
                "Você não pode aceitar enquanto outra corrida está em andamento."
            "limite_corridas_simultaneas" ->
                "Limite de corridas simultâneas atingido. Conclua uma antes de aceitar outra."
            else -> "Não foi possível aceitar esta corrida."
        }
    }

    private fun mensagemMotivoRecusa(motivo: String): String {
        return when (motivo) {
            "oferta_nao_pertence_ao_entregador" -> "Oferta não pertence ao seu perfil."
            "pedido_nao_aguardando_entregador" -> "Pedido não está mais aguardando entregador."
            else -> "Não foi possível recusar esta corrida."
        }
    }

    private fun mensagemErroCallable(error: Exception): String {
        val fError = error as? FirebaseFunctionsException
        return when (fError?.code) {
            FirebaseFunctionsException.Code.UNAUTHENTICATED -> "Sessão expirada. Faça login novamente."
            FirebaseFunctionsException.Code.PERMISSION_DENIED -> "Permissão negada para esta ação."
            FirebaseFunctionsException.Code.NOT_FOUND -> "Pedido não encontrado."
            FirebaseFunctionsException.Code.DEADLINE_EXCEEDED -> "Tempo esgotado. Tente novamente."
            else -> error.message ?: "Erro ao processar solicitação."
        }
    }

    private fun codigoErroCallable(error: Exception): String {
        val fError = error as? FirebaseFunctionsException
        return when (fError?.code) {
            FirebaseFunctionsException.Code.UNAUTHENTICATED -> "callable_unauthenticated"
            FirebaseFunctionsException.Code.PERMISSION_DENIED -> "callable_permission_denied"
            FirebaseFunctionsException.Code.NOT_FOUND -> "callable_not_found"
            FirebaseFunctionsException.Code.DEADLINE_EXCEEDED -> "callable_deadline_exceeded"
            FirebaseFunctionsException.Code.UNAVAILABLE -> "callable_unavailable"
            FirebaseFunctionsException.Code.INTERNAL -> "callable_internal"
            null -> "callable_unknown"
            else -> "callable_${fError.code.name.lowercase()}"
        }
    }
}

