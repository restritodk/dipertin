// Arquivo: functions/veiculos_entregador.js
//
// Mantém compat do painel web de aprovação de entregadores: quando o entregador
// altera dados do veículo ATIVO na subcoleção `users/{uid}/veiculos/{vid}`,
// copiamos as informações chave para campos planos em `users/{uid}` que o
// painel web historicamente lê: `veiculoTipo`, `url_crlv`.
//
// Por que:
//   O app do entregador (Fase 3) passou a operar sobre a subcoleção `veiculos`
//   para suportar múltiplos veículos cadastrados + seleção de ativo. O painel
//   web ainda lê os campos planos. Este trigger é a ponte de compat enquanto
//   o painel não for migrado.

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const { normalizarTipoVeiculo } = require("./tipos_entrega");

/** Códigos internos → rótulos já usados pelo painel web. */
function tipoParaPainel(codigo) {
    const v = String(codigo || "").trim().toLowerCase();
    if (v === "moto") return "Moto";
    if (v === "carro") return "Carro";
    if (v === "carro_frete") return "Carro frete";
    if (v === "bike" || v === "bicicleta") return "Bicicleta";
    return "";
}

async function sincronizarAtivoDoUsuario(uid) {
    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef
        .collection("veiculos")
        .where("ativo", "==", true)
        .limit(1)
        .get();

    if (snap.empty) {
        // Nenhum veículo ativo — zera compat e sinaliza pro painel.
        try {
            await userRef.set({
                veiculo_ativo_id: admin.firestore.FieldValue.delete(),
                tipo_veiculo_canonico: admin.firestore.FieldValue.delete(),
            }, {merge: true});
        } catch (e) {
            console.warn("[veiculos] limpar ativo:", e);
        }
        return null;
    }

    const ativo = snap.docs[0];
    const data = ativo.data() || {};
    const vid = ativo.id;

    // Lê status do CRLV (se houver subdoc) para refletir no campo plano.
    let urlCrlv = "";
    try {
        const crlvSnap = await userRef
            .collection("veiculos")
            .doc(vid)
            .collection("documentos")
            .doc("crlv")
            .get();
        if (crlvSnap.exists) {
            urlCrlv = String(crlvSnap.data().url || "");
        }
    } catch (e) {
        console.warn("[veiculos] ler crlv:", e);
    }

    const patch = {
        veiculo_ativo_id: vid,
    };
    const tipoLabel = tipoParaPainel(data.tipo);
    if (tipoLabel) patch.veiculoTipo = tipoLabel;
    if (urlCrlv) patch.url_crlv = urlCrlv;

    // Campo canônico (bicicleta|moto|carro|carro_frete) — usado pela fila
    // de despacho para filtrar entregadores compatíveis com a loja do pedido.
    const canonico = normalizarTipoVeiculo(data.tipo) ||
        normalizarTipoVeiculo(tipoLabel);
    if (canonico) {
        patch.tipo_veiculo_canonico = canonico;
    } else {
        patch.tipo_veiculo_canonico = admin.firestore.FieldValue.delete();
    }

    await userRef.set(patch, {merge: true});
    return patch;
}

/**
 * Trigger na subcoleção `users/{uid}/veiculos/{vid}`. Sincroniza campos planos
 * no doc do usuário sempre que qualquer veículo for criado/atualizado/apagado
 * — porque a mudança pode ter trocado o veículo ativo (ex.: o cliente mudou
 * `ativo: false -> true`).
 */
exports.sincronizarVeiculoAtivoCampoPlano = functions.firestore
    .document("users/{uid}/veiculos/{veiculoId}")
    .onWrite(async (change, context) => {
        const uid = context.params.uid;
        try {
            await sincronizarAtivoDoUsuario(uid);
        } catch (e) {
            console.error("[sincronizarVeiculoAtivoCampoPlano]", uid, e);
        }
        return null;
    });

/**
 * Também reage a mudanças no doc do CRLV (upload/aprovação/reprovação) para
 * propagar a URL pro campo plano quando for do veículo ativo.
 */
exports.sincronizarCrlvVeiculoAtivo = functions.firestore
    .document("users/{uid}/veiculos/{veiculoId}/documentos/{tipo}")
    .onWrite(async (change, context) => {
        const {uid, tipo} = context.params;
        if (String(tipo) !== "crlv") return null;
        try {
            await sincronizarAtivoDoUsuario(uid);
        } catch (e) {
            console.error("[sincronizarCrlvVeiculoAtivo]", uid, e);
        }
        return null;
    });
