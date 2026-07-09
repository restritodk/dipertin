/**
 * Diagnóstico Fiscal — verifica por que a emissão falha
 * 
 * Uso: node diagnostico_fiscal.js <storeId>
 * 
 * storeId = ID da loja (uid do lojista no Firebase Auth)
 * Se não souber o storeId, rode sem argumentos que lista tudo.
 */

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');
const fs = require('fs');

async function main() {
  const storeId = process.argv[2];

  // Inicializa Firebase Admin
  let sa;
  const saPath = path.join(__dirname, 'depertin_cliente', 'functions', 'serviceAccountKey.json');
  const saPath2 = path.join(__dirname, 'serviceAccountKey.json');

  if (fs.existsSync(saPath)) {
    sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  } else if (fs.existsSync(saPath2)) {
    sa = JSON.parse(fs.readFileSync(saPath2, 'utf8'));
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    sa = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  } else {
    console.error('❌ Nenhuma service account encontrada.');
    console.error('  Coloque o JSON em: depertin_cliente/functions/serviceAccountKey.json');
    console.error('  Ou crie a variável: GOOGLE_APPLICATION_CREDENTIALS');
    process.exit(1);
  }

  try {
    initializeApp({ credential: cert(sa), projectId: 'depertin-f940f' });
  } catch (e) {
    // Já inicializado
  }

  const db = getFirestore();

  console.log('═══════════════════════════════════════════════');
  console.log(' DIAGNÓSTICO FISCAL — Firestore');
  console.log('═══════════════════════════════════════════════\n');

  if (!storeId) {
    // Lista todas as lojas com configuração fiscal
    console.log('📋 Nenhum storeId fornecido. Listando todas as configurações:\n');

    const settingsSnap = await db.collection('store_fiscal_settings').get();
    if (settingsSnap.empty) {
      console.log('   Nenhuma store_fiscal_settings encontrada.\n');
    } else {
      for (const doc of settingsSnap.docs) {
        const d = doc.data();
        const sid = d.store_id || '—';
        const snome = d.store_name || '—';
        const intId = d.integration_id || '—';
        console.log(`   📍 Loja: ${snome}`);
        console.log(`      store_id: ${sid}`);
        console.log(`      integration_id: ${intId}`);
        console.log(`      Tem company_tax_data: ${d.company_tax_data ? '✅ SIM' : '❌ NÃO'}`);
        console.log('');
      }
    }

    console.log('👉 Para verificar uma loja específica, execute:');
    console.log('   node diagnostico_fiscal.js <storeId>\n');
    return;
  }

  // ─── 1. store_fiscal_settings ───
  console.log('🔍 1. VERIFICANDO store_fiscal_settings');
  console.log('──────────────────────────────────────────');
  const settingsSnap = await db.collection('store_fiscal_settings')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();

  if (settingsSnap.empty) {
    console.log('   ❌ NENHUMA store_fiscal_settings encontrada para este storeId!');
    console.log('      → Configure a integração fiscal no admin.');
    return;
  }

  const sDoc = settingsSnap.docs[0];
  const s = sDoc.data();
  console.log(`   ✅ Documento encontrado: ${sDoc.id}`);

  const intId = s.integration_id || '';
  const taxData = s.company_tax_data;
  const integData = s.integration_data;

  console.log(`   integration_id: ${intId || '❌ VAZIO'}`);
  console.log(`   company_tax_data: ${taxData ? '✅ PRESENTE' : '❌ AUSENTE'}`);

  if (taxData) {
    console.log(`      razao_social: ${taxData.razao_social || '❌ VAZIO'}`);
    console.log(`      cnpj: ${taxData.cnpj || '❌ VAZIO'}`);
    console.log(`      ie: ${taxData.ie || '❌ VAZIO'}`);
    console.log(`      logradouro: ${taxData.logradouro || '❌ VAZIO'}`);
    console.log(`      numero: ${taxData.numero || '❌ VAZIO'}`);
    console.log(`      bairro: ${taxData.bairro || '❌ VAZIO'}`);
    console.log(`      cidade: ${taxData.cidade || '❌ VAZIO'}`);
    console.log(`      uf: ${taxData.uf || '❌ VAZIO'}`);
    console.log(`      cep: ${taxData.cep || '❌ VAZIO'}`);
  }

  console.log(`   integration_data desnormalizado: ${integData ? '✅ PRESENTE' : '❌ AUSENTE'}`);
  if (integData) {
    console.log(`      provider: ${integData.provider || integData.provider_name || '—'}`);
  }
  console.log('');

  // ─── 2. fiscal_integrations ───
  console.log('🔍 2. VERIFICANDO fiscal_integrations');
  console.log('──────────────────────────────────────────');
  if (intId) {
    const integSnap = await db.collection('fiscal_integrations').doc(intId).get();
    if (integSnap.exists) {
      const i = integSnap.data();
      console.log('   ✅ Documento ENCONTRADO em fiscal_integrations!');
      console.log(`      provider: ${i.provider || '—'}`);
      console.log(`      provider_name: ${i.provider_name || '—'}`);
      console.log(`      environment: ${i.environment || '—'}`);
      console.log(`      Tem api_key: ${i.api_key ? '✅' : '❌ NÃO'}`);
      console.log(`      Tem access_token: ${i.access_token ? '✅' : '❌ NÃO'}`);
      console.log(`      Tem certificate: ${i.certificate ? '✅' : '❌ NÃO'}`);
    } else {
      console.log('   ❌ Documento NÃO ENCONTRADO em fiscal_integrations!');
      console.log(`      → O doc ${intId} não existe em fiscal_integrations.`);
      console.log('      → Crie um documento com este mesmo ID.');
      console.log('      → Campos obrigatórios: provider, environment, api_key');
    }
  } else {
    console.log('   ⚠️ Sem integration_id para verificar');
  }
  console.log('');

  // ─── 3. lojista_integracao ───
  console.log('🔍 3. VERIFICANDO lojista_integracao');
  console.log('──────────────────────────────────────────');
  const liSnap = await db.collection('lojista_integracao')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();

  if (liSnap.empty) {
    console.log('   ❌ NENHUM documento em lojista_integracao para este store_id!');
    console.log('      → Sem isso, a emissão falha com "Limite mensal atingido".');
  } else {
    const liDoc = liSnap.docs[0];
    const li = liDoc.data();
    console.log(`   ✅ Documento encontrado: ${liDoc.id}`);
    console.log(`      status: ${li.status || '—'}`);
    console.log(`      plano_nome: ${li.plano_nome || '—'}`);
    const limite = li.limite_mensal || 0;
    const emitidas = li.notas_emitidas || 0;
    console.log(`      limite_mensal: ${limite}`);
    console.log(`      notas_emitidas: ${emitidas}`);
    console.log(`      notas_restantes: ${limite - emitidas}`);
  }
  console.log('');

  // ─── RESUMO ───
  console.log('═══════════════════════════════════════════════');
  console.log(' 📋 RESUMO');
  console.log('═══════════════════════════════════════════════\n');

  // Verifica fiscal_integrations
  let integExiste = false;
  if (intId) {
    const integSnap = await db.collection('fiscal_integrations').doc(intId).get();
    integExiste = integSnap.exists;
  }

  const etapas = [
    { nome: 'store_fiscal_settings (company_tax_data com CNPJ)', ok: !!(taxData && taxData.cnpj) },
    { nome: 'store_fiscal_settings (integration_id preenchido)', ok: !!intId },
    { nome: 'fiscal_integrations/{id} existe', ok: integExiste },
    { nome: 'lojista_integracao (store_id existe)', ok: !liSnap.empty },
  ];

  for (const etapa of etapas) {
    console.log(`   ${etapa.ok ? '✅' : '❌'} ${etapa.nome}`);
  }
  console.log('');

  const todasOk = etapas.every(e => e.ok);
  if (todasOk) {
    console.log('   ✅ Todos os requisitos estão OK!');
    console.log('      O erro deve ser no payload do cliente/destinatário.\n');
  } else {
    console.log('   ❌ Existem requisitos faltando.\n');
  }

  // Sugestões de correção
  if (!integExiste && intId) {
    console.log('💡 Para criar fiscal_integrations:');
    console.log('   db.collection("fiscal_integrations").doc("' + intId + '").set({');
    console.log('     provider: "focus_nfe",');
    console.log('     provider_name: "Focus NF-e",');
    console.log('     environment: "sandbox",');
    console.log('     api_key: "SUA_CHAVE_AQUI",');
    console.log('     created_at: firebase.firestore.FieldValue.serverTimestamp()');
    console.log('   })');
    console.log('');
  }

  if (liSnap.empty) {
    console.log('💡 Para criar lojista_integracao:');
    console.log('   1. Vá em Assinaturas → Configurações no painel admin');
    console.log('   2. Ou rode no console do Firestore:');
    console.log('      db.collection("lojista_integracao").add({');
    console.log('        store_id: "' + storeId + '",');
    console.log('        store_nome: "NOME DA LOJA",');
    console.log('        status: "ativa",');
    console.log('        limite_mensal: 100,');
    console.log('        notas_emitidas: 0,');
    console.log('        ciclo_ref: "' + new Date().toISOString().slice(0, 7) + '",');
    console.log('        created_at: firebase.firestore.FieldValue.serverTimestamp(),');
    console.log('        updated_at: firebase.firestore.FieldValue.serverTimestamp()');
    console.log('      })');
    console.log('');
  }

  console.log('═══════════════════════════════════════════════\n');
}

main().catch(console.error);
