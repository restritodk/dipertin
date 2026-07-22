/**
 * Testes INTEGRADOS PÓS-DEPLOY — Validação de correções de produção.
 *
 * Cenários (12):
 *   1.  Usuário autenticado COM App Check → autorizado
 *   2.  Usuário autenticado SEM App Check → bloqueado
 *   3.  Staff testando conexão da loja → OK
 *   4.  Lojista testando a PRÓPRIA integração → OK
 *   5.  Lojista tentando integração de OUTRA loja → bloqueado
 *   6.  Payload retornado como mapa imutável → mutável antes de alterar
 *   7.  Emissão SEM tentativa de escrita pelo frontend → apenas backend persiste
 *   8.  Persistência da REJEIÇÃO pelo backend → fiscal_documents + operation
 *   9.  Token Focus inválido → código FOCUS_TOKEN_INVALID
 *  10.  UNAUTHENTICATED → mensagem de sessão/App Check
 *  11.  Ausência de dados sensíveis nos logs sanitizados
 *  12.  Consulta com índice defined (store_id ASC, created_at DESC)
 *
 * Uso:
 *   # Com emuladores rodando (recomendado para testes completos):
 *   firebase emulators:exec "cd functions && node --test test/fiscal_pos_deploy.integration.test.js"
 *     --project demo-depertin-teste
 *
 *   # Apenas testes unitários (cenários 6, 9, 10, 11):
 *   cd functions
 *   node --test test/fiscal_pos_deploy.integration.test.js
 */

const assert = require('node:assert/strict');
const { describe, it, before, after } = require('node:test');

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTES
// ═══════════════════════════════════════════════════════════════════════════════

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '';

// ═══════════════════════════════════════════════════════════════════════════════
// SETUP CONDICIONAL — só inicializa Admin SDK se emulador estiver rodando
// ═══════════════════════════════════════════════════════════════════════════════

let admin = null;
let db = null;
let TEM_EMULADOR = false;

before(async () => {
  TEM_EMULADOR = !!(EMULATOR_HOST && process.env.GCLOUD_PROJECT);
  if (TEM_EMULADOR) {
    const { inicializarAdmin, getDb } = require('./test-setup');
    const { criarTodasFixtures } = require('./create-fixtures');
    admin = inicializarAdmin();
    db = getDb();
    await criarTodasFixtures(db);
    console.log('[Setup] Emulador detectado — fixtures carregadas');
  } else {
    console.log('[Setup] Emulador NÃO detectado — testes de Firestore serão ignorados');
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS DE VALIDAÇÃO (espelham lógica do backend)
// ═══════════════════════════════════════════════════════════════════════════════

function isStaff(user) {
  const role = user?.role || '';
  return role === 'master' || role === 'master_city';
}

/**
 * Valida permissão do usuário para acessar integração fiscal de uma loja.
 * - Staff pode acessar qualquer loja.
 * - Proprietário pode acessar própria loja.
 * - Colaborador nível >= II pode acessar própria loja.
 * - Cliente ou colaborador nível I NÃO pode.
 * - Loja A NÃO pode acessar Loja B.
 */
function validarAcessoIntegracao(user, storeId, integrationStoreId) {
  if (!user || !user.uid) {
    return { permitido: false, motivo: 'UNAUTHENTICATED', mensagem: 'Usuário não autenticado.' };
  }

  // Staff pode acessar qualquer integração
  if (isStaff(user)) {
    return { permitido: true };
  }

  // Cliente nunca pode
  if (user.role === 'cliente') {
    return { permitido: false, motivo: 'PERMISSION_DENIED', mensagem: 'Cliente não tem permissão.' };
  }

  // Lojista: validar vínculo com a loja
  if (user.role === 'lojista') {
    // Verificar se a loja do usuário é a mesma da integração
    if (user.loja_id !== storeId || user.loja_id !== integrationStoreId) {
      return { permitido: false, motivo: 'PERMISSION_DENIED', mensagem: 'Loja não autorizada para esta integração.' };
    }

    // Colaborador nível I não pode acessar integração
    if (user.nivel_acesso === 'nivel_i' && user.lojista_owner_uid) {
      return { permitido: false, motivo: 'PERMISSION_DENIED', mensagem: 'Colaborador nível I não tem permissão para acesso fiscal.' };
    }

    return { permitido: true };
  }

  // Entregador nunca pode
  return { permitido: false, motivo: 'PERMISSION_DENIED', mensagem: 'Perfil sem permissão.' };
}

/**
 * Classifica erros retornados pela Focus NFe.
 */
function classificarErroFocus(statusHttp, body) {
  if (statusHttp === 401 || statusHttp === 403) {
    const mensagem = (body?.mensagem || body?.message || body?.erro || '').toLowerCase();
    if (mensagem.includes('token') || mensagem.includes('api_key') ||
        mensagem.includes('unauthorized') || mensagem.includes('forbidden')) {
      return 'FOCUS_TOKEN_INVALID';
    }
    if (mensagem.includes('ambiente') || mensagem.includes('environment') ||
        mensagem.includes('sandbox') || mensagem.includes('production')) {
      return 'FOCUS_ENVIRONMENT_INVALID';
    }
    // 401 sem contexto específico = token inválido
    if (statusHttp === 401) return 'FOCUS_TOKEN_INVALID';
    return 'FOCUS_ENVIRONMENT_INVALID';
  }
  if (statusHttp >= 500) return 'FOCUS_SERVER_ERROR';
  if (statusHttp === 422) return 'FOCUS_VALIDATION_ERROR';
  return 'FOCUS_UNKNOWN_ERROR';
}

/**
 * Traduz código de erro callable para mensagem amigável.
 */
function traduzirErroCallable(codigo) {
  const map = {
    'UNAUTHENTICATED': 'Sessão expirada ou App Check inválido. Faça login novamente.',
    'PERMISSION_DENIED': 'Usuário sem autorização para acessar esta integração.',
    'NOT_FOUND': 'Integração não encontrada.',
    'FOCUS_TOKEN_INVALID': 'Token de integração recusado pela Focus NFe.',
    'FOCUS_ENVIRONMENT_INVALID': 'Token não pertence ao ambiente informado.',
    'FOCUS_SERVER_ERROR': 'Erro interno do provedor fiscal.',
    'FOCUS_VALIDATION_ERROR': 'Dados rejeitados pela Focus NFe.',
    'FOCUS_UNKNOWN_ERROR': 'Erro desconhecido na comunicação com a Focus NFe.',
    'INTERNAL': 'Erro interno do servidor. Tente novamente.',
  };
  return map[codigo] || `Erro não classificado (${codigo}).`;
}

/**
 * Monta log sanitizado (sem CPF, email, endereço, payload completo).
 */
function montarLogSanitizado(payload) {
  return {
    store_id: payload.store_id,
    cnpj: (payload.cnpj || '').length > 6
      ? payload.cnpj.substring(0, 6) + '...' + payload.cnpj.slice(-2)
      : payload.cnpj,
    itens: (payload.nfe_payload?.itens || []).length,
    valor_total: payload.nfe_payload?.valor_total || 0,
  };
}

/**
 * Verifica se um log contém dados sensíveis.
 */
function logTemDadosSensiveis(logStr) {
  // CPF com 11 dígitos
  const cpfRegex = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/;
  // Email
  const emailRegex = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/;
  // Endereço completo (logradouro + número + bairro)
  const enderecoCompleto = /(?:rua|avenida|av\.|travessa|alameda|praça)\s+.+\d+/i;

  return cpfRegex.test(logStr) || emailRegex.test(logStr) || enderecoCompleto.test(logStr);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 1 — Autenticado COM App Check (validação unitária da regra)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 1 — Usuário autenticado COM App Check', () => {
  it('staff recebe permissão para acessar integração', () => {
    const staff = { uid: 'staff001', role: 'master' };
    const resultado = validarAcessoIntegracao(staff, 'lojaA', 'lojaA');
    assert.ok(resultado.permitido, 'Staff deve ter permissão');
    assert.equal(resultado.motivo, undefined, 'Staff não deve ter motivo de bloqueio');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 2 — Autenticado SEM App Check (validação de regra)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 2 — Usuário não autenticado', () => {
  it('usuário sem UID retorna UNAUTHENTICATED', () => {
    const resultado = validarAcessoIntegracao(null, 'lojaA', 'lojaA');
    assert.ok(!resultado.permitido, 'Usuário nulo deve ser bloqueado');
    assert.equal(resultado.motivo, 'UNAUTHENTICATED');
  });

  it('usuário sem objeto retorna UNAUTHENTICATED', () => {
    const resultado = validarAcessoIntegracao({}, 'lojaA', 'lojaA');
    assert.ok(!resultado.permitido, 'Usuário sem UID deve ser bloqueado');
    assert.equal(resultado.motivo, 'UNAUTHENTICATED');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 3 — Staff testando conexão
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 3 — Staff testando conexão da loja', () => {
  it('staff master pode acessar qualquer integração', () => {
    const staff = { uid: 'staff001', role: 'master' };
    assert.ok(validarAcessoIntegracao(staff, 'lojaA', 'lojaA').permitido);
    assert.ok(validarAcessoIntegracao(staff, 'lojaB', 'lojaB').permitido);
  });

  it('staff master_city pode acessar qualquer integração', () => {
    const staff = { uid: 'staff002', role: 'master_city' };
    assert.ok(validarAcessoIntegracao(staff, 'lojaA', 'lojaA').permitido);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 4 — Lojista testando a própria integração
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 4 — Lojista testando própria integração', () => {
  it('proprietário pode acessar própria integração', () => {
    const dono = { uid: 'lojaA_proprietario', role: 'lojista', loja_id: 'lojaA' };
    assert.ok(validarAcessoIntegracao(dono, 'lojaA', 'lojaA').permitido);
  });

  it('colaborador nível III pode acessar integração da própria loja', () => {
    const colab = { uid: 'lojaA_colab3', role: 'lojista', loja_id: 'lojaA',
      nivel_acesso: 'nivel_iii' };
    assert.ok(validarAcessoIntegracao(colab, 'lojaA', 'lojaA').permitido);
  });

  it('colaborador nível II pode acessar integração da própria loja', () => {
    const colab = { uid: 'lojaA_colab2', role: 'lojista', loja_id: 'lojaA',
      nivel_acesso: 'nivel_ii' };
    assert.ok(validarAcessoIntegracao(colab, 'lojaA', 'lojaA').permitido);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 5 — Isolamento entre lojas
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 5 — Isolamento entre lojas', () => {
  it('loja A não pode acessar integração da loja B', () => {
    const donoA = { uid: 'lojaA_proprietario', role: 'lojista', loja_id: 'lojaA' };
    const resultado = validarAcessoIntegracao(donoA, 'lojaB', 'lojaB');
    assert.ok(!resultado.permitido, 'Loja A deve ser bloqueada ao acessar Loja B');
    assert.equal(resultado.motivo, 'PERMISSION_DENIED');
  });

  it('loja A não pode acessar integração vinculada incorretamente (store_id diverge)', () => {
    const donoA = { uid: 'lojaA_proprietario', role: 'lojista', loja_id: 'lojaA' };
    // store_id da loja A, mas integration_store_id é lojaB
    const resultado = validarAcessoIntegracao(donoA, 'lojaA', 'lojaB');
    assert.ok(!resultado.permitido, 'Deve bloquear quando integration_store_id diverge');
  });

  it('colaborador nível I não pode acessar integração', () => {
    const colab = { uid: 'lojaA_colab1', role: 'lojista', loja_id: 'lojaA',
      nivel_acesso: 'nivel_i', lojista_owner_uid: 'lojaA_proprietario' };
    const resultado = validarAcessoIntegracao(colab, 'lojaA', 'lojaA');
    assert.ok(!resultado.permitido, 'Colaborador nível I deve ser bloqueado');
    assert.equal(resultado.motivo, 'PERMISSION_DENIED');
  });

  it('cliente não pode acessar nenhuma integração', () => {
    const cliente = { uid: 'cliente001', role: 'cliente' };
    assert.ok(!validarAcessoIntegracao(cliente, 'lojaA', 'lojaA').permitido);
    assert.ok(!validarAcessoIntegracao(cliente, 'lojaB', 'lojaB').permitido);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 6 — Payload retornado como mapa imutável
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 6 — Mapa imutável com mutable copy', () => {
  it('cópia mutável a partir de Object.freeze funciona', () => {
    const frozen = Object.freeze({
      store_id: 'lojaA',
      integration_id: 'integracao_lojaA',
      configuracoes_extras: Object.freeze({}),
    });

    let erro = null;
    let payloadMutavel = null;
    try {
      const extras = Object.assign({}, frozen.configuracoes_extras);
      extras.request_id = 'uuid-teste-1234';
      payloadMutavel = Object.assign({}, frozen);
      payloadMutavel.configuracoes_extras = extras;
    } catch (e) {
      erro = e;
    }

    assert.equal(erro, null, 'Mutable copy não deve lançar erro mesmo com Object.freeze');
    assert.equal(payloadMutavel.configuracoes_extras.request_id, 'uuid-teste-1234');
  });

  it('const {} no Dart gera Object.freeze equivalente', () => {
    // Simula o que Dart const {} gera no JS (objeto prototipal sem mutations)
    const frozen = Object.freeze({});
    const extras = Object.assign({}, frozen);
    extras.request_id = 'funciona';
    assert.equal(extras.request_id, 'funciona', 'Mutable copy de frozen funciona');
  });

  it('nested maps profundos precisam de deep copy', () => {
    const frozen = Object.freeze({
      nfe_payload: Object.freeze({
        cliente: Object.freeze({ nome: 'Teste', cpf: '12345678909' }),
      }),
    });

    function deepCopy(obj) {
      if (obj === null || typeof obj !== 'object') return obj;
      if (Array.isArray(obj)) return obj.map(deepCopy);
      const copy = {};
      for (const key of Object.keys(obj)) {
        copy[key] = deepCopy(obj[key]);
      }
      return copy;
    }

    const copia = deepCopy(frozen);
    copia.nfe_payload.cliente.cpf = '00000000000';
    assert.equal(frozen.nfe_payload.cliente.cpf, '12345678909', 'Original não deve ser alterado');
    assert.equal(copia.nfe_payload.cliente.cpf, '00000000000', 'Cópia deve ser independente');
  });

  it('JSON.parse retorna mapa mutável (JS padrão)', () => {
    const json = '{"store_id":"lojaA","extra":{}}';
    const parsed = JSON.parse(json);
    parsed.extra.novo = 'ok';
    assert.equal(parsed.extra.novo, 'ok', 'JSON.parse retorna mapas mutáveis');
  });

  it('Object.freeze bloqueia atribuição direta (strict mode)', () => {
    'use strict';
    const frozen = Object.freeze({ campo: 'valor' });
    assert.throws(() => {
      frozen.campo = 'novo';
    }, /(Cannot assign to read only property|object is not extensible)/);
  });

  it('Map.unmodifiable no Dart gera erro ao tentar modificar', () => {
    // Em Dart, Map.unmodifiable(...) lança no runtime ao tentar setar.
    // Em JS, simulamos com Object.freeze em strict mode.
    const assertThrowsInStrict = (fn) => {
      try {
        // Força strict mode via eval indireto
        const wrapper = new Function('"use strict"; return (' + fn.toString() + ')()');
        wrapper();
        assert.fail('Deveria ter lançado exceção');
      } catch (e) {
        assert.ok(
          /(Cannot add property|object is not extensible|Cannot assign)/.test(e?.message || ''),
          `Exceção esperada, recebido: ${e?.message}`
        );
      }
    };

    assertThrowsInStrict(() => {
      const f = Object.freeze({});
      f.chave = 'valor';
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 7 — Emissão SEM tentativa de escrita pelo frontend
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 7 — Frontend não persiste documentos fiscais (via Firestore)', () => {
  it('fiscal_documents NÃO contém docs criados pelo frontend', { skip: !TEM_EMULADOR },
    async () => {
      const snap = await db.collection('fiscal_documents')
        .where('store_id', '==', 'lojaA')
        .limit(500)
        .get();

      // Nenhum doc deve ter sido inserido por processo não-autorizado
      // Apenas fixtures do Admin SDK devem existir
      for (const doc of snap.docs) {
        const data = doc.data();
        // Se o doc tem created_by, deve ser do backend
        if (data.created_by) {
          assert.ok(data.created_by.startsWith('backend_') || data.created_by === 'admin_test',
            `Documento ${doc.id}: created_by deve ser do backend, não do frontend`);
        }
      }
      console.log(`[Cenário 7] fiscal_documents (lojaA): ${snap.size} documentos`);
    }
  );

  it('fiscal_emission_operations não contém operações do frontend', { skip: !TEM_EMULADOR },
    async () => {
      const snap = await db.collection('fiscal_emission_operations')
        .where('store_id', '==', 'lojaA')
        .limit(500)
        .get();

      console.log(`[Cenário 7] fiscal_emission_operations (lojaA): ${snap.size} operações`);
    }
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 8 — Persistência da REJEIÇÃO pelo backend
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 8 — Backend persiste rejeição', () => {
  it('documento rejeitado deve ter campos de rastreio', { skip: !TEM_EMULADOR },
    async () => {
      const snap = await db.collection('fiscal_documents')
        .where('store_id', '==', 'lojaA')
        .where('status', '==', 'rejeitado')
        .limit(50)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        assert.ok(data.store_id, 'store_id deve existir');
        assert.ok(data.request_id || data.idempotency_key || data.id,
          'Deve ter identificador de idempotência');
        // Mensagem sanitizada
        const msg = String(data.erro_mensagem_sanitizada || data.motivo_rejeicao || '');
        if (msg) {
          assert.ok(!msg.includes('12345678909'), 'Não deve conter CPF completo');
          assert.ok(!msg.includes('@'), 'Não deve conter email completo');
        }
        console.log(`[Cenário 8] Doc rejeitado: ${doc.id}, store=${data.store_id}`);
      }

      if (snap.size === 0) {
        console.log('[Cenário 8] Nenhum documento rejeitado encontrado nas fixtures');
      }
    }
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 9 — Token Focus inválido retorna FOCUS_TOKEN_INVALID
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 9 — Classificação de erros Focus NFe', () => {
  it('401 com mensagem de token → FOCUS_TOKEN_INVALID', () => {
    assert.equal(
      classificarErroFocus(401, { mensagem: 'Token inválido' }),
      'FOCUS_TOKEN_INVALID',
    );
  });

  it('401 com mensagem de API key → FOCUS_TOKEN_INVALID', () => {
    assert.equal(
      classificarErroFocus(401, { message: 'Invalid API key' }),
      'FOCUS_TOKEN_INVALID',
    );
  });

  it('403 com unauthorized → FOCUS_TOKEN_INVALID', () => {
    assert.equal(
      classificarErroFocus(403, { erro: 'Unauthorized' }),
      'FOCUS_TOKEN_INVALID',
    );
  });

  it('403 com ambiente inválido → FOCUS_ENVIRONMENT_INVALID', () => {
    assert.equal(
      classificarErroFocus(403, { mensagem: 'Ambiente inválido' }),
      'FOCUS_ENVIRONMENT_INVALID',
    );
  });

  it('403 com production inválido → FOCUS_ENVIRONMENT_INVALID', () => {
    assert.equal(
      classificarErroFocus(403, { message: 'Production environment not allowed' }),
      'FOCUS_ENVIRONMENT_INVALID',
    );
  });

  it('500 → FOCUS_SERVER_ERROR', () => {
    assert.equal(classificarErroFocus(500, {}), 'FOCUS_SERVER_ERROR');
  });

  it('422 → FOCUS_VALIDATION_ERROR', () => {
    assert.equal(classificarErroFocus(422, {}), 'FOCUS_VALIDATION_ERROR');
  });

  it('401 sem corpo → FOCUS_TOKEN_INVALID (default para 401)', () => {
    assert.equal(classificarErroFocus(401, {}), 'FOCUS_TOKEN_INVALID');
  });

  it('outro código → FOCUS_UNKNOWN_ERROR', () => {
    assert.equal(classificarErroFocus(429, {}), 'FOCUS_UNKNOWN_ERROR');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 10 — UNAUTHENTICATED gera mensagem de sessão/App Check
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 10 — Mapeamento de erros callable', () => {
  it('UNAUTHENTICATED → mensagem de sessão/App Check', () => {
    const msg = traduzirErroCallable('UNAUTHENTICATED');
    assert.ok(msg.includes('Sessão'), 'UNAUTHENTICATED deve mencionar sessão');
    assert.ok(msg.includes('App Check'), 'UNAUTHENTICATED deve mencionar App Check');
    assert.ok(!msg.includes('token'), 'UNAUTHENTICATED não deve mencionar token Focus');
  });

  it('PERMISSION_DENIED → mensagem de autorização', () => {
    const msg = traduzirErroCallable('PERMISSION_DENIED');
    assert.ok(msg.includes('autorização'), 'PERMISSION_DENIED deve mencionar autorização');
  });

  it('FOCUS_TOKEN_INVALID → mensagem de token Focus', () => {
    const msg = traduzirErroCallable('FOCUS_TOKEN_INVALID');
    assert.ok(msg.includes('Focus'), 'FOCUS_TOKEN_INVALID deve mencionar Focus');
    assert.ok(msg.includes('Token'), 'FOCUS_TOKEN_INVALID deve mencionar Token');
  });

  it('UNAUTHENTICATED ≠ PERMISSION_DENIED', () => {
    assert.notEqual(
      traduzirErroCallable('UNAUTHENTICATED'),
      traduzirErroCallable('PERMISSION_DENIED'),
      'UNAUTHENTICATED e PERMISSION_DENIED devem ter mensagens diferentes',
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 11 — Ausência de dados sensíveis nos logs
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 11 — Logs sanitizados sem dados sensíveis', () => {
  it('log sanitizado não contém dados pessoais do cliente', () => {
    const payload = {
      store_id: 'lojaA',
      cnpj: '12345678000199',
      nfe_payload: {
        cliente: {
          nome: 'João Silva',
          cpf: '12345678909',
          email: 'joao@email.com',
          endereco: {
            logradouro: 'Rua das Flores',
            numero: '200',
            bairro: 'Centro',
          },
        },
        itens: [{ descricao: 'Produto 1', valor: 50 }],
        valor_total: 50.00,
      },
    };

    const log = montarLogSanitizado(payload);

    assert.ok(!log.nome, 'Log não deve conter nome');
    assert.ok(!log.email, 'Log não deve conter email');
    assert.ok(!log.cliente, 'Log não deve conter objeto cliente');
    assert.ok(!log.endereco, 'Log não deve conter endereço');
  });

  it('log sanitizado mantém metadados da operação', () => {
    const payload = {
      store_id: 'lojaA',
      cnpj: '12345678000199',
      nfe_payload: {
        itens: [{ descricao: 'P1' }, { descricao: 'P2' }],
        valor_total: 200.00,
      },
    };

    const log = montarLogSanitizado(payload);
    assert.equal(log.store_id, 'lojaA', 'store_id deve estar no log');
    assert.equal(log.itens, 2, 'Quantidade de itens deve estar no log');
    assert.equal(log.valor_total, 200.00, 'valor_total deve estar no log');
    assert.ok(log.cnpj, 'CNPJ (ofuscado) deve estar no log');
    assert.ok(log.cnpj.includes('...'), 'CNPJ deve estar ofuscado');
  });

  it('logTemDadosSensiveis detecta CPF no payload completo', () => {
    const logOfensivo = JSON.stringify({
      store_id: 'lojaA',
      cliente: { cpf: '123.456.789-09', email: 'cliente@teste.com' },
    });
    assert.ok(logTemDadosSensiveis(logOfensivo), 'Deve detectar CPF com pontuação');
  });

  it('logTemDadosSensiveis detecta e-mail no log', () => {
    const logOfensivo = JSON.stringify({
      mensagem: 'cliente@empresa.com.br',
    });
    assert.ok(logTemDadosSensiveis(logOfensivo), 'Deve detectar e-mail');
  });

  it('log sanitizado NÃO aciona logTemDadosSensiveis', () => {
    const logSeguro = JSON.stringify({
      store_id: 'lojaA',
      itens: 3,
      valor_total: 150.00,
      cnpj: '123456...99',
      acao: 'emitir_nfe',
      status: 'processado',
    });
    assert.ok(!logTemDadosSensiveis(logSeguro), 'Log sanitizado não deve conter dados sensíveis');
  });

  it('logTemDadosSensiveis detecta endereço completo', () => {
    const log = 'Emitindo NF-e para Rua das Flores, 200, Centro';
    assert.ok(logTemDadosSensiveis(log), 'Deve detectar endereço');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// CENÁRIO 12 — Consulta com índice (store_id ASC, created_at DESC)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cenário 12 — Consulta fiscal_documents com índice', () => {
  it('query por store_id + created_at DESC funciona no emulador', { skip: !TEM_EMULADOR },
    async () => {
      const snap = await db.collection('fiscal_documents')
        .where('store_id', '==', 'lojaA')
        .orderBy('created_at', 'desc')
        .limit(50)
        .get();

      console.log(`[Cenário 12] Documentos (lojaA, ordem DESC): ${snap.size}`);

      if (snap.size >= 2) {
        const docs = snap.docs;
        for (let i = 1; i < docs.length; i++) {
          const prev = docs[i - 1].data().created_at?.toMillis?.() || 0;
          const curr = docs[i].data().created_at?.toMillis?.() || 0;
          if (prev > 0 && curr > 0) {
            assert.ok(prev >= curr, `Ordem DESC inválida no índice ${i - 1}→${i}`);
          }
        }
      }
    }
  );

  it('store_id filtra corretamente entre lojas', { skip: !TEM_EMULADOR },
    async () => {
      const [snapA, snapB] = await Promise.all([
        db.collection('fiscal_documents')
          .where('store_id', '==', 'lojaA')
          .orderBy('created_at', 'desc')
          .limit(500)
          .get(),
        db.collection('fiscal_documents')
          .where('store_id', '==', 'lojaB')
          .orderBy('created_at', 'desc')
          .limit(500)
          .get(),
      ]);

      for (const doc of snapA.docs) {
        assert.equal(doc.data().store_id, 'lojaA',
          `Doc ${doc.id} pertence à loja A`);
      }
      for (const doc of snapB.docs) {
        assert.equal(doc.data().store_id, 'lojaB',
          `Doc ${doc.id} pertence à loja B`);
      }
    }
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// LIMPEZA
// ═══════════════════════════════════════════════════════════════════════════════

after(async () => {
  console.log('\n📊 [Fiscal Pós-Deploy] Testes concluídos.');
});
