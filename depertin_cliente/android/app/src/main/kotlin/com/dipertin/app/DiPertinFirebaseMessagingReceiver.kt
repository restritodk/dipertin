package com.dipertin.app

import android.content.Context
import android.content.Intent
import io.flutter.plugins.firebase.messaging.ContextHolder
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

/**
 * Intercepta ofertas de corrida em **data-only** quando o app não está em primeiro plano:
 * exibe notificação nativa com FullScreenIntent (sem depender do isolate Dart em background).
 *
 * Demais mensagens seguem o fluxo original do plugin Flutter.
 */
class DiPertinFirebaseMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (ContextHolder.getApplicationContext() == null) {
            val appCtx = context.applicationContext ?: context
            ContextHolder.setApplicationContext(appCtx)
        }
        super.onReceive(context, intent)
    }
}
