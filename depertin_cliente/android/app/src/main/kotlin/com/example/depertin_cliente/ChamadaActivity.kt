package com.example.depertin_cliente

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.view.WindowManager
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import java.text.NumberFormat
import java.util.Locale

open class ChamadaActivity : AppCompatActivity() {
    private val db by lazy { FirebaseFirestore.getInstance() }
    private val auth by lazy { FirebaseAuth.getInstance() }
    private val moneyBr by lazy { NumberFormat.getCurrencyInstance(Locale("pt", "BR")) }

    private var pedidoId: String = ""
    private var expiraEmMs: Long = 0L
    private var countdown: CountDownTimer? = null
    private var carregando = false

    private lateinit var txtTitulo: TextView
    private lateinit var txtValor: TextView
    private lateinit var txtValorLabel: TextView
    private lateinit var txtColeta: TextView
    private lateinit var txtEntrega: TextView
    private lateinit var txtMetas: TextView
    private lateinit var txtTimer: TextView
    private lateinit var progressTimer: ProgressBar
    private lateinit var btnAceitar: Button
    private lateinit var btnRecusar: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            km?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }

        setContentView(R.layout.activity_chamada)
        bindViews()
        preencherDados()
        configurarAcoes()
        iniciarContador()
        cancelarNotificacaoAtual()
    }

    override fun onDestroy() {
        countdown?.cancel()
        super.onDestroy()
    }

    private fun bindViews() {
        txtTitulo = findViewById(R.id.chamada_titulo)
        txtValor = findViewById(R.id.chamada_valor)
        txtValorLabel = findViewById(R.id.chamada_valor_label)
        txtColeta = findViewById(R.id.chamada_coleta)
        txtEntrega = findViewById(R.id.chamada_entrega)
        txtMetas = findViewById(R.id.chamada_metas)
        txtTimer = findViewById(R.id.chamada_timer)
        progressTimer = findViewById(R.id.chamada_timer_progress)
        btnAceitar = findViewById(R.id.chamada_btn_aceitar)
        btnRecusar = findViewById(R.id.chamada_btn_recusar)
    }

    private fun preencherDados() {
        pedidoId = intent.getStringExtra("order_id")?.trim().orEmpty()
        expiraEmMs = intent.getStringExtra("despacho_expira_em_ms")
            ?.toLongOrNull()
            ?: (System.currentTimeMillis() + 15_000L)

        val taxa = intent.getStringExtra("delivery_fee")?.toDoubleOrNull() ?: 0.0
        val pickup = intent.getStringExtra("pickup_location").orEmpty()
        val delivery = intent.getStringExtra("delivery_location").orEmpty()
        val dAte = intent.getStringExtra("distance_to_store_km").orEmpty()
        val dRota = intent.getStringExtra("distance_store_to_customer_km").orEmpty()
        val tMin = intent.getStringExtra("tempo_estimado_min").orEmpty()

        txtTitulo.text = if (pedidoId.isNotEmpty()) "Nova corrida #${pedidoId.take(8)}" else "Nova corrida"
        txtValor.text = moneyBr.format(taxa)
        txtValorLabel.text = "ganho líquido"
        txtColeta.text = if (pickup.isNotBlank()) "Coleta: $pickup" else "Coleta: —"
        txtEntrega.text = if (delivery.isNotBlank()) "Entrega: $delivery" else "Entrega: —"
        txtMetas.text = buildString {
            append("Você→Loja: ")
            append(if (dAte.isBlank()) "—" else "${dAte.replace('.', ',')} km")
            append("   •   Loja→Cliente: ")
            append(if (dRota.isBlank()) "—" else "${dRota.replace('.', ',')} km")
            if (tMin.isNotBlank()) {
                append("   •   ~")
                append(tMin)
                append(" min")
            }
        }
    }

    private fun configurarAcoes() {
        btnAceitar.setOnClickListener { aceitarOferta() }
        btnRecusar.setOnClickListener { recusarOferta() }
    }

    private fun iniciarContador() {
        val totalMs = (expiraEmMs - System.currentTimeMillis()).coerceAtLeast(0L)
        val duracaoSeg = 15
        progressTimer.max = duracaoSeg
        progressTimer.progress = (totalMs / 1000L).toInt().coerceAtMost(duracaoSeg)
        atualizarTextoTimer((totalMs / 1000L).toInt())

        countdown?.cancel()
        countdown = object : CountDownTimer(totalMs, 250L) {
            override fun onTick(millisUntilFinished: Long) {
                val sec = (millisUntilFinished / 1000L).toInt().coerceAtLeast(0)
                progressTimer.progress = sec.coerceAtMost(duracaoSeg)
                atualizarTextoTimer(sec)
            }

            override fun onFinish() {
                progressTimer.progress = 0
                txtTimer.text = "Tempo esgotado"
                if (!carregando) finish()
            }
        }.start()
    }

    private fun atualizarTextoTimer(segundos: Int) {
        txtTimer.text = if (segundos <= 0) "Tempo esgotado" else "Aceite em ${segundos}s"
    }

    private fun setCarregando(ativo: Boolean, acao: String = "") {
        carregando = ativo
        btnAceitar.isEnabled = !ativo
        btnRecusar.isEnabled = !ativo
        if (ativo) {
            when (acao) {
                "aceitar" -> btnAceitar.text = "Aceitando..."
                "recusar" -> btnRecusar.text = "Recusando..."
            }
        } else {
            btnAceitar.text = "Aceitar corrida"
            btnRecusar.text = "Recusar"
        }
    }

    private fun aceitarOferta() {
        val uid = auth.currentUser?.uid
        if (uid.isNullOrBlank() || pedidoId.isBlank()) {
            abrirRadar()
            return
        }
        setCarregando(true, "aceitar")

        val userRef = db.collection("users").document(uid)
        val pedidoRef = db.collection("pedidos").document(pedidoId)

        userRef.get()
            .addOnSuccessListener { userSnap ->
                val ud = userSnap.data ?: emptyMap<String, Any>()
                val nomeEntregador = ud["nome"]?.toString().orEmpty().ifBlank { "Entregador parceiro" }
                val foto = ud["foto_perfil"]?.toString().orEmpty()
                val tel = ud["telefone"]?.toString().orEmpty()
                val veiculo = ud["veiculoTipo"]?.toString().orEmpty()

                db.runTransaction { t ->
                    val snap = t.get(pedidoRef)
                    if (!snap.exists()) throw IllegalStateException("Pedido não encontrado.")
                    val p = snap.data ?: emptyMap<String, Any>()
                    if (p["entregador_id"] != null) {
                        throw IllegalStateException("Corrida já aceita por outro entregador.")
                    }
                    val st = p["status"]?.toString().orEmpty()
                    if (st != "aguardando_entregador" && st != "a_caminho") {
                        throw IllegalStateException("Este pedido não está mais disponível.")
                    }
                    val alvo = p["despacho_oferta_uid"]?.toString().orEmpty()
                    if (alvo.isNotBlank() && alvo != uid) {
                        throw IllegalStateException("Esta oferta não está disponível para você.")
                    }
                    t.update(
                        pedidoRef,
                        mapOf(
                            "status" to "entregador_indo_loja",
                            "entregador_id" to uid,
                            "entregador_nome" to nomeEntregador,
                            "entregador_foto_url" to foto,
                            "entregador_telefone" to tel,
                            "entregador_veiculo" to veiculo,
                            "entregador_aceito_em" to FieldValue.serverTimestamp(),
                            "despacho_oferta_uid" to FieldValue.delete(),
                            "despacho_oferta_expira_em" to FieldValue.delete(),
                            "despacho_oferta_estado" to "aceito",
                            "despacho_job_lock" to FieldValue.delete(),
                        ),
                    )
                    null
                }.addOnSuccessListener {
                    abrirRadar()
                }.addOnFailureListener { e ->
                    setCarregando(false)
                    toast("Não foi possível aceitar: ${e.message ?: "erro"}")
                }
            }
            .addOnFailureListener { e ->
                setCarregando(false)
                toast("Não foi possível aceitar: ${e.message ?: "erro"}")
            }
    }

    private fun recusarOferta() {
        val uid = auth.currentUser?.uid
        if (uid.isNullOrBlank() || pedidoId.isBlank()) {
            finish()
            return
        }
        setCarregando(true, "recusar")
        val pedidoRef = db.collection("pedidos").document(pedidoId)

        db.runTransaction { t ->
            val snap = t.get(pedidoRef)
            if (!snap.exists()) return@runTransaction false
            val p = snap.data ?: emptyMap<String, Any>()
            val status = p["status"]?.toString().orEmpty()
            val alvo = p["despacho_oferta_uid"]?.toString().orEmpty()
            if (status != "aguardando_entregador" || alvo != uid) {
                return@runTransaction false
            }
            t.update(
                pedidoRef,
                mapOf(
                    "despacho_recusados" to FieldValue.arrayUnion(uid),
                    "despacho_oferta_uid" to FieldValue.delete(),
                    "despacho_oferta_expira_em" to FieldValue.delete(),
                    "despacho_oferta_estado" to "recusado",
                ),
            )
            true
        }.addOnSuccessListener {
            finish()
        }.addOnFailureListener { e ->
            setCarregando(false)
            toast("Não foi possível recusar: ${e.message ?: "erro"}")
        }
    }

    private fun abrirRadar() {
        val i = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_ABRIR_ENTREGADOR, true)
            putExtra(MainActivity.EXTRA_ORDER_ID, pedidoId)
        }
        startActivity(i)
        finish()
    }

    private fun toast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }

    private fun cancelarNotificacaoAtual() {
        val id = (if (pedidoId.isNotBlank()) pedidoId else intent.getStringExtra("google.message_id"))
            ?.hashCode()
            ?: return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        nm?.cancel(id)
    }
}
