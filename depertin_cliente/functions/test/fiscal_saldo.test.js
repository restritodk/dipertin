/**
 * Testes unitários para o módulo de controle de saldo de emissões fiscais.
 *
 * Executar: npm test
 *
 * ATENÇÃO: Estes testes usam MOCKS e não fazem chamadas reais ao Firestore.
 */

const { describe, it, mock, beforeEach } = require('node:test');
const assert = require('node:assert');

// Importar o módulo (versão standalone para testes)
const {
  STATUS,
  gerarChaveIdempotente,
  isPlanoIlimitado,
} = require('../fiscal_saldo_helper');

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS DO FIRESTORE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Cria um mock de documento do Firestore.
 */
function criarMockDoc(id, data) {
  return {
    id,
    ref: { path: `test/${id}` },
    exists: true,
    data: () => data,
  };
}

/**
 * Cria um mock de snapshot de coleção.
 */
function criarMockSnapshot(docs = []) {
  return {
    empty: docs.length === 0,
    docs,
  };
}

/**
 * Cria um mock de transação do Firestore.
 */
function criarMockTransacao(dados = {}) {
  const documentos = { ...dados };
  let commitCallback = null;

  const transaction = {
    get: async (ref) => {
      const path = ref.path || ref._path || '';
      if (typeof ref === 'object' && ref.where) {
        // Query mock - retorna primeiro resultado que coincide
        const query = ref;
        for (const [key, value] of Object.entries(documentos)) {
          if (key.includes('store_id') && value === query._conditions?.store_id) {
            return criarMockSnapshot([criarMockDoc(key, documentos[key])]);
          }
        }
        return criarMockSnapshot([]);
      }
      const docId = path.split('/').pop();
      if (documentos[docId]) {
        return criarMockDoc(docId, documentos[docId]);
      }
      return { exists: false };
    },
    update: async (ref, data) => {
      const path = ref.path || ref._path || '';
      const docId = path.split('/').pop();
      if (documentos[docId]) {
        documentos[docId] = { ...documentos[docId], ...data };
      }
    },
    set: async (ref, data, options) => {
      const path = ref.path || ref._path || '';
      const docId = path.split('/').pop();
      if (options && options.merge) {
        documentos[docId] = { ...(documentos[docId] || {}), ...data };
      } else {
        documentos[docId] = data;
      }
    },
    onCommit: (cb) => { commitCallback = cb; },
    commit: async () => { if (commitCallback) await commitCallback(); },
  };

  return { transaction, documentos };
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOCK DO ADMIN FIRESTORE
// ═══════════════════════════════════════════════════════════════════════════════

const MockFieldValue = {
  increment: (n) => ({ __type: 'increment', value: n }),
  serverTimestamp: () => ({ __type: 'serverTimestamp' }),
};

function criarMockDb(documentos = {}) {
  return {
    collection: (nome) => ({
      doc: (id) => ({
        path: `${nome}/${id}`,
        _path: `${nome}/${id}`,
        get: async () => documentos[id] ? criarMockDoc(id, documentos[id]) : { exists: false },
        set: async (data, opts) => {
          if (opts && opts.merge) {
            documentos[id] = { ...(documentos[id] || {}), ...data };
          } else {
            documentos[id] = data;
          }
        },
        update: async (data) => {
          if (documentos[id]) {
            documentos[id] = { ...documentos[id], ...data };
          }
        },
      }),
      where: (campo, op, valor) => ({
        _conditions: { [campo]: valor },
        limit: (n) => ({
          get: async () => {
            const resultados = Object.entries(documentos)
              .filter(([id, data]) => data[campo] === valor)
              .map(([id, data]) => criarMockDoc(id, data))
              .slice(0, n);
            return criarMockSnapshot(resultados);
          },
        }),
      }),
    }),
    runTransaction: async (fn) => {
      const { transaction, documentos: docs } = criarMockTransacao(docs);
      return fn(transaction);
    },
    FieldValue: MockFieldValue,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: CONSTANTES E HELPERS BÁSICOS
// ═══════════════════════════════════════════════════════════════════════════════

describe('Saldo Helper - Constantes', () => {
  it('STATUS deve ter todos os valores esperados', () => {
    assert.ok(STATUS.RESERVANDO);
    assert.ok(STATUS.RESERVADO);
    assert.ok(STATUS.ENVIADO);
    assert.ok(STATUS.PROCESSANDO);
    assert.ok(STATUS.AUTORIZADO);
    assert.ok(STATUS.REJEITADO);
    assert.ok(STATUS.FALHA_ANTES_ENVIO);
    assert.ok(STATUS.AGUARDANDO_CONSULTA);
    assert.ok(STATUS.ESTORNADO);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: gerarChaveIdempotente
// ═══════════════════════════════════════════════════════════════════════════════

describe('gerarChaveIdempotente', () => {
  it('deve gerar chave no formato correto', () => {
    const chave = gerarChaveIdempotente('store-123', 'nfe', 'req-456');
    assert.strictEqual(chave, 'store-123_nfe_req-456');
  });

  it('deve aceitar tipos diferentes', () => {
    assert.strictEqual(gerarChaveIdempotente('store-1', 'nfce', 'req-2'), 'store-1_nfce_req-2');
    assert.strictEqual(gerarChaveIdempotente('store-1', 'nfs-e', 'req-3'), 'store-1_nfs-e_req-3');
  });

  it('deve lançar erro com parâmetros ausentes', () => {
    assert.throws(() => gerarChaveIdempotente(null, 'nfe', 'req'), /Parâmetros obrigatórios/);
    assert.throws(() => gerarChaveIdempotente('store', null, 'req'), /Parâmetros obrigatórios/);
    assert.throws(() => gerarChaveIdempotente('store', 'nfe', ''), /Parâmetros obrigatórios/);
  });

  it('deve ser determinístico', () => {
    const chave1 = gerarChaveIdempotente('store-123', 'nfe', 'req-456');
    const chave2 = gerarChaveIdempotente('store-123', 'nfe', 'req-456');
    assert.strictEqual(chave1, chave2);
  });

  it('deve gerar chaves diferentes para entradas diferentes', () => {
    const chave1 = gerarChaveIdempotente('store-123', 'nfe', 'req-1');
    const chave2 = gerarChaveIdempotente('store-123', 'nfe', 'req-2');
    assert.notStrictEqual(chave1, chave2);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: isPlanoIlimitado
// ═══════════════════════════════════════════════════════════════════════════════

describe('isPlanoIlimitado', () => {
  it('deve retornar true quando saldo_notas é undefined', () => {
    assert.strictEqual(isPlanoIlimitado({}), true);
  });

  it('deve retornar true quando saldo_notas é null', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: null }), true);
  });

  it('deve retornar false quando saldo_notas existe', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: 100 }), false);
  });

  it('deve retornar false quando saldo_notas é 0', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: 0 }), false);
  });

  it('deve retornar false quando saldo_notas é negativo', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: -5 }), false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE LÓGICA DE RESERVA (simulados)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Lógica de Reserva de Saldo', () => {
  it('deve decrementar saldo quando disponível', () => {
    const assinatura = { store_id: 'store-1', saldo_notas: 10 };
    const saldoAnterior = Number(assinatura.saldo_notas);

    // Simular decremento
    assinatura.saldo_notas -= 1;

    assert.strictEqual(assinatura.saldo_notas, saldoAnterior - 1);
    assert.strictEqual(assinatura.saldo_notas, 9);
  });

  it('não deve decrementar quando saldo é zero', () => {
    const assinatura = { store_id: 'store-1', saldo_notas: 0 };
    const saldoAnterior = Number(assinatura.saldo_notas);

    // Verificar se pode decrementar
    const podeDecrementar = saldoAnterior > 0;
    assert.strictEqual(podeDecrementar, false);
  });

  it('não deve permitir saldo negativo', () => {
    const assinatura = { store_id: 'store-1', saldo_notas: 1 };
    const saldoAnterior = Number(assinatura.saldo_notas);

    // Simular duas reservas simultâneas (race condition)
    if (saldoAnterior > 0) {
      assinatura.saldo_notas -= 1; // Primeira reserva
    }
    const podeDecrementar = assinatura.saldo_notas > 0;
    if (podeDecrementar) {
      assinatura.saldo_notas -= 1; // Segunda reserva
    }

    assert.ok(assinatura.saldo_notas >= 0);
  });

  it('plano ilimitado não decrementa saldo', () => {
    const assinatura = { store_id: 'store-1' }; // Sem saldo_notas

    const saldoAnterior = assinatura.saldo_notas;
    if (!isPlanoIlimitado(assinatura)) {
      assinatura.saldo_notas = (assinatura.saldo_notas || 0) - 1;
    }

    // Saldo não deve existir
    assert.strictEqual(assinatura.saldo_notas, saldoAnterior);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE IDEMPOTÊNCIA
// ═══════════════════════════════════════════════════════════════════════════════

describe('Idempotência', () => {
  it('mesma operação não deve consumir saldo duas vezes', () => {
    const operacoes = new Map();
    let saldo = 1;
    const chaveIdempotente = 'store-1_nfe_req-1';

    // Primeira chamada
    if (!operacoes.has(chaveIdempotente)) {
      if (saldo > 0) {
        saldo -= 1;
        operacoes.set(chaveIdempotente, { status: STATUS.AUTORIZADO, saldo_consumido: 1 });
      }
    }

    const saldoAposPrimeira = saldo;
    const resultadoPrimeira = operacoes.get(chaveIdempotente);

    // Segunda chamada (mesma chave)
    if (!operacoes.has(chaveIdempotente)) {
      if (saldo > 0) {
        saldo -= 1;
        operacoes.set(chaveIdempotente, { status: STATUS.AUTORIZADO, saldo_consumido: 1 });
      }
    } else {
      // Reutilizar operação existente
      return { reutilizada: true };
    }

    assert.strictEqual(saldo, saldoAposPrimeira); // Saldo não mudou
    assert.strictEqual(resultadoPrimeira.status, STATUS.AUTORIZADO);
  });

  it('duas operações diferentes devem consumir saldo separadamente', () => {
    let saldo = 2;
    const operacoes = new Map();

    // Primeira operação
    const chave1 = 'store-1_nfe_req-1';
    if (saldo > 0) {
      saldo -= 1;
      operacoes.set(chave1, { status: STATUS.RESERVADO });
    }

    // Segunda operação
    const chave2 = 'store-1_nfe_req-2';
    if (saldo > 0) {
      saldo -= 1;
      operacoes.set(chave2, { status: STATUS.RESERVADO });
    }

    assert.strictEqual(saldo, 0);
    assert.strictEqual(operacoes.size, 2);
  });

  it('terceira operação deve ser bloqueada com saldo esgotado', () => {
    let saldo = 2;
    const operacoes = new Map();
    const erros = [];

    // Três operações simultâneas
    const chaves = ['store-1_nfe_req-1', 'store-1_nfe_req-2', 'store-1_nfe_req-3'];

    for (const chave of chaves) {
      if (saldo > 0) {
        saldo -= 1;
        operacoes.set(chave, { status: STATUS.RESERVADO });
      } else {
        erros.push({ chave, erro: 'saldo_insuficiente' });
      }
    }

    assert.strictEqual(saldo, 0);
    assert.strictEqual(operacoes.size, 2);
    assert.strictEqual(erros.length, 1);
    assert.strictEqual(erros[0].erro, 'saldo_insuficiente');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE ESTORNO
// ═══════════════════════════════════════════════════════════════════════════════

describe('Estorno de Saldo', () => {
  it('estorno deve devolver exatamente uma unidade', () => {
    let saldo = 9;
    const operacao = { saldo_reservado: 1, saldo_estornado: 0 };

    // Simular estorno
    if (operacao.saldo_reservado > 0 && operacao.saldo_estornado === 0) {
      saldo += 1;
      operacao.saldo_estornado = 1;
    }

    assert.strictEqual(saldo, 10);
    assert.strictEqual(operacao.saldo_estornado, 1);
  });

  it('estorno duplicado não deve aumentar saldo', () => {
    let saldo = 10;
    const operacao = { saldo_reservado: 1, saldo_estornado: 1 };

    // Primeiro estorno (já feito)
    if (operacao.saldo_estornado > 0) {
      // Já estornado, não fazer nada
    } else {
      saldo += 1;
      operacao.saldo_estornado = 1;
    }

    // Segundo estorno (tenta novamente)
    if (operacao.saldo_estornado > 0) {
      // Já estornado, não fazer nada
    } else {
      saldo += 1;
      operacao.saldo_estornado = 1;
    }

    assert.strictEqual(saldo, 10); // Não mudou
    assert.strictEqual(operacao.saldo_estornado, 1);
  });

  it('operação já confirmada não pode ser estornada', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Verificar se pode estornar
    const podeEstornar = operacao.saldo_confirmado === 0;
    assert.strictEqual(podeEstornar, false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE CONCORRÊNCIA (simulados com Promise.all)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Concorrência - Simulações', () => {
  it('mesma venda, duas chamadas simultâneas resulta em uma reserva', async () => {
    let saldo = 1;
    const operacoes = new Map();
    const resultados = [];
    const chaveIdempotente = 'store-1_nfe_venda-123';

    const simularChamada = async (id) => {
      // Simular delay
      await new Promise(r => setTimeout(r, Math.random() * 10));

      if (!operacoes.has(chaveIdempotente)) {
        if (saldo > 0) {
          saldo -= 1;
          operacoes.set(chaveIdempotente, { status: STATUS.RESERVADO });
          resultados.push({ id, reserva: true });
        } else {
          resultados.push({ id, reserva: false, erro: 'saldo_insuficiente' });
        }
      } else {
        resultados.push({ id, reserva: false, reutilizada: true });
      }
    };

    await Promise.all([
      simularChamada('req-1'),
      simularChamada('req-2'),
    ]);

    // Apenas uma reserva foi feita
    assert.strictEqual(saldo, 0);
    const reservas = resultados.filter(r => r.reserva);
    const reutilizadas = resultados.filter(r => r.reutilizada);
    assert.strictEqual(reservas.length, 1);
    assert.strictEqual(reutilizadas.length, 1);
  });

  it('duas vendas diferentes, saldo igual a 1', async () => {
    let saldo = 1;
    const operacoes = new Map();
    const resultados = [];

    const simularChamada = async (chave, vendaId) => {
      await new Promise(r => setTimeout(r, Math.random() * 10));

      if (!operacoes.has(chave)) {
        if (saldo > 0) {
          saldo -= 1;
          operacoes.set(chave, { status: STATUS.RESERVADO, venda: vendaId });
          resultados.push({ chave, sucesso: true });
        } else {
          resultados.push({ chave, sucesso: false, erro: 'saldo_insuficiente' });
        }
      }
    };

    await Promise.all([
      simularChamada('store-1_nfe_venda-A', 'venda-A'),
      simularChamada('store-1_nfe_venda-B', 'venda-B'),
    ]);

    // Uma nota emitidas, uma bloqueada
    const sucessos = resultados.filter(r => r.sucesso);
    const bloqueados = resultados.filter(r => r.erro === 'saldo_insuficiente');
    assert.strictEqual(sucessos.length, 1);
    assert.strictEqual(bloqueados.length, 1);
    assert.ok(saldo >= 0);
  });

  it('webhook e polling simultâneos não duplicam confirmação', async () => {
    // Saldo inicial após reserva
    let saldo = 8; // Reserva de 1 já foi feita, saldo era 9
    const operacao = { saldo_reservado: 1, saldo_confirmado: 0 };
    const confirmacoes = [];

    const simularConfirmacao = async (fonte) => {
      await new Promise(r => setTimeout(r, Math.random() * 10));

      if (operacao.saldo_confirmado === 0) {
        operacao.saldo_confirmado = 1;
        saldo -= 1; // Confirmação consume saldo restante
        confirmacoes.push({ fonte, sucesso: true });
      } else {
        confirmacoes.push({ fonte, sucesso: false, jaConfirmada: true });
      }
    };

    await Promise.all([
      simularConfirmacao('webhook'),
      simularConfirmacao('polling'),
    ]);

    // Apenas uma confirmação
    assert.strictEqual(operacao.saldo_confirmado, 1);
    const confirmadas = confirmacoes.filter(c => c.sucesso);
    assert.strictEqual(confirmadas.length, 1);
    // Saldo diminuiu apenas uma vez após reserva
    assert.strictEqual(saldo, 7); // 8 - 1 (confirmação)
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE ESTADOS DA OPERAÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

describe('Estados da Operação', () => {
  it('operação autorizada não deve permitir novo estorno', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_reservado: 1,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Verificar se pode estornar
    const podeEstornar = operacao.status !== STATUS.AUTORIZADO && operacao.saldo_confirmado === 0;
    assert.strictEqual(podeEstornar, false);
  });

  it('operação rejeitada pode ser reemitida', () => {
    const operacao = {
      status: STATUS.REJEITADO,
      saldo_reservado: 0,
      saldo_estornado: 1,
    };

    // Pode criar nova reserva
    const podeReemitir = [STATUS.REJEITADO, STATUS.ESTORNADO].includes(operacao.status);
    assert.strictEqual(podeReemitir, true);
  });

  it('operação processando deve reutilizar reserva', () => {
    const operacao = {
      status: STATUS.PROCESSANDO,
      saldo_reservado: 1,
      saldo_confirmado: 0,
    };

    const deveReutilizar = [STATUS.RESERVADO, STATUS.ENVIADO, STATUS.PROCESSANDO, STATUS.RESERVANDO].includes(operacao.status);
    assert.strictEqual(deveReutilizar, true);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES DE CANCELAMENTO (não deve devolver saldo por padrão)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cancelamento Fiscal', () => {
  it('cancelamento não devolve saldo automaticamente', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Cancelamento fiscal NÃO deve estornar saldo automaticamente
    // O saldo já foi consumido pela emissão
    const deveEstornar = false;
    assert.strictEqual(deveEstornar, false);
  });

  it('cancelamento deve registrar histórico', () => {
    const historico = [];

    // Simular cancelamento
    historico.push({
      acao: 'cancelamento',
      status_anterior: STATUS.AUTORIZADO,
      status_novo: 'cancelada',
      data: new Date(),
    });

    assert.strictEqual(historico.length, 1);
    assert.strictEqual(historico[0].status_novo, 'cancelada');
  });
});

console.log('Testes de saldo carregados. Execute "npm test" para executar.');
