package com.example.depertin_cliente

import java.util.concurrent.ConcurrentHashMap

/**
 * Estado efêmero por requestId para evitar fluxos visuais duplicados.
 * Fonte de verdade de negócio continua no backend/Firestore.
 */
object IncomingDeliveryFlowState {
    data class State(
        var notificationShown: Boolean = false,
        var screenOpened: Boolean = false,
        var accepted: Boolean = false,
        var rejected: Boolean = false,
        var expired: Boolean = false,
        var cancelled: Boolean = false,
        var touchedAtMs: Long = System.currentTimeMillis(),
    ) {
        fun terminal(): Boolean = accepted || rejected || expired || cancelled
    }

    private const val MAX_IDLE_MS = 10 * 60 * 1000L
    private val byRequestId = ConcurrentHashMap<String, State>()

    private fun normalize(requestId: String): String = requestId.trim()

    private fun cleanup(now: Long = System.currentTimeMillis()) {
        byRequestId.entries.removeIf { now - it.value.touchedAtMs > MAX_IDLE_MS }
    }

    fun shouldShowNotification(requestId: String): Boolean {
        val id = normalize(requestId)
        if (id.isEmpty()) return true
        val now = System.currentTimeMillis()
        cleanup(now)
        val state = byRequestId[id]
        if (state == null) return true
        state.touchedAtMs = now
        return !state.screenOpened && !state.terminal()
    }

    fun markNotificationShown(requestId: String) {
        val id = normalize(requestId)
        if (id.isEmpty()) return
        val now = System.currentTimeMillis()
        cleanup(now)
        val state = byRequestId.getOrPut(id) { State() }
        state.notificationShown = true
        state.touchedAtMs = now
    }

    fun markScreenOpened(requestId: String) {
        val id = normalize(requestId)
        if (id.isEmpty()) return
        val now = System.currentTimeMillis()
        cleanup(now)
        val state = byRequestId.getOrPut(id) { State() }
        state.screenOpened = true
        state.touchedAtMs = now
    }

    fun markAccepted(requestId: String) = markTerminal(requestId) { it.accepted = true }

    fun markRejected(requestId: String) = markTerminal(requestId) { it.rejected = true }

    fun markExpired(requestId: String) = markTerminal(requestId) { it.expired = true }

    fun markCancelled(requestId: String) = markTerminal(requestId) { it.cancelled = true }

    private fun markTerminal(requestId: String, update: (State) -> Unit) {
        val id = normalize(requestId)
        if (id.isEmpty()) return
        val now = System.currentTimeMillis()
        cleanup(now)
        val state = byRequestId.getOrPut(id) { State() }
        update(state)
        state.touchedAtMs = now
    }
}

