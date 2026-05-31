"use strict";

/**
 * Push + histórico quando [entregador_perfil_operacional] muda (bloqueio,
 * exclusão solicitada ou reativação). Cobre ações do app e do painel admin.
 * Não altera payloads/canais existentes — mesmo padrão de
 * `entregador_status_notificacao.js` (high_importance_channel).
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const notificationDispatcher = require("./notification_dispatcher");

const PERFIL = {
    ATIVO: "ativo",
    BLOQ_TEMP: "bloqueado_temporario",
    BLOQ_DEF: "bloqueado_definitivo",
    EXCLUSAO: "exclusao_solicitada",
};

const EVENTO = {
    BLOQ_TEMP: "bloqueado_temporario",
    BLOQ_DEF: "bloqueado_definitivo",
    EXCLUSAO: "exclusao_solicitada",
    REATIVADO: "reativado",
};

const LOGO_DIPERTIN_URL = "https://www.dipertin.com.br/assets/logo.png";

function docIndicaEntregador(d) {
    if (!d) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(d[k] || "").toLowerCase().trim() === "entregador") return true;
    }
    return false;
}

function normalizarPerfil(v) {
    return String(v || "").trim().toLowerCase();
}

function eraBloqueioOperacionalPerfil(perfilAntes, antes) {
    const pa = normalizarPerfil(perfilAntes);
    if (
        pa === PERFIL.BLOQ_TEMP ||
        pa === PERFIL.BLOQ_DEF ||
        pa === PERFIL.EXCLUSAO
    ) {
        return true;
    }
    if (!antes || !docIndicaEntregador(antes)) return false;
    if (antes.block_active === true) return true;
    const st = String(antes.entregador_status || "").toLowerCase();
    return st === "bloqueio_temporario" || st === "bloqueado" || st === "bloqueada";
}

function detectarEventoPerfil(perfilAntes, perfilDepois, antes) {
    const pd = normalizarPerfil(perfilDepois);
    if (!pd || pd === normalizarPerfil(perfilAntes)) return "";

    if (pd === PERFIL.BLOQ_TEMP) return EVENTO.BLOQ_TEMP;
    if (pd === PERFIL.BLOQ_DEF) return EVENTO.BLOQ_DEF;
    if (pd === PERFIL.EXCLUSAO) return EVENTO.EXCLUSAO;
    if (pd === PERFIL.ATIVO && eraBloqueioOperacionalPerfil(perfilAntes, antes)) {
        return EVENTO.REATIVADO;
    }
    return "";
}

function conteudoNotificacao(evento) {
    switch (evento) {
        case EVENTO.BLOQ_TEMP:
            return {
                titulo: "Conta bloqueada temporariamente",
                corpo:
                    "Sua conta foi bloqueada temporariamente. Verifique as informações no seu painel.",
                type: "ENTREGADOR_PERFIL_BLOQUEIO_TEMPORARIO",
                tipoNotificacao: "entregador_perfil_bloqueio_temporario",
                destino: "painel_bloqueio",
            };
        case EVENTO.BLOQ_DEF:
            return {
                titulo: "Conta bloqueada",
                corpo:
                    "Seu perfil de entregador foi bloqueado. Verifique as informações no seu painel.",
                type: "ENTREGADOR_PERFIL_BLOQUEIO_DEFINITIVO",
                tipoNotificacao: "entregador_perfil_bloqueio_definitivo",
                destino: "painel_bloqueio",
            };
        case EVENTO.EXCLUSAO:
            return {
                titulo: "Conta de entregador excluída",
                corpo: "Sua solicitação de exclusão foi recebida com sucesso.",
                type: "ENTREGADOR_PERFIL_EXCLUSAO_SOLICITADA",
                tipoNotificacao: "entregador_perfil_exclusao_solicitada",
                destino: "painel_bloqueio_exclusao",
            };
        case EVENTO.REATIVADO:
            return {
                titulo: "Conta reativada",
                corpo: "Seu perfil de entregador foi reativado com sucesso.",
                type: "ENTREGADOR_PERFIL_REATIVADO",
                tipoNotificacao: "entregador_perfil_reativado",
                destino: "radar",
            };
        default:
            return null;
    }
}

function chaveIdempotencia(uid, evento, perfilAntes, perfilDepois, depois) {
    if (evento === EVENTO.REATIVADO) {
        return `perfil_entregador_${uid}_reativado_${normalizarPerfil(perfilAntes)}_${normalizarPerfil(perfilDepois)}`;
    }
    const start = depois.block_start_at;
    let startSec = 0;
    if (start && typeof start.toDate === "function") {
        startSec = Math.floor(start.toDate().getTime() / 1000);
    } else if (start && start._seconds != null) {
        startSec = start._seconds;
    }
    return `perfil_entregador_${uid}_${evento}_${startSec}`;
}

async function persistirHistorico(db, uid, titulo, corpo, tipoNotificacao, segmento, dados, idempotenciaChave) {
    try {
        const items = db
            .collection("notificacoes_usuario")
            .doc(uid)
            .collection("items");
        const dup = await items
            .where("idempotencia_chave", "==", idempotenciaChave)
            .limit(1)
            .get();
        if (!dup.empty) return false;

        await items.add({
            titulo: String(titulo || "").slice(0, 200),
            corpo: String(corpo || "").slice(0, 500),
            tipo_notificacao: tipoNotificacao,
            segmento,
            dados: notificationDispatcher.dataSoStrings(dados),
            idempotencia_chave: idempotenciaChave,
            origem: "cloud_function_perfil_entregador",
            lida: false,
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
    } catch (e) {
        console.warn(
            `[entregador-perfil-notif] historico uid=${uid}:`,
            e?.message || e,
        );
        return false;
    }
}

async function enviarPushPerfilOperacional(db, uid, evento, conteudo, idempotenciaChave) {
    const { token, ok } = await notificationDispatcher.obterTokenValidado(
        db,
        uid,
        "entregador",
    );
    if (!ok || !token) return false;

    const data = notificationDispatcher.dataSoStrings({
        type: conteudo.type,
        tipoNotificacao: conteudo.tipoNotificacao,
        segmento: "entregador",
        evento,
        destino_entregador: conteudo.destino,
        idempotencia_chave: idempotenciaChave,
    });

    await admin.messaging().send({
        notification: {
            title: conteudo.titulo,
            body: conteudo.corpo,
            imageUrl: LOGO_DIPERTIN_URL,
        },
        android: {
            priority: "high",
            collapseKey: `entregador_perfil_${evento}_${uid}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
                imageUrl: LOGO_DIPERTIN_URL,
            },
        },
        apns: {
            headers: {
                "apns-priority": "10",
                "apns-push-type": "alert",
            },
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
        data,
        token,
    });

    return true;
}

exports.onEntregadorPerfilOperacionalAtualizado = functions.firestore
    .document("users/{uid}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};

        if (!docIndicaEntregador(depois)) return null;

        const perfilAntes = antes.entregador_perfil_operacional;
        const perfilDepois = depois.entregador_perfil_operacional;

        const evento = detectarEventoPerfil(perfilAntes, perfilDepois, antes);
        if (!evento) return null;

        const conteudo = conteudoNotificacao(evento);
        if (!conteudo) return null;

        const uid = context.params.uid;
        const idempotenciaChave = chaveIdempotencia(
            uid,
            evento,
            perfilAntes,
            perfilDepois,
            depois,
        );

        if (
            String(depois.notif_perfil_entregador_idempotencia || "") ===
            idempotenciaChave
        ) {
            console.log(
                `[entregador-perfil-notif] idempotência uid=${uid} evento=${evento}`,
            );
            return null;
        }

        const db = admin.firestore();
        console.log(
            `[entregador-perfil-notif] evento=${evento} uid=${uid} perfil=${normalizarPerfil(perfilDepois)}`,
        );

        let pushOk = false;
        let historicoOk = false;
        try {
            pushOk = await enviarPushPerfilOperacional(
                db,
                uid,
                evento,
                conteudo,
                idempotenciaChave,
            );
        } catch (e) {
            console.error(
                `[entregador-perfil-notif] Falha push uid=${uid}:`,
                e?.message || e,
            );
        }

        try {
            historicoOk = await persistirHistorico(
                db,
                uid,
                conteudo.titulo,
                conteudo.corpo,
                conteudo.tipoNotificacao,
                "entregador",
                {
                    type: conteudo.type,
                    tipoNotificacao: conteudo.tipoNotificacao,
                    segmento: "entregador",
                    evento,
                    destino_entregador: conteudo.destino,
                },
                idempotenciaChave,
            );
        } catch (e) {
            console.warn(
                `[entregador-perfil-notif] Falha histórico uid=${uid}:`,
                e?.message || e,
            );
        }

        try {
            await change.after.ref.set(
                {
                    notif_perfil_entregador_ultimo_evento: evento,
                    notif_perfil_entregador_em:
                        admin.firestore.FieldValue.serverTimestamp(),
                    notif_perfil_entregador_push_ok: pushOk,
                    notif_perfil_entregador_historico_ok: historicoOk,
                    notif_perfil_entregador_idempotencia: idempotenciaChave,
                },
                { merge: true },
            );
        } catch (e) {
            console.warn(
                `[entregador-perfil-notif] Falha auditoria uid=${uid}:`,
                e?.message || e,
            );
        }

        return null;
    });

/** Usado por `entregador_status_notificacao.js` para não enviar "Conta aprovada" na reativação. */
exports.eraBloqueioOperacionalPerfilParaNotificacao = eraBloqueioOperacionalPerfil;
