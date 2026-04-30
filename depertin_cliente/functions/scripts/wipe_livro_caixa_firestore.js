/**
 * Limpa lançamentos do Livro Caixa (Firestore) para ambiente de teste → produção limpa.
 *
 * SEMPRE apaga (com confirmação):
 *   - receitas_app     (receitas manuais + espelhos util_* dos anúncios)
 *   - despesas_app     (saídas registradas no painel)
 *
 * Opcional (DIPERTIN_WIPE_ANUNCIOS_VALORES=SIM):
 *   Remove campos financeiros dos docs em servicos_destaque, telefones_premium,
 *   eventos, vagas, achados, banners (anúncios permanecem; só zera cobrança).
 *
 * NÃO apaga: pedidos, users, produtos, chat, FCM, saques_solicitacoes, estornos.
 * Comissões/taxas no painel vêm de pedidos ENTREGUES — se ainda existirem, o KPI
 * "Comissões / Taxas" continuará > 0 até apagares ou usares projeto Firestore vazio.
 *
 * Uso (PowerShell, pasta depertin_cliente/functions):
 *   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 *   $env:DIPERTIN_CONFIRM_WIPE_CAIXA="SIM"
 *   # opcional: também zerar valores nos anúncios
 *   $env:DIPERTIN_WIPE_ANUNCIOS_VALORES="SIM"
 *   npm run wipe:livro-caixa
 *
 * Dry-run (só lista contagens, não apaga):
 *   $env:DIPERTIN_WIPE_DRY_RUN="SIM"
 *   $env:DIPERTIN_CONFIRM_WIPE_CAIXA="SIM"
 */

const admin = require('firebase-admin');

const CONFIRM = (process.env.DIPERTIN_CONFIRM_WIPE_CAIXA || '').trim().toUpperCase();
const DRY = (process.env.DIPERTIN_WIPE_DRY_RUN || '').trim().toUpperCase() === 'SIM';
const WIPE_ANUNCIOS = (process.env.DIPERTIN_WIPE_ANUNCIOS_VALORES || '')
  .trim()
  .toUpperCase() === 'SIM';

const BATCH_DEL = 400;
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'depertin-f940f';

const ANUNCIOS_COLECOES = [
  'servicos_destaque',
  'telefones_premium',
  'eventos',
  'vagas',
  'achados',
  'banners',
];

const CAMPOS_FINANCEIROS = [
  'valor_total',
  'valor_diario',
  'valor_mensal',
  'valor',
  'valor_unitario',
  'modalidade_valor',
  'gera_receita',
  'qtd_dias',
  'qtd_dias_contratados',
  'nome_dono',
];

async function countCollection(db, name) {
  const agg = await db.collection(name).count().get();
  return agg.data().count;
}

async function deleteCollectionByChunks(db, name) {
  const ref = db.collection(name);
  let total = 0;

  if (DRY) {
    const n = await countCollection(db, name);
    console.log(`  [dry-run] apagaria ${n} documento(s) de ${name}`);
    return 0;
  }

  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await ref.limit(BATCH_DEL).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
    console.log(`  apagados ${snap.size} de ${name} (total parcial ${total})`);
  }
  return total;
}

async function limparCamposFinanceirosAnuncios(db) {
  const FieldValue = admin.firestore.FieldValue;
  let docsAtualizados = 0;

  for (const col of ANUNCIOS_COLECOES) {
    const snap = await db.collection(col).get();
    if (snap.empty) {
      console.log(`  ${col}: 0 documentos.`);
      continue;
    }

    if (DRY) {
      console.log(`  [dry-run] atualizaria ${snap.size} doc(s) em ${col} (zerar financeiro)`);
      docsAtualizados += snap.size;
      continue;
    }

    for (let i = 0; i < snap.docs.length; i += BATCH_DEL) {
      const chunk = snap.docs.slice(i, i + BATCH_DEL);
      const batch = db.batch();
      for (const doc of chunk) {
        const patch = { gera_receita: false };
        for (const campo of CAMPOS_FINANCEIROS) {
          if (campo === 'gera_receita') continue;
          patch[campo] = FieldValue.delete();
        }
        batch.update(doc.ref, patch);
      }
      await batch.commit();
      docsAtualizados += chunk.length;
      console.log(`  ${col}: removidos campos financeiros de ${chunk.length} doc(s).`);
    }
  }

  return docsAtualizados;
}

async function main() {
  if (CONFIRM !== 'SIM' && CONFIRM !== 'YES') {
    console.error(
      'Recusado: define DIPERTIN_CONFIRM_WIPE_CAIXA=SIM (ou YES) para executar.',
    );
    process.exit(1);
  }

  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID });
  }

  const db = admin.firestore();

  console.log(`Projeto: ${PROJECT_ID}`);
  console.log(`Modo: ${DRY ? 'DRY-RUN (não grava)' : 'EXECUÇÃO REAL'}`);
  console.log(`Zerar valores nos anúncios: ${WIPE_ANUNCIOS ? 'SIM' : 'NÃO'}\n`);

  const nRec = await countCollection(db, 'receitas_app');
  const nDesp = await countCollection(db, 'despesas_app');
  console.log(`Contagem atual: receitas_app=${nRec}, despesas_app=${nDesp}\n`);

  if (!DRY) {
    await deleteCollectionByChunks(db, 'receitas_app');
    await deleteCollectionByChunks(db, 'despesas_app');
    console.log('\nColeções receitas_app e despesas_app processadas.');
  } else {
    await deleteCollectionByChunks(db, 'receitas_app');
    await deleteCollectionByChunks(db, 'despesas_app');
  }

  if (WIPE_ANUNCIOS) {
    console.log('\nLimpando campos financeiros nos anúncios...');
    await limparCamposFinanceirosAnuncios(db);
  }

  console.log('\nFeito. Se ainda vires comissões no painel, são de pedidos entregues em `pedidos`.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
