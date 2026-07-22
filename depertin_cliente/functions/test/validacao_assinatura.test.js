/**
 * Testes unitários para validarAssinaturaParaEmissao
 *
 * Executar: npm test
 *
 * ATENÇÃO: Estes testes são MOCKADOS e não fazem chamadas reais ao Firestore.
 * Use emuladores ou teste de integração para testes completos.
 */

const { describe, it, mock, beforeEach } = require('node:test');
const assert = require('node:assert');

/**
 * Versão standalone da função de validação para teste.
 * Copia a lógica de fiscal_nfe_proxy.js para evitar dependência de Admin SDK.
 */
async function validarAssinaturaParaEmissaoMock(db, storeId) {
  const snap = await db
    .collection('assinaturas_clientes')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();

  if (snap.empty) {
    return {
      sucesso: false,
      status: 'assinatura_nao_encontrada',
      mensagem: 'Nenhuma assinatura encontrada para esta loja.',
      erro: 'Assinatura não localizada.',
      technicalMessage: `Nenhuma assinatura em assinaturas_clientes com store_id="${storeId}".`,
      validationErrors: ['Assinatura não encontrada. Contrate um plano para emitir notas fiscais.'],
    };
  }

  const assinatura = snap.docs[0].data();

  // Verifica status
  const statusAssinatura = String(assinatura.status || '').toLowerCase();
  if (statusAssinatura !== 'ativo' && statusAssinatura !== 'active') {
    return {
      sucesso: false,
      status: 'assinatura_inativa',
      mensagem: `Assinatura está ${assinatura.status || 'inativa'}. Ative-a para emitir notas.`,
      erro: `Status da assinatura: ${assinatura.status}`,
      technicalMessage: `Assinatura store_id="${storeId}" com status="${assinatura.status}". Apenas "ativo" é permitido.`,
      validationErrors: [`Assinatura ${assinatura.status || 'inativa'}.`],
    };
  }

  // Verifica pagamento confirmado via status do Mercado Pago
  const mpStatus = String(assinatura.pagamento_mp_status || '').toLowerCase();
  if (mpStatus && mpStatus !== 'approved' && mpStatus !== 'authorized') {
    return {
      sucesso: false,
      status: 'pagamento_nao_confirmado',
      mensagem: 'Pagamento da assinatura não aprovado.',
      erro: `pagamento_mp_status=${mpStatus}`,
      technicalMessage: `Assinatura store_id="${storeId}" com pagamento_mp_status="${mpStatus}". Apenas "approved" ou "authorized" é permitido.`,
      validationErrors: ['Pagamento não aprovado. Aguarde aprovação ou entre em contato com o suporte.'],
    };
  }

  // Verifica módulo fiscal contratado
  // Converte para minúsculas para comparação case-insensitive
  const modulosExtras = (assinatura.modulos_extras || []).map(m => String(m).toLowerCase());
  const moduloFiscalContratado =
    modulosExtras.includes('fiscal') ||
    modulosExtras.includes('modulo_fiscal') ||
    modulosExtras.includes('nfe') ||
    modulosExtras.includes('nfce') ||
    modulosExtras.includes('notas_fiscais');

  if (!moduloFiscalContratado) {
    return {
      sucesso: false,
      status: 'modulo_fiscal_nao_contratado',
      mensagem: 'Módulo fiscal não está incluído no seu plano.',
      erro: 'modulo_fiscal não contratado',
      technicalMessage: `Assinatura store_id="${storeId}" não possui módulo fiscal em modulos_extras=${JSON.stringify(modulosExtras)}.`,
      validationErrors: ['Seu plano não inclui emissão fiscal. Contrate um plano com módulo fiscal.'],
    };
  }

  // Verifica módulo suspenso
  if (assinatura.modulo_fiscal_suspenso === true || modulosExtras.includes('fiscal_suspenso')) {
    return {
      sucesso: false,
      status: 'modulo_fiscal_suspenso',
      mensagem: 'Módulo fiscal está temporariamente suspenso.',
      erro: 'modulo_fiscal_suspenso=true',
      technicalMessage: `Assinatura store_id="${storeId}" com módulo fiscal suspenso.`,
      validationErrors: ['Módulo fiscal suspenso. Entre em contato com o suporte.'],
    };
  }

  // Verifica vencimento
  if (assinatura.data_fim || assinatura.end_date) {
    const fimDate = assinatura.data_fim?.toDate
      ? assinatura.data_fim.toDate()
      : assinatura.end_date instanceof Date
        ? assinatura.end_date
        : new Date(assinatura.data_fim || assinatura.end_date);

    if (fimDate && fimDate < new Date()) {
      return {
        sucesso: false,
        status: 'assinatura_vencida',
        mensagem: `Assinatura vencida em ${fimDate.toLocaleDateString('pt-BR')}.`,
        erro: `data_fim=${fimDate.toISOString()}`,
        technicalMessage: `Assinatura store_id="${storeId}" com data_fim="${fimDate.toISOString()}" (vencida).`,
        validationErrors: [`Assinatura vencida em ${fimDate.toLocaleDateString('pt-BR')}. Renove para continuar.`],
      };
    }
  }

  // Verifica saldo
  const saldoNotas = assinatura.saldo_notas;
  if (saldoNotas !== undefined && saldoNotas !== null && Number(saldoNotas) <= 0) {
    return {
      sucesso: false,
      status: 'saldo_insuficiente',
      mensagem: 'Saldo de notas fiscais esgotado.',
      erro: `saldo_notas=${saldoNotas}`,
      technicalMessage: `Assinatura store_id="${storeId}" com saldo_notas=${saldoNotas} (zerado ou negativo).`,
      validationErrors: ['Saldo de notas fiscais esgotado. Adquira mais notas ou aguarde a renovação do plano.'],
    };
  }

  return { sucesso: true, assinatura };
}

/**
 * Versão standalone da função de validação para documentos existentes.
 */
async function validarAssinaturaParaDocumentoExistenteMock(db, storeId) {
  const snap = await db
    .collection('assinaturas_clientes')
    .where('store_id', '==', storeId)
    .limit(1)
    .get();

  if (snap.empty) {
    return {
      sucesso: false,
      status: 'assinatura_nao_encontrada',
      mensagem: 'Assinatura não encontrada para esta loja.',
      erro: 'Assinatura não localizada.',
      technicalMessage: `Nenhuma assinatura em assinaturas_clientes com store_id="${storeId}".`,
      validationErrors: ['Assinatura não encontrada.'],
    };
  }

  const assinatura = snap.docs[0].data();

  // Para operações em documentos existentes, apenas verificamos que a assinatura PERTENCE a esta loja.
  return { sucesso: true, assinatura };
}

/**
 * Cria mock de db para testes.
 */
function criarMockDb(assinaturas = []) {
  return {
    collection: (nome) => ({
      where: (campo, op, valor) => ({
        limit: (n) => ({
          get: async () => ({
            empty: assinaturas.length === 0,
            docs: assinaturas.map(a => ({
              id: a.id || 'doc-1',
              data: () => ({ ...a }),
            })),
          }),
        }),
      }),
    }),
  };
}

// ============================================================================
// TESTES: validarAssinaturaParaEmissao
// ============================================================================

describe('validarAssinaturaParaEmissao', () => {
  it('deve bloquear quando assinatura não existe', async () => {
    const db = criarMockDb([]);
    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-inexistente');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'assinatura_nao_encontrada');
    assert.ok(resultado.mensagem.includes('encontrada'));
  });

  it('deve bloquear quando status não é ativo', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'suspenso',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'assinatura_inativa');
    assert.ok(resultado.mensagem.includes('suspenso'));
  });

  it('deve bloquear quando pagamento_mp_status não é approved', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'pending',
      modulos_extras: ['fiscal'],
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'pagamento_nao_confirmado');
  });

  it('deve bloquear quando módulo fiscal não está em modulos_extras', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['gestao_comercial', 'relatorios'],
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'modulo_fiscal_nao_contratado');
  });

  it('deve bloquear quando módulo fiscal está suspenso', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal', 'fiscal_suspenso'],
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'modulo_fiscal_suspenso');
  });

  it('deve bloquear quando assinatura está vencida', async () => {
    const dataVencida = new Date();
    dataVencida.setDate(dataVencida.getDate() - 30); // 30 dias atrás

    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      data_fim: dataVencida.toISOString(),
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'assinatura_vencida');
  });

  it('deve bloquear quando saldo é zero', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      saldo_notas: 0,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'saldo_insuficiente');
  });

  it('deve bloquear quando saldo é negativo', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      saldo_notas: -5,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'saldo_insuficiente');
  });

  it('deve permitir quando tudo está válido', async () => {
    const dataFutura = new Date();
    dataFutura.setDate(dataFutura.getDate() + 30); // 30 dias no futuro

    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal', 'gestao_comercial'],
      data_fim: dataFutura.toISOString(),
      saldo_notas: 100,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
    assert.ok(resultado.assinatura);
  });

  it('deve aceitar "active" como status válido', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'active', // em inglês
      pagamento_mp_status: 'approved',
      modulos_extras: ['nfe'],
      saldo_notas: 50,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
  });

  it('deve aceitar "authorized" como status de pagamento', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'authorized',
      modulos_extras: ['nfce'],
      saldo_notas: 50,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
  });

  it('deve aceitar módulos fiscais em diferentes formatos', async () => {
    const modulosTeste = [
      ['fiscal'],
      ['modulo_fiscal'],
      ['nfe'],
      ['nfce'],
      ['notas_fiscais'],
      ['fiscal', 'outro'],
      ['NFE'], // maiúsculas
    ];

    for (const modulos of modulosTeste) {
      const db = criarMockDb([{
        id: 'assinatura-1',
        store_id: 'store-123',
        status: 'ativo',
        pagamento_mp_status: 'approved',
        modulos_extras: modulos,
        saldo_notas: 50,
      }]);

      const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');
      assert.strictEqual(resultado.sucesso, true, `Falhou para modulos: ${JSON.stringify(modulos)}`);
    }
  });

  it('deve permitir quando saldo_notas não existe (ilimitado)', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      // saldo_notas não existe - plano ilimitado
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
  });
});

// ============================================================================
// TESTES: validarAssinaturaParaDocumentoExistente
// ============================================================================

describe('validarAssinaturaParaDocumentoExistente', () => {
  it('deve bloquear quando assinatura não existe', async () => {
    const db = criarMockDb([]);
    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-inexistente');

    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'assinatura_nao_encontrada');
  });

  it('deve permitir quando assinatura existe, mesmo que vencida', async () => {
    const dataVencida = new Date();
    dataVencida.setDate(dataVencida.getDate() - 60); // 60 dias atrás

    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'cancelado', // cancelada!
      pagamento_mp_status: 'refunded',
      modulos_extras: [],
      data_fim: dataVencida.toISOString(),
      saldo_notas: 0,
    }]);

    // Para documento existente, apenas verifica que a assinatura pertence à loja
    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
    assert.ok(resultado.assinatura);
  });

  it('deve permitir quando assinatura está suspensa', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'suspenso',
      pagamento_mp_status: 'pending',
      modulos_extras: ['fiscal_suspenso'],
    }]);

    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-123');

    assert.strictEqual(resultado.sucesso, true);
  });

  it('deve permitir quando pagamento não está aprovado', async () => {
    const db = criarMockDb([{
      id: 'assinatura-1',
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'pending', // pendente
      modulos_extras: ['fiscal'],
    }]);

    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-123');

    // Não verifica pagamento para documento existente
    assert.strictEqual(resultado.sucesso, true);
  });
});

// ============================================================================
// TESTES DE COMPARAÇÃO: Quando cada validação deve ser usada
// ============================================================================

describe('Comparação: Emissão vs Documento Existente', () => {
  it('Emissão: deve bloquear por assinatura vencida', async () => {
    const dataVencida = new Date();
    dataVencida.setDate(dataVencida.getDate() - 10);

    const db = criarMockDb([{
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      data_fim: dataVencida.toISOString(),
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');
    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'assinatura_vencida');
  });

  it('Documento existente: NÃO bloqueia por assinatura vencida', async () => {
    const dataVencida = new Date();
    dataVencida.setDate(dataVencida.getDate() - 10);

    const db = criarMockDb([{
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      data_fim: dataVencida.toISOString(),
    }]);

    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-123');
    assert.strictEqual(resultado.sucesso, true); // Permite!
  });

  it('Emissão: deve bloquear por saldo zero', async () => {
    const db = criarMockDb([{
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      saldo_notas: 0,
    }]);

    const resultado = await validarAssinaturaParaEmissaoMock(db, 'store-123');
    assert.strictEqual(resultado.sucesso, false);
    assert.strictEqual(resultado.status, 'saldo_insuficiente');
  });

  it('Documento existente: NÃO bloqueia por saldo zero', async () => {
    const db = criarMockDb([{
      store_id: 'store-123',
      status: 'ativo',
      pagamento_mp_status: 'approved',
      modulos_extras: ['fiscal'],
      saldo_notas: 0,
    }]);

    const resultado = await validarAssinaturaParaDocumentoExistenteMock(db, 'store-123');
    assert.strictEqual(resultado.sucesso, true); // Permite!
  });
});

console.log('Testes carregados. Execute "npm test" para executar.');
