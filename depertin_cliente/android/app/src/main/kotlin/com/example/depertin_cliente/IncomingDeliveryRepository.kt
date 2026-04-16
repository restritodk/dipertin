package com.example.depertin_cliente

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

    fun aceitar(orderId: String, onDone: (Boolean, String?) -> Unit) {
        val uid = auth.currentUser?.uid
        if (uid.isNullOrBlank() || orderId.isBlank()) {
            onDone(false, "Sessão inválida.")
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
                    onDone(true, null)
                    return@addOnSuccessListener
                }
                if (aceito == false) {
                    val motivo = map?.get("motivo")?.toString().orEmpty()
                    onDone(false, mensagemMotivoAceite(motivo))
                    return@addOnSuccessListener
                }
                onDone(false, "Resposta inválida do servidor ao aceitar.")
            }
            .addOnFailureListener { e ->
                onDone(false, mensagemErroCallable(e))
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
}

