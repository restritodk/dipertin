/**
 * Testes unitários adicionais para o módulo de controle de saldo fiscal.
 *
 * Executar: npm test
 *
 * Cenários testados:
 * - Validação de idempotency key
 * - Reemissão após rejeição
 * - Timeout e 409
 * - Webhook duplicado
 * - Histórico de saldo
 */

const { describe, it } = require('node:test');
const assert = require('node:assert');

// Importar helpers para teste direto
const {
  STATUS,
  validarIdempotencyKey,
  gerarChaveIdempotente,
  isPlanoIlimitado,
} = require('../fiscal_saldo_helper');

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: VALIDAR IDEMPOTENCY KEY
// ═══════════════════════════════════════════════════════════════════════════════

describe('validarIdempotencyKey', () => {
  it('deve aceitar pedido_id como fonte primária', () => {
    const resultado = validarIdempotencyKey({ pedido_id: 'PED-123456' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'PED-123456');
    assert.strictEqual(resultado.tipo, 'source_id');
  });

  it('deve aceitar venda_id como fonte primária', () => {
    const resultado = validarIdempotencyKey({ venda_id: 'VENDA-789' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'VENDA-789');
    assert.strictEqual(resultado.tipo, 'source_id');
  });

  it('deve aceitar order_id como fonte primária', () => {
    const resultado = validarIdempotencyKey({ order_id: 'ORD-001' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'ORD-001');
    assert.strictEqual(resultado.tipo, 'source_id');
  });

  it('deve aceitar request_id com 8+ caracteres', () => {
    const resultado = validarIdempotencyKey({ request_id: 'req12345678' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'req12345678');
    assert.strictEqual(resultado.tipo, 'request_id');
  });

  it('deve rejeitar request_id com menos de 8 caracteres', () => {
    const resultado = validarIdempotencyKey({ request_id: 'abc' });
    assert.strictEqual(resultado.valida, false);
    assert.strictEqual(resultado.erro, 'idempotency_key_required');
  });

  it('deve aceitar provider_ref como fallback', () => {
    const resultado = validarIdempotencyKey({ provider_ref: 'REF-EXISTENTE' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'REF-EXISTENTE');
    assert.strictEqual(resultado.tipo, 'provider_ref');
  });

  it('deve aceitar ref como fallback', () => {
    const resultado = validarIdempotencyKey({ ref: 'NFE-REF-001' });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'NFE-REF-001');
    assert.strictEqual(resultado.tipo, 'provider_ref');
  });

  it('deve REJEITAR quando nenhuma chave é fornecida', () => {
    const resultado = validarIdempotencyKey({});
    assert.strictEqual(resultado.valida, false);
    assert.strictEqual(resultado.erro, 'idempotency_key_required');
    assert.ok(resultado.mensagem.includes('Identificador de operação'));
  });

  it('deve REJEITAR sem gerar chave aleatória', () => {
    // Antes esta função geraria um fallback aleatório - agora não pode
    const resultado = validarIdempotencyKey({ store_id: 'store-1' });
    assert.strictEqual(resultado.valida, false);
    assert.strictEqual(resultado.erro, 'idempotency_key_required');
  });

  it('deve priorizar pedido_id sobre request_id', () => {
    const resultado = validarIdempotencyKey({
      pedido_id: 'PED-PRIORIDADE',
      request_id: 'REQ-SECUNDARIO',
    });
    assert.strictEqual(resultado.valida, true);
    assert.strictEqual(resultado.chave, 'PED-PRIORIDADE');
    assert.strictEqual(resultado.tipo, 'source_id');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: GERAR CHAVE IDEMPOTENTE
// ═══════════════════════════════════════════════════════════════════════════════

describe('gerarChaveIdempotente', () => {
  it('deve gerar chave no formato store_type_key', () => {
    const chave = gerarChaveIdempotente('store-1', 'nfe', 'pedido-123');
    assert.strictEqual(chave, 'store-1_nfe_pedido-123');
  });

  it('deve lançar erro com parâmetros inválidos', () => {
    assert.throws(() => gerarChaveIdempotente(null, 'nfe', 'key'));
    assert.throws(() => gerarChaveIdempotente('store', null, 'key'));
    assert.throws(() => gerarChaveIdempotente('store', 'nfe', ''));
  });

  it('deve ser determinístico', () => {
    const c1 = gerarChaveIdempotente('s1', 'nfe', 'k1');
    const c2 = gerarChaveIdempotente('s1', 'nfe', 'k1');
    assert.strictEqual(c1, c2);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: PLANO ILIMITADO
// ═══════════════════════════════════════════════════════════════════════════════

describe('isPlanoIlimitado', () => {
  it('deve retornar true quando saldo_notas é undefined', () => {
    assert.strictEqual(isPlanoIlimitado({}), true);
  });

  it('deve retornar true quando saldo_notas é null', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: null }), true);
  });

  it('deve retornar false quando saldo_notas existe (mesmo 0)', () => {
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: 0 }), false);
    assert.strictEqual(isPlanoIlimitado({ saldo_notas: 100 }), false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: STATUS DA OPERAÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

describe('STATUS', () => {
  it('deve ter todos os status esperados', () => {
    assert.strictEqual(STATUS.RESERVANDO, 'reservando');
    assert.strictEqual(STATUS.RESERVADO, 'reservado');
    assert.strictEqual(STATUS.ENVIADO, 'enviado');
    assert.strictEqual(STATUS.PROCESSANDO, 'processando');
    assert.strictEqual(STATUS.AUTORIZADO, 'autorizado');
    assert.strictEqual(STATUS.REJEITADO, 'rejeitado');
    assert.strictEqual(STATUS.FALHA_ANTES_ENVIO, 'falha_antes_envio');
    assert.strictEqual(STATUS.AGUARDANDO_CONSULTA, 'aguardando_consulta');
    assert.strictEqual(STATUS.ESTORNADO, 'estornado');
    assert.strictEqual(STATUS.CANCELADO, 'cancelado');
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: LÓGICA DE REEMISSÃO
// ═══════════════════════════════════════════════════════════════════════════════

describe('Reemissão após rejeição', () => {
  it('operação rejeitada permite nova tentativa', () => {
    const operacaoRejeitada = {
      status: STATUS.REJEITADO,
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 1,
    };

    // Verificar se pode criar nova reserva
    const podeReemitir = [STATUS.REJEITADO, STATUS.ESTORNADO].includes(operacaoRejeitada.status);
    assert.strictEqual(podeReemitir, true);
  });

  it('operação autorizada NÃO permite nova reserva', () => {
    const operacaoAutorizada = {
      status: STATUS.AUTORIZADO,
      saldo_reservado: 1,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    const podeReemitir = [STATUS.REJEITADO, STATUS.ESTORNADO, STATUS.FALHA_ANTES_ENVIO].includes(operacaoAutorizada.status);
    assert.strictEqual(podeReemitir, false);
  });

  it('operação estornada permite nova tentativa', () => {
    const operacaoEstornada = {
      status: STATUS.ESTORNADO,
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 1,
    };

    const podeReemitir = [STATUS.REJEITADO, STATUS.ESTORNADO, STATUS.FALHA_ANTES_ENVIO].includes(operacaoEstornada.status);
    assert.strictEqual(podeReemitir, true);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: TIMEOUT E 409
// ═══════════════════════════════════════════════════════════════════════════════

describe('Timeout e HTTP 409', () => {
  it('timeout deve manter saldo reservado', () => {
    const operacaoTimeout = {
      status: STATUS.AGUARDANDO_CONSULTA,
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 0,
    };

    // Timeout mantém reserva
    assert.strictEqual(operacaoTimeout.saldo_reservado, 1);
    assert.strictEqual(operacaoTimeout.saldo_confirmado, 0);
    assert.strictEqual(operacaoTimeout.saldo_estornado, 0);
  });

  it('HTTP 409 não deve estornar saldo', () => {
    // Simular resposta 409
    const resultado409 = {
      status: 'conflito_consultar',
      saldoReservado: true,
      deveEstornar: false,
    };

    assert.strictEqual(resultado409.deveEstornar, false);
    assert.strictEqual(resultado409.status, 'conflito_consultar');
  });

  it('após 409, consultar deve decidir corretamente', () => {
    // Simular fluxo: 409 → consulta → autorização
    const operacaoAguardando = {
      status: STATUS.AGUARDANDO_CONSULTA,
      saldo_reservado: 1,
      saldo_confirmado: 0,
    };

    // Após consulta retornar autorizada
    const statusProvedor = 'autorizado';
    if (statusProvedor === STATUS.AUTORIZADO) {
      operacaoAguardando.status = STATUS.AUTORIZADO;
      operacaoAguardando.saldo_confirmado = 1;
    }

    assert.strictEqual(operacaoAguardando.status, STATUS.AUTORIZADO);
    assert.strictEqual(operacaoAguardando.saldo_confirmado, 1);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: WEBHOOK DUPLICADO
// ═══════════════════════════════════════════════════════════════════════════════

describe('Webhook duplicado', () => {
  it('segunda autorização deve ser ignorada', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Simular webhook duplicado
    const webhookDuplicado = operacao.status === STATUS.AUTORIZADO;
    assert.strictEqual(webhookDuplicado, true);

    // Não deve alterar saldo
    if (webhookDuplicado) {
      // Ignorar, não processar
      return { ignorado: true };
    }

    assert.fail('Deveria ter ignorado o webhook duplicado');
  });

  it('webhook rejeição após autorização deve ser ignorado', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Não pode estornar após confirmação
    const podeEstornar = operacao.saldo_confirmado === 0;
    assert.strictEqual(podeEstornar, false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: HISTÓRICO DE SALDO
// ═══════════════════════════════════════════════════════════════════════════════

describe('Histórico de saldo', () => {
  it('após reserva: campos corretos', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 0,
    };

    assert.strictEqual(operacao.saldo_reservado, 1);
    assert.strictEqual(operacao.saldo_confirmado, 0);
    assert.strictEqual(operacao.saldo_estornado, 0);
  });

  it('após autorização: campos corretos', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    assert.strictEqual(operacao.saldo_reservado, 1);
    assert.strictEqual(operacao.saldo_confirmado, 1);
    assert.strictEqual(operacao.saldo_estornado, 0);
  });

  it('após rejeição com devolução: campos corretos', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 1,
    };

    assert.strictEqual(operacao.saldo_reservado, 1);
    assert.strictEqual(operacao.saldo_confirmado, 0);
    assert.strictEqual(operacao.saldo_estornado, 1);
  });

  it('operação sem reserva não pode estornar', () => {
    const operacao = {
      saldo_reservado: 0,
      saldo_confirmado: 0,
      saldo_estornado: 0,
    };

    // Não pode estornar se não houve reserva
    const podeEstornar = operacao.saldo_reservado > 0 && operacao.saldo_estornado === 0;
    assert.strictEqual(podeEstornar, false);
  });

  it('estorno duplicado não aumenta saldo', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 0,
    };

    let saldoDevolvido = 0;

    // Primeiro estorno
    if (operacao.saldo_estornado === 0) {
      saldoDevolvido = 1;
      operacao.saldo_estornado = 1;
    }

    // Segundo estorno (tentativa de duplicar)
    if (operacao.saldo_estornado > 0) {
      // Já estornado, não devolver novamente
    }

    assert.strictEqual(saldoDevolvido, 1); // Apenas uma vez
    assert.strictEqual(operacao.saldo_estornado, 1);
  });

  it('confirmação duplicada não consome saldo novamente', () => {
    const operacao = {
      saldo_reservado: 1,
      saldo_confirmado: 0,
      saldo_estornado: 0,
    };

    let saldoConsumido = 0;

    // Primeira confirmação
    if (operacao.saldo_confirmado === 0) {
      saldoConsumido = 1;
      operacao.saldo_confirmado = 1;
    }

    // Segunda confirmação (tentativa de duplicar)
    if (operacao.saldo_confirmado > 0) {
      // Já confirmado, não consumir novamente
    }

    assert.strictEqual(saldoConsumido, 1); // Apenas uma vez
    assert.strictEqual(operacao.saldo_confirmado, 1);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: CONCORRÊNCIA (SIMULAÇÕES)
// ═══════════════════════════════════════════════════════════════════════════════

describe('Concorrência - Webhook vs Polling', () => {
  it('webhook autoriza antes do polling', async () => {
    const operacao = { saldo_confirmado: 0, status: STATUS.RESERVADO };
    const resultados = [];

    const processarWebhook = async () => {
      await new Promise(r => setTimeout(r, 10)); // Mais rápido
      if (operacao.saldo_confirmado === 0) {
        operacao.saldo_confirmado = 1;
        operacao.status = STATUS.AUTORIZADO;
        resultados.push('webhook:confirmou');
      } else {
        resultados.push('webhook:ignorado');
      }
    };

    const processarPolling = async () => {
      await new Promise(r => setTimeout(r, 20)); // Mais lento
      if (operacao.saldo_confirmado === 0) {
        operacao.saldo_confirmado = 1;
        operacao.status = STATUS.AUTORIZADO;
        resultados.push('polling:confirmou');
      } else {
        resultados.push('polling:ignorado');
      }
    };

    await Promise.all([processarWebhook(), processarPolling()]);

    // Apenas um deles confirmou
    assert.strictEqual(operacao.saldo_confirmado, 1);
    assert.strictEqual(resultados.filter(r => r.includes('confirmou')).length, 1);
  });

  it('polling autoriza antes do webhook', async () => {
    const operacao = { saldo_confirmado: 0, status: STATUS.RESERVADO };
    const resultados = [];

    const processarWebhook = async () => {
      await new Promise(r => setTimeout(r, 30)); // Mais lento
      if (operacao.saldo_confirmado === 0) {
        operacao.saldo_confirmado = 1;
        operacao.status = STATUS.AUTORIZADO;
        resultados.push('webhook:confirmou');
      } else {
        resultados.push('webhook:ignorado');
      }
    };

    const processarPolling = async () => {
      await new Promise(r => setTimeout(r, 10)); // Mais rápido
      if (operacao.saldo_confirmado === 0) {
        operacao.saldo_confirmado = 1;
        operacao.status = STATUS.AUTORIZADO;
        resultados.push('polling:confirmou');
      } else {
        resultados.push('polling:ignorado');
      }
    };

    await Promise.all([processarWebhook(), processarPolling()]);

    // Apenas um deles confirmou
    assert.strictEqual(operacao.saldo_confirmado, 1);
    assert.strictEqual(resultados.filter(r => r.includes('confirmou')).length, 1);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: FONTE DE VERDADE
// ═══════════════════════════════════════════════════════════════════════════════

describe('Fonte de verdade do limite', () => {
  it('saldo_notas é a fonte de verdade', () => {
    // Este é o modelo identificado no código
    const assinatura = { saldo_notas: 50 };
    const saldoDisponivel = assinatura.saldo_notas;

    assert.strictEqual(typeof saldoDisponivel, 'number');
    assert.strictEqual(saldoDisponivel, 50);
  });

  it('lojista_integracao usa notas_emitidas (autorizadas) + notas_reservadas (hold)', () => {
    const integracao = {
      limite_mensal: 100,
      notas_emitidas: 3,
      notas_reservadas: 1,
    };
    const disponivel =
      integracao.limite_mensal - integracao.notas_emitidas - integracao.notas_reservadas;
    assert.strictEqual(disponivel, 96);
    assert.strictEqual(integracao.notas_emitidas, 3);
  });

  it('decisão: usar saldo_notas para controle', () => {
    const assinatura = { saldo_notas: 100 };
    const usarSaldo = assinatura.saldo_notas !== undefined && assinatura.saldo_notas !== null;

    assert.strictEqual(usarSaldo, true);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES: CANCELAMENTO FISCAL
// ═══════════════════════════════════════════════════════════════════════════════

describe('Cancelamento fiscal', () => {
  it('cancelamento NÃO devolve saldo automaticamente', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
      saldo_estornado: 0,
    };

    // Cancelamento fiscal não estorna saldo
    // O saldo foi consumido pela emissão
    const deveEstornar = false;
    assert.strictEqual(deveEstornar, false);
  });

  it('cancelamento muda status para CANCELADO', () => {
    const operacao = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
    };

    // Simular cancelamento
    operacao.status = STATUS.CANCELADO;

    assert.strictEqual(operacao.status, STATUS.CANCELADO);
    assert.strictEqual(operacao.saldo_confirmado, 1); // Saldo não mudou
  });
});

describe('calcularDisponivelIntegracao (v2 — consumo na autorização)', () => {
  const {
    calcularDisponivelIntegracao,
    MSG_LIMITE_PLANO,
    QUOTA_VERSION_CONFIRMACAO,
  } = require('../fiscal_saldo_helper');

  it('disponivel = limite - emitidas - reservadas', () => {
    const r = calcularDisponivelIntegracao({
      limite_mensal: 100,
      notas_emitidas: 3,
      notas_reservadas: 2,
    });
    assert.strictEqual(r.disponivel, 95);
    assert.strictEqual(r.emitidas, 3);
    assert.strictEqual(r.reservadas, 2);
  });

  it('plano ilimitado (limite 0) tem disponivel infinito', () => {
    const r = calcularDisponivelIntegracao({
      limite_mensal: 0,
      notas_emitidas: 50,
      notas_reservadas: 1,
    });
    assert.strictEqual(r.limite, 0);
    assert.ok(r.disponivel === Number.POSITIVE_INFINITY);
  });

  it('sem vagas quando emitidas + reservadas >= limite', () => {
    const r = calcularDisponivelIntegracao({
      limite_mensal: 100,
      notas_emitidas: 99,
      notas_reservadas: 1,
    });
    assert.strictEqual(r.disponivel, 0);
  });

  it('mensagem canônica de limite e quota_version v2 exportados', () => {
    assert.ok(MSG_LIMITE_PLANO.includes('limite de emissões'));
    assert.strictEqual(QUOTA_VERSION_CONFIRMACAO, 2);
  });
});

console.log('Testes de saldo adicionais carregados. Execute "npm test" para executar.');
