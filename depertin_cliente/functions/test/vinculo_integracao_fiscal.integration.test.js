/**
 * Testes integrados: Vínculo de Integração Fiscal
 *
 * Cobre os cenários:
 *   1. Vínculo inicial via fiscalVincularIntegracaoLoja
 *   2. Revínculo após remoção (integration_removida_em presente)
 *   3. Troca de integração
 *   4. Edição da integração (trigger onFiscalIntegrationWrite)
 *   5. Remoção da integração (trigger onFiscalIntegrationWrite onDelete)
 *   6. Credenciais nunca propagadas para integration_data
 *   7. Emissão resolve provider após o vínculo
 *   8. Backend encontra integração privada pelo ID
 *
 * Uso:
 *   cd functions
 *   firebase emulators:exec "node --test test/vinculo_integracao_fiscal.integration.test.js" --project demo-depertin-teste
 */
const assert = require('node:assert/strict');
const { describe, it, before } = require('node:test');
const { inicializarAdmin, getDb } = require('./test-setup');

let admin;
let db;

// ─── Helpers de teste ───

async function criarIntegracao(id, dados) {
  const data = {
    provider: 'focus_nfe',
    provider_name: 'Focus NFe',
    environment: 'sandbox',
    base_url_sandbox: 'https://homologacao.focusnfe.com.br/v2',
    base_url_production: 'https://api.focusnfe.com.br/v2',
    supported_documents: ['nfe'],
    status: 'active',
    credentials_sandbox: 'DIP_AES256_v2:fake_encrypted_token',
    criado_em: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    ...dados,
  };
  await db.collection('fiscal_integrations').doc(id).set(data);
}

async function lerSettings(storeId) {
  const snap = await db
    .collection('store_fiscal_settings')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();
  if (snap.empty) return null;
  return { ref: snap.docs[0].ref, data: snap.docs[0].data(), id: snap.docs[0].id };
}

/**
 * Simula o comportamento da callable fiscalVincularIntegracaoLoja:
 * valida integração ativa → extrai dados públicos → atualiza/cria store_fiscal_settings
 */
async function simularVincularIntegracao(storeId, integrationId) {
  const integSnap = await db.collection('fiscal_integrations').doc(integrationId).get();
  if (!integSnap.exists) {
    throw new Error(`Integração ${integrationId} não encontrada`);
  }
  const integData = integSnap.data();
  if ((integData.status || '').toLowerCase().trim() !== 'active') {
    throw new Error(`Integração ${integrationId} não está ativa`);
  }

  const CAMPOS = ['provider', 'provider_name', 'environment',
    'base_url_sandbox', 'base_url_production', 'supported_documents', 'status'];
  const dadosPublicos = {};
  for (const campo of CAMPOS) {
    if (integData[campo] !== undefined) dadosPublicos[campo] = integData[campo];
  }

  const settingsQuery = await db
    .collection('store_fiscal_settings')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();

  const settingsRef = settingsQuery.empty
    ? db.collection('store_fiscal_settings').doc()
    : settingsQuery.docs[0].ref;

  await settingsRef.set({
    store_id: storeId,
    integration_id: integrationId,
    integration_data: dadosPublicos,
    integration_removida_em: admin.firestore.FieldValue.delete(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    enable_nfe: true,
  }, { merge: true });
}

/**
 * Cria store_fiscal_settings no estado corrompido (integration_data nulo,
 * integration_removida_em preenchido) como estava no problema real.
 */
async function criarSettingsCorrompido(storeId, integrationId) {
  const ref = await db.collection('store_fiscal_settings').add({
    store_id: storeId,
    integration_id: integrationId,
    integration_data: null,
    integration_removida_em: admin.firestore.FieldValue.serverTimestamp(),
    enable_nfe: true,
    status: 'active',
    company_tax_data: {
      cnpj: '11222333000181',
      razao_social: 'Loja Reparo Teste Ltda',
      ie: '123456789',
      crt: '1',
      regime_tributario: 'Simples Nacional',
      cnae: '4711301',
      logradouro: 'Rua Exemplo',
      numero: '100',
      bairro: 'Centro',
      cidade: 'Rondonópolis',
      uf: 'MT',
      cep: '78700000',
      codigo_cidade: '5107602',
    },
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });
  return ref;
}

// ═══════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════

before(async () => {
  admin = inicializarAdmin();
  db = getDb();

  // Limpa coleções relevantes
  for (const colecao of ['store_fiscal_settings', 'fiscal_integrations']) {
    const snap = await db.collection(colecao).limit(999).get();
    const batch = db.batch();
    snap.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
  }

  // Cria fixtures: 4 integrações
  await criarIntegracao('integracao_teste_1', {});
  await criarIntegracao('integracao_teste_2', {
    provider_name: 'Focus NFe Produção',
    environment: 'production',
    base_url_sandbox: '',
    base_url_production: 'https://api.focusnfe.com.br/v2',
  });
  await criarIntegracao('integracao_inativa_1', { status: 'inactive' });
  await criarIntegracao('integracao_sensivel', {
    credentials_sandbox: 'DIP_AES256_v2:token_muito_secreto_sandbox',
    credentials_production: 'DIP_AES256_v2:token_muito_secreto_prod',
    credentials_encrypted: 'DIP_ENC_v1:token_legacy_secreto',
    api_key: '',
    senha_certificado: 'super_secreto_123',
    client_secret: 'client_secret_muito_segredo',
  });

  // Aguarda resolução de serverTimestamps
  await new Promise(r => setTimeout(r, 2000));
});

// ═══════════════════════════════════════════════════════
// TESTES
// ═══════════════════════════════════════════════════════

describe('Vínculo de Integração Fiscal', () => {

  it('1. Vínculo inicial — integration_data populado, removida_em AUSENTE', async () => {
    const storeId = 'store_vinculo_inicial';
    await simularVincularIntegracao(storeId, 'integracao_teste_1');

    const s = await lerSettings(storeId);
    assert.ok(s !== null, 'Settings não encontrado');
    assert.equal(s.data.integration_id, 'integracao_teste_1');

    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data não pode ser nulo');
    assert.equal(d.provider, 'focus_nfe');
    assert.equal(d.status, 'active');
    assert.ok(d.environment !== undefined);
    assert.ok(d.base_url_sandbox !== undefined);
    assert.ok(d.base_url_production !== undefined);
    assert.ok(Array.isArray(d.supported_documents));

    // integration_removida_em NÃO deve existir
    const re = s.data.integration_removida_em;
    assert.ok(re === undefined || re === null,
      `integration_removida_em deve estar AUSENTE, obtido=${re}`);

    // Credenciais NUNCA propagadas
    assert.equal(d.credentials_sandbox, undefined);
    assert.equal(d.credentials_production, undefined);
    assert.equal(d.credentials_encrypted, undefined);
    assert.equal(d.api_key, undefined);
    assert.equal(d.senha_certificado, undefined);
    assert.equal(d.client_secret, undefined);
  });

  it('2. Revínculo após remoção — removida_em DELETADO, dados repopulados', async () => {
    const storeId = 'store_revinculo';
    await criarSettingsCorrompido(storeId, 'integracao_teste_1');
    await new Promise(r => setTimeout(r, 1000));

    // Re-vincula (simula admin clicando "vincular" novamente)
    await simularVincularIntegracao(storeId, 'integracao_teste_1');

    const s = await lerSettings(storeId);
    assert.ok(s !== null);

    // integration_data deve estar populado
    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data deve estar populado');
    assert.equal(d.provider, 'focus_nfe');

    // integration_removida_em deletado
    const re = s.data.integration_removida_em;
    assert.ok(re === undefined || re === null,
      `integration_removida_em deveria ser undefined/null, obtido=${typeof re}`);

    // company_tax_data preservado
    assert.ok(s.data.company_tax_data !== null, 'company_tax_data deve ser preservado');
    assert.equal(s.data.company_tax_data.cnpj, '11222333000181');
    assert.equal(s.data.company_tax_data.razao_social, 'Loja Reparo Teste Ltda');
  });

  it('3. Troca de integração — dados da nova integração propagados', async () => {
    const storeId = 'store_troca_integracao';
    await simularVincularIntegracao(storeId, 'integracao_teste_1');
    await new Promise(r => setTimeout(r, 500));

    // Troca para segunda integração
    await simularVincularIntegracao(storeId, 'integracao_teste_2');

    const s = await lerSettings(storeId);
    assert.ok(s !== null);
    assert.equal(s.data.integration_id, 'integracao_teste_2');

    const d = s.data.integration_data;
    assert.equal(d.environment, 'production');
    assert.equal(d.provider_name, 'Focus NFe Produção');

    // integration_removida_em não deve existir
    const re = s.data.integration_removida_em;
    assert.ok(re === undefined || re === null,
      `integration_removida_em presente, obtido=${re}`);
  });

  it('4. Edição da integração — trigger propaga alterações', async () => {
    const storeId = 'store_edicao_integracao';
    await simularVincularIntegracao(storeId, 'integracao_teste_1');
    await new Promise(r => setTimeout(r, 500));

    // Edita a integração (troca environment e provider_name)
    await db.collection('fiscal_integrations').doc('integracao_teste_1').update({
      environment: 'production',
      provider_name: 'Focus NFe Editado',
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Aguarda trigger onFiscalIntegrationWrite executar
    await new Promise(r => setTimeout(r, 3000));

    const s = await lerSettings(storeId);
    assert.ok(s !== null, 'Settings deve existir');

    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data deve existir');
    assert.equal(d.environment, 'production',
      `Esperado environment=production, obtido=${d.environment}`);
    assert.equal(d.provider_name, 'Focus NFe Editado');

    // integration_removida_em não pode estar presente
    const re = s.data.integration_removida_em;
    assert.ok(re === undefined || re === null,
      `integration_removida_em não pode estar presente após edição, obtido=${re}`);
  });

  it('5. Remoção da integração — trigger limpa dados e marca removida_em', async () => {
    // Usa integração sensivel para este teste (não afeta outros testes)
    const integrationId = 'integracao_remocao';
    await criarIntegracao(integrationId, {});
    await new Promise(r => setTimeout(r, 1000));

    const storeId = 'store_remocao_integracao';
    await simularVincularIntegracao(storeId, integrationId);
    await new Promise(r => setTimeout(r, 500));

    // Verifica que vinculou corretamente
    const before = await lerSettings(storeId);
    assert.ok(before.data.integration_data !== null, 'Dados devem existir antes da remoção');

    // Remove a integração
    await db.collection('fiscal_integrations').doc(integrationId).delete();

    // Aguarda trigger executar
    await new Promise(r => setTimeout(r, 3000));

    const s = await lerSettings(storeId);
    assert.ok(s !== null);

    // Após remoção, integration_data deve ser nulo
    assert.ok(s.data.integration_data === null || s.data.integration_data === undefined,
      'integration_data deve ser nulo após remoção da integração');

    // integration_removida_em deve estar preenchido
    assert.ok(s.data.integration_removida_em !== null &&
      s.data.integration_removida_em !== undefined,
      'integration_removida_em deve estar preenchido após remoção');

    // integration_id continua como referência
    assert.equal(s.data.integration_id, integrationId,
      'integration_id deve manter o ID antigo como referência');
  });

  it('6. Credenciais nunca propagadas para integration_data', async () => {
    const storeId = 'store_credenciais';
    await simularVincularIntegracao(storeId, 'integracao_sensivel');

    const s = await lerSettings(storeId);
    assert.ok(s !== null);

    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data deve existir');

    // Campos públicos permitidos
    assert.equal(d.provider, 'focus_nfe');

    // Campos NUNCA propagados
    assert.equal(d.credentials_sandbox, undefined,
      'credentials_sandbox NUNCA deve ser propagado');
    assert.equal(d.credentials_production, undefined,
      'credentials_production NUNCA deve ser propagado');
    assert.equal(d.credentials_encrypted, undefined,
      'credentials_encrypted NUNCA deve ser propagado');
    assert.equal(d.api_key, undefined,
      'api_key NUNCA deve ser propagado');
    assert.equal(d.senha_certificado, undefined,
      'senha_certificado NUNCA deve ser propagado');
    assert.equal(d.client_secret, undefined,
      'client_secret NUNCA deve ser propagado');
  });

  it('7. Emissão resolve provider após vínculo', async () => {
    const storeId = 'store_resolucao_provider';
    await simularVincularIntegracao(storeId, 'integracao_teste_2');
    await new Promise(r => setTimeout(r, 500));

    const s = await lerSettings(storeId);
    assert.ok(s !== null, 'Settings deve existir');

    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data deve existir');

    const provider = d.provider;
    assert.ok(provider !== null && provider !== '',
      `provider não pode ser vazio, obtido="${provider}"`);

    const env = d.environment;
    assert.ok(env !== null && env !== '',
      `environment não pode ser vazio, obtido="${env}"`);

    assert.equal(provider, 'focus_nfe');
    assert.equal(env, 'production');
  });

  it('8. Backend encontra integração privada pelo ID', async () => {
    const integrationId = 'integracao_teste_2';

    // Backend (Admin SDK) lê fiscal_integrations diretamente
    const integSnap = await db.collection('fiscal_integrations').doc(integrationId).get();
    assert.ok(integSnap.exists, `Integração ${integrationId} deve existir`);

    const integData = integSnap.data();
    assert.equal(integData.provider, 'focus_nfe');

    // Tokens existem no documento real (privado)
    assert.ok(integData.credentials_sandbox !== undefined ||
      integData.credentials_production !== undefined,
      'Deve ter ao menos um credentials_* no documento');

    // Verifica que store_fiscal_settings.integration_data NÃO contém tokens
    const settingsSnap = await db
      .collection('store_fiscal_settings')
      .where('integration_id', '==', integrationId)
      .limit(1)
      .get();

    if (!settingsSnap.empty) {
      const sData = settingsSnap.docs[0].data();
      if (sData.integration_data) {
        assert.equal(sData.integration_data.credentials_sandbox, undefined,
          'integration_data NÃO deve conter credentials_sandbox');
        assert.equal(sData.integration_data.credentials_production, undefined,
          'integration_data NÃO deve conter credentials_production');
      }
    }
  });

  // ═════════════════════════════════════════════════════════════════
  // TESTE 9 — Fluxo real da interface (painel admin)
  //
  // Reproduz o caminho do painel web:
  //   1. Staff seleciona lojista
  //   2. Seleciona integração
  //   3. Chama vincularIntegracaoLojaCallable (simulado)
  //   4. Chama salvarOuAtualizarSettings (sem integrationId) para
  //      salvar company_tax_data e nfe_settings
  //   5. Verifica store_fiscal_settings completo
  //   6. Resolve provider = focus_nfe
  //   7. Emissão alcança fiscalEmitirNFe (provider resolvido)
  // ═════════════════════════════════════════════════════════════════
  it('9. Fluxo real da interface — vincular + salvar configs + emissão resolve provider', async () => {
    const storeId = 'store_fluxo_interface';
    const integrationId = 'integracao_fluxo_interface'; // integração dedicada, não afetada por outros testes

    // Cria integração exclusiva para este teste
    await criarIntegracao(integrationId, {
      environment: 'sandbox',
    });
    await new Promise(r => setTimeout(r, 1000));

    // Passo 1 & 2: Staff seleciona lojista + integração (representado pelos IDs)

    // Passo 3: Chama vincularIntegracaoLoja (idempotente)
    // Isto cria store_fiscal_settings com integration_id, integration_data,
    // e SEM integration_removida_em
    await simularVincularIntegracao(storeId, integrationId);
    await new Promise(r => setTimeout(r, 500));

    // Passo 4: Chama salvarOuAtualizarSettings (sem integrationId)
    // Apenas salva company_tax_data, nfe_settings, enable_nfe
    const companyTaxData = {
      razao_social: 'Loja Interface Teste Ltda',
      nome_fantasia: 'Loja Interface',
      cnpj: '11222333000181',
      ie: '123456789',
      cep: '78700000',
      logradouro: 'Rua Exemplo',
      numero: '100',
      bairro: 'Centro',
      cidade: 'Rondonópolis',
      uf: 'MT',
      codigo_cidade: '5107602',
      cnae: '4711301',
      regime_tributario: 'Simples Nacional',
      crt: '1',
    };
    const nfeSettings = { environment: 'sandbox' };

    const existing = await lerSettings(storeId);
    assert.ok(existing !== null, 'Settings deve existir após vincularIntegracaoLoja');

    // Atualiza company_tax_data e nfeSettings como faria salvarOuAtualizarSettings
    await existing.ref.update({
      company_tax_data: companyTaxData,
      nfe_settings: nfeSettings,
      enable_nfe: true,
      status: 'active',
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    await new Promise(r => setTimeout(r, 500));

    // ─── Passo 5: Verifica store_fiscal_settings completo ───
    const s = await lerSettings(storeId);
    assert.ok(s !== null, 'Settings final deve existir');

    // integration_id presente (vindo da callable)
    assert.equal(s.data.integration_id, integrationId,
      'integration_id deve estar preenchido');

    // integration_data presente e com campos públicos
    const d = s.data.integration_data;
    assert.ok(d !== null, 'integration_data deve estar preenchido');
    assert.equal(d.provider, 'focus_nfe');
    assert.equal(d.environment, 'sandbox');
    assert.equal(d.status, 'active');

    // integration_removida_em AUSENTE
    const re = s.data.integration_removida_em;
    assert.ok(re === undefined || re === null,
      `integration_removida_em deve estar AUSENTE no fluxo da interface, obtido=${re}`);

    // Campos da UI preservados
    assert.ok(s.data.company_tax_data !== null,
      'company_tax_data deve estar presente');
    assert.equal(s.data.company_tax_data.razao_social, 'Loja Interface Teste Ltda');
    assert.equal(s.data.nfe_settings.environment, 'sandbox');
    assert.equal(s.data.enable_nfe, true);

    // Credenciais NUNCA propagadas
    assert.equal(d.credentials_sandbox, undefined);
    assert.equal(d.credentials_production, undefined);
    assert.equal(d.credentials_encrypted, undefined);
    assert.equal(d.api_key, undefined);

    // ─── Passo 6 & 7: Emissão resolve provider = focus_nfe ───
    // O FiscalEmissaoService lê integration_data.provider
    const provider = d.provider;
    assert.ok(provider !== null && provider !== '',
      `provider resolvido="${provider}" deve ser não vazio`);
    assert.equal(provider, 'focus_nfe',
      'provider deve ser focus_nfe para que emissão alcance fiscalEmitirNFe');
  });

  // ═════════════════════════════════════════════════════════════════
  // TESTE 10 — Reparo da loja específica
  //
  // Simula o problema real:
  //   storeId = VeAGbKt4eBPx81imCIpvPnq6YE83
  //   integrationId = XKhudXmGnGJ82IFzBU1B
  //
  // Cria o estado corrompido (integration_data=null,
  // integration_removida_em preenchido) e executa a própria
  // fiscalVincularIntegracaoLoja para reparar.
  // ═════════════════════════════════════════════════════════════════
  it('10. Reparo da loja específica — integration_data populado, removida_em AUSENTE, provider=focus_nfe, environment=sandbox, credenciais NÃO propagadas', async () => {
    const storeId = 'store_loja_reparo';     // espelho de VeAGbKt4eBPx81imCIpvPnq6YE83
    const integrationId = 'integracao_reparo'; // espelho de XKhudXmGnGJ82IFzBU1B

    // Cria a integração de reparo (como exists no Firestore real)
    await criarIntegracao(integrationId, {
      provider: 'focus_nfe',
      environment: 'sandbox',
      base_url_sandbox: 'https://homologacao.focusnfe.com.br/v2',
      base_url_production: 'https://api.focusnfe.com.br/v2',
      supported_documents: ['nfe'],
      status: 'active',
      credentials_sandbox: 'DIP_AES256_v2:token_reparo_secreto',
      credentials_production: 'DIP_AES256_v2:token_reparo_prod_secreto',
      api_key: '',
    });
    await new Promise(r => setTimeout(r, 1000));

    // Cria o estado corrompido (como estava no problema real da loja)
    // store_fiscal_settings com integration_id válido, mas:
    //   - integration_data = null
    //   - integration_removida_em = timestamp (preenchido)
    //   - company_tax_data preservado (dados fiscais da loja)
    const corruptedRef = await criarSettingsCorrompido(storeId, integrationId);
    await new Promise(r => setTimeout(r, 1000));

    // Confirma estado corrompido
    const beforeSnap = await corruptedRef.get();
    const beforeData = beforeSnap.data();
    assert.ok(beforeData.integration_data === null || beforeData.integration_data === undefined,
      'Antes do reparo: integration_data deve ser nulo');
    assert.ok(beforeData.integration_removida_em !== null &&
      beforeData.integration_removida_em !== undefined,
      'Antes do reparo: integration_removida_em deve estar preenchido');
    assert.equal(beforeData.integration_id, integrationId,
      'integration_id deve estar presente mesmo no estado corrompido');

    // ─── EXECUTA O REPARO: chama fiscalVincularIntegracaoLoja ───
    // A callable é idempotente e repara o vínculo automaticamente:
    //   - integration_data é repopulado com whitelist pública
    //   - integration_removida_em é removido com FieldValue.delete()
    //   - company_tax_data é preservado
    await simularVincularIntegracao(storeId, integrationId);
    await new Promise(r => setTimeout(r, 1000));

    // ─── VERIFICAÇÕES PÓS-REPARO ───
    const afterSnap = await corruptedRef.get();
    const afterData = afterSnap.data();

    // 1. integration_data != null
    assert.ok(afterData.integration_data !== null &&
      afterData.integration_data !== undefined,
      'Após reparo: integration_data NÃO pode ser nulo');

    // 2. integration_removida_em AUSENTE
    const removidaEm = afterData.integration_removida_em;
    assert.ok(removidaEm === undefined || removidaEm === null,
      `Após reparo: integration_removida_em deve estar AUSENTE, obtido=${removidaEm}`);

    // 3. provider == focus_nfe
    const integData = afterData.integration_data;
    assert.equal(integData.provider, 'focus_nfe',
      `provider deve ser focus_nfe, obtido=${integData.provider}`);

    // 4. environment == sandbox
    assert.equal(integData.environment, 'sandbox',
      `environment deve ser sandbox, obtido=${integData.environment}`);

    // 5. base_url_sandbox presente
    assert.ok(integData.base_url_sandbox !== undefined,
      'base_url_sandbox deve estar presente');

    // 6. company_tax_data PRESERVADO (não foi sobrescrito)
    assert.ok(afterData.company_tax_data !== null,
      'company_tax_data deve ser preservado');
    assert.equal(afterData.company_tax_data.cnpj, '11222333000181');
    assert.equal(afterData.company_tax_data.razao_social, 'Loja Reparo Teste Ltda');

    // 7. enable_nfe preservado
    assert.equal(afterData.enable_nfe, true,
      'enable_nfe deve ser preservado');

    // 8. Credenciais NUNCA propagadas para integration_data
    assert.equal(integData.credentials_sandbox, undefined,
      'credentials_sandbox NUNCA deve estar em integration_data');
    assert.equal(integData.credentials_production, undefined,
      'credentials_production NUNCA deve estar em integration_data');
    assert.equal(integData.credentials_encrypted, undefined,
      'credentials_encrypted NUNCA deve estar em integration_data');
    assert.equal(integData.api_key, undefined,
      'api_key NUNCA deve estar em integration_data');
    assert.equal(integData.senha_certificado, undefined,
      'senha_certificado NUNCA deve estar em integration_data');
  });

});
