/**
 * Cria no Firestore:
 * - utilizador Auth + doc em `users` (lojista aprovado em Toledo, PR)
 * - produto de teste na coleção `produtos` (id fixo: seed_produto_toledo_pr)
 *
 * Pré-requisitos:
 * 1. Na pasta `functions`: npm install
 * 2. Credenciais Admin (uma das opções):
 *    - Variável de ambiente GOOGLE_APPLICATION_CREDENTIALS apontando para a chave JSON
 *      de conta de serviço com permissão no projeto Firebase; ou
 *    - gcloud auth application-default login (conta com acesso ao projeto)
 * 3. Executar:
 *    cd depertin_cliente/functions
 *    node scripts/seed_produto_toledo_pr.js
 *
 * Na app: escolhe a cidade "Toledo" no topo da vitrine (tem de coincidir com o campo
 * `cidade` do lojista abaixo — usa capitalização "Toledo").
 */

const admin = require('firebase-admin');

const EMAIL_LOJA = 'loja.teste.toledo.dipertin@local.test';
const SENHA_LOJA = 'SeedToledo2026!'; // altera depois se fores usar login real
const CIDADE_VITRINE = 'Toledo';
const NOME_LOJA = 'Loja Teste Toledo PR';

const PRODUTO_ID = 'seed_produto_toledo_pr';
const IMAGEM_TESTE =
  'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400';

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: 'depertin-f940f' });
  }

  const auth = admin.auth();
  const db = admin.firestore();

  let uid;
  try {
    const existing = await auth.getUserByEmail(EMAIL_LOJA);
    uid = existing.uid;
    console.log('Utilizador Auth já existe:', EMAIL_LOJA, uid);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await auth.createUser({
        email: EMAIL_LOJA,
        password: SENHA_LOJA,
        emailVerified: true,
        displayName: NOME_LOJA,
      });
      uid = created.uid;
      console.log('Criado utilizador Auth:', EMAIL_LOJA, uid);
    } else {
      throw e;
    }
  }

  await db
    .collection('users')
    .doc(uid)
    .set(
      {
        email: EMAIL_LOJA,
        nome: NOME_LOJA,
        nome_loja: NOME_LOJA,
        role: 'lojista',
        tipoUsuario: 'lojista',
        cidade: CIDADE_VITRINE,
        status_loja: 'aprovada',
        ativo: true,
        loja_aberta: true,
        telefone: '',
        cpf: '',
      },
      { merge: true },
    );

  console.log('Doc users atualizado para lojista Toledo:', uid);

  await db
    .collection('produtos')
    .doc(PRODUTO_ID)
    .set(
      {
        lojista_id: uid,
        nome: 'Produto teste — Toledo PR',
        descricao:
          'Produto de teste para Toledo, Paraná. Pode apagar no Console quando não precisar.',
        preco: 24.9,
        oferta: 19.9,
        categoria_nome: 'Testes',
        imagens: [IMAGEM_TESTE],
        tipo_venda: 'imediata',
        estoque_qtd: 50,
        prazo_encomenda: '',
        ativo: true,
        cidade: CIDADE_VITRINE.toLowerCase(),
        data_criacao: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  console.log('Produto gravado:', PRODUTO_ID);
  console.log('Login lojista (opcional):', EMAIL_LOJA, '/', SENHA_LOJA);
  console.log('Na vitrine, cidade deve ser:', CIDADE_VITRINE);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
