"use strict";

/**
 * Script único de backfill: recalcula `assinaturas_ativas` em todos os planos.
 *
 * Uso:
 *   cd depertin_cliente/functions
 *   node scripts/recalcular_contadores_assinaturas.js
 *
 * Requer service account configurada via GOOGLE_APPLICATION_CREDENTIALS
 * ou firebase-admin via CLI autenticada.
 */

const admin = require("firebase-admin");

// Inicializa com a mesma config do Firebase CLI (ADC)
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();
const COLECAO_ASSINATURAS = "assinaturas_clientes";
const COLECAO_PLANOS = "modulos_planos";
const STATUS_ATIVO = ["ativo", "em_atraso", "suspenso"];

async function main() {
    console.log("=== Recalculando contadores de planos ===");

    const planosSnap = await db.collection(COLECAO_PLANOS).get();
    if (planosSnap.empty) {
        console.log("Nenhum plano encontrado.");
        process.exit(0);
    }

    let processados = 0;
    let erros = 0;

    for (const doc of planosSnap.docs) {
        const planId = doc.id;
        const planName = doc.data().nome || planId;

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

            console.log(`  ✅ ${planName}: ${total} assinatura(s) ativa(s)`);
            processados++;
        } catch (e) {
            console.error(`  ❌ ${planName}: erro - ${e.message}`);
            erros++;
        }
    }

    console.log(`\n=== Concluído: ${processados} planos processados, ${erros} erro(s) ===`);
    process.exit(erros > 0 ? 1 : 0);
}

main().catch((err) => {
    console.error("Erro fatal:", err);
    process.exit(1);
});
