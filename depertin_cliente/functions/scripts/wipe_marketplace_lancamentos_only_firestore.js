/**
 * ZERA apenas LANÇAMENTOS / histórico operacional financeiro dos perfis marketplace,
 * mantendo documentos users, Firebase Auth, produtos, lojas_public, endereços, veículos, etc.
 *
 * Remove:
 * - receitas_app, despesas_app (Livro Caixa)
 * - estornos (histórico no painel)
 * - pedidos (+ subcoleção mensagens) e avaliacoes (id pedido) envolvendo cliente/lojista/entregador
 * - saques_solicitacoes desses utilizadores
 * - fiscal/{uid} para entregadores (agregados por ano/mês)
 *
 * Ajusta saldo: define users.saldo = 0 para roles cliente, lojista, entregador
 * (após remover movimentos que alimentavam a carteira no app).
 *
 * NÃO remove: users, Auth, produtos, lojas_public, notificacoes_usuario, subcoleções de cadastro.
 *
 * Confirmação: DIPERTIN_CONFIRM_WIPE_LANCAMENTOS=SIM
 * Dry-run: DIPERTIN_WIPE_DRY_RUN=SIM
 *
 * cd depertin_cliente/functions
 * $env:GOOGLE_CLOUD_QUOTA_PROJECT="depertin-f940f"
 * $env:DIPERTIN_CONFIRM_WIPE_LANCAMENTOS="SIM"
 * npm run wipe:marketplace-lancamentos
 */

const admin = require('firebase-admin');

const CONFIRM = (process.env.DIPERTIN_CONFIRM_WIPE_LANCAMENTOS || '')
  .trim()
  .toUpperCase();
const DRY = (process.env.DIPERTIN_WIPE_DRY_RUN || '').trim().toUpperCase() === 'SIM';
const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'depertin-f940f';

const ROLES_MARKETPLACE = ['cliente', 'lojista', 'entregador'];
const BATCH = 400;

async function deleteQueryDocs(queryRef, label) {
  const fs = queryRef.firestore;
  let n = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await queryRef.limit(BATCH).get();
    if (snap.empty) break;
    if (DRY) {
      console.log(`  [dry-run] apagaria ${snap.size} doc(s) em ${label}`);
      n += snap.size;
      break;
    }
    const batch = fs.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    n += snap.size;
    console.log(`  apagados ${snap.size} (${label}), acumulado ${n}`);
  }
  return n;
}

async function wipeSubcollection(db, parentPath, subName, label) {
  const sub = db.doc(parentPath).collection(subName);
  return deleteQueryDocs(sub, label);
}

async function deleteFiscalEntregador(db, uid) {
  const root = db.collection('fiscal').doc(uid);
  const anos = await root.collection('anos').get();
  if (anos.empty) {
    if (!DRY) await root.delete().catch(() => {});
    return;
  }
  if (DRY) {
    console.log(`  [dry-run] fiscal/${uid}: ${anos.size} ano(s)`);
    return;
  }
  for (const adoc of anos.docs) {
    const meses = await adoc.ref.collection('meses').get();
    for (const m of meses.docs) await m.ref.delete();
    await adoc.ref.delete();
  }
  await root.delete().catch(() => {});
}

async function batchDeleteDocs(fs, docs, label) {
  if (!docs.length) return;
  if (DRY) {
    console.log(`  [dry-run] apagaria ${docs.length} em ${label}`);
    return;
  }
  for (let i = 0; i < docs.length; i += BATCH) {
    const chunk = docs.slice(i, i + BATCH);
    const batch = fs.batch();
    chunk.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    console.log(`  apagados ${chunk.length} (${label})`);
  }
}

async function main() {
  if (CONFIRM !== 'SIM' && CONFIRM !== 'YES') {
    console.error(
      'Recusado: define DIPERTIN_CONFIRM_WIPE_LANCAMENTOS=SIM (este script NÃO apaga users nem Auth).',
    );
    process.exit(1);
  }

  if (!process.env.GOOGLE_CLOUD_QUOTA_PROJECT) {
    process.env.GOOGLE_CLOUD_QUOTA_PROJECT = PROJECT_ID;
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT_ID,
    });
  }

  const db = admin.firestore();
  const fs = db;

  console.log(`Projeto: ${PROJECT_ID}`);
  console.log(
    `Modo: ${DRY ? 'DRY-RUN' : 'EXECUÇÃO REAL'} — só lançamentos (users e Auth preservados)\n`,
  );

  console.log('--- receitas_app / despesas_app / estornos ---');
  await deleteQueryDocs(db.collection('receitas_app'), 'receitas_app');
  await deleteQueryDocs(db.collection('despesas_app'), 'despesas_app');
  await deleteQueryDocs(db.collection('estornos'), 'estornos');

  const usersSnap = await db
    .collection('users')
    .where('role', 'in', ROLES_MARKETPLACE)
    .get();

  const uids = usersSnap.docs.map((d) => d.id);
  const entregadores = new Set(
    usersSnap.docs.filter((d) => d.data().role === 'entregador').map((d) => d.id),
  );

  console.log(`\nUtilizadores marketplace (preservados): ${uids.length}`);
  if (uids.length === 0) {
    console.log('Sem users marketplace. Livro caixa/estornos já tratados acima.');
    console.log('Concluído.');
    process.exit(0);
  }

  const pedidoIds = new Set();
  const camposPedido = ['cliente_id', 'loja_id', 'lojista_id', 'entregador_id'];
  for (const uid of uids) {
    for (const f of camposPedido) {
      const pq = await db.collection('pedidos').where(f, '==', uid).get();
      pq.docs.forEach((d) => pedidoIds.add(d.id));
    }
  }
  console.log(`Pedidos a remover (histórico): ${pedidoIds.size}`);

  if (!DRY) {
    for (const pid of pedidoIds) {
      await wipeSubcollection(db, `pedidos/${pid}`, 'mensagens', `pedidos/${pid}/mensagens`);
      await db.collection('pedidos').doc(pid).delete();
    }
    console.log(`Pedidos apagados: ${pedidoIds.size}`);
  } else {
    console.log(`[dry-run] apagaria ${pedidoIds.size} pedidos (+ mensagens)`);
  }

  if (!DRY) {
    for (const pid of pedidoIds) {
      await db.collection('avaliacoes').doc(pid).delete().catch(() => {});
    }
  } else if (pedidoIds.size > 0) {
    console.log('[dry-run] apagaria avaliacoes por id de pedido');
  }

  for (const eid of entregadores) {
    await deleteFiscalEntregador(db, eid);
  }

  for (let i = 0; i < uids.length; i += 10) {
    const chunk = uids.slice(i, i + 10);
    const sq = await db
      .collection('saques_solicitacoes')
      .where('user_id', 'in', chunk)
      .get();
    await batchDeleteDocs(fs, sq.docs, 'saques_solicitacoes');
  }

  console.log('\n--- Zerando saldo e rating da loja (sem pedidos/avaliações) ---');
  if (!DRY) {
    for (const doc of usersSnap.docs) {
      const uid = doc.id;
      const role = (doc.data().role || '').toString();
      const patch = { saldo: 0 };
      if (role === 'lojista') {
        patch.rating_media = 0;
        patch.total_avaliacoes = 0;
      }
      await db.collection('users').doc(uid).set(patch, { merge: true });
      console.log(
        `  users/${uid} saldo=0${role === 'lojista' ? ' + rating/avaliações zerados' : ''}`,
      );
    }
  } else {
    for (const doc of usersSnap.docs) {
      const role = (doc.data().role || '').toString();
      console.log(
        `  [dry-run] saldo=0 users/${doc.id}${role === 'lojista' ? ' + rating' : ''}`,
      );
    }
  }

  console.log('\nConcluído. Auth e cadastro (produtos, loja, docs) não foram alterados.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
