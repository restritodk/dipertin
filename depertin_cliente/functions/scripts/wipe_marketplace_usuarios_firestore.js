/**
 * ⚠️ DESTRUTIVO: APAGA utilizadores marketplace no Firestore E no Firebase Auth,
 * além de produtos, lojas_public, dados fiscais, notificações guardadas, etc.
 * Não use se a intenção for só zerar lançamentos — use
 * `wipe_marketplace_lancamentos_only_firestore.js` (npm run wipe:marketplace-lancamentos).
 *
 * REMOVE dados de utilizadores marketplace: cliente, lojista, entregador.
 *
 * Também esvazia receitas_app, despesas_app e estornos (histórico global no painel),
 * além do Livro Caixa (pode repetir-se; é idempotente).
 *
 * Preserva: users com role master, master_city (não entram na query).
 *
 * ATENÇÃO: irreversível. Use DIPERTIN_WIPE_DRY_RUN=SIM primeiro.
 *
 * cd depertin_cliente/functions
 * $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 * $env:GOOGLE_CLOUD_QUOTA_PROJECT="depertin-f940f"
 * $env:DIPERTIN_CONFIRM_WIPE_MARKETPLACE="SIM"
 * $env:DIPERTIN_WIPE_DRY_RUN="SIM"
 * npm run wipe:marketplace-usuarios
 */

const admin = require('firebase-admin');

const CONFIRM = (process.env.DIPERTIN_CONFIRM_WIPE_MARKETPLACE || '')
  .trim()
  .toUpperCase();
const DRY = (process.env.DIPERTIN_WIPE_DRY_RUN || '').trim().toUpperCase() === 'SIM';
const PROJECT_ID =
  process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'depertin-f940f';

const ROLES_MARKETPLACE = ['cliente', 'lojista', 'entregador'];
const BATCH = 400;

/** Apaga todos os docs retornados por uma CollectionReference ou Query. */
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

async function wipeUserSubcollections(db, uid) {
  const base = `users/${uid}`;
  await deleteQueryDocs(db.collection(`${base}/enderecos`), `${base}/enderecos`);

  const veSnap = await db.collection(`${base}/veiculos`).get();
  if (!DRY) {
    for (const vdoc of veSnap.docs) {
      await deleteQueryDocs(
        vdoc.ref.collection('documentos'),
        `${base}/veiculos/${vdoc.id}/documentos`,
      );
      await vdoc.ref.delete();
    }
  } else if (!veSnap.empty) {
    console.log(`  [dry-run] veículos ${veSnap.size} em ${uid}`);
  }

  await deleteQueryDocs(db.collection(`${base}/documentos`), `${base}/documentos`);
  await deleteQueryDocs(db.collection(`${base}/chaves_pix`), `${base}/chaves_pix`);
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
      'Recusado: define DIPERTIN_CONFIRM_WIPE_MARKETPLACE=SIM para executar.',
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
  const auth = admin.auth();

  console.log(`Projeto: ${PROJECT_ID}`);
  console.log(`Modo: ${DRY ? 'DRY-RUN (não grava)' : 'EXECUÇÃO REAL'}\n`);

  console.log('--- receitas_app / despesas_app / estornos ---');
  await deleteQueryDocs(db.collection('receitas_app'), 'receitas_app');
  await deleteQueryDocs(db.collection('despesas_app'), 'despesas_app');
  await deleteQueryDocs(db.collection('estornos'), 'estornos');

  const usersSnap = await db
    .collection('users')
    .where('role', 'in', ROLES_MARKETPLACE)
    .get();

  const uids = usersSnap.docs.map((d) => d.id);
  const lojistas = new Set(
    usersSnap.docs.filter((d) => d.data().role === 'lojista').map((d) => d.id),
  );
  const entregadores = new Set(
    usersSnap.docs.filter((d) => d.data().role === 'entregador').map((d) => d.id),
  );

  console.log(
    `\nUtilizadores marketplace: ${uids.length} (cliente/lojista/entregador)`,
  );
  if (uids.length === 0) {
    console.log('\nSem users marketplace a remover (Auth não tocado).');
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
  console.log(`Pedidos referenciados: ${pedidoIds.size}`);

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
    console.log('[dry-run] apagaria avaliacoes pelos ids de pedido');
  }

  const lojArr = [...lojistas];
  for (let i = 0; i < lojArr.length; i += 10) {
    const chunk = lojArr.slice(i, i + 10);
    const pq = await db.collection('produtos').where('loja_id', 'in', chunk).get();
    await batchDeleteDocs(fs, pq.docs, 'produtos (loja_id)');
    const p2 = await db.collection('produtos').where('lojista_id', 'in', chunk).get();
    await batchDeleteDocs(fs, p2.docs, 'produtos (lojista_id)');
  }

  if (!DRY) {
    for (const lid of lojistas) {
      await db.collection('lojas_public').doc(lid).delete().catch(() => {});
    }
  }
  console.log(
    DRY ? '[dry-run] lojas_public lojistas' : `lojas_public removidos: ${lojistas.size}`,
  );

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

  for (const uid of uids) {
    await wipeSubcollection(
      db,
      `notificacoes_usuario/${uid}`,
      'items',
      `notificacoes_usuario/${uid}/items`,
    );
    if (!DRY) {
      await db.collection('notificacoes_usuario').doc(uid).delete().catch(() => {});
    }
  }

  for (const uid of uids) {
    await wipeUserSubcollections(db, uid);
    if (!DRY) {
      await db.collection('users').doc(uid).delete();
      console.log(`  users/${uid} removido`);
    } else {
      console.log(`  [dry-run] removeria users/${uid}`);
    }
  }

  if (!DRY) {
    for (const uid of uids) {
      try {
        await auth.deleteUser(uid);
        console.log(`  Auth removido: ${uid}`);
      } catch (e) {
        console.warn(`  Auth falhou ${uid}: ${e.message}`);
      }
    }
  } else {
    console.log('[dry-run] não remove contas Auth');
  }

  console.log('\nConcluído.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
