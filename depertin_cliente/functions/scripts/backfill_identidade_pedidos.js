// Fase 3G.3 — backfill da identidade denormalizada em pedidos ativos.
//
// Propósito:
//   Pedidos criados ANTES desta fase não têm `cliente_nome`,
//   `cliente_foto_perfil` e `loja_foto`. Sem isso, após apertar a rule de
//   `users`, o lojista veria "Cliente" sem nome/foto nos pedidos ativos, e
//   futuras telas (entregador indo pro cliente) também ficariam sem info.
//
// Funcionamento:
//   - Varre `pedidos` e ignora os que estão em status final (entregue/cancelado).
//   - Para cada pedido ativo, lê `users/{cliente_id}` e `users/{loja_id}`
//     (Admin SDK bypassa rules) e preenche os campos denormalizados.
//   - Em dry-run (default) apenas imprime o que seria alterado.
//   - Com `--confirm` faz o commit.
//
// Uso:
//   node scripts/backfill_identidade_pedidos.js            # dry-run
//   node scripts/backfill_identidade_pedidos.js --confirm  # executa

const admin = require("firebase-admin");
const {
    STATUS_PEDIDO_FINALIZADO,
    extrairIdentidadeUser,
    melhorFotoLoja,
    nomeLoja,
    telefoneLoja,
} = require("../sincronizar_identidade_pedidos");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";
const CONFIRMAR = process.argv.includes("--confirm");
const BATCH_SIZE = 400;

async function preCarregarUsers(db, uids) {
    const unicos = Array.from(new Set(uids.filter((u) => u && u.length > 0)));
    const mapa = new Map();
    for (let i = 0; i < unicos.length; i += 10) {
        const lote = unicos.slice(i, i + 10);
        const snaps = await Promise.all(
            lote.map((u) => db.collection("users").doc(u).get()),
        );
        snaps.forEach((snap, idx) => {
            mapa.set(lote[idx], snap.exists ? snap.data() : null);
        });
    }
    return mapa;
}

async function main() {
    admin.initializeApp({projectId: PROJECT_ID});
    const db = admin.firestore();
    console.log(
        `[backfill_identidade_pedidos] projeto=${PROJECT_ID} confirmar=${CONFIRMAR}`,
    );

    const snap = await db.collection("pedidos").get();
    console.log(`Encontrados ${snap.size} pedido(s). Filtrando ativos...`);

    const pedidosAtivos = snap.docs.filter((d) => {
        const s = (d.data().status || "").toString();
        return !STATUS_PEDIDO_FINALIZADO.includes(s);
    });
    console.log(`${pedidosAtivos.length} pedido(s) ativo(s) para processar.`);

    const uidsClientes = pedidosAtivos.map((d) => d.data().cliente_id || "");
    const uidsLojas = pedidosAtivos.map((d) => d.data().loja_id || "");
    const usersClientes = await preCarregarUsers(db, uidsClientes);
    const usersLojas = await preCarregarUsers(db, uidsLojas);

    let atualizados = 0;
    let naoPrecisa = 0;
    let batch = db.batch();
    let operacoesNoBatch = 0;

    for (const doc of pedidosAtivos) {
        const data = doc.data() || {};
        const clienteId = (data.cliente_id || "").toString();
        const lojaId = (data.loja_id || "").toString();

        const clienteData = usersClientes.get(clienteId);
        const lojaData = usersLojas.get(lojaId);

        const patch = {};

        if (clienteData) {
            const id = extrairIdentidadeUser(clienteData);
            if ((data.cliente_nome || "") !== id.nome && id.nome) {
                patch.cliente_nome = id.nome;
            }
            if (
                (data.cliente_foto_perfil || "") !== id.fotoCliente &&
                id.fotoCliente
            ) {
                patch.cliente_foto_perfil = id.fotoCliente;
            }
            if ((data.cliente_telefone || "") !== id.telefone && id.telefone) {
                patch.cliente_telefone = id.telefone;
            }
        }

        if (lojaData) {
            const fotoLoja = melhorFotoLoja(lojaData);
            const nLoja = nomeLoja(lojaData);
            const telLoja = telefoneLoja(lojaData);
            if ((data.loja_foto || "") !== fotoLoja && fotoLoja) {
                patch.loja_foto = fotoLoja;
            }
            if ((data.loja_nome || "") !== nLoja && nLoja) {
                patch.loja_nome = nLoja;
            }
            if ((data.loja_telefone || "") !== telLoja && telLoja) {
                patch.loja_telefone = telLoja;
            }
        }

        if (Object.keys(patch).length === 0) {
            naoPrecisa++;
            continue;
        }

        if (CONFIRMAR) {
            batch.update(doc.ref, patch);
            operacoesNoBatch++;
            if (operacoesNoBatch >= BATCH_SIZE) {
                await batch.commit();
                batch = db.batch();
                operacoesNoBatch = 0;
            }
        }
        atualizados++;
        console.log(
            `[${doc.id}] ${Object.keys(patch).join(", ")} ` +
                `(cliente=${clienteId.slice(0, 6)}, loja=${lojaId.slice(0, 6)})`,
        );
    }

    if (CONFIRMAR && operacoesNoBatch > 0) {
        await batch.commit();
    }

    console.log("\nResumo:");
    console.log(`  Ativos inspecionados : ${pedidosAtivos.length}`);
    console.log(`  A atualizar          : ${atualizados}`);
    console.log(`  Já OK                : ${naoPrecisa}`);
    if (!CONFIRMAR) {
        console.log(
            "\n(dry-run — nada foi gravado. Rode com --confirm pra aplicar.)",
        );
    }
}

main().catch((e) => {
    console.error("Falhou:", e);
    process.exit(1);
});
