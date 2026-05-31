"use strict";

/**
 * Bloqueio / desbloqueio / exclusão do perfil de entregador iniciados pelo app.
 * Reutiliza campos block_* e entregador_status do painel admin.
 * Push de mudança de perfil: trigger `entregador_perfil_operacional_notificacao.js`.
 */
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const functionsV1 = require("firebase-functions/v1");

const CALL_OPTS = { region: "us-central1", enforceAppCheck: false };

const BR = {
    PAUSA_TEMPORARIA: "PAUSA_TEMPORARIA_ENTREGADOR",
    PAUSA_DEFINITIVA: "PAUSA_DEFINITIVA_ENTREGADOR",
    EXCLUSAO_PERFIL: "EXCLUSAO_PERFIL_ENTREGADOR",
};

const PERFIL = {
    ATIVO: "ativo",
    BLOQ_TEMP: "bloqueado_temporario",
    BLOQ_DEF: "bloqueado_definitivo",
    EXCLUSAO: "exclusao_solicitada",
    REMOVIDO: "perfil_removido",
};

const DIAS_EXCLUSAO = 30;

const STATUS_CORRIDA_ATIVA = [
    "aguardando_entregador",
    "entregador_indo_loja",
    "saiu_entrega",
    "a_caminho",
    "em_rota",
    "pronto",
];

function assertAuth(request) {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Faça login para continuar.");
    }
    return request.auth.uid;
}

function toDateMaybe(ts) {
    if (!ts) return null;
    if (typeof ts.toDate === "function") return ts.toDate();
    if (ts._seconds != null) return new Date(ts._seconds * 1000);
    return null;
}

function docIndicaEntregador(d) {
    const role = String(d.role || d.tipoUsuario || "").toLowerCase();
    return role === "entregador";
}

function motivoPareceFinanceiro(motivo) {
    const s = String(motivo || "").toLowerCase();
    return /pagamento|inadimpl|financeir|suspens|falta de pagamento|cobran|mensalidade|plano|pend(ência|encia) financeira|regulariz|débito|debito/.test(
        s,
    );
}

function entregadorRecusadoSomenteCorrecaoCadastro(d) {
    if (d.recusa_cadastro === true) return true;
    const sl = String(d.entregador_status || "");
    if (sl !== "bloqueado" && sl !== "bloqueada") return false;
    if (Object.prototype.hasOwnProperty.call(d, "block_active")) return false;
    const motivo = String(d.motivo_recusa || "").trim();
    if (!motivo) return false;
    return !motivoPareceFinanceiro(motivo);
}

function entregadorBloqueadoOperacionalJs(d) {
    if (!docIndicaEntregador(d)) return false;
    if (entregadorRecusadoSomenteCorrecaoCadastro(d)) return false;
    const sl = String(d.entregador_status || "");

    if (sl === "bloqueado") return true;

    if (sl === "bloqueio_temporario") {
        const end = toDateMaybe(d.block_end_at);
        if (end && Date.now() > end.getTime()) return false;
        return true;
    }

    if (sl === "bloqueado" || sl === "bloqueada") {
        if (!Object.prototype.hasOwnProperty.call(d, "block_active")) return true;
    }

    if (d.block_active !== true) return false;

    if (String(d.block_type) === "BLOCK_TEMPORARY") {
        const end = toDateMaybe(d.block_end_at);
        if (end && Date.now() > end.getTime()) return false;
    }
    return true;
}

function motivoPermiteDesbloqueioSelf(reason) {
    return reason === BR.PAUSA_TEMPORARIA || reason === BR.PAUSA_DEFINITIVA;
}

async function assertEntregadorAprovadoSemCorrida(db, uid) {
    const ref = db.collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new HttpsError("not-found", "Perfil não encontrado.");
    }
    const d = snap.data() || {};
    if (!docIndicaEntregador(d)) {
        throw new HttpsError(
            "failed-precondition",
            "Esta ação é apenas para contas de entregador.",
        );
    }
    if (String(d.entregador_status || "") !== "aprovado" && !entregadorBloqueadoOperacionalJs(d)) {
        if (String(d.entregador_perfil_operacional || "") === PERFIL.EXCLUSAO) {
            throw new HttpsError(
                "failed-precondition",
                "Exclusão do perfil de entregador já foi solicitada.",
            );
        }
        throw new HttpsError(
            "failed-precondition",
            "Cadastro de entregador ainda não está aprovado para esta ação.",
        );
    }
    if (String(d.block_reason || "") === BR.EXCLUSAO_PERFIL) {
        throw new HttpsError(
            "failed-precondition",
            "Exclusão do perfil já solicitada. Aguarde o prazo ou fale com o suporte.",
        );
    }

    const pedidos = await db
        .collection("pedidos")
        .where("entregador_id", "==", uid)
        .where("status", "in", STATUS_CORRIDA_ATIVA)
        .limit(1)
        .get();

    if (!pedidos.empty) {
        throw new HttpsError(
            "failed-precondition",
            "Finalize ou cancele as entregas em andamento antes de continuar.",
        );
    }

    return { ref, data: d };
}

function calcularDuracaoMs({ dias, meses }) {
    const d = Number(dias);
    const m = Number(meses);
    if (Number.isFinite(m) && m > 0) {
        return Math.round(m * 30 * 24 * 60 * 60 * 1000);
    }
    if (Number.isFinite(d) && d > 0) {
        return Math.round(d * 24 * 60 * 60 * 1000);
    }
    return 0;
}

async function registrarAuditoriaSelf(ref, payload) {
    try {
        await ref.collection("bloqueios_auditoria").add({
            ...payload,
            block_origin: "self",
            applied_at: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        console.warn("[entregador_perfil_operacional] auditoria:", e?.message || e);
    }
}

exports.entregadorAutoBloquearTemporario = onCall(CALL_OPTS, async (request) => {
    const uid = assertAuth(request);
    const db = admin.firestore();
    const { ref, data } = await assertEntregadorAprovadoSemCorrida(db, uid);

    if (entregadorBloqueadoOperacionalJs(data)) {
        throw new HttpsError(
            "failed-precondition",
            "Sua conta já está bloqueada. Use Desbloquear na Área de Perigo.",
        );
    }

    const ms = calcularDuracaoMs(request.data || {});
    if (ms <= 0) {
        throw new HttpsError(
            "invalid-argument",
            "Informe por quantos dias ou meses deseja pausar (mínimo 1 dia).",
        );
    }
    if (ms > 365 * 24 * 60 * 60 * 1000) {
        throw new HttpsError("invalid-argument", "Período máximo: 12 meses.");
    }

    const motivoTexto = String((request.data || {}).motivo || "").trim().slice(0, 500);
    const end = admin.firestore.Timestamp.fromDate(new Date(Date.now() + ms));

    await ref.update({
        entregador_status: "bloqueio_temporario",
        entregador_perfil_operacional: PERFIL.BLOQ_TEMP,
        status_conta: "BLOCKED",
        block_active: true,
        block_type: "BLOCK_TEMPORARY",
        block_reason: BR.PAUSA_TEMPORARIA,
        block_origin: "self",
        block_start_at: admin.firestore.FieldValue.serverTimestamp(),
        block_end_at: end,
        motivo_bloqueio:
            motivoTexto ||
            "Pausa temporária solicitada pelo entregador",
        is_online: false,
        recusa_cadastro: admin.firestore.FieldValue.delete(),
    });

    await registrarAuditoriaSelf(ref, {
        action: "self_block_temporary",
        entregador_nome: data.nome || data.nome_completo || "",
        duration_ms: ms,
        motivo: motivoTexto || null,
    });

    return { ok: true, block_end_at: end.toMillis() };
});

exports.entregadorAutoBloquearDefinitivo = onCall(CALL_OPTS, async (request) => {
    const uid = assertAuth(request);
    const db = admin.firestore();
    const { ref, data } = await assertEntregadorAprovadoSemCorrida(db, uid);

    if (entregadorBloqueadoOperacionalJs(data)) {
        throw new HttpsError(
            "failed-precondition",
            "Sua conta já está bloqueada. Use Desbloquear na Área de Perigo.",
        );
    }

    const motivoTexto = String((request.data || {}).motivo || "").trim().slice(0, 500);

    await ref.update({
        entregador_status: "bloqueado",
        entregador_perfil_operacional: PERFIL.BLOQ_DEF,
        status_conta: "BLOCKED",
        block_active: true,
        block_type: "BLOCK_FULL",
        block_reason: BR.PAUSA_DEFINITIVA,
        block_origin: "self",
        block_start_at: admin.firestore.FieldValue.serverTimestamp(),
        block_end_at: admin.firestore.FieldValue.delete(),
        motivo_bloqueio:
            motivoTexto ||
            "Bloqueio por tempo indeterminado solicitado pelo entregador",
        is_online: false,
        recusa_cadastro: admin.firestore.FieldValue.delete(),
    });

    await registrarAuditoriaSelf(ref, {
        action: "self_block_permanent",
        entregador_nome: data.nome || data.nome_completo || "",
        motivo: motivoTexto || null,
    });

    return { ok: true };
});

exports.entregadorSolicitarExclusaoPerfil = onCall(CALL_OPTS, async (request) => {
    const uid = assertAuth(request);
    const db = admin.firestore();
    const { ref, data } = await assertEntregadorAprovadoSemCorrida(db, uid);

    if (entregadorBloqueadoOperacionalJs(data)) {
        throw new HttpsError(
            "failed-precondition",
            "Conta já bloqueada. Se já solicitou exclusão, aguarde o prazo de 30 dias.",
        );
    }

    const now = new Date();
    const efetiva = new Date(now.getTime() + DIAS_EXCLUSAO * 24 * 60 * 60 * 1000);
    const tsNow = admin.firestore.Timestamp.fromDate(now);
    const tsEfetiva = admin.firestore.Timestamp.fromDate(efetiva);

    await ref.update({
        entregador_status: "bloqueado",
        entregador_perfil_operacional: PERFIL.EXCLUSAO,
        status_conta: "BLOCKED",
        block_active: true,
        block_type: "BLOCK_FULL",
        block_reason: BR.EXCLUSAO_PERFIL,
        block_origin: "self",
        block_start_at: admin.firestore.FieldValue.serverTimestamp(),
        block_end_at: admin.firestore.FieldValue.delete(),
        motivo_bloqueio: "Solicitação de exclusão do perfil de entregador",
        entregador_exclusao_perfil_solicitada_em: tsNow,
        entregador_exclusao_perfil_em: tsEfetiva,
        entregador_reingresso_bloqueado_ate: tsEfetiva,
        is_online: false,
        recusa_cadastro: admin.firestore.FieldValue.delete(),
    });

    await registrarAuditoriaSelf(ref, {
        action: "self_delete_profile_request",
        entregador_nome: data.nome || data.nome_completo || "",
        exclusao_em: efetiva.toISOString(),
    });

    return {
        ok: true,
        exclusao_efetiva_em: efetiva.getTime(),
        dias_restantes: DIAS_EXCLUSAO,
    };
});

exports.entregadorAutoDesbloquearConta = onCall(CALL_OPTS, async (request) => {
    const uid = assertAuth(request);
    const db = admin.firestore();
    const ref = db.collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new HttpsError("not-found", "Perfil não encontrado.");
    }
    const d = snap.data() || {};
    if (!docIndicaEntregador(d)) {
        throw new HttpsError("failed-precondition", "Conta não é de entregador.");
    }

    const reason = String(d.block_reason || "");
    if (reason === BR.EXCLUSAO_PERFIL) {
        throw new HttpsError(
            "failed-precondition",
            "Exclusão do perfil em andamento. O desbloqueio não está disponível.",
        );
    }
    if (String(d.block_origin || "") !== "self" || !motivoPermiteDesbloqueioSelf(reason)) {
        throw new HttpsError(
            "failed-precondition",
            "Este bloqueio só pode ser removido pelo suporte ou pelo painel administrativo.",
        );
    }
    if (!entregadorBloqueadoOperacionalJs(d)) {
        return { ok: true, ja_ativo: true };
    }

    await ref.update({
        entregador_status: "aprovado",
        entregador_perfil_operacional: PERFIL.ATIVO,
        status_conta: "ACTIVE",
        block_active: false,
        block_type: admin.firestore.FieldValue.delete(),
        block_reason: admin.firestore.FieldValue.delete(),
        block_origin: admin.firestore.FieldValue.delete(),
        block_start_at: admin.firestore.FieldValue.delete(),
        block_end_at: admin.firestore.FieldValue.delete(),
        motivo_bloqueio: admin.firestore.FieldValue.delete(),
    });

    await registrarAuditoriaSelf(ref, {
        action: "self_unblock",
        entregador_nome: d.nome || d.nome_completo || "",
        previous_reason: reason,
    });

    return { ok: true };
});

/** Remove apenas o perfil de entregador após 30 dias; mantém conta (role=cliente) e histórico. */
async function removerPerfilEntregadorDoc(ref, d) {
    const nome = d.nome || d.nome_completo || "";
    await ref.update({
        role: "cliente",
        entregador_status: admin.firestore.FieldValue.delete(),
        entregador_perfil_operacional: PERFIL.REMOVIDO,
        entregador_perfil_removido_em: admin.firestore.FieldValue.serverTimestamp(),
        plano_entregador_id: admin.firestore.FieldValue.delete(),
        veiculoTipo: admin.firestore.FieldValue.delete(),
        veiculo_ativo_id: admin.firestore.FieldValue.delete(),
        is_online: false,
        block_active: false,
        status_conta: "ACTIVE",
        block_type: admin.firestore.FieldValue.delete(),
        block_reason: admin.firestore.FieldValue.delete(),
        block_origin: admin.firestore.FieldValue.delete(),
        block_start_at: admin.firestore.FieldValue.delete(),
        block_end_at: admin.firestore.FieldValue.delete(),
        motivo_bloqueio: admin.firestore.FieldValue.delete(),
        entregador_exclusao_perfil_solicitada_em: admin.firestore.FieldValue.delete(),
        entregador_exclusao_perfil_em: admin.firestore.FieldValue.delete(),
    });

    await registrarAuditoriaSelf(ref, {
        action: "profile_removed_after_waiting_period",
        entregador_nome: nome,
    });
}

exports.processarExclusoesPerfilEntregador = functionsV1.pubsub
    .schedule("every day 04:30")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const snap = await db
            .collection("users")
            .where("entregador_perfil_operacional", "==", PERFIL.EXCLUSAO)
            .where("entregador_exclusao_perfil_em", "<=", now)
            .limit(200)
            .get();

        let processados = 0;
        for (const doc of snap.docs) {
            const d = doc.data() || {};
            if (String(d.block_reason || "") !== BR.EXCLUSAO_PERFIL) continue;
            try {
                await removerPerfilEntregadorDoc(doc.ref, d);
                processados += 1;
            } catch (e) {
                console.error(
                    `[exclusao_perfil_entregador] ${doc.id}:`,
                    e?.message || e,
                );
            }
        }
        console.log(
            `[exclusao_perfil_entregador] Verificados: ${snap.size}. Perfis removidos: ${processados}.`,
        );
        return null;
    });
