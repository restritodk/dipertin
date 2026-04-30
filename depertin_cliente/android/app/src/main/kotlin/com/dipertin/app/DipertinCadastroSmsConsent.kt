package com.dipertin.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.MethodChannel
import java.util.regex.Pattern

/**
 * SMS User Consent API (Play Services): o utilizador autoriza a leitura de **uma**
 * mensagem recebida — sem permissão READ_SMS permanente. Compatível com SMS da
 * Comtele (sem hash do SMS Retriever).
 */
object DipertinCadastroSmsConsent {
    private var receiver: BroadcastReceiver? = null

    fun start(
        activity: FragmentActivity,
        replyChannel: MethodChannel,
        regex: String,
    ) {
        stop(activity)
        // Documentação Google: registrar o receiver antes de solicitar o consentimento.
        registerReceiver(activity, replyChannel, regex)
        SmsRetriever.getClient(activity).startSmsUserConsent(null).addOnFailureListener {
            unregister(activity)
        }
    }

    private fun registerReceiver(
        activity: FragmentActivity,
        replyChannel: MethodChannel,
        regex: String,
    ) {
        unregister(activity)
        val filter = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
        receiver =
            object : BroadcastReceiver() {
                override fun onReceive(
                    context: Context?,
                    intent: Intent?,
                ) {
                    unregister(activity)
                    if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                    val extras = intent.extras ?: return
                    @Suppress("DEPRECATION")
                    val status =
                        extras.getParcelable<Status>(SmsRetriever.EXTRA_STATUS)
                            ?: return
                    if (status.statusCode != CommonStatusCodes.SUCCESS) return
                    val message =
                        extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE)
                            ?: return
                    val code = extractCode(message, regex) ?: return
                    Handler(Looper.getMainLooper()).post {
                        try {
                            replyChannel.invokeMethod("onOtp", code)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        val r = receiver!!
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(
                    r,
                    filter,
                    Context.RECEIVER_EXPORTED,
                )
            } else {
                activity.registerReceiver(r, filter)
            }
        } catch (_: Exception) {
            receiver = null
        }
    }

    private fun extractCode(
        message: String,
        regex: String,
    ): String? =
        try {
            val p = Pattern.compile(regex)
            val m = p.matcher(message)
            var last: String? = null
            while (m.find()) {
                last = m.group()
            }
            last
        } catch (_: Exception) {
            null
        }

    fun stop(activity: FragmentActivity) {
        unregister(activity)
    }

    private fun unregister(activity: FragmentActivity) {
        val r = receiver ?: return
        receiver = null
        try {
            activity.unregisterReceiver(r)
        } catch (_: Exception) {
        }
    }
}
