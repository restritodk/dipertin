/**
 * Script de Correção — integration_id em store_fiscal_settings
 *
 * Lojas que tiveram integração fiscal criada ANTES da correção do bug
 * (06/jul/2026) não possuem `integration_id` preenchido em
 * `store_fiscal_settings`.
 *
 * Este script varre os registros com integration_id vazio, encontra o
 * doc correspondente em `lojista_integracao` pelo store_id, extrai o
 * ID do provedor do campo `observacao` e atualiza o campo.
 *
 * Formato esperado em observacao:
 *   "Provedor: Focus NFe (abc123def)"
 *
 * Uso:
 *   node scripts/corrigir_integration_id_settings.js [--dry-run]
 *   node scripts/corrigir_integration_id_settings.js [--dry-run] [--loja=LOJA_ID]
 *
 * Flags:
 *   --dry-run   Apenas lista o que seria alterado, não persiste
 *   --loja=ID   Executa apenas para uma loja específica
 *
 * Segurança:
 *   - NÃO altera dados sensíveis (tokens, certificados, senhas)
 *   - NÃO sobrescreve integration_id já preenchido
 *   - Operação idempotente
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

/**
 * Extrai o ID do provedor do campo observacao.
 * Formato: "Provedor: Focus NFe (abc123def)"
 * Retorna o ID dentro dos parênteses ou null.
 */
function extrairProviderIdDaObservacao(observacao) {
  if (!observacao || typeof observacao !== 'string') return null;
  const match = observacao.match(/\(([^)]+)\)$/);
  return match ? match[1].trim() : null;
}

async function corrigir() {
  console.log('═'.repeat(60));
  console.log('CORREÇÃO — integration_id EM store_fiscal_settings');
  console.log(`Modo: ${dryRun ? 'DRY-RUN (sem persistência)' : 'PRODUÇÃO'}`);
  if (lojaEspecifica) console.log(`Loja específica: ${lojaEspecifica}`);
  console.log('═'.repeat(60));

  // 1. Busca settings com integration_id vazio
  let settingsQuery = db
    .collection('store_fiscal_settings')
    .where('integration_id', '==', '');

  if (lojaEspecifica) {
    settingsQuery = settingsQuery.where('store_id', '==', lojaEspecifica);
  }

  const settingsSnap = await settingsQuery.get();

  if (settingsSnap.empty) {
    console.log('\n✅ Nenhum registro com integration_id vazio encontrado.');
    return;
  }

  console.log(`\n📋 Encontrados ${settingsSnap.docs.length} registro(s) com integration_id vazio.\n`);

  let corrigidos = 0;
  let ignorados = 0;
  let erros = 0;

  for (const settingsDoc of settingsSnap.docs) {
    const settingsData = settingsDoc.data();
    const storeId = settingsData.store_id || '';
    const settingsId = settingsDoc.id;

    if (!storeId) {
      console.log(`  ⚠️  [${settingsId}] Sem store_id — ignorando`);
      ignorados++;
      continue;
    }

    // 2. Busca lojista_integracao correspondente
    const integSnap = await db
      .collection('lojista_integracao')
      .where('store_id', '==', storeId)
      .limit(1)
      .get();

    if (integSnap.empty) {
      console.log(`  ⚠️  [${storeId}] Sem lojista_integracao correspondente — ignorando`);
      ignorados++;
      continue;
    }

    const integData = integSnap.docs[0].data();
    const observacao = integData.observacao || '';
    const integrationId = extrairProviderIdDaObservacao(observacao);

    if (!integrationId) {
      console.log(`  ⚠️  [${storeId}] Não foi possível extrair providerId da observacao "${observacao}" — ignorando`);
      ignorados++;
      continue;
    }

    // 3. Verifica se o provider realmente existe em fiscal_integrations
    const providerDoc = await db.collection('fiscal_integrations').doc(integrationId).get();
    if (!providerDoc.exists) {
      console.log(`  ⚠️  [${storeId}] Provider ${integrationId} não encontrado em fiscal_integrations — ignorando`);
      ignorados++;
      continue;
    }

    // 4. Atualiza
    if (dryRun) {
      console.log(`  🔍 [DRY-RUN] [${storeId}] store_fiscal_settings/${settingsId}`);
      console.log(`      integration_id: "" → "${integrationId}"`);
      console.log(`      provider: ${observacao}`);
      corrigidos++;
    } else {
      try {
        await db.collection('store_fiscal_settings').doc(settingsId).update({
          integration_id: integrationId,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`  ✅ [${storeId}] store_fiscal_settings/${settingsId} atualizado → ${integrationId}`);
        corrigidos++;
      } catch (e) {
        console.error(`  ❌ [${storeId}] Erro ao atualizar: ${e.message}`);
        erros++;
      }
    }
  }

  // Resumo
  console.log('\n' + '═'.repeat(60));
  console.log('RESUMO');
  console.log(`  Registros com integration_id vazio: ${settingsSnap.docs.length}`);
  console.log(`  Corrigidos:                        ${corrigidos}`);
  console.log(`  Ignorados (sem dados suficientes): ${ignorados}`);
  console.log(`  Erros:                             ${erros}`);
  console.log('═'.repeat(60));

  if (dryRun && corrigidos > 0) {
    console.log('\n💡 Execute sem --dry-run para aplicar as correções.');
  }
}

corrigir().catch((err) => {
  console.error('Erro fatal:', err);
  process.exit(1);
});
