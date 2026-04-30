package com.dipertin.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.MethodChannel
import java.util.regex.Pattern

/**
 * SMS User Consent API (Play Services): o sistema mostra um diálogo para autorizar
 * **uma** mensagem. O fluxo correto é receber [SmsRetriever.EXTRA_CONSENT_INTENT] no
 * broadcast e abrir com [ActivityResultLauncher]; o texto do SMS vem no `data` de
 * `onActivityResult` — **não** em [SmsRetriever.EXTRA_SMS_MESSAGE] só no receiver.
 */
object DipertinCadastroSmsConsent {
    private var receiver: BroadcastReceiver? = null
    private var replyChannel: MethodChannel? = null
    private var regex: String = "\\d{6}"

    fun onConsentActivityResult(
        resultCode: Int,
        data: Intent?,
    ) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            return
        }
        val message =
            data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
                ?: return
        deliverCode(message)
    }

    fun start(
        activity: FragmentActivity,
        consentLauncher: ActivityResultLauncher<Intent>,
        channel: MethodChannel,
        pattern: String,
    ) {
        stop(activity)
        replyChannel = channel
        regex = pattern.ifBlank { "\\d{6}" }
        registerReceiver(activity, consentLauncher)
        SmsRetriever.getClient(activity).startSmsUserConsent(null).addOnFailureListener {
            unregister(activity)
        }
    }

    private fun registerReceiver(
        activity: FragmentActivity,
        consentLauncher: ActivityResultLauncher<Intent>,
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

                    val consentIntent =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            extras.getParcelable(
                                SmsRetriever.EXTRA_CONSENT_INTENT,
                                Intent::class.java,
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT)
                        }

                    val directMessage = extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE)

                    when {
                        consentIntent != null -> {
                            try {
                                consentLauncher.launch(consentIntent)
                            } catch (_: Exception) {
                                /* utilizador pode digitar manualmente */
                            }
                        }
                        directMessage != null -> {
                            deliverCode(directMessage)
                        }
                        else -> {}
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

    private fun deliverCode(message: String) {
        val code = extractCode(message, regex) ?: return
        val ch = replyChannel ?: return
        Handler(Looper.getMainLooper()).post {
            try {
                ch.invokeMethod("onOtp", code)
            } catch (_: Exception) {
            }
        }
    }

    private fun extractCode(
        message: String,
        regex: String,
    ): String? {
        try {
            val p = Pattern.compile(regex)
            val m = p.matcher(message)
            var last: String? = null
            while (m.find()) {
                last = m.group()
            }
            if (last != null && last.length == 6) return last
        } catch (_: Exception) {
        }
        val digits = message.replace("[^0-9]".toRegex(), "")
        return if (digits.length >= 6) digits.substring(digits.length - 6) else null
    }

    fun stop(activity: FragmentActivity) {
        unregister(activity)
        replyChannel = null
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
