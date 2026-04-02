/**
 * Cria um utilizador master para o painel web (depertin_web).
 *
 * O login do painel exige:
 * - Firebase Auth (email/senha)
 * - Documento em `users` com role `master`, `master_city` ou `lojista`
 *
 * Por defeito: e-mail técnico master.
 * Para conta master principal use: npm run seed:master
 *
 * cd depertin_cliente/functions
 * $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 * npm run seed:superadmin
 *
 * Variáveis opcionais:
 *   DIPERTIN_SUPERADMIN_EMAIL
 *   DIPERTIN_SUPERADMIN_PASSWORD  (mín. 6 caracteres)
 */

const admin = require('firebase-admin');

const EMAIL =
  process.env.DIPERTIN_SUPERADMIN_EMAIL || 'painel.superadmin@depertin.seed';
const PASSWORD =
  process.env.DIPERTIN_SUPERADMIN_PASSWORD || 'DiPertinPainel2026!';

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
    console.log('Auth já existia; senha atualizada para a do seed:', EMAIL, uid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await auth.createUser({
        email: EMAIL,
        password: PASSWORD,
        emailVerified: true,
        displayName: 'Super Admin DiPertin',
      });
      uid = created.uid;
      console.log('Criado Auth:', EMAIL, uid);
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
        nome: 'Super Admin',
        role: 'master',
        tipoUsuario: 'master',
        primeiro_acesso: false,
        ativo: true,
      },
      { merge: true },
    );

  console.log('Firestore users atualizado (master):', uid);
  console.log('---');
  console.log('E-mail:', EMAIL);
  console.log('Senha:', PASSWORD);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
