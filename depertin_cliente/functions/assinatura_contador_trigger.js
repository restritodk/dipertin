"use strict";

/**
 * Trigger Firestore + callable para gerenciar o contador `assinaturas_ativas`
 * nos planos (`modulos_planos/{planId}`).
 *
 * Trigger: atualiza o contador sempre que uma assinatura é criada/atualizada/excluída.
 * Callable: recalcula todos os contadores manualmente (backfill/auditoria).
 *
 * Status considerados "ativas": ativo, em_atraso, suspenso
 * Status não contados: cancelado, pagamento_pendente
 */

const functions = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const COLECAO_ASSINATURAS = "assinaturas_clientes";
const COLECAO_PLANOS = "modulos_planos";

const STATUS_ATIVO = ["ativo", "em_atraso", "suspenso"];

/**
 * Recalcula e atualiza o campo `assinaturas_ativas` no plano.
 */
async function atualizarContador(db, planId) {
    if (!planId) return;

    try {
        // Conta quantas assinaturas ativas existem para este plano
        const snap = await db
            .collection(COLECAO_ASSINATURAS)
            .where("plan_id", "==", planId)
            .where("status", "in", STATUS_ATIVO)
            .count()
            .get();

        const total = snap.count || 0;

        // Atualiza o contador no documento do plano
        await db.collection(COLECAO_PLANOS).doc(planId).update({
            assinaturas_ativas: total,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(
            "[assinatura-contador] Plano " + planId + ": assinaturas_ativas atualizado para " + total,
        );
    } catch (e) {
        console.warn("[assinatura-contador] Erro ao atualizar contador do plano " + planId + ":", e.message);
    }
}

/**
 * onWrite: dispara em qualquer escrita em assinaturas_clientes/{docId}.
 */
exports.atualizarContadorAssinaturasOnWrite = functions.firestore
    .document("assinaturas_clientes/{docId}")
    .onWrite(async (change, context) => {
        const db = admin.firestore();

        const antes = change.before.exists ? change.before.data() || {} : null;
        const depois = change.after.exists ? change.after.data() || {} : null;

        const planIdAntes = antes ? String(antes.plan_id || "") : "";
        const planIdDepois = depois ? String(depois.plan_id || "") : "";

        // Se o documento foi excluído
        if (!depois) {
            if (planIdAntes) {
                await atualizarContador(db, planIdAntes);
            }
            return null;
        }

        // Se o documento foi criado ou o plan_id mudou
        if (!antes || planIdAntes !== planIdDepois) {
            if (planIdAntes) {
                await atualizarContador(db, planIdAntes);
            }
            if (planIdDepois) {
                await atualizarContador(db, planIdDepois);
            }
            return null;
        }

        // Verificar se o status mudou (ativo ↔ cancelado)
        const statusAntes = String(antes.status || "");
        const statusDepois = String(depois.status || "");

        const antesEraAtivo = STATUS_ATIVO.includes(statusAntes);
        const depoisEAtivo = STATUS_ATIVO.includes(statusDepois);

        if (antesEraAtivo !== depoisEAtivo && planIdDepois) {
            await atualizarContador(db, planIdDepois);
        }

        return null;
    });

/**
 * Recalcula todos os planos de uma vez (backfill ou auditoria).
 */
async function recalcularTodosContadores(db) {
    const planosSnap = await db.collection(COLECAO_PLANOS).get();
    if (planosSnap.empty) {
        console.log("[assinatura-contador] Nenhum plano encontrado para recalcular.");
        return { ok: true, planos: 0 };
    }

    let processados = 0;
    for (const doc of planosSnap.docs) {
        const planId = doc.id;
        try {
            const snap = await db
                .collection(COLECAO_ASSINATURAS)
                .where("plan_id", "==", planId)
                .where("status", "in", STATUS_ATIVO)
                .count()
                .get();

            const total = snap.count || 0;

            await db.collection(COLECAO_PLANOS).doc(planId).update({
                assinaturas_ativas: total,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });

            processados++;
        } catch (e) {
            console.warn("[assinatura-contador] Erro ao recalcular plano " + planId + ":", e.message);
        }
    }

    console.log("[assinatura-contador] Recalculo concluído: " + processados + " planos processados.");
    return { ok: true, planos: processados };
}

/**
 * Callable v2: staff pode recalcular todos os contadores manualmente.
 */
exports.adminRecalcularContadoresAssinaturas = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 120 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Autenticação necessária.");
        }

        // Verificar se é staff
        const userSnap = await admin.firestore().collection("users").doc(request.auth.uid).get();
        if (!userSnap.exists) {
            throw new HttpsError("failed-precondition", "Perfil não encontrado.");
        }
        const userData = userSnap.data() || {};
        const role = String(userData.role || userData.tipoUsuario || "");
        const staffRoles = ["master", "master_city", "staff"];
        if (!staffRoles.includes(role.toLowerCase())) {
            throw new HttpsError("permission-denied", "Apenas administradores podem recalcular contadores.");
        }

        const db = admin.firestore();
        const resultado = await recalcularTodosContadores(db);

        return {
            ok: true,
            planosProcessados: resultado.planos || 0,
            mensagem: resultado.planos > 0
                ? resultado.planos + " planos atualizados."
                : "Nenhum plano encontrado.",
        };
    },
);
