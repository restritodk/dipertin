// Arquivo: functions/fiscal_entregador.js
//
// Fase 4 — Informações fiscais do entregador.
//
// Trigger onUpdate em `pedidos/{pedidoId}`. Quando o pedido transita para
// `entregue` (e já possui `financeiro_version`), agrega os valores da corrida
// em:
//   fiscal/{uid}                           — doc-raiz com `ano_atual`
//   fiscal/{uid}/anos/{ano}                — agregado anual
//   fiscal/{uid}/anos/{ano}/meses/{mm}     — agregado mensal
//
// Campos agregados: `ganhos_brutos`, `taxas`, `liquido`, `corridas`.
//
// Idempotência: flag `fiscal_registrado: true` no próprio pedido. Retries do
// trigger que já foi aplicado caem fora (não dobra valor). Essa checagem é
// feita em transação, garantindo atomicidade do incremento + flag.

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

function num(v) {
    if (v == null || v === "") return 0;
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
}

function mmPad(mes) {
    return String(mes).padStart(2, "0");
}

async function agregarFiscal(db, pedidoRef, pedidoId, pedido) {
    const entregadorId = String(pedido.entregador_id || "").trim();
    if (!entregadorId) return null;

    // Data de referência: prioriza `entregue_em`, cai pra `data_entrega` e,
    // por fim, `now()` (edge case em pedidos sem timestamp).
    let dataRef = null;
    if (pedido.entregue_em && pedido.entregue_em.toDate) {
        dataRef = pedido.entregue_em.toDate();
    } else if (pedido.data_entrega && pedido.data_entrega.toDate) {
        dataRef = pedido.data_entrega.toDate();
    } else {
        dataRef = new Date();
    }
    const ano = dataRef.getFullYear();
    const mes = dataRef.getMonth() + 1;

    const liquido = num(pedido.valor_liquido_entregador);
    // Ganhos brutos do entregador = taxa de entrega original (antes da comissão
    // da plataforma sobre o frete).
    const brutos = num(pedido.taxa_entrega);
    // Taxa (comissão da plataforma sobre a parte do entregador).
    const taxas = num(pedido.taxa_entregador);

    // Se nada veio, nada a agregar (evita doc "vazio" se o pedido foi
    // cancelado depois da entrega ou se a versão financeira não rodou).
    if (liquido <= 0 && brutos <= 0 && taxas <= 0) return null;

    const rootRef = db.collection("fiscal").doc(entregadorId);
    const anoRef = rootRef.collection("anos").doc(String(ano));
    const mesRef = anoRef.collection("meses").doc(mmPad(mes));

    await db.runTransaction(async (tx) => {
        const pedSnap = await tx.get(pedidoRef);
        const p = pedSnap.data() || {};
        if (p.fiscal_registrado === true) {
            // Idempotência: já foi contabilizado.
            return;
        }

        const patch = {
            ganhos_brutos: admin.firestore.FieldValue.increment(brutos),
            taxas: admin.firestore.FieldValue.increment(taxas),
            liquido: admin.firestore.FieldValue.increment(liquido),
            corridas: admin.firestore.FieldValue.increment(1),
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        };

        tx.set(rootRef, {
            ano_atual: ano,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(anoRef, patch, {merge: true});
        tx.set(mesRef, patch, {merge: true});

        tx.update(pedidoRef, {
            fiscal_registrado: true,
            fiscal_registrado_em: admin.firestore.FieldValue.serverTimestamp(),
            fiscal_ano: ano,
            fiscal_mes: mmPad(mes),
        });
    });

    return {entregadorId, ano, mes, brutos, taxas, liquido};
}

exports.agregarFiscalEntregadorOnEntrega = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const sa = String(antes.status || "");
        const sd = String(depois.status || "");
        if (sd !== "entregue" || sa === "entregue") return null;

        // Precisa ter pelo menos financeiro v2 rodado pra ter certeza que os
        // campos `valor_liquido_entregador` e `taxa_entregador` estão ok.
        const finVer = Number(depois.financeiro_version || 0);
        if (!finVer) {
            console.log(
                `[fiscal] pedido ${context.params.pedidoId} sem financeiro_version, pulando`,
            );
            return null;
        }

        const db = admin.firestore();
        try {
            const res = await agregarFiscal(
                db,
                change.after.ref,
                context.params.pedidoId,
                depois,
            );
            if (res) {
                console.log(
                    `[fiscal] entregador=${res.entregadorId} ${res.ano}/${res.mes} ` +
                    `+bruto=${res.brutos.toFixed(2)} ` +
                    `+taxa=${res.taxas.toFixed(2)} ` +
                    `+liquido=${res.liquido.toFixed(2)}`,
                );
            }
        } catch (e) {
            console.error(
                `[fiscal] pedido ${context.params.pedidoId}:`,
                e.message || e,
            );
        }
        return null;
    });

exports.agregarFiscal = agregarFiscal;
