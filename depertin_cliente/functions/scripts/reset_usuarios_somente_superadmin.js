/**
 * ATENÇÃO: operação DESTRUTIVA.
 *
 * 1) Conta utilizadores em Firebase Authentication e documentos em `users` (Firestore).
 * 2) Apaga TODOS os utilizadores Auth exceto o e-mail indicado.
 * 3) Apaga TODOS os documentos em `users` exceto o UID desse utilizador.
 * 4) Garante que o utilizador restante existe em Auth + Firestore com role master
 *    (acesso total ao painel).
 *
 * Não apaga pedidos, produtos, etc. — apenas Auth e coleção `users`. IDs antigos noutras
 * coleções podem ficar órfãos até limpares manualmente se precisares.
 *
 * cd depertin_cliente/functions
 * $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 * $env:DIPERTIN_CONFIRM_RESET="SIM"
 * npm run reset:usuarios-superadmin
 *
 * Opcional:
 *   DIPERTIN_KEEP_EMAIL (default: master@teste.com)
 *   DIPERTIN_KEEP_PASSWORD (default: master) — repõe sempre esta senha no Auth
 */

const admin = require('firebase-admin');

const KEEP_EMAIL = (
  process.env.DIPERTIN_KEEP_EMAIL || 'master@teste.com'
).trim().toLowerCase();
const KEEP_PASSWORD =
  process.env.DIPERTIN_KEEP_PASSWORD || 'master';
const CONFIRM = (process.env.DIPERTIN_CONFIRM_RESET || '').trim().toUpperCase();

async function listAllAuthUids(auth) {
  const uids = [];
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    res.users.forEach((u) => uids.push(u.uid));
    pageToken = res.pageToken;
  } while (pageToken);
  return uids;
}

async function deleteFirestoreUserDocsExcept(db, keepUid) {
  const snap = await db.collection('users').get();
  const toDelete = snap.docs.filter((d) => d.id !== keepUid);
  console.log(
    `Firestore users: ${snap.size} documento(s); a remover ${toDelete.length} (mantém ${keepUid}).`,
  );

  const batchSize = 450;
  for (let i = 0; i < toDelete.length; i += batchSize) {
    const batch = db.batch();
    const chunk = toDelete.slice(i, i + batchSize);
    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function main() {
  if (CONFIRM !== 'SIM' && CONFIRM !== 'YES') {
    console.error(
      'Recusado: define DIPERTIN_CONFIRM_RESET=SIM (ou YES) para executar o reset.',
    );
    process.exit(1);
  }

  if (!KEEP_PASSWORD || KEEP_PASSWORD.length < 6) {
    console.error('DIPERTIN_KEEP_PASSWORD deve ter pelo menos 6 caracteres (Auth).');
    process.exit(1);
  }

  if (!admin.apps.length) {
    admin.initializeApp({ projectId: 'depertin-f940f' });
  }

  const auth = admin.auth();
  const db = admin.firestore();

  const authUidsBefore = await listAllAuthUids(auth);
  const usersSnap = await db.collection('users').get();
  console.log('--- Antes ---');
  console.log('Firebase Auth (utilizadores):', authUidsBefore.length);
  console.log('Firestore coleção users (documentos):', usersSnap.size);

  let keepUid;
  try {
    const existing = await auth.getUserByEmail(KEEP_EMAIL);
    keepUid = existing.uid;
    await auth.updateUser(keepUid, {
      password: KEEP_PASSWORD,
      emailVerified: true,
      displayName: 'Super Admin DiPertin',
    });
    console.log('Auth: utilizador existente atualizado:', KEEP_EMAIL, keepUid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await auth.createUser({
        email: KEEP_EMAIL,
        password: KEEP_PASSWORD,
        emailVerified: true,
        displayName: 'Super Admin DiPertin',
      });
      keepUid = created.uid;
      console.log('Auth: utilizador criado:', KEEP_EMAIL, keepUid);
    } else {
      throw e;
    }
  }

  await db
    .collection('users')
    .doc(keepUid)
    .set(
      {
        email: KEEP_EMAIL,
        nome: 'Super Admin',
        role: 'master',
        tipoUsuario: 'master',
        primeiro_acesso: false,
        ativo: true,
      },
      { merge: true },
    );
  console.log('Firestore: users/' + keepUid + ' com role=master');

  await deleteFirestoreUserDocsExcept(db, keepUid);

  const toRemoveAuth = authUidsBefore.filter((uid) => uid !== keepUid);
  console.log('Auth: a apagar', toRemoveAuth.length, 'utilizador(es)...');
  for (const uid of toRemoveAuth) {
    try {
      await auth.deleteUser(uid);
    } catch (err) {
      console.warn('Falha ao apagar Auth', uid, err.message || err);
    }
  }

  const authUidsAfter = await listAllAuthUids(auth);
  const usersSnapAfter = await db.collection('users').get();
  console.log('--- Depois ---');
  console.log('Firebase Auth (utilizadores):', authUidsAfter.length);
  console.log('Firestore coleção users (documentos):', usersSnapAfter.size);
  console.log('---');
  console.log('Login painel:', KEEP_EMAIL);
  console.log('Senha (reposta pelo script):', KEEP_PASSWORD);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
