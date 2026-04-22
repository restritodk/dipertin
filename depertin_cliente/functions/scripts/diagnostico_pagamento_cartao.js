/**
 * Diagnóstico: lista os últimos pedidos com tentativa de pagamento por cartão
 * e mostra o motivo de recusa exato gravado no Firestore.
 *
 * Uso: node scripts/diagnostico_pagamento_cartao.js [limite]
 * Exemplo: node scripts/diagnostico_pagamento_cartao.js 20
 */
const admin = require("firebase-admin");
const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";

async function main() {
    if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
    const db = admin.firestore();

    const limite = Number(process.argv[2] || 20);

    // Descobre nome do campo de data (criado_em, created_at, data_criacao, etc.).
    const sampleSnap = await db.collection("pedidos").limit(1).get();
    if (sampleSnap.empty) {
        console.log("Sem pedidos no banco.");
        return;
    }
    const sample = sampleSnap.docs[0].data() || {};
    const campoData = [
        "criado_em",
        "created_at",
        "createdAt",
        "data_criacao",
        "data_pedido",
        "mp_atualizado_em",
    ].find((c) => sample[c]);
    console.log(`[diag] Usando campo de ordenação: ${campoData || "(sem ordenação)"}`);

    const queryBase = db.collection("pedidos");
    const s = campoData
        ? await queryBase.orderBy(campoData, "desc").limit(limite * 5).get()
        : await queryBase.limit(limite * 5).get();
    const docs = s.docs.filter((d) => {
        const v = d.data() || {};
        const metodo = String(v.metodo_pagamento || v.pagamento_metodo || "").toLowerCase();
        const tipoCart = String(v.pagamento_cartao_tipo_solicitado || "").toLowerCase();
        const tent = Array.isArray(v.pagamento_tentativas_historico) && v.pagamento_tentativas_historico.length > 0;
        return (
            tipoCart === "credito" ||
            tipoCart === "debito" ||
            metodo.includes("cart") ||
            metodo === "cartao" ||
            tent
        );
    }).slice(0, limite);
    const snap = { docs };

    console.log(`\n=== Últimas ${snap.docs.length} tentativas de pagamento por cartão ===\n`);
    for (const doc of snap.docs) {
        const d = doc.data() || {};
        const criadoEm = d.criado_em?.toDate?.()
            ? d.criado_em.toDate().toISOString()
            : "—";
        console.log("----------------------------------------");
        console.log(`Pedido: ${doc.id}`);
        console.log(`Criado: ${criadoEm}`);
        console.log(`Cliente UID: ${d.cliente_uid || d.user_id || "—"}`);
        console.log(`Valor total: R$ ${Number(d.valor_total || d.total || 0).toFixed(2)}`);
        console.log(`Status pedido: ${d.status || "—"}`);
        console.log(`MP status: ${d.mp_status || d.status_pagamento_mp || "—"}`);
        console.log(`MP status_detail: ${d.mp_erro_detalhe || "—"}`);
        console.log(`Recusa código: ${d.pagamento_recusado_codigo || "—"}`);
        console.log(`Recusa mensagem: ${d.pagamento_recusado_mensagem || "—"}`);
        console.log(`Tipo solicitado: ${d.pagamento_cartao_tipo_solicitado || "—"}`);
        console.log(`Bandeira MP: ${d.pagamento_cartao_bandeira_mp || "—"}`);
        console.log(`Tipo MP: ${d.pagamento_cartao_tipo_mp || "—"}`);

        // Tentativas registradas.
        const tentativas = Array.isArray(d.pagamento_tentativas_historico)
            ? d.pagamento_tentativas_historico
            : [];
        if (tentativas.length) {
            console.log(`Tentativas (${tentativas.length}):`);
            for (const t of tentativas.slice(-5)) {
                const when = t.em?.toDate?.()
                    ? t.em.toDate().toISOString()
                    : (t.em || "");
                console.log(
                    `  • ${when} | etapa=${t.etapa} status=${t.status} ` +
                    `| ${t.erro || t.erro_codigo || t.payment_method || ""}`,
                );
            }
        }
    }
    console.log("----------------------------------------\n");
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
