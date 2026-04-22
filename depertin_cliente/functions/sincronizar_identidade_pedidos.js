// Fase 3G.3 — sincroniza a identidade denormalizada (nome + foto) nos pedidos
// ativos quando o cliente ou o lojista atualiza seu perfil em `users/{uid}`.
//
// Contexto:
//   Os pedidos agora carregam `cliente_nome`, `cliente_foto_perfil`, `loja_nome`
//   e `loja_foto` como snapshot denormalizado (ver `cart_screen.dart`). Isso
//   permite que lojista e entregador exibam essas informações sem precisar
//   ler `users/{outro_uid}`, o que era o bloqueio pra fechar a rule de `users`
//   contra scraping entre autenticados.
//
// Compromisso:
//   A cópia denormalizada no pedido fica "carimbada no momento da criação",
//   mas se o usuário trocar foto/nome, pedidos em andamento refletem a
//   atualização. Pedidos finalizados (entregue/cancelado) NÃO são alterados —
//   ficam com o snapshot histórico.
//
// Segurança:
//   Este trigger roda com Admin SDK (bypass rules), o que é ok porque só
//   escreve campos públicos de identidade em pedidos cuja relação
//   (`cliente_id`/`loja_id`) já envolve o usuário alterado.

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

const STATUS_PEDIDO_FINALIZADO = [
    "entregue",
    "cancelado",
    "cancelado_pelo_cliente",
    "cancelado_pela_loja",
    "cancelado_pelo_lojista",
    "estornado",
    "expirado",
];

// Limite de atualizações por execução. Em condições normais um usuário tem
// poucos pedidos ativos simultâneos; esse teto evita explosão em edge cases
// (usuário com histórico gigantesco mudando a foto várias vezes).
const MAX_PEDIDOS_POR_SYNC = 200;

/** Lê campos de nome/foto/telefone no doc de users (cliente ou lojista). */
function extrairIdentidadeUser(data) {
    const d = data || {};
    const nome = (
        d.nome ||
        d.nomeCompleto ||
        d.nome_completo ||
        d.displayName ||
        ""
    )
        .toString()
        .trim();
    const fotoCliente = (d.foto_perfil || d.foto || "").toString().trim();
    const telefone = (
        d.telefone ||
        d.whatsapp ||
        d.celular ||
        d.telefone_contato ||
        ""
    )
        .toString()
        .trim();
    return {nome, fotoCliente, telefone};
}

/** Lê o telefone comercial da loja (mesma prioridade usada no checkout). */
function telefoneLoja(data) {
    const d = data || {};
    for (const k of ["telefone", "whatsapp", "celular"]) {
        const v = (d[k] || "").toString().trim();
        if (v) return v;
    }
    return "";
}

/** Prioriza a melhor imagem de loja pra `loja_foto` (mesma lógica do app). */
function melhorFotoLoja(data) {
    const d = data || {};
    for (const k of [
        "foto_perfil",
        "foto",
        "foto_logo",
        "foto_capa",
        "imagem",
    ]) {
        const v = (d[k] || "").toString().trim();
        if (v) return v;
    }
    return "";
}

function nomeLoja(data) {
    const d = data || {};
    return (
        d.loja_nome ||
        d.nome_loja ||
        d.nome_fantasia ||
        d.nome ||
        ""
    )
        .toString()
        .trim();
}

function isLojistaDoc(data) {
    if (!data) return false;
    const r = (data.role || data.tipoUsuario || data.tipo || "").toString();
    return r === "lojista";
}

function isEntregadorDoc(data) {
    if (!data) return false;
    const r = (data.role || data.tipoUsuario || data.tipo || "").toString();
    return r === "entregador";
}

/** Lê o código da audição declarada no perfil (`acessibilidade.audicao`). */
function audicaoEntregador(data) {
    const d = data || {};
    const a = d.acessibilidade && typeof d.acessibilidade === "object"
        ? d.acessibilidade
        : {};
    const raw = (a.audicao || "").toString().trim().toLowerCase();
    if (raw === "surdo") return "surdo";
    if (raw === "deficiencia" || raw === "deficiência") return "deficiencia";
    if (raw === "normal") return "normal";
    return "";
}

/**
 * Atualiza em batch os pedidos ativos de um usuário com a nova identidade.
 * @param {string} campoId - "cliente_id" ou "loja_id".
 * @param {string} uid - UID do usuário alterado.
 * @param {object} patch - Campos que vão ser atualizados no pedido.
 */
async function atualizarPedidosAtivos(campoId, uid, patch) {
    const camposModificados = Object.keys(patch).filter(
        (k) => patch[k] !== undefined,
    );
    if (camposModificados.length === 0) return;

    const db = admin.firestore();
    const snap = await db
        .collection("pedidos")
        .where(campoId, "==", uid)
        .limit(MAX_PEDIDOS_POR_SYNC)
        .get();

    if (snap.empty) return;

    const batch = db.batch();
    let atualizados = 0;
    for (const doc of snap.docs) {
        const data = doc.data() || {};
        const statusAtual = (data.status || "").toString();
        if (STATUS_PEDIDO_FINALIZADO.includes(statusAtual)) continue;

        // Só atualiza se algum dos campos realmente mudou no pedido.
        const mudou = camposModificados.some(
            (k) => (data[k] || "") !== (patch[k] || ""),
        );
        if (!mudou) continue;

        batch.update(doc.ref, patch);
        atualizados++;
    }

    if (atualizados > 0) {
        await batch.commit();
        console.log(
            `[sincronizarIdentidadePedidos] ${campoId}=${uid} ` +
                `atualizou ${atualizados} pedido(s) ativo(s)`,
        );
    }
}

/**
 * Trigger onUpdate em users. Detecta mudanças em nome/foto e propaga pros
 * pedidos ativos do cliente e/ou da loja.
 */
exports.sincronizarIdentidadePedidosOnUpdate = functions.firestore
    .document("users/{uid}")
    .onUpdate(async (change, context) => {
        const uid = context.params.uid;
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};

        // --- Identidade do CLIENTE nos pedidos (cliente_id == uid) ---
        const antesId = extrairIdentidadeUser(antes);
        const depoisId = extrairIdentidadeUser(depois);
        const patchCliente = {};
        if (antesId.nome !== depoisId.nome) {
            patchCliente.cliente_nome = depoisId.nome;
        }
        if (antesId.fotoCliente !== depoisId.fotoCliente) {
            patchCliente.cliente_foto_perfil = depoisId.fotoCliente;
        }
        if (antesId.telefone !== depoisId.telefone) {
            patchCliente.cliente_telefone = depoisId.telefone;
        }
        if (Object.keys(patchCliente).length > 0) {
            try {
                await atualizarPedidosAtivos("cliente_id", uid, patchCliente);
            } catch (e) {
                console.error(
                    `[sincronizarIdentidadePedidos] erro cliente_id=${uid}:`,
                    e,
                );
            }
        }

        // --- Perfil do ENTREGADOR nos pedidos (entregador_id == uid) ---
        // Propaga mudança da preferência de acessibilidade auditiva pra pedidos
        // ativos em que o entregador já foi atribuído.
        if (isEntregadorDoc(antes) || isEntregadorDoc(depois)) {
            const audicaoAntes = audicaoEntregador(antes);
            const audicaoDepois = audicaoEntregador(depois);
            if (audicaoAntes !== audicaoDepois) {
                try {
                    await atualizarPedidosAtivos("entregador_id", uid, {
                        entregador_acessibilidade_audicao: audicaoDepois,
                    });
                } catch (e) {
                    console.error(
                        `[sincronizarIdentidadePedidos] erro entregador_id=${uid}:`,
                        e,
                    );
                }
            }
        }

        // --- Identidade da LOJA nos pedidos (loja_id == uid) ---
        // Só faz sentido se o doc é de lojista (antes ou depois).
        if (isLojistaDoc(antes) || isLojistaDoc(depois)) {
            const nomeAntes = nomeLoja(antes);
            const nomeDepois = nomeLoja(depois);
            const fotoAntes = melhorFotoLoja(antes);
            const fotoDepois = melhorFotoLoja(depois);
            const telAntes = telefoneLoja(antes);
            const telDepois = telefoneLoja(depois);
            const patchLoja = {};
            if (nomeAntes !== nomeDepois && nomeDepois) {
                patchLoja.loja_nome = nomeDepois;
            }
            if (fotoAntes !== fotoDepois) {
                patchLoja.loja_foto = fotoDepois;
            }
            if (telAntes !== telDepois) {
                patchLoja.loja_telefone = telDepois;
            }
            if (Object.keys(patchLoja).length > 0) {
                try {
                    await atualizarPedidosAtivos("loja_id", uid, patchLoja);
                } catch (e) {
                    console.error(
                        `[sincronizarIdentidadePedidos] erro loja_id=${uid}:`,
                        e,
                    );
                }
            }
        }

        return null;
    });

exports.STATUS_PEDIDO_FINALIZADO = STATUS_PEDIDO_FINALIZADO;
exports.extrairIdentidadeUser = extrairIdentidadeUser;
exports.melhorFotoLoja = melhorFotoLoja;
exports.nomeLoja = nomeLoja;
exports.telefoneLoja = telefoneLoja;
