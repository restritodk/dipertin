#!/usr/bin/env node
/**
 * Cria dados fictícios no Firebase Emulator para testes integrados.
 *
 * Uso:
 *   firebase emulators:exec "node test/create-fixtures.js && npm test"
 *   OU manual com emuladores rodando:
 *   $env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"; $env:GCLOUD_PROJECT="demo-depertin-teste"
 *   node test/create-fixtures.js
 *
 * ATENÇÃO: Só funciona no EMULADOR. Bloqueia se detectar produção.
 */

const admin = require('firebase-admin');
const { verificarEmuladores, inicializarAdmin, getDb, PROJETO_EMULADOR } = require('./test-setup');

// ═══════════════════════════════════════════════════════════════════════════════
// DADOS FICTÍCIOS
// ═══════════════════════════════════════════════════════════════════════════════

const TIMESTAMP_NOW = admin.firestore.Timestamp.now();
const TIMESTAMP_PASSADO = admin.firestore.Timestamp.fromDate(new Date('2025-01-01'));
const TIMESTAMP_FUTURO = admin.firestore.Timestamp.fromDate(new Date('2027-01-01'));

// ─── USUÁRIOS ───

const USUARIOS = {
  staff001: {
    uid: 'staff001',
    email: 'staff@dipertin.teste',
    nome: 'Staff Master',
    role: 'master',
    loja_id: null,
  },
  lojaA_proprietario: {
    uid: 'lojaA_proprietario',
    email: 'loja.a@teste.com',
    nome: 'Proprietário Loja A',
    role: 'lojista',
    loja_id: 'lojaA',
    nivel_acesso: 'nivel_iii',
  },
  lojaA_colaborador_nivel1: {
    uid: 'lojaA_colab1',
    email: 'colab1.lojaa@teste.com',
    nome: 'Colaborador Nível I (Loja A)',
    role: 'lojista',
    loja_id: 'lojaA',
    lojista_owner_uid: 'lojaA_proprietario',
    painel_colaborador_nivel: 1,
    nivel_acesso: 'nivel_i',
  },
  lojaA_colaborador_nivel2: {
    uid: 'lojaA_colab2',
    email: 'colab2.lojaa@teste.com',
    nome: 'Colaborador Nível II (Loja A)',
    role: 'lojista',
    loja_id: 'lojaA',
    lojista_owner_uid: 'lojaA_proprietario',
    painel_colaborador_nivel: 2,
    nivel_acesso: 'nivel_ii',
  },
  lojaA_colaborador_nivel3: {
    uid: 'lojaA_colab3',
    email: 'colab3.lojaa@teste.com',
    nome: 'Colaborador Nível III (Loja A)',
    role: 'lojista',
    loja_id: 'lojaA',
    lojista_owner_uid: 'lojaA_proprietario',
    painel_colaborador_nivel: 3,
    nivel_acesso: 'nivel_iii',
  },
  lojaB_proprietario: {
    uid: 'lojaB_proprietario',
    email: 'loja.b@teste.com',
    nome: 'Proprietário Loja B',
    role: 'lojista',
    loja_id: 'lojaB',
  },
  cliente001: {
    uid: 'cliente001',
    email: 'cliente@teste.com',
    nome: 'Cliente Comum',
    role: 'cliente',
    loja_id: null,
  },
};

// ─── ASSINATURAS ───

const ASSINATURAS = {
  ativa_com_fiscal: {
    id: 'assinatura_ativa_fiscal',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 10,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    data_fim: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  ativa_sem_fiscal: {
    id: 'assinatura_ativa_sem_fiscal',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: [],
    saldo_notas: 10,
    plano_id: 'plano_basico',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    data_fim: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  pendente: {
    id: 'assinatura_pendente',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'pendente',
    pagamento_mp_status: 'pending',
    modulos_extras: ['fiscal'],
    saldo_notas: 0,
    plano_id: 'plano_premium',
    data_inicio: null,
    data_expiracao: null,
    criado_em: TIMESTAMP_NOW,
  },
  suspensa: {
    id: 'assinatura_suspensa',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'suspensa',
    pagamento_mp_status: 'rejected',
    modulos_extras: ['fiscal'],
    saldo_notas: 0,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    suspensa_em: TIMESTAMP_NOW,
    criado_em: TIMESTAMP_PASSADO,
  },
  cancelada: {
    id: 'assinatura_cancelada',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'cancelada',
    pagamento_mp_status: 'cancelled',
    modulos_extras: ['fiscal'],
    saldo_notas: 0,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_PASSADO,
    cancelada_em: TIMESTAMP_PASSADO,
    criado_em: TIMESTAMP_PASSADO,
  },
  vencida: {
    id: 'assinatura_vencida',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 0,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_PASSADO, // Expirada
    criado_em: TIMESTAMP_PASSADO,
  },
  pagamento_pendente: {
    id: 'assinatura_pgto_pendente',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'pending', // Pagamento pendente
    modulos_extras: ['fiscal'],
    saldo_notas: 5,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  saldo_zero: {
    id: 'assinatura_saldo_zero',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 0,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  saldo_um: {
    id: 'assinatura_saldo_um',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 1,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  saldo_dez: {
    id: 'assinatura_saldo_dez',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 10,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    data_fim: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  ilimitado: {
    id: 'assinatura_ilimitado',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: null, // null = ilimitado
    plano_id: 'plano_ilimitado',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
  // Assinatura para Loja B (mesmo plano, saldo diferente)
  lojaB_assinatura: {
    id: 'lojaB_assinatura',
    store_id: 'lojaB',
    loja_id: 'lojaB',
    status: 'ativo',
    pagamento_mp_status: 'approved',
    modulos_extras: ['fiscal'],
    saldo_notas: 5,
    plano_id: 'plano_premium',
    data_inicio: TIMESTAMP_PASSADO,
    data_expiracao: TIMESTAMP_FUTURO,
    criado_em: TIMESTAMP_PASSADO,
  },
};

// ─── PLANOS ───

const PLANOS = {
  basico: {
    id: 'plano_basico',
    nome: 'Plano Básico',
    preco: 49.90,
    modulos_inclusos: [],
    notas_inclusas: 5,
    criado_em: TIMESTAMP_PASSADO,
  },
  premium: {
    id: 'plano_premium',
    nome: 'Plano Premium',
    preco: 99.90,
    modulos_inclusos: ['fiscal', 'comercial'],
    notas_inclusas: 50,
    criado_em: TIMESTAMP_PASSADO,
  },
  ilimitado: {
    id: 'plano_ilimitado',
    nome: 'Plano Ilimitado',
    preco: 199.90,
    modulos_inclusos: ['fiscal', 'comercial', 'assinaturas'],
    notas_inclusas: -1, // -1 = ilimitado
    criado_em: TIMESTAMP_PASSADO,
  },
};

// ─── INTEGRAÇÕES FISCAIS ───

const INTEGRACOES = {
  lojaA_ativa: {
    id: 'integracao_lojaA',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    provider: 'focus_nfe',
    status: 'active',
    ambiente: 'homologacao',
    credentials_encrypted: 'fake_encrypted_token_lojaA',
    criado_em: TIMESTAMP_PASSADO,
  },
  lojaB_ativa: {
    id: 'integracao_lojaB',
    store_id: 'lojaB',
    loja_id: 'lojaB',
    provider: 'focus_nfe',
    status: 'active',
    ambiente: 'homologacao',
    credentials_encrypted: 'fake_encrypted_token_lojaB',
    criado_em: TIMESTAMP_PASSADO,
  },
  inativa: {
    id: 'integracao_inativa',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    provider: 'focus_nfe',
    status: 'inactive',
    ambiente: 'homologacao',
    credentials_encrypted: 'fake_encrypted_token_inativa',
    criado_em: TIMESTAMP_PASSADO,
  },
  vinculo_incorreto: {
    id: 'integracao_vinculo_errado',
    store_id: 'lojaB',      // Pertence à Loja B
    loja_id: 'lojaB',
    provider: 'focus_nfe',
    status: 'active',
    ambiente: 'homologacao',
    credentials_encrypted: 'fake_encrypted_token_lojaB',
    criado_em: TIMESTAMP_PASSADO,
  },
};

// ─── DOCUMENTOS FISCAIS ───

const DOCUMENTOS = {
  processando: {
    id: 'doc_processando',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'processando',
    numero: '100001',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000011000000001',
    criado_em: TIMESTAMP_NOW,
  },
  autorizado: {
    id: 'doc_autorizado',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'autorizado',
    numero: '100002',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000021000000002',
    xml_path: 'fiscal/lojaA/xml/100002.xml',
    danfe_path: 'fiscal/lojaA/danfe/100002.pdf',
    criado_em: TIMESTAMP_PASSADO,
    autorizado_em: TIMESTAMP_PASSADO,
  },
  rejeitado: {
    id: 'doc_rejeitado',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'rejeitado',
    numero: '100003',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000031000000003',
    motivo_rejeicao: 'CNPJ do emitente inválido',
    codigo_rejeicao: '215',
    criado_em: TIMESTAMP_PASSADO,
    rejeitado_em: TIMESTAMP_PASSADO,
  },
  cancelado: {
    id: 'doc_cancelado',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'cancelado',
    numero: '100004',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000041000000004',
    xml_path: 'fiscal/lojaA/xml/100004.xml',
    danfe_path: 'fiscal/lojaA/danfe/100004.pdf',
    criado_em: TIMESTAMP_PASSADO,
    autorizado_em: TIMESTAMP_PASSADO,
    cancelado_em: TIMESTAMP_PASSADO,
  },
  sem_xml: {
    id: 'doc_sem_xml',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'autorizado',
    numero: '100005',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000051000000005',
    // Sem xml_path
    danfe_path: 'fiscal/lojaA/danfe/100005.pdf',
    criado_em: TIMESTAMP_PASSADO,
  },
  sem_danfe: {
    id: 'doc_sem_danfe',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    status: 'autorizado',
    numero: '100006',
    serie: '1',
    chave_acesso: '35240100000000000000550010000000061000000006',
    xml_path: 'fiscal/lojaA/xml/100006.xml',
    // Sem danfe_path
    criado_em: TIMESTAMP_PASSADO,
  },
  lojaB_documento: {
    id: 'doc_lojaB',
    store_id: 'lojaB',
    loja_id: 'lojaB',
    integration_id: 'integracao_lojaB',
    status: 'autorizado',
    numero: '200001',
    serie: '1',
    chave_acesso: '35240100000000000000550020000000011000000001',
    xml_path: 'fiscal/lojaB/xml/200001.xml',
    danfe_path: 'fiscal/lojaB/danfe/200001.pdf',
    criado_em: TIMESTAMP_PASSADO,
  },
};

// ─── OPERAÇÕES FISCAIS ───

const OPERACOES_FISCAIS = {
  reservada: {
    id: 'op_reservada',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'reservado',
    saldo_reservado: 1,
    saldo_confirmado: 0,
    saldo_estornado: 0,
    idempotency_key: 'test-ik-reservada',
    criado_em: TIMESTAMP_NOW,
  },
  processando: {
    id: 'op_processando',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'processando',
    saldo_reservado: 1,
    saldo_confirmado: 0,
    saldo_estornado: 0,
    idempotency_key: 'test-ik-processando',
    provider_ref: 'prov-001',
    criado_em: TIMESTAMP_NOW,
  },
  autorizado: {
    id: 'op_autorizado',
    store_id: 'lojaA',
    loja_id: 'lojaA',
    status: 'autorizado',
    saldo_reservado: 0,
    saldo_confirmado: 1,
    saldo_estornado: 0,
    idempotency_key: 'test-ik-autorizado',
    provider_ref: 'prov-002',
    criado_em: TIMESTAMP_PASSADO,
  },
};

// ─── CONFIGURAÇÕES FISCAIS DA LOJA ───

const STORE_SETTINGS = {
  lojaA: {
    id: 'settings_lojaA',
    store_id: 'lojaA',
    integration_id: 'integracao_lojaA',
    ambiente: 'homologacao',
    serie_nfe: '1',
    ultimo_numero: 100006,
    criado_em: TIMESTAMP_PASSADO,
    company_tax_data: {
      cnpj: '12345678000199',
      razao_social: 'Loja Teste Ltda',
      nome_fantasia: 'Loja Teste',
      ie: '123456789',
      regime_tributario: 'Simples Nacional',
      crt: '1',
      cnae: '4711301',
      logradouro: 'Rua Exemplo',
      numero: '123',
      bairro: 'Centro',
      cidade: 'Rondonópolis',
      uf: 'MT',
      cep: '78700000',
      codigo_cidade: '5107602',
      telefone: '5566999999999',
    },
  },
  lojaB: {
    id: 'settings_lojaB',
    store_id: 'lojaB',
    integration_id: 'integracao_lojaB',
    ambiente: 'homologacao',
    serie_nfe: '1',
    ultimo_numero: 200001,
    criado_em: TIMESTAMP_PASSADO,
    company_tax_data: {
      cnpj: '98765432000188',
      razao_social: 'Loja B Teste Ltda',
      nome_fantasia: 'Loja B',
      ie: '987654321',
      regime_tributario: 'Simples Nacional',
      crt: '1',
      cnae: '4711301',
      logradouro: 'Av Teste',
      numero: '456',
      bairro: 'Jardim',
      cidade: 'Toledo',
      uf: 'PR',
      cep: '85900000',
      codigo_cidade: '4127700',
      telefone: '5545999999999',
    },
  },
};

// ═══════════════════════════════════════════════════════════════════════════════
// FUNÇÕES DE CRIAÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

async function criarUsuarios(db) {
  console.log('\n👤 Criando usuários...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(USUARIOS)) {
    const ref = db.collection('users').doc(data.uid);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(USUARIOS).length} usuários criados`);
}

async function criarPlanos(db) {
  console.log('\n📋 Criando planos...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(PLANOS)) {
    const ref = db.collection('assinaturas_planos').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(PLANOS).length} planos criados`);
}

async function criarAssinaturas(db) {
  console.log('\n📦 Criando assinaturas...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(ASSINATURAS)) {
    const ref = db.collection('assinaturas_clientes').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(ASSINATURAS).length} assinaturas criadas`);
}

async function criarIntegracoes(db) {
  console.log('\n🔌 Criando integrações fiscais...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(INTEGRACOES)) {
    const ref = db.collection('fiscal_integrations').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(INTEGRACOES).length} integrações criadas`);
}

async function criarDocumentos(db) {
  console.log('\n📄 Criando documentos fiscais...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(DOCUMENTOS)) {
    const ref = db.collection('fiscal_documents').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(DOCUMENTOS).length} documentos criados`);
}

async function criarOperacoesFiscais(db) {
  console.log('\n⚙️  Criando operações fiscais...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(OPERACOES_FISCAIS)) {
    const ref = db.collection('fiscal_emission_operations').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(OPERACOES_FISCAIS).length} operações criadas`);
}

async function criarStoreSettings(db) {
  console.log('\n⚙️  Criando configurações de loja...');
  const batch = db.batch();
  for (const [key, data] of Object.entries(STORE_SETTINGS)) {
    const ref = db.collection('store_fiscal_settings').doc(data.id);
    batch.set(ref, data, { merge: true });
  }
  await batch.commit();
  console.log(`  ✅ ${Object.keys(STORE_SETTINGS).length} configurações criadas`);
}

/**
 * Cria TODAS as fixtures no banco do emulador.
 * Pode ser chamado de outros arquivos de teste.
 */
async function criarTodasFixtures(db) {
  await criarUsuarios(db);
  await criarPlanos(db);
  await criarAssinaturas(db);
  await criarIntegracoes(db);
  await criarDocumentos(db);
  await criarOperacoesFiscais(db);
  await criarStoreSettings(db);
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTS — para reuso em arquivos de teste
// ═══════════════════════════════════════════════════════════════════════════════

module.exports = {
  criarUsuarios,
  criarPlanos,
  criarAssinaturas,
  criarIntegracoes,
  criarDocumentos,
  criarOperacoesFiscais,
  criarStoreSettings,
  criarTodasFixtures,
};

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN (execução direta)
// ═══════════════════════════════════════════════════════════════════════════════

if (require.main === module) {
  (async () => {
    console.log('══════════════════════════════════════════════════════════');
    console.log('  🧪 CRIADOR DE FIXTURES — Firebase Emulator');
    console.log(`  Projeto: ${PROJETO_EMULADOR}`);
    console.log('══════════════════════════════════════════════════════════\n');

    inicializarAdmin();
    const db = getDb();

    await criarTodasFixtures(db);

    console.log('\n══════════════════════════════════════════════════════════');
    console.log('  ✅ Fixtures criadas com sucesso!');
    console.log('══════════════════════════════════════════════════════════\n');
  })().catch(err => {
    console.error('❌ Erro ao criar fixtures:', err);
    process.exit(1);
  });
}
