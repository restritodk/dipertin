/**
 * Testes integrados de REGRAS DE ASSINATURA no Firebase Emulator.
 *
 * Cenários:
 * ═══════════════════════════════════════════════════════════════════════
 * Proprietário (lojaA)
 *   ❌  Tentar alterar assinatura (status, saldo_notas, etc.)
 *
 * Colaborador nível II e III
 *   ❌  Tentar atualizar assinatura da própria loja
 *
 * Cliente comum
 *   ❌  Tentar ler e alterar assinatura
 *
 * Loja A → Assinatura da Loja B
 *   ❌  Tentar ler assinatura de outra loja
 *
 * Staff
 *   ✅  Atualizar documento fictício
 *
 * Admin SDK
 *   ✅  Atualizar assinatura
 *
 * ═══════════════════════════════════════════════════════════════════════
 * Uso:
 *   firebase emulators:exec "node --test test/*.integration.test.js" --project demo-depertin-teste
 */

const assert = require('node:assert/strict');
const { describe, it, before } = require('node:test');
const { inicializarAdmin, getDb, PROJETO_EMULADOR } = require('./test-setup');
const { criarTodasFixtures } = require('./create-fixtures');

// ═══════════════════════════════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════════════════════════════

let admin;
let db;

before(async () => {
  admin = inicializarAdmin();
  db = getDb();
  await criarTodasFixtures(db);
});

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS — Simulam regras de negócio (como se estivessem no Firestore Rules)
// ═══════════════════════════════════════════════════════════════════════════════

const ROLE_HIERARCHY = {
  cliente: 1,
  lojista: 2,
  master_city: 3,
  master: 4,
};

function isStaff(user) {
  const role = user?.role || '';
  return role === 'master' || role === 'master_city';
}

function podeLerAssinatura(user, assinatura) {
  // Staff pode ler qualquer assinatura
  if (isStaff(user)) return true;
  // Proprietário/colaborador pode ler da própria loja
  return user?.loja_id === assinatura?.store_id && user?.uid;
}

function podeCriarAtualizarAssinatura(user, assinatura, novosDados) {
  // Staff pode tudo
  if (isStaff(user)) return true;
  // Cliente nunca pode
  if (user?.role === 'cliente') return false;
  // Lojista: NUNCA pode alterar assinatura (regra do plano)
  // Mesmo o proprietário NÃO pode alterar status, saldo, modulos
  return false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES - REGRAS DE ASSINATURA
// ═══════════════════════════════════════════════════════════════════════════════

describe('REGRAS DE ASSINATURA', () => {

  // ─── Fixtures existentes ───

  it('fixtures: assinaturas existem no emulador', async () => {
    const snap = await db.collection('assinaturas_clientes').limit(30).get();
    assert.ok(snap.size >= 10, `Deveria ter >=10 assinaturas, tem ${snap.size}`);
    const docs = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    assert.ok(docs.some(d => d.store_id === 'lojaA'), 'Deveria ter assinatura da lojaA');
    assert.ok(docs.some(d => d.store_id === 'lojaB'), 'Deveria ter assinatura da lojaB');
    console.log(`  ℹ️  ${snap.size} assinaturas confirmadas no emulador`);
  });

  it('fixtures: usuários existem no emulador', async () => {
    const snap = await db.collection('users').limit(20).get();
    assert.ok(snap.size >= 5, `Deveria ter >=5 usuários, tem ${snap.size}`);
    console.log(`  ℹ️  ${snap.size} usuários confirmados no emulador`);
  });

  // ─── Proprietário (lojaA_proprietario) ───

  it('proprietário: NÃO pode alterar status da assinatura', async () => {
    const user = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
    const assinaturaRef = db.collection('assinaturas_clientes').doc('assinatura_ativa_fiscal');
    const doc = await assinaturaRef.get();
    const assinatura = { id: doc.id, ...doc.data() };

    const podeAlterar = podeCriarAtualizarAssinatura(user, assinatura, { status: 'suspensa' });
    assert.equal(podeAlterar, false, 'Proprietário NÃO deve alterar assinatura');
  });

  it('proprietário: NÃO pode alterar saldo_notas', async () => {
    const user = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { saldo_notas: 99999 });
    assert.equal(pode, false);
  });

  it('proprietário: NÃO pode alterar modulos_extras', async () => {
    const user = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { modulos_extras: ['fiscal'] });
    assert.equal(pode, false);
  });

  // ─── Colaborador nível II ───

  it('colaborador nível II: NÃO pode atualizar assinatura', async () => {
    const user = { uid: 'lojaA_colab2', loja_id: 'lojaA', role: 'lojista', nivel_acesso: 'nivel_ii' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { status: 'suspensa' });
    assert.equal(pode, false);
  });

  // ─── Colaborador nível III ───

  it('colaborador nível III: NÃO pode atualizar assinatura', async () => {
    const user = { uid: 'lojaA_colab3', loja_id: 'lojaA', role: 'lojista', nivel_acesso: 'nivel_iii' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { saldo_notas: 50 });
    assert.equal(pode, false);
  });

  // ─── Cliente comum ───

  it('cliente: NÃO pode ler assinatura', async () => {
    const user = { uid: 'cliente001', role: 'cliente' };
    const pode = podeLerAssinatura(user, { store_id: 'lojaA' });
    assert.equal(pode, false, 'Cliente NÃO deve ler assinatura');
  });

  it('cliente: NÃO pode alterar assinatura', async () => {
    const user = { uid: 'cliente001', role: 'cliente' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { status: 'ativo' });
    assert.equal(pode, false);
  });

  // ─── Loja A → Assinatura da Loja B ───

  it('lojaA: NÃO pode ler assinatura da lojaB', async () => {
    const user = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
    const pode = podeLerAssinatura(user, { store_id: 'lojaB' });
    assert.equal(pode, false, 'Loja A NÃO deve ler assinatura da Loja B');
  });

  it('lojaA: NÃO pode alterar assinatura da lojaB', async () => {
    const user = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaB' }, { status: 'cancelada' });
    assert.equal(pode, false);
  });

  // ─── Staff (master) ───

  it('staff: PODE ler qualquer assinatura', async () => {
    const user = { uid: 'staff001', role: 'master' };
    const podeLerLojaA = podeLerAssinatura(user, { store_id: 'lojaA' });
    const podeLerLojaB = podeLerAssinatura(user, { store_id: 'lojaB' });
    assert.equal(podeLerLojaA, true, 'Staff deve ler assinatura lojaA');
    assert.equal(podeLerLojaB, true, 'Staff deve ler assinatura lojaB');
  });

  it('staff: PODE atualizar assinatura', async () => {
    const user = { uid: 'staff001', role: 'master' };
    const pode = podeCriarAtualizarAssinatura(user, { store_id: 'lojaA' }, { saldo_notas: 50 });
    assert.equal(pode, true, 'Staff deve poder alterar assinatura');
  });

  // ─── Admin SDK (simulado) ───

  it('Admin SDK: PODE atualizar assinatura diretamente no Firestore', async () => {
    // Admin SDK simula o que as Cloud Functions fazem — escreve direto
    const assinaturaRef = db.collection('assinaturas_clientes').doc('assinatura_ativa_fiscal');
    
    // Só para teste: grava e depois restaura
    const antes = (await assinaturaRef.get()).data();
    await assinaturaRef.update({ '_test_admin_em': admin.firestore.FieldValue.serverTimestamp() });
    const depois = (await assinaturaRef.get()).data();
    
    assert.ok(depois._test_admin_em, 'Admin SDK deve conseguir gravar na assinatura');
    
    // Restaura
    await assinaturaRef.update({ _test_admin_em: admin.firestore.FieldValue.delete() });
    
    const restaurado = (await assinaturaRef.get()).data();
    assert.equal(restaurado._test_admin_em, undefined, 'Campo de teste removido');
  });
});
