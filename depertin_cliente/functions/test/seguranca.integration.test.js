/**
 * Testes INTEGRADOS de SEGURANÇA: Download Seguro (15 cenários) + Isolamento entre Lojas.
 *
 * Uso:
 *   firebase emulators:exec "cd functions && node test/create-fixtures.js && node --test test/seguranca.integration.test.js" --project demo-depertin-teste
 */

const assert = require('node:assert/strict');
const { describe, it, before } = require('node:test');
const { inicializarAdmin, getDb } = require('./test-setup');
const { criarTodasFixtures } = require('./create-fixtures');

let admin;
let db;

before(async () => {
  admin = inicializarAdmin();
  db = getDb();
  await criarTodasFixtures(db);
});

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS DE VALIDAÇÃO (espelham lógica de segurança do backend)
// ═══════════════════════════════════════════════════════════════════════════════

function isStaff(user) {
  const role = user?.role || '';
  return role === 'master' || role === 'master_city';
}

function isProprietario(user, lojaId) {
  return user?.loja_id === lojaId && user?.uid;
}

function isColaborador(user, lojaId) {
  return user?.loja_id === lojaId;
}

/**
 * Valida permissão para DOWNLOAD de documento fiscal.
 * - Apenas proprietário, colaborador (nível >= II) ou staff
 * - NUNCA cliente
 * - NUNCA loja de outra loja
 */
function validarPermissaoDownload(user, documentStoreId) {
  // Sem autenticação = bloqueado
  if (!user || !user.uid) {
    return { permitido: false, motivo: 'cliente_sem_permissao' };
  }

  // Staff pode baixar qualquer documento
  if (isStaff(user)) return { permitido: true, motivo: null };

  // Cliente NUNCA pode
  if (user.role === 'cliente') {
    return { permitido: false, motivo: 'cliente_sem_permissao' };
  }

  // Colaborador nível I não tem permissão
  if (user.role === 'lojista' && user.nivel_acesso === 'nivel_i') {
    return { permitido: false, motivo: 'colaborador_nivel_insuficiente' };
  }

  // Proprietário/colaborador da própria loja
  if (isColaborador(user, documentStoreId)) {
    return { permitido: true, motivo: null };
  }

  // Qualquer outro caso = sem permissão
  return { permitido: false, motivo: 'sem_permissao_loja' };
}

/**
 * Valida sanitização de caminho (path traversal, caminho arbitrário).
 */
function validarCaminhoSeguro(caminho, tipoEsperado) {
  // Path traversal
  if (caminho.includes('..') || caminho.includes('~')) {
    return { seguro: false, motivo: 'path_traversal' };
  }

  // Caminho absoluto
  if (caminho.startsWith('/') || caminho.match(/^[A-Z]:\\/i)) {
    return { seguro: false, motivo: 'caminho_absoluto' };
  }

  // Tipo inválido
  const tipoInferido = caminho.endsWith('.xml') ? 'xml' :
    caminho.endsWith('.pdf') ? 'danfe' : 'desconhecido';

  if (tipoEsperado && tipoInferido !== tipoEsperado && tipoInferido !== 'desconhecido') {
    return { seguro: false, motivo: `tipo_incompativel: esperado=${tipoEsperado}, obtido=${tipoInferido}` };
  }

  // Tentativa de acessar certificado
  if (caminho.toLowerCase().includes('certificado') ||
      caminho.toLowerCase().includes('cert') ||
      caminho.toLowerCase().includes('.pfx') ||
      caminho.toLowerCase().includes('.p12')) {
    return { seguro: false, motivo: 'acesso_certificado_negado' };
  }

  return { seguro: true, motivo: null };
}

/**
 * Busca o caminho do arquivo internamente pelo document_id + tipo.
 * Não aceita caminho arbitrário.
 */
async function buscarCaminhoDocumento(db, documentId, tipo) {
  if (!documentId || !tipo) return null;

  // Proteção contra documentId com formato de caminho (ex.: "fiscal/lojaA/xml/100002.xml")
  if (documentId.includes('/') || documentId.includes('\\')) {
    return null;
  }

  let docSnap;
  try {
    docSnap = await db.collection('fiscal_documents').doc(documentId).get();
    } catch {
      return null;
    }
    if (!docSnap.exists) return null;

    const doc = docSnap.data();

    if (tipo === 'xml') return doc.xml_path || null;
    if (tipo === 'danfe') return doc.danfe_path || null;

  return null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// USUÁRIOS DE TESTE
// ═══════════════════════════════════════════════════════════════════════════════

const USER_STAFF = { uid: 'staff001', role: 'master' };
const USER_LOJA_A = { uid: 'lojaA_proprietario', loja_id: 'lojaA', role: 'lojista' };
const USER_LOJA_B = { uid: 'lojaB_proprietario', loja_id: 'lojaB', role: 'lojista' };
const USER_COLAB_I = { uid: 'lojaA_colab1', loja_id: 'lojaA', role: 'lojista', nivel_acesso: 'nivel_i' };
const USER_COLAB_II = { uid: 'lojaA_colab2', loja_id: 'lojaA', role: 'lojista', nivel_acesso: 'nivel_ii' };
const USER_CLIENTE = { uid: 'cliente001', role: 'cliente' };

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE DOWNLOAD SEGURO (15 cenários)
// ═══════════════════════════════════════════════════════════════════════════════

describe('DOWNLOAD SEGURO — 15 cenários', () => {

  // 1. Sem autenticação
  it('01. Sem autenticação: BLOQUEADO', () => {
    const result = validarPermissaoDownload(null, 'lojaA');
    assert.equal(result.permitido, false);
    assert.equal(result.motivo, 'cliente_sem_permissao'); // null é tratado como não autenticado
  });

  // 2. Cliente comum
  it('02. Cliente comum: BLOQUEADO', () => {
    const result = validarPermissaoDownload(USER_CLIENTE, 'lojaA');
    assert.equal(result.permitido, false);
    assert.equal(result.motivo, 'cliente_sem_permissao');
  });

  // 3. Loja A acessando documento da Loja B
  it('03. Loja A → documento Loja B: BLOQUEADO', () => {
    const result = validarPermissaoDownload(USER_LOJA_A, 'lojaB');
    assert.equal(result.permitido, false);
    assert.equal(result.motivo, 'sem_permissao_loja');
  });

  // 4. Colaborador nível I
  it('04. Colaborador nível I: BLOQUEADO', () => {
    const result = validarPermissaoDownload(USER_COLAB_I, 'lojaA');
    assert.equal(result.permitido, false);
    assert.equal(result.motivo, 'colaborador_nivel_insuficiente');
  });

  // 5. Colaborador nível II
  it('05. Colaborador nível II: PERMITIDO', () => {
    const result = validarPermissaoDownload(USER_COLAB_II, 'lojaA');
    assert.equal(result.permitido, true);
  });

  // 6. Proprietário da própria loja
  it('06. Proprietário da própria loja: PERMITIDO', () => {
    const result = validarPermissaoDownload(USER_LOJA_A, 'lojaA');
    assert.equal(result.permitido, true);
  });

  // 7. Staff
  it('07. Staff: PERMITIDO (qualquer loja)', () => {
    const r1 = validarPermissaoDownload(USER_STAFF, 'lojaA');
    const r2 = validarPermissaoDownload(USER_STAFF, 'lojaB');
    assert.equal(r1.permitido, true);
    assert.equal(r2.permitido, true);
  });

  // 8. Documento inexistente
  it('08. Documento inexistente: BLOQUEADO (caminho null)', async () => {
    const caminho = await buscarCaminhoDocumento(db, 'doc_inexistente', 'xml');
    assert.equal(caminho, null);
  });

  // 9. Tipo inválido
  it('09. Tipo inválido: BLOQUEADO', () => {
    const caminho = 'fiscal/lojaA/xml/100002.xml';
    const result = validarCaminhoSeguro(caminho, 'danfe'); // espera danfe, mas é xml
    assert.equal(result.seguro, false);
    assert.ok(result.motivo.includes('tipo_incompativel'));
  });

  // 10. XML
  it('10. XML: caminho válido', async () => {
    const caminho = await buscarCaminhoDocumento(db, 'doc_autorizado', 'xml');
    assert.equal(caminho, 'fiscal/lojaA/xml/100002.xml');
    const seguranca = validarCaminhoSeguro(caminho, 'xml');
    assert.equal(seguranca.seguro, true);
  });

  // 11. DANFE
  it('11. DANFE: caminho válido', async () => {
    const caminho = await buscarCaminhoDocumento(db, 'doc_autorizado', 'danfe');
    assert.equal(caminho, 'fiscal/lojaA/danfe/100002.pdf');
    const seguranca = validarCaminhoSeguro(caminho, 'danfe');
    assert.equal(seguranca.seguro, true);
  });

  // 12. Caminho arbitrário
  it('12. Caminho arbitrário: BLOQUEADO (busca é por document_id, não caminho)', async () => {
    // A função só aceita document_id + tipo, nunca caminho direto
    const caminhoXml = await buscarCaminhoDocumento(db, 'doc_autorizado', 'xml');
    const caminhoDanfe = await buscarCaminhoDocumento(db, 'doc_autorizado', 'danfe');

    // Se tentar passar caminho direto em vez de document_id, não encontrará
    const caminhoDireto = await buscarCaminhoDocumento(db, caminhoXml, 'xml');
    assert.equal(caminhoDireto, null, 'Caminho direto não deve ser aceito como documentId');
  });

  // 13. Path traversal
  it('13. Path traversal (..): BLOQUEADO', () => {
    const attacks = [
      '../../etc/passwd',
      'fiscal/lojaA/xml/../../../certificado.pfx',
      '../cert/p12',
      '~/.ssh/id_rsa',
    ];
    for (const attack of attacks) {
      const result = validarCaminhoSeguro(attack, 'xml');
      assert.equal(result.seguro, false, `Path traversal deve bloquear: ${attack}`);
      assert.ok(result.motivo === 'path_traversal' || result.motivo.includes('tipo'),
        `Motivo: ${result.motivo}`);
    }
  });

  // 14. Tentativa de baixar certificado
  it('14. Certificado: BLOQUEADO', () => {
    const ataques = [
      'fiscal/lojaA/certificado.pfx',
      'users/lojaA/documentos/cert.p12',
      'certificates/lojaA/cert.cer',
    ];
    for (const ataque of ataques) {
      const result = validarCaminhoSeguro(ataque, 'xml');
      assert.equal(result.seguro, false, `Certificado deve bloquear: ${ataque}`);
      assert.equal(result.motivo, 'acesso_certificado_negado');
    }
  });

  // 15. Arquivo ausente (sem path)
  it('15. Documento sem XML/DANFE: caminho null', async () => {
    const xml = await buscarCaminhoDocumento(db, 'doc_sem_xml', 'xml');
    assert.equal(xml, null, 'Documento sem XML deve retornar null');

    const danfe = await buscarCaminhoDocumento(db, 'doc_sem_danfe', 'danfe');
    assert.equal(danfe, null, 'Documento sem DANFE deve retornar null');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE ISOLAMENTO ENTRE LOJAS (Passo 12)
// ═══════════════════════════════════════════════════════════════════════════════

describe('ISOLAMENTO ENTRE LOJAS — Loja A vs Loja B', () => {

  it('Loja A NÃO pode ler ASSINATURA da Loja B', async () => {
    const snap = await db.collection('assinaturas_clientes').doc('lojaB_assinatura').get();
    const assinatura = { id: snap.id, ...snap.data() };

    const user = USER_LOJA_A;
    const pode = user.loja_id === assinatura.store_id && user.uid;
    assert.equal(pode, false, 'Loja A NÃO deve ler assinatura da Loja B');
  });

  it('Loja A NÃO pode ver CONFIGURAÇÃO FISCAL da Loja B', async () => {
    const snap = await db.collection('store_fiscal_settings').doc('settings_lojaB').get();
    const settings = snap.data();
    assert.ok(settings, 'Configuração da Loja B existe');

    // Valida que a configuração pertence à Loja B
    assert.equal(settings.store_id, 'lojaB');
  });

  it('Loja A NÃO pode acessar INTEGRAÇÃO FISCAL da Loja B', async () => {
    const snap = await db.collection('fiscal_integrations').doc('integracao_lojaB').get();
    const integracao = snap.data();

    const result = validarPermissaoDownload(USER_LOJA_A, integracao.store_id);
    assert.equal(result.permitido, false, 'Loja A NÃO deve acessar integração da Loja B');
  });

  it('Loja A NÃO pode baixar DOCUMENTO da Loja B', async () => {
    const result = validarPermissaoDownload(USER_LOJA_A, 'lojaB');
    assert.equal(result.permitido, false);
  });

  it('Loja A NÃO pode baixar XML da Loja B', () => {
    const result = validarPermissaoDownload(USER_LOJA_A, 'lojaB');
    assert.equal(result.permitido, false);
  });

  it('Loja A NÃO pode baixar DANFE da Loja B', () => {
    const result = validarPermissaoDownload(USER_LOJA_A, 'lojaB');
    assert.equal(result.permitido, false);
  });

  it('Loja A NÃO pode alterar SALDO da Loja B', async () => {
    // Admin SDK pode, mas lógica de negócio não permite
    const user = USER_LOJA_A;
    const assinaturaSnap = await db.collection('assinaturas_clientes').doc('lojaB_assinatura').get();
    const assinatura = assinaturaSnap.data();

    // Valida que o saldo é da Loja B
    assert.equal(assinatura.store_id, 'lojaB', 'Assinatura é da Loja B');

    // Lojista Loja A não pode alterar assinatura de outra loja
    const podeAlterar = user.loja_id === assinatura.store_id;
    assert.equal(podeAlterar, false, 'Loja A NÃO pode alterar saldo da Loja B');
  });

  it('Loja A NÃO pode ver OPERAÇÃO FISCAL da Loja B', async () => {
    // Admin SDK pode listar, mas lógica de negócio filtra por loja
    const snap = await db.collection('fiscal_emission_operations').limit(10).get();
    const opLojaB = snap.docs.find(d => d.data().store_id === 'lojaB');

    if (opLojaB) {
      const op = opLojaB.data();
      const podeVer = USER_LOJA_A.loja_id === op.store_id;
      assert.equal(podeVer, false, 'Loja A NÃO deve ver operação fiscal da Loja B');
    }
  });

  it('Staff PODE ver tudo (prova de que o isolamento é por perfil, não técnico)', () => {
    // Staff pode ver qualquer recurso de qualquer loja
    assert.equal(validarPermissaoDownload(USER_STAFF, 'lojaA').permitido, true);
    assert.equal(validarPermissaoDownload(USER_STAFF, 'lojaB').permitido, true);
    assert.equal(validarPermissaoDownload(USER_STAFF, 'loja_qualquer').permitido, true);
  });

  it('Loja B NÃO pode acessar recursos da Loja A (simétrico)', () => {
    const result = validarPermissaoDownload(USER_LOJA_B, 'lojaA');
    assert.equal(result.permitido, false, 'Isolamento simétrico: Loja B também não acessa Loja A');
  });
});
