package com.dipertin.app

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context

/**
 * Espelha a lógica de [io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingUtils]
 * (package-private) para decidir se o app está em primeiro plano.
 */
object AppForegroundHelper {
    fun isForeground(context: Context): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km != null && km.isKeyguardLocked) {
            return false
        }
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        val processes = am.runningAppProcesses ?: return false
        val pkg = context.packageName
        for (p in processes) {
            if (p.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                p.processName == pkg
            ) {
                return true
            }
        }
        return false
    }
}
