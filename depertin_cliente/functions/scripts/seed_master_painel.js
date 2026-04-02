/**
 * Conta Master (aprova lojas, mesmo poder staff nas regras Firestore).
 *
 * cd depertin_cliente/functions
 * $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 * npm run seed:master
 *
 * DIPERTIN_MASTER_EMAIL / DIPERTIN_MASTER_PASSWORD (opcional)
 */

const admin = require('firebase-admin');

const EMAIL = process.env.DIPERTIN_MASTER_EMAIL || 'master@teste.com';
const PASSWORD = process.env.DIPERTIN_MASTER_PASSWORD || 'master';

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: 'depertin-f940f' });
  }

  const auth = admin.auth();
  const db = admin.firestore();

  let uid;
  try {
    const existing = await auth.getUserByEmail(EMAIL);
    uid = existing.uid;
    await auth.updateUser(uid, { password: PASSWORD });
    console.log('Auth existente; senha atualizada:', EMAIL);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await auth.createUser({
        email: EMAIL,
        password: PASSWORD,
        emailVerified: true,
        displayName: 'Master DiPertin',
      });
      uid = created.uid;
      console.log('Auth criado:', EMAIL, uid);
    } else {
      throw e;
    }
  }

  await db
    .collection('users')
    .doc(uid)
    .set(
      {
        email: EMAIL,
        nome: 'Master',
        role: 'master',
        tipoUsuario: 'master',
        primeiro_acesso: false,
        ativo: true,
      },
      { merge: true },
    );

  console.log('Firestore: role=master, tipoUsuario=master');
  console.log('Faça: firebase deploy --only firestore:rules');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
