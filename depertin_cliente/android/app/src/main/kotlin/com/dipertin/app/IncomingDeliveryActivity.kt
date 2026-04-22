package com.dipertin.app

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.view.ViewOutlineProvider
import com.google.firebase.firestore.FirebaseFirestore
import java.net.URL
import java.text.NumberFormat
import java.util.Locale

class IncomingDeliveryActivity : AppCompatActivity() {
    private val tag = "IncomingDeliveryFlow"
    private val db by lazy { FirebaseFirestore.getInstance() }
    private var orderId: String = ""
    private var requestId: String = ""
    private var expiresAtMs: Long = 0L
    private var timer: CountDownTimer? = null
    private var actionLoading = false
    private var activeAction: String? = null
    private var ringtonePlayer: MediaPlayer? = null

    private lateinit var txtBadge: TextView
    private lateinit var imgStoreAvatar: ImageView
    private lateinit var txtStoreName: TextView
    private lateinit var txtTitle: TextView
    private lateinit var txtSubtitle: TextView
    private lateinit var txtGainValue: TextView
    private lateinit var txtPickup: TextView
    private lateinit var txtDelivery: TextView
    private lateinit var txtCountdownTop: TextView
    private lateinit var progressCountdownTop: ProgressBar
    private lateinit var txtCountdown: TextView
    private lateinit var progressCountdown: ProgressBar
    private lateinit var btnAccept: Button
    private lateinit var btnReject: Button

    private val moneyBr by lazy { NumberFormat.getCurrencyInstance(Locale("pt", "BR")) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(tag, "IncomingDeliveryActivity.onCreate action=${intent?.action}")
        configureLockScreenBehavior()
        setContentView(R.layout.activity_incoming_delivery)
        bindViews()
        applyIntent(intent)
        setupActions()
        startTimeoutTimer()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.i(tag, "IncomingDeliveryActivity.onNewIntent action=${intent.action}")
        applyIntent(intent)
        startTimeoutTimer()
    }

    override fun onDestroy() {
        timer?.cancel()
        stopRingtone()
        super.onDestroy()
    }

    override fun onStop() {
        stopRingtone()
        super.onStop()
    }

    private fun bindViews() {
        txtBadge = findViewById(R.id.txtBadge)
        imgStoreAvatar = findViewById(R.id.imgStoreAvatar)
        txtStoreName = findViewById(R.id.txtStoreName)
        txtTitle = findViewById(R.id.txtTitle)
        txtSubtitle = findViewById(R.id.txtSubtitle)
        txtGainValue = findViewById(R.id.txtGainValue)
        txtPickup = findViewById(R.id.txtPickup)
        txtDelivery = findViewById(R.id.txtDelivery)
        txtCountdownTop = findViewById(R.id.txtCountdownTop)
        progressCountdownTop = findViewById(R.id.progressCountdownTop)
        txtCountdown = findViewById(R.id.txtCountdown)
        progressCountdown = findViewById(R.id.progressCountdown)
        btnAccept = findViewById(R.id.btnAccept)
        btnReject = findViewById(R.id.btnReject)

        imgStoreAvatar.outlineProvider = ViewOutlineProvider.BACKGROUND
        imgStoreAvatar.clipToOutline = true
    }

    private fun applyIntent(intent: Intent?) {
        val extras = intent?.extras
        if (extras != null) {
            val allKeys = extras.keySet().sorted()
            Log.i(tag, "Intent extras [${allKeys.size}]: ${allKeys.joinToString { "$it=${extras.getString(it)}" }}")
        } else {
            Log.w(tag, "Intent sem extras")
        }

        orderId = intent?.getStringExtra(IncomingDeliveryContract.EXTRA_ORDER_ID).orEmpty()
        requestId = intent?.getStringExtra(IncomingDeliveryContract.EXTRA_REQUEST_ID)
            ?.trim()
            .orEmpty()
            .ifBlank {
                IncomingDeliveryContract.requestId(
                    orderId,
                    intent?.getStringExtra("despacho_oferta_seq"),
                )
            }
        if (requestId.isNotBlank()) {
            IncomingDeliveryFlowState.markScreenOpened(requestId)
        }
        if (orderId.isNotBlank()) {
            NotificationUtils.cancelIncomingNotification(this, orderId)
        }
        expiresAtMs = intent?.getStringExtra(IncomingDeliveryContract.EXTRA_EXPIRES_AT)
            ?.toLongOrNull()
            ?: 0L

        val netFee = intent?.getStringExtra("net_delivery_fee")?.toDoubleOrNull()
            ?: intent?.getStringExtra("delivery_fee")?.toDoubleOrNull()
            ?: 0.0
        val pickup = intent?.getStringExtra("pickup_location").orEmpty().ifBlank { "--" }
        val delivery = intent?.getStringExtra("delivery_location").orEmpty().ifBlank { "--" }
        val storeName = firstNonBlank(
            intent?.getStringExtra("loja_nome"),
            intent?.getStringExtra("store_name"),
            intent?.getStringExtra("pickup_name"),
            intent?.getStringExtra("pickup_location"),
        ).ifBlank { "Loja parceira" }
        val storePhoto = firstNonBlank(
            intent?.getStringExtra("loja_foto_url"),
            intent?.getStringExtra("loja_imagem_url"),
            intent?.getStringExtra("loja_foto"),
            intent?.getStringExtra("store_photo_url"),
            intent?.getStringExtra("store_image_url"),
            intent?.getStringExtra("loja_logo_url"),
            intent?.getStringExtra("store_logo_url"),
        )

        txtBadge.text = "NOVA CORRIDA"
        txtStoreName.text = storeName
        carregarFotoLoja(storePhoto) {
            carregarFotoLojaDoFirestore(orderId)
        }
        txtTitle.text = "Nova corrida"
        txtSubtitle.text = "Confira rota e ganho antes de aceitar."
        txtGainValue.text = moneyBr.format(netFee)
        txtPickup.text = pickup
        txtDelivery.text = delivery
        Log.i(tag, "IncomingDeliveryActivity payload orderId=$orderId requestId=$requestId loja=$storeName")
        startRingtoneIfNeeded()
    }

    private fun setupActions() {
        btnAccept.setOnClickListener { handleAccept() }
        btnReject.setOnClickListener { handleReject() }
    }

    private fun setLoading(loading: Boolean) {
        actionLoading = loading
        if (loading) stopRingtone()
        btnAccept.isEnabled = !loading
        btnReject.isEnabled = !loading
        if (loading) {
            if (activeAction == "accept") {
                btnAccept.text = "ACEITANDO..."
                btnReject.text = "RECUSAR"
            } else {
                btnAccept.text = "ACEITAR CORRIDA"
                btnReject.text = "RECUSANDO..."
            }
        } else {
            activeAction = null
            btnAccept.text = "ACEITAR CORRIDA"
            btnReject.text = "RECUSAR"
        }
    }

    private fun startTimeoutTimer() {
        timer?.cancel()
        val remaining = (expiresAtMs - System.currentTimeMillis()).coerceAtLeast(0L)
        if (remaining <= 0L) {
            stopRingtone()
            btnAccept.isEnabled = false
            btnReject.isEnabled = false
            txtCountdown.text = "Tempo esgotado"
            txtCountdownTop.text = "0s"
            progressCountdown.max = 1
            progressCountdown.progress = 0
            progressCountdownTop.max = 1
            progressCountdownTop.progress = 0
            IncomingDeliveryFlowState.markExpired(requestId)
            if (!actionLoading) {
                finish()
            }
            return
        }
        val maxSeconds = (remaining / 1000L).toInt().coerceAtLeast(1)
        progressCountdown.max = maxSeconds
        progressCountdown.progress = maxSeconds
        progressCountdownTop.max = maxSeconds
        progressCountdownTop.progress = maxSeconds
        txtCountdown.text = "Expira em ${maxSeconds}s"
        txtCountdownTop.text = "${maxSeconds}s"
        timer = object : CountDownTimer(remaining, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                val seconds = (millisUntilFinished / 1000L).toInt().coerceAtLeast(0)
                progressCountdown.progress = seconds
                progressCountdownTop.progress = seconds
                txtCountdown.text = if (seconds > 0) "Expira em ${seconds}s" else "Tempo esgotado"
                txtCountdownTop.text = if (seconds > 0) "${seconds}s" else "0s"
            }

            override fun onFinish() {
                stopRingtone()
                progressCountdown.progress = 0
                progressCountdownTop.progress = 0
                txtCountdown.text = "Tempo esgotado"
                txtCountdownTop.text = "0s"
                btnAccept.isEnabled = false
                btnReject.isEnabled = false
                IncomingDeliveryFlowState.markExpired(requestId)
                if (!actionLoading) finish()
            }
        }.start()
    }

    private fun configureLockScreenBehavior() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun handleAccept() {
        if (orderId.isBlank()) {
            openMainRadar()
            return
        }
        NotificationUtils.cancelIncomingNotification(this, orderId)
        stopRingtone()
        activeAction = "accept"
        setLoading(true)
        IncomingDeliveryRepository.aceitar(orderId) { ok, msg ->
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                NotificationUtils.cancelIncomingNotification(this, orderId)
                if (ok) {
                    IncomingDeliveryFlowState.markAccepted(requestId)
                    openMainRadar()
                } else {
                    IncomingDeliveryFlowState.markCancelled(requestId)
                    if (!msg.isNullOrBlank()) {
                        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
                    }
                    setLoading(false)
                }
            }
        }
    }

    private fun handleReject() {
        if (orderId.isBlank()) {
            finish()
            return
        }
        NotificationUtils.cancelIncomingNotification(this, orderId)
        stopRingtone()
        activeAction = "reject"
        setLoading(true)
        IncomingDeliveryRepository.recusar(orderId) { ok, msg ->
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                NotificationUtils.cancelIncomingNotification(this, orderId)
                if (!ok && !msg.isNullOrBlank()) {
                    Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
                }
                if (ok) {
                    IncomingDeliveryFlowState.markRejected(requestId)
                } else {
                    IncomingDeliveryFlowState.markCancelled(requestId)
                }
                finish()
            }
        }
    }

    private fun firstNonBlank(vararg values: String?): String {
        for (value in values) {
            if (!value.isNullOrBlank()) return value
        }
        return ""
    }

    private fun carregarFotoLoja(url: String, onFail: (() -> Unit)? = null) {
        if (url.isBlank() || url == "--") {
            imgStoreAvatar.setImageResource(R.drawable.splash)
            onFail?.invoke()
            return
        }
        imgStoreAvatar.setImageResource(R.drawable.splash)
        Thread {
            try {
                val normalizada = normalizarUrlImagem(url)
                val connection = URL(normalizada).openConnection().apply {
                    connectTimeout = 5000
                    readTimeout = 5000
                }
                connection.getInputStream().use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    runOnUiThread {
                        if (bitmap != null) {
                            imgStoreAvatar.setImageBitmap(bitmap)
                        } else {
                            imgStoreAvatar.setImageResource(R.drawable.splash)
                            onFail?.invoke()
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(tag, "Falha ao carregar foto da loja: ${e.message}")
                runOnUiThread {
                    imgStoreAvatar.setImageResource(R.drawable.splash)
                    onFail?.invoke()
                }
            }
        }.start()
    }

    private fun carregarFotoLojaDoFirestore(orderIdLocal: String) {
        if (orderIdLocal.isBlank()) return
        db.collection("pedidos")
            .document(orderIdLocal)
            .get()
            .addOnSuccessListener { pedidoSnap ->
                if (!pedidoSnap.exists() || orderIdLocal != orderId) return@addOnSuccessListener

                val fotoPedido = firstNonBlank(
                    pedidoSnap.getString("loja_foto_url"),
                    pedidoSnap.getString("loja_imagem_url"),
                    pedidoSnap.getString("loja_foto"),
                    pedidoSnap.getString("store_photo_url"),
                    pedidoSnap.getString("store_image_url"),
                    pedidoSnap.getString("loja_logo_url"),
                    pedidoSnap.getString("store_logo_url"),
                )
                if (fotoPedido.isNotBlank()) {
                    carregarFotoLoja(fotoPedido)
                    return@addOnSuccessListener
                }

                val lojaId = firstNonBlank(
                    pedidoSnap.getString("loja_id"),
                    pedidoSnap.getString("store_id"),
                    pedidoSnap.getString("seller_id"),
                    pedidoSnap.getString("lojista_id"),
                )
                if (lojaId.isBlank()) return@addOnSuccessListener

                db.collection("users")
                    .document(lojaId)
                    .get()
                    .addOnSuccessListener { lojaSnap ->
                        if (!lojaSnap.exists() || orderIdLocal != orderId) return@addOnSuccessListener
                        val fotoLoja = firstNonBlank(
                            lojaSnap.getString("foto_perfil"),
                            lojaSnap.getString("foto_url"),
                            lojaSnap.getString("loja_foto_url"),
                            lojaSnap.getString("loja_imagem_url"),
                            lojaSnap.getString("store_photo_url"),
                            lojaSnap.getString("store_image_url"),
                            lojaSnap.getString("logo_url"),
                        )
                        if (fotoLoja.isNotBlank()) {
                            carregarFotoLoja(fotoLoja)
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.w(tag, "Falha ao buscar foto da loja no users: ${e.message}")
                    }
            }
            .addOnFailureListener { e ->
                Log.w(tag, "Falha ao buscar pedido para fallback de foto: ${e.message}")
            }
    }

    private fun normalizarUrlImagem(url: String): String {
        val limpa = url.trim()
        if (limpa.isEmpty()) return limpa
        val semEspacos = limpa.replace(" ", "%20")
        if (semEspacos.startsWith("http://")) {
            return "https://${semEspacos.removePrefix("http://")}"
        }
        return semEspacos
    }

    private fun startRingtoneIfNeeded() {
        val remaining = (expiresAtMs - System.currentTimeMillis()).coerceAtLeast(0L)
        if (remaining <= 0L || actionLoading) return
        if (ringtonePlayer != null) return
        try {
            val player = MediaPlayer.create(this, R.raw.chamada_entregador) ?: return
            player.isLooping = true
            player.start()
            ringtonePlayer = player
        } catch (e: Exception) {
            Log.w(tag, "Falha ao iniciar toque da chamada: ${e.message}")
        }
    }

    private fun stopRingtone() {
        val player = ringtonePlayer ?: return
        try {
            if (player.isPlaying) player.stop()
        } catch (_: Exception) {
            // ignora
        }
        try {
            player.release()
        } catch (_: Exception) {
            // ignora
        }
        ringtonePlayer = null
    }

    private fun openMainRadar() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_ABRIR_ENTREGADOR, true)
            putExtra(MainActivity.EXTRA_ORDER_ID, orderId)
        }
        startActivity(intent)
        finish()
    }
}
