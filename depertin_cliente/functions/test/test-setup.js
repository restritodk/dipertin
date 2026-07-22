/**
 * Configuração e proteção para testes integrados no Firebase Emulator.
 *
 * USO OBRIGATÓRIO: este módulo deve ser importado primeiro em
 * todos os arquivos de teste integrado.
 *
 * Proteções:
 * - Aborta se qualquer env var de emulador estiver faltando
 * - Aborta se detectar que o projeto real está sendo acessado
 * - Inicializa o Admin SDK apontado para o emulador
 */

const assert = require('node:assert');
const admin = require('firebase-admin');

// Carrega .env e .env.local para que FISCAL_MASTER_KEY fique disponível nos testes
// .env.local tem precedência (usado para secrets locais que conflitam com Secret Manager)
require('dotenv').config();
require('dotenv').config({ path: require('path').resolve(__dirname, '..', '.env.local'), override: true });

// NOTA: o Firebase Emulator define apenas FIRESTORE_EMULATOR_HOST,
// NÃO FIREBASE_FIRESTORE_EMULATOR_HOST.
const VARIAVEIS_EMULADOR = [
  { var: 'FIRESTORE_EMULATOR_HOST', label: 'Firestore', esperado: '127.0.0.1:8080' },
  { var: 'FIREBASE_AUTH_EMULATOR_HOST', label: 'Auth', esperado: '127.0.0.1:9099' },
  { var: 'FIREBASE_STORAGE_EMULATOR_HOST', label: 'Storage', esperado: '127.0.0.1:9199' },
];

const PROJETO_EMULADOR = 'demo-depertin-teste';

/**
 * Verifica se TODAS as variáveis de ambiente do emulador estão configuradas.
 * Aborta com mensagem clara se alguma estiver faltando.
 */
function verificarEmuladores() {
  console.log(`\n🔒 [test-setup] VERIFICANDO ISOLAMENTO — projeto alvo: ${PROJETO_EMULADOR}\n`);

  const faltantes = [];

  for (const entry of VARIAVEIS_EMULADOR) {
    const valor = process.env[entry.var];
    if (!valor || valor.trim() === '') {
      faltantes.push(entry.var);
    }
  }

  // Verificação especial: GCLOUD_PROJECT
  const gcloudProject = process.env.GCLOUD_PROJECT;
  if (!gcloudProject || gcloudProject.trim() === '') {
    faltantes.push('GCLOUD_PROJECT');
  }

  if (faltantes.length > 0) {
    const linhas = faltantes.map(v => `  - ${v}`).join('\n');
    console.error(`\n❌ [test-setup] BLOQUEADO — Variáveis de emulador faltando:\n${linhas}\n`);
    console.error(`\n⚠️  Execute os testes com:\n`);
    console.error(`   firebase emulators:exec "npm test"\n`);
    console.error(`   Ou manualmente:\n`);
    console.error(`   \$env:FIRESTORE_EMULATOR_HOST=\"127.0.0.1:8080\"`);
    console.error(`   \$env:FIREBASE_AUTH_EMULATOR_HOST=\"127.0.0.1:9099\"`);
    console.error(`   \$env:FIREBASE_STORAGE_EMULATOR_HOST=\"127.0.0.1:9199\"`);
    console.error(`   \$env:GCLOUD_PROJECT=\"${PROJETO_EMULADOR}\"\n`);
    process.exit(1);
  }

  // Proteção contra produção: GCLOUD_PROJECT não pode ser o projeto real
  if (gcloudProject === 'depertin-f940f') {
    console.error(`\n❌ [test-setup] BLOQUEADO — GCLOUD_PROJECT aponta para PRODUÇÃO (${gcloudProject})!\n`);
    console.error('   Configure GCLOUD_PROJECT para o projeto do emulador antes de executar testes.\n');
    process.exit(1);
  }

  // Proteção contra produção: FIRESTORE_EMULATOR_HOST deve apontar para localhost/127.0.0.1
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST || '';
  if (!firestoreHost.includes('127.0.0.1') && !firestoreHost.includes('localhost')) {
    console.error(`\n❌ [test-setup] BLOQUEADO — FIRESTORE_EMULATOR_HOST não aponta para localhost!\n`);
    console.error(`   Valor atual: ${firestoreHost}\n`);
    process.exit(1);
  }

  console.log(`✅ [test-setup] Ambiente isolado OK — GCLOUD_PROJECT=${gcloudProject}`);
  console.log(`✅ [test-setup] Firestore: ${process.env.FIRESTORE_EMULATOR_HOST}`);
  console.log(`✅ [test-setup] Auth: ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`);
  console.log(`✅ [test-setup] Storage: ${process.env.FIREBASE_STORAGE_EMULATOR_HOST}\n`);
}

/**
 * Inicializa o Admin SDK apontando exclusivamente para o emulador.
 */
function inicializarAdmin() {
  verificarEmuladores();

  if (!admin.apps.length) {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';
    process.env.GCLOUD_PROJECT = PROJETO_EMULADOR;

    admin.initializeApp({
      projectId: PROJETO_EMULADOR,
      storageBucket: `${PROJETO_EMULADOR}.appspot.com`,
    });

    console.log(`✅ [test-setup] Admin SDK inicializado para projeto: ${PROJETO_EMULADOR}\n`);
  }

  return admin;
}

/**
 * Retorna a referência do Firestore do emulador.
 */
function getDb() {
  return admin.firestore();
}

/**
 * Limpa TODOS os dados do emulador (usar apenas antes de fixtures).
 */
async function limparEmulador() {
  const db = getDb();
  console.log('🧹 [test-setup] Limpando dados do emulador...');

  const colecoes = [
    'assinaturas_clientes',
    'fiscal_emission_operations',
    'fiscal_documents',
    'fiscal_integrations',
    'fiscal_logs',
    'store_fiscal_settings',
    'assinaturas_planos',
    'users',
  ];

  for (const colecao of colecoes) {
    try {
      const snap = await db.collection(colecao).limit(500).get();
      if (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
        console.log(`  🗑️  ${colecao}: ${snap.size} docs removidos`);
      }
    } catch (e) {
      // Coleção pode não existir — ignorar
    }
  }

  console.log('✅ [test-setup] Emulador limpo.\n');
}

module.exports = {
  verificarEmuladores,
  inicializarAdmin,
  getDb,
  limparEmulador,
  PROJETO_EMULADOR,
};
