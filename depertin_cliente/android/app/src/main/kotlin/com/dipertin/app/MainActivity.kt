package com.dipertin.app

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// NOTA (abr/2026): herdamos de FlutterFragmentActivity (e não FlutterActivity)
// porque o plugin `local_auth_android` usa `BiometricPrompt`, que é um Fragment
// e requer um host FragmentActivity. FlutterFragmentActivity é compatível com
// todos os plugins FCM/receivers/MethodChannels já integrados neste projeto.
class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_ABRIR_ENTREGADOR = "dipertin_open_entregador"
        const val EXTRA_ORDER_ID = "dipertin_order_id"
        private const val NAV_CHANNEL = "dipertin.android/nav"

        @JvmStatic
        var pendingAbrirEntregador: Boolean = false

        @JvmStatic
        var pendingOrderId: String? = null

        /**
         * True só enquanto o [MainActivity] (Flutter) está em `onResume`.
         * Usado pelo FCM nativo para não pular a chamada quando só o
         * [FloatingIconService] mantém o processo em "foreground".
         */
        @JvmStatic
        @Volatile
        var isFlutterHostResumed: Boolean = false

        /**
         * Mapa `pedidoId → OfertaLocal` para ofertas que o entregador já
         * decidiu (ACEITOU ou RECUSOU) localmente mas o backend ainda pode
         * não ter processado.
         *
         * Usado pelo Flutter (via MethodChannel `getOfertasProcessadasLocais`)
         * para evitar que o `_ofertaFullscreenSub` reabra a tela de chamada
         * durante a janela entre o tap do entregador e o backend gravar
         * `entregador_id` no Firestore.
         *
         * Por que guardar `seq`: o backend pode re-despachar o mesmo
         * pedidoId pra mim depois de uma recusa (lojista clicou
         * "Solicitar Entregador" de novo). Nesse cenário o
         * `despacho_oferta_seq` aumenta. O Flutter compara o seq atual
         * vindo do Firestore com o `seq` armazenado aqui — se for maior,
         * é uma NOVA oferta e o bloqueio local é ignorado/liberado.
         *
         * Vive na `companion object` (estática) — sobrevive à recriação
         * do widget Flutter quando MainActivity é trazido ao topo após
         * `IncomingDeliveryActivity.openMainRadar`.
         *
         * Limpeza: TTL de 60s + remoção explícita via
         * `confirmarOfertaProcessadaPorBackend` quando o Flutter confirma
         * que o backend setou `entregador_id` (status pós-aceite).
         */
        data class OfertaLocal(val seq: Long, val timestampMs: Long)

        @JvmStatic
        val ofertasProcessadasLocais: java.util.concurrent.ConcurrentHashMap<String, OfertaLocal> =
            java.util.concurrent.ConcurrentHashMap<String, OfertaLocal>()

        private const val OFERTA_LOCAL_TTL_MS = 60_000L

        @JvmStatic
        fun marcarOfertaProcessadaLocal(orderId: String, seq: Long) {
            val id = orderId.trim()
            if (id.isEmpty()) return
            limparOfertasLocaisExpiradas()
            ofertasProcessadasLocais[id] = OfertaLocal(seq, System.currentTimeMillis())
        }

        @JvmStatic
        fun limparOfertaProcessadaLocal(orderId: String) {
            val id = orderId.trim()
            if (id.isEmpty()) return
            ofertasProcessadasLocais.remove(id)
        }

        private fun limparOfertasLocaisExpiradas() {
            val agora = System.currentTimeMillis()
            ofertasProcessadasLocais.entries.removeAll {
                agora - it.value.timestampMs > OFERTA_LOCAL_TTL_MS
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isFlutterHostResumed = true
    }

    override fun onPause() {
        isFlutterHostResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        isFlutterHostResumed = false
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        captureLaunchIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureLaunchIntent(intent)
    }

    private fun captureLaunchIntent(i: Intent?) {
        if (i == null) return
        if (i.getBooleanExtra(EXTRA_ABRIR_ENTREGADOR, false)) {
            pendingAbrirEntregador = true
            pendingOrderId = i.getStringExtra(EXTRA_ORDER_ID)
        }
    }

    private fun openIncomingDeliveryScreenFromMap(raw: Map<*, *>?): Boolean {
        if (raw == null) return false
        val payload = mutableMapOf<String, String>()
        for ((k, v) in raw.entries) {
            val key = k?.toString()?.trim().orEmpty()
            if (key.isEmpty()) continue
            payload[key] = v?.toString().orEmpty()
        }
        val orderId = payload[IncomingDeliveryContract.EXTRA_ORDER_ID]
            ?: payload["orderId"]
            ?: payload["order_id"]
            ?: payload["pedido_id"]
            ?: ""
        if (orderId.isBlank()) return false
        val requestId = payload[IncomingDeliveryContract.EXTRA_REQUEST_ID]
            ?.trim()
            .orEmpty()
            .ifBlank { IncomingDeliveryContract.requestIdFromPayload(payload) }
        val intent = Intent(this, IncomingDeliveryActivity::class.java).apply {
            action = IncomingDeliveryContract.ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            for ((k, v) in payload) {
                putExtra(k, v)
            }
            putExtra(IncomingDeliveryContract.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID, requestId)
        }
        startActivity(intent)
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NAV_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingNav" -> {
                    val abrir = pendingAbrirEntregador
                    val oid = pendingOrderId
                    pendingAbrirEntregador = false
                    pendingOrderId = null
                    result.success(
                        mapOf(
                            "openEntregador" to abrir,
                            "orderId" to (oid ?: ""),
                        ),
                    )
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(NotificationManager::class.java)
                        result.success(nm?.canUseFullScreenIntent() == true)
                    } else {
                        result.success(true)
                    }
                }
                "openFullScreenIntentSettings" -> {
                    val opened = try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val i = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(i)
                            true
                        } else {
                            false
                        }
                    } catch (_: ActivityNotFoundException) {
                        false
                    } catch (_: Exception) {
                        false
                    }
                    result.success(opened)
                }

                // ── Bateria ────────────────────────────────────────
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as? PowerManager
                    result.success(pm?.isIgnoringBatteryOptimizations(packageName) == true)
                }
                "openBatteryOptimizationSettings" -> {
                    result.success(OemPermissions.openBatterySettings(this))
                }

                // ── Overlay ────────────────────────────────────────
                "canDrawOverlays" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "openOverlayPermissionSettings" -> {
                    result.success(OemPermissions.openOverlaySettings(this))
                }

                // ── Autostart ──────────────────────────────────────
                "openAutostartSettings" -> {
                    result.success(OemPermissions.openAutostartSettings(this))
                }

                // ── Bateria OEM (tela proprietária) ────────────────
                "openOemBatterySettings" -> {
                    result.success(OemPermissions.openOemBatteryManager(this))
                }

                // ── Ícone flutuante ─────────────────────────────────
                "startFloatingIcon" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        result.success(false)
                    } else {
                        FloatingIconService.start(this)
                        result.success(true)
                    }
                }
                "stopFloatingIcon" -> {
                    FloatingIconService.stop(this)
                    result.success(true)
                }
                "isFloatingIconRunning" -> {
                    result.success(FloatingIconService.isRunning)
                }

                // ── Notificações ───────────────────────────────────
                "areNotificationsEnabled" -> {
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                }
                "openNotificationSettings" -> {
                    result.success(OemPermissions.openNotificationSettings(this))
                }
                "cancelIncomingCorridaNotification" -> {
                    val orderId = call.arguments as? String
                    if (!orderId.isNullOrBlank()) {
                        NotificationUtils.cancelIncomingNotification(this, orderId)
                    }
                    result.success(null)
                }
                "openIncomingDeliveryScreen" -> {
                    val opened = openIncomingDeliveryScreenFromMap(call.arguments as? Map<*, *>)
                    result.success(opened)
                }

                // ── Despacho sequencial: ofertas processadas localmente ───
                // Permite ao Flutter consultar e limpar o estado nativo de
                // ofertas que o entregador já decidiu (aceite/recusa) na
                // fullscreen. Evita o loop em que o listener Firestore do
                // dashboard reabre a IncomingDeliveryActivity logo após o
                // entregador clicar Aceitar — a janela entre o tap e o
                // backend gravar `entregador_id` é exatamente quando o bug
                // se manifesta.
                "getOfertasProcessadasLocais" -> {
                    limparOfertasLocaisExpiradas()
                    // Retorna Map<orderId:String, seq:Long> pra que o
                    // Flutter compare contra o seq vindo do Firestore e
                    // libere o lock automaticamente em caso de re-dispatch.
                    val payload = HashMap<String, Long>()
                    for ((id, oferta) in ofertasProcessadasLocais) {
                        payload[id] = oferta.seq
                    }
                    result.success(payload)
                }
                "confirmarOfertaProcessadaPorBackend" -> {
                    val orderId = call.arguments as? String
                    if (!orderId.isNullOrBlank()) {
                        limparOfertaProcessadaLocal(orderId)
                    }
                    result.success(true)
                }

                // Lê e LIMPA o motivo da última falha de aceite registrada
                // pelo IncomingDeliveryActivity / IncomingDeliveryActionReceiver.
                // O dashboard chama isso no initState e a cada `resumed`
                // pra mostrar SnackBar — assim o entregador entende por que
                // a oferta sumiu (ex.: corrida já aceita por outro
                // entregador, ou rede falhou).
                "consumirUltimaFalhaAceite" -> {
                    val payload = UltimaFalhaAceiteStore.consumir(applicationContext)
                    result.success(payload)
                }

                // ── Info do dispositivo ────────────────────────────
                "getDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                            "sdk" to Build.VERSION.SDK_INT,
                        ),
                    )
                }

                // ── Vibração em padrão ─────────────────────────────
                "vibratePattern" -> {
                    val args = call.arguments as? Map<*, *>
                    val durations = (args?.get("durations") as? List<*>)
                        ?.mapNotNull { (it as? Number)?.toLong() }
                        ?: listOf(0L, 700L, 400L, 700L, 400L, 700L, 400L, 700L)
                    val repeat = (args?.get("repeat") as? Number)?.toInt() ?: -1
                    result.success(VibrationHelper.vibratePattern(this, durations, repeat))
                }
                "cancelVibrate" -> {
                    VibrationHelper.cancel(this)
                    result.success(true)
                }

                // ── Flash da câmera (LED) ──────────────────────────
                "torchBlink" -> {
                    val args = call.arguments as? Map<*, *>
                    val onMs = (args?.get("onMs") as? Number)?.toLong() ?: 250L
                    val offMs = (args?.get("offMs") as? Number)?.toLong() ?: 250L
                    val times = (args?.get("times") as? Number)?.toInt() ?: 8
                    result.success(TorchHelper.blink(this, onMs, offMs, times))
                }
                "torchOff" -> {
                    TorchHelper.stop(this)
                    result.success(true)
                }

                // ── Tela de detalhes do app no sistema ─────────────
                "openAppDetailsSettings" -> {
                    val opened = try {
                        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(i)
                        true
                    } catch (_: Exception) {
                        false
                    }
                    result.success(opened)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        ocultarBarraNavegacao()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) ocultarBarraNavegacao()
    }

    private fun ocultarBarraNavegacao() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.navigationBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}

/**
 * Intents específicos por fabricante (OEM) para permissões que o Android
 * padrão não cobre ou que OEMs customizam com telas proprietárias.
 *
 * Marcas cobertas: Xiaomi / Redmi / Poco (MIUI / HyperOS), Samsung (One UI),
 * Oppo / OnePlus / Realme (ColorOS / OxygenOS), Vivo / iQOO (Funtouch / OriginOS),
 * Huawei / Honor (EMUI / MagicUI), Asus (ZenUI), Lenovo / Motorola, Infinix / Tecno (HiOS),
 * Nokia (Android puro), Sony, LG, Meizu (Flyme), Letv (LeEco).
 */
object OemPermissions {

    private fun manufacturer(): String = Build.MANUFACTURER.lowercase()
    private fun brand(): String = Build.BRAND.lowercase()

    private fun tryStartActivity(ctx: Context, intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun tryComponent(ctx: Context, pkg: String, cls: String): Boolean {
        return tryStartActivity(ctx, Intent().apply {
            component = ComponentName(pkg, cls)
        })
    }

    private fun tryAction(ctx: Context, action: String, uri: Uri? = null): Boolean {
        return tryStartActivity(ctx, if (uri != null) Intent(action, uri) else Intent(action))
    }

    // ═══════════════════════════════════════════════════════════════════
    //  AUTOSTART
    // ═══════════════════════════════════════════════════════════════════

    fun openAutostartSettings(ctx: Context): Boolean {
        val m = manufacturer()
        val b = brand()
        val intents = mutableListOf<() -> Boolean>()

        // Xiaomi / Redmi / Poco (MIUI + HyperOS)
        if (m.contains("xiaomi") || m.contains("redmi") || b.contains("poco")) {
            intents += { tryComponent(ctx, "com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity") }
            intents += { tryAction(ctx, "miui.intent.action.OP_AUTO_START") }
        }

        // Oppo / OnePlus / Realme (ColorOS / OxygenOS)
        if (m.contains("oppo") || m.contains("oneplus") || m.contains("realme") || b.contains("realme")) {
            intents += { tryComponent(ctx, "com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity") }
            intents += { tryComponent(ctx, "com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity") }
            intents += { tryComponent(ctx, "com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity") }
        }

        // Vivo / iQOO (Funtouch / OriginOS)
        if (m.contains("vivo") || b.contains("iqoo")) {
            intents += { tryComponent(ctx, "com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity") }
            intents += { tryComponent(ctx, "com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager") }
        }

        // Huawei / Honor (EMUI / MagicUI)
        if (m.contains("huawei") || m.contains("honor")) {
            intents += { tryComponent(ctx, "com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity") }
            intents += { tryComponent(ctx, "com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity") }
            intents += { tryComponent(ctx, "com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity") }
        }

        // Samsung
        if (m.contains("samsung")) {
            intents += { tryComponent(ctx, "com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity") }
            intents += { tryComponent(ctx, "com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity") }
        }

        // Asus (ZenUI)
        if (m.contains("asus")) {
            intents += { tryComponent(ctx, "com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity") }
            intents += { tryComponent(ctx, "com.asus.mobilemanager", "com.asus.mobilemanager.entry.FunctionActivity") }
        }

        // Lenovo / Motorola
        if (m.contains("lenovo") || m.contains("motorola")) {
            intents += { tryComponent(ctx, "com.lenovo.security", "com.lenovo.security.purebackground.PureBackgroundActivity") }
        }

        // Infinix / Tecno (HiOS / XOS)
        if (m.contains("infinix") || m.contains("tecno") || b.contains("infinix") || b.contains("tecno")) {
            intents += { tryComponent(ctx, "com.transsion.phonemanager", "com.transsion.phonemanager.module.autostart.AutoStartActivity") }
        }

        // Meizu (Flyme)
        if (m.contains("meizu")) {
            intents += { tryComponent(ctx, "com.meizu.safe", "com.meizu.safe.permission.SmartBGActivity") }
        }

        // Letv / LeEco
        if (m.contains("letv") || m.contains("leeco")) {
            intents += { tryComponent(ctx, "com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity") }
        }

        for (attempt in intents) {
            if (attempt()) return true
        }

        // Fallback universal: tela de detalhes do app
        return tryAction(ctx, Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${ctx.packageName}"))
    }

    // ═══════════════════════════════════════════════════════════════════
    //  OVERLAY (Exibir sobre outros apps)
    // ═══════════════════════════════════════════════════════════════════

    fun openOverlaySettings(ctx: Context): Boolean {
        // Tentativa padrão com URI do pacote
        if (tryAction(ctx, Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${ctx.packageName}"))) {
            return true
        }

        val m = manufacturer()

        // MIUI: editor de permissões do app
        if (m.contains("xiaomi") || m.contains("redmi")) {
            if (tryStartActivity(ctx, Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                    putExtra("extra_pkgname", ctx.packageName)
                })) return true
        }

        // Fallback: lista geral de overlay
        if (tryAction(ctx, Settings.ACTION_MANAGE_OVERLAY_PERMISSION)) return true

        // Último recurso: detalhes do app
        return tryAction(ctx, Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${ctx.packageName}"))
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BATERIA — fluxo padrão + OEM
    // ═══════════════════════════════════════════════════════════════════

    fun openBatterySettings(ctx: Context): Boolean {
        // Padrão Android: solicitar ignorar otimização de bateria para o app
        if (tryAction(ctx, Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${ctx.packageName}"))) {
            return true
        }
        // Fallback: lista geral
        if (tryAction(ctx, Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) return true

        return tryAction(ctx, Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${ctx.packageName}"))
    }

    /** Abre o gerenciador de bateria proprietário do fabricante. */
    fun openOemBatteryManager(ctx: Context): Boolean {
        val m = manufacturer()
        val b = brand()
        val intents = mutableListOf<() -> Boolean>()

        // Xiaomi / Redmi / Poco
        if (m.contains("xiaomi") || m.contains("redmi") || b.contains("poco")) {
            intents += { tryComponent(ctx, "com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity") }
            intents += { tryComponent(ctx, "com.miui.securitycenter", "com.miui.powercenter.PowerSettings") }
        }

        // Huawei / Honor
        if (m.contains("huawei") || m.contains("honor")) {
            intents += { tryComponent(ctx, "com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity") }
            intents += { tryComponent(ctx, "com.huawei.systemmanager", "com.huawei.systemmanager.power.ui.HwPowerManagerActivity") }
        }

        // Samsung (Device Care / Device Maintenance)
        if (m.contains("samsung")) {
            intents += { tryComponent(ctx, "com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity") }
            intents += { tryComponent(ctx, "com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity") }
        }

        // Oppo / OnePlus / Realme
        if (m.contains("oppo") || m.contains("oneplus") || m.contains("realme") || b.contains("realme")) {
            intents += { tryComponent(ctx, "com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity") }
            intents += { tryComponent(ctx, "com.oplus.battery", "com.oplus.powermanager.fuelgaue.PowerUsageModelActivity") }
        }

        // Vivo / iQOO
        if (m.contains("vivo") || b.contains("iqoo")) {
            intents += { tryComponent(ctx, "com.vivo.abe", "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity") }
        }

        // Infinix / Tecno
        if (m.contains("infinix") || m.contains("tecno") || b.contains("infinix") || b.contains("tecno")) {
            intents += { tryComponent(ctx, "com.transsion.phonemanager", "com.transsion.phonemanager.module.powersaver.PowerSaverActivity") }
        }

        for (attempt in intents) {
            if (attempt()) return true
        }

        // Fallback: bateria padrão Android
        return openBatterySettings(ctx)
    }

    // ═══════════════════════════════════════════════════════════════════
    //  NOTIFICAÇÕES
    // ═══════════════════════════════════════════════════════════════════

    fun openNotificationSettings(ctx: Context): Boolean {
        if (tryStartActivity(ctx, Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
            })) return true

        return tryAction(ctx, Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${ctx.packageName}"))
    }
}

/**
 * Helper para vibração em padrão real (estilo chamada recebida), funciona
 * também quando o celular está bloqueado. Requer permissão VIBRATE no
 * manifest. Em dispositivos que suportam VibrationEffect (API 26+), usa
 * waveform; fallback para o API legado em dispositivos antigos.
 */
object VibrationHelper {
    private fun obterVibrator(ctx: Context): Vibrator? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                    as? VibratorManager
                manager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Exception) {
            null
        }
    }

    fun vibratePattern(ctx: Context, durations: List<Long>, repeat: Int): Boolean {
        if (durations.isEmpty()) return false
        val v = obterVibrator(ctx) ?: return false
        if (!v.hasVibrator()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createWaveform(
                    durations.toLongArray(),
                    repeat,
                )
                v.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(durations.toLongArray(), repeat)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun cancel(ctx: Context) {
        try { obterVibrator(ctx)?.cancel() } catch (_: Exception) {}
    }
}

/**
 * Helper para piscar o LED da câmera (lanterna). Usa `setTorchMode` do
 * `CameraManager` (API 23+), que funciona mesmo com o celular bloqueado e
 * sem precisar abrir a câmera. Reentrante: se for chamado de novo enquanto
 * pisca, cancela o loop anterior antes de iniciar.
 */
object TorchHelper {
    @Volatile private var piscando = false
    private var handler: Handler? = null
    private var cameraManager: CameraManager? = null
    private var cameraId: String? = null

    private fun resolver(ctx: Context): Pair<CameraManager, String>? {
        val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return null
        val id = try {
            cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (_: Exception) {
            null
        } ?: return null
        return cm to id
    }

    fun blink(ctx: Context, onMs: Long, offMs: Long, times: Int): Boolean {
        stop(ctx)
        val (cm, id) = resolver(ctx) ?: return false
        cameraManager = cm
        cameraId = id
        val h = Handler(Looper.getMainLooper())
        handler = h
        piscando = true

        var restante = times
        val pulseRunnable = object : Runnable {
            override fun run() {
                if (!piscando) return
                if (restante <= 0) {
                    try { cm.setTorchMode(id, false) } catch (_: Exception) {}
                    piscando = false
                    return
                }
                restante--
                try { cm.setTorchMode(id, true) } catch (_: Exception) {}
                h.postDelayed({
                    if (!piscando) return@postDelayed
                    try { cm.setTorchMode(id, false) } catch (_: Exception) {}
                    h.postDelayed(this, offMs)
                }, onMs)
            }
        }
        h.post(pulseRunnable)
        return true
    }

    fun stop(ctx: Context) {
        piscando = false
        handler?.removeCallbacksAndMessages(null)
        handler = null
        try {
            val cm = cameraManager ?: ctx.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            val id = cameraId ?: return
            cm?.setTorchMode(id, false)
        } catch (_: Exception) {}
    }
}
