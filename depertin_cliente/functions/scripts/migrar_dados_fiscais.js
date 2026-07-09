/**
 * Script de Migração — Dados Fiscais
 *
 * Cria dados fiscais padrão para lojas que ainda não têm configuração fiscal.
 * Ajusta lojas antigas sem quebrar lojistas já ativos.
 *
 * Uso:
 *   node scripts/migrar_dados_fiscais.js [--dry-run]
 *   node scripts/migrar_dados_fiscais.js [--dry-run] [--loja=LOJA_ID]
 *
 * Flags:
 *   --dry-run   Apenas lista o que seria alterado, não persiste
 *   --loja=ID   Executa apenas para uma loja específica
 *
 * Segurança:
 *   - NÃO cria nem altera dados fiscais sensíveis (tokens, certificados)
 *   - Apenas estrutura inicial: status, limite mensal, flags
 *   - Preserva configurações existentes (não sobrescreve)
 */
const admin = require('firebase-admin');
const path = require('path');

// Inicializa Firebase Admin (fora das Functions)
const serviceAccount = process.env.GOOGLE_APPLICATION_CREDENTIALS
  ? path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS)
  : null;

if (!admin.apps.length) {
  if (serviceAccount) {
    const cred = require(serviceAccount);
    admin.initializeApp({ credential: admin.credential.cert(cred) });
  } else {
    admin.initializeApp();
  }
}

const db = admin.firestore();

// Parse args
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const lojaEspecifica = args.find(a => a.startsWith('--loja='))?.split('=')[1] || null;

async function migrar() {
  console.log('═'.repeat(60));
  console.log('MIGRAÇÃO DE DADOS FISCAIS');
  console.log(`Modo: ${dryRun ? 'DRY-RUN (sem persistência)' : 'PRODUÇÃO'}`);
  if (lojaEspecifica) console.log(`Loja específica: ${lojaEspecifica}`);
  console.log('═'.repeat(60));

  let totalLojas = 0;
  let jaConfiguradas = 0;
  let novasConfiguracoes = 0;
  let novasIntegracoes = 0;
  let erros = 0;

  try {
    // Buscar lojas elegíveis
    let query = db.collection('users')
      .where('role', '==', 'lojista')
      .where('status_loja', 'in', ['aprovada', 'aprovado'])
      .limit(1000);

    if (lojaEspecifica) {
      query = db.collection('users').doc(lojaEspecifica).collection('_dummy').limit(0);
      // Para loja específica, buscar direto
      const lojaDoc = await db.collection('users').doc(lojaEspecifica).get();
      if (!lojaDoc.exists) {
        console.error(`❌ Loja ${lojaEspecifica} não encontrada.`);
        return;
      }
      const lojaData = lojaDoc.data();
      if (lojaData.role !== 'lojista') {
        console.error(`❌ Documento ${lojaEspecifica} não é um lojista. Role: ${lojaData.role}`);
        return;
      }
      await processarLoja(lojaDoc.id, lojaData);
      console.log(`\n✅ Loja ${lojaEspecifica} processada.`);
      return;
    }

    const lojas = await query.get();
    console.log(`\n📊 Total de lojas a processar: ${lojas.size}`);

    let processed = 0;
    for (const doc of lojas.docs) {
      totalLojas++;
      await processarLoja(doc.id, doc.data());
      processed++;
      if (processed % 50 === 0) {
        console.log(`  Progresso: ${processed}/${lojas.size}`);
      }
    }

    console.log('\n' + '═'.repeat(60));
    console.log('RESUMO DA MIGRAÇÃO:');
    console.log(`  Lojas processadas:     ${totalLojas}`);
    console.log(`  Já configuradas:       ${jaConfiguradas}`);
    console.log(`  Novas configurações:   ${novasConfiguracoes}`);
    console.log(`  Novas integrações:     ${novasIntegracoes}`);
    console.log(`  Erros:                 ${erros}`);
    console.log('═'.repeat(60));

  } catch (error) {
    console.error('❌ Erro fatal na migração:', error);
    process.exit(1);
  }

  async function processarLoja(lojaId, lojaData) {
    const lojaNome = lojaData.nome_loja || lojaData.nome || lojaId;

    try {
      // 1. Verificar se já tem store_fiscal_settings
      const settingsSnap = await db.collection('store_fiscal_settings')
        .where('store_id', '==', lojaId)
        .limit(1)
        .get();

      if (!settingsSnap.empty) {
        jaConfiguradas++;
        return; // Já configurada, preservar
      }

      // 2. Verificar se já tem lojista_integracao
      const integracaoSnap = await db.collection('lojista_integracao')
        .where('store_id', '==', lojaId)
        .limit(1)
        .get();

      if (!dryRun) {
        // 3. Criar store_fiscal_settings padrão
        const settingsData = {
          store_id: lojaId,
          enable_nfe: true,
          enable_nfce: false,
          enable_nfse: false,
          status: 'pending',
          ambiente: 'homologacao', // Começa em homologação por segurança
          nfe_settings: {
            serie: '1',
            ambiente: 'homologacao',
          },
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.collection('store_fiscal_settings').add(settingsData);
        novasConfiguracoes++;

        // 4. Criar lojista_integracao com limite padrão
        if (integracaoSnap.empty) {
          const mesRef = `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}`;
          const limitePadrao = parseInt(process.env.FISCAL_LIMITE_PADRAO_MENSAL || '200', 10);

          await db.collection('lojista_integracao').add({
            store_id: lojaId,
            ativa: true,
            limiteMensal: limitePadrao,
            notasEmitidas: 0,
            notasRestantes: limitePadrao,
            mesReferencia: mesRef,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          novasIntegracoes++;
        }

        console.log(`  ✅ ${lojaNome} (${lojaId}): configuracao criada`);
      } else {
        console.log(`  🔷 ${lojaNome} (${lojaId}): seria criada (dry-run)`);
        novasConfiguracoes++;
      }
    } catch (error) {
      erros++;
      console.error(`  ❌ ${lojaNome} (${lojaId}): erro - ${error.message}`);
    }
  }
}

migrar().then(() => {
  console.log('\nMigração finalizada.');
  process.exit(0);
}).catch(err => {
  console.error('Erro não tratado:', err);
  process.exit(1);
});
