// Fase 4 — backfill das informações fiscais do entregador.
//
// Propósito:
//   Agregar os campos `ganhos_brutos`, `taxas`, `liquido` e `corridas` em
//   `fiscal/{entregadorId}/anos/{ano}` e `.../meses/{mm}` a partir do histórico
//   de pedidos já `entregues`. Usado para popular os totais existentes
//   (pedidos criados antes do trigger `agregarFiscalEntregadorOnEntrega`).
//
// Funcionamento:
//   - Varre pedidos com `status == 'entregue'` e `fiscal_registrado != true`.
//   - Aplica a mesma agregação da Cloud Function, idempotente via flag
//     `fiscal_registrado` no próprio pedido.
//   - Em dry-run (default) apenas imprime o que seria agregado. Com
//     `--confirm` executa a transação.
//
// Uso:
//   node scripts/backfill_fiscal_entregador.js            # dry-run
//   node scripts/backfill_fiscal_entregador.js --confirm  # executa

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";
const CONFIRMAR = process.argv.includes("--confirm");

async function main() {
    if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
    const db = admin.firestore();
    const {agregarFiscal} = require("../fiscal_entregador");

    console.log(
        `[backfill_fiscal_entregador] projeto=${PROJECT_ID} confirmar=${CONFIRMAR}`,
    );

    const snap = await db
        .collection("pedidos")
        .where("status", "==", "entregue")
        .get();
    console.log(`Encontrados ${snap.size} pedido(s) entregues.`);

    let processados = 0;
    let ignorados = 0;
    for (const doc of snap.docs) {
        const d = doc.data() || {};
        if (d.fiscal_registrado === true) {
            ignorados += 1;
            continue;
        }
        if (!d.entregador_id) {
            ignorados += 1;
            continue;
        }
        if (!CONFIRMAR) {
            console.log(
                `[dry-run] ${doc.id} entregador=${d.entregador_id} ` +
                `bruto=${Number(d.taxa_entrega || 0)} ` +
                `taxa=${Number(d.taxa_entregador || 0)} ` +
                `liquido=${Number(d.valor_liquido_entregador || 0)}`,
            );
            processados += 1;
            continue;
        }
        try {
            const r = await agregarFiscal(db, doc.ref, doc.id, d);
            if (r) {
                processados += 1;
                if (processados % 50 === 0) {
                    console.log(`  ...processados=${processados}`);
                }
            } else {
                ignorados += 1;
            }
        } catch (e) {
            console.error(`  erro pedido=${doc.id}:`, e.message || e);
        }
    }

    console.log(
        `Concluído. processados=${processados} ignorados=${ignorados}`,
    );
    process.exit(0);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
