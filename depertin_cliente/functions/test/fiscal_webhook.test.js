/**
 * Testes para o Webhook Fiscal — fiscal_webhook.js
 *
 * Uso: node --test test/fiscal_webhook.test.js
 * Requer: Node 20+
 *
 * Testa a lógica de validação de origem e mapeamento de status
 * sem chamar o Firebase em si (mockando as dependências).
 */
const assert = require('node:assert');
const { describe, it, mock } = require('node:test');
const crypto = require('crypto');

// ─── Código sob teste (extraído da fiscal_webhook.js) ───

const WEBHOOK_SECRET = 'test_webhook_secret_key_123456';

function validarOrigem(req, provider) {
  switch (provider) {
    case 'focus_nfe': {
      const signature = req.headers['x-focus-signature'] || '';
      if (!signature || !WEBHOOK_SECRET) {
        return { valido: false, motivo: 'Falta assinatura ou secret nao configurado' };
      }
      const body = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
      const expected = crypto
        .createHmac('sha256', WEBHOOK_SECRET)
        .update(body)
        .digest('hex');
      return signature === expected
        ? { valido: true }
        : { valido: false, motivo: 'HMAC invalido' };
    }

    case 'plug_notas': {
      const apiKey = req.headers['x-api-key'] || '';
      if (!apiKey) {
        return { valido: false, motivo: 'Header X-API-Key ausente' };
      }
      return { valido: apiKey.length >= 10 };
    }

    case 'enotas': {
      const auth = req.headers['authorization'] || '';
      if (!auth.startsWith('Bearer ')) {
        return { valido: false, motivo: 'Authorization header invalido' };
      }
      return { valido: auth.length > 20 };
    }

    case 'nuvem_fiscal': {
      const auth = req.headers['authorization'] || '';
      if (!auth.startsWith('Bearer ')) {
        return { valido: false, motivo: 'Authorization header invalido' };
      }
      return { valido: auth.length > 20 };
    }

    case 'custom':
    case 'webmania_br': {
      return { valido: true };
    }

    default: {
      if (WEBHOOK_SECRET) {
        const body = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
        const signature = req.headers['x-webhook-signature'] || '';
        const expected = crypto
          .createHmac('sha256', WEBHOOK_SECRET)
          .update(body)
          .digest('hex');
        return signature === expected
          ? { valido: true }
          : { valido: false, motivo: 'Assinatura invalida' };
      }
      return { valido: true };
    }
  }
}

function mapearStatus(statusProvedor) {
  const s = String(statusProvedor || '').toLowerCase().trim();

  if (['autorizado', 'aprovado', 'aprovada', 'authorized', 'approved',
       'autorizada', 'concluido', 'concluída', 'completed', 'processed',
       'processado', 'emitido', 'emitida', 'issued', 'success',
       'sucesso', 'ok', 'homologado'].includes(s)) {
    return 'autorizada';
  }

  if (['processando', 'processing', 'pendente', 'pending', 'enviado',
       'sent', 'fila', 'queue', 'na_fila'].includes(s)) {
    return 'processando';
  }

  if (['rejeitado', 'rejeitada', 'rejected', 'recusado', 'recusada',
       'refused', 'denied', 'erro', 'error', 'falhou', 'failed',
       'invalid', 'invalido', 'inválida'].includes(s)) {
    return 'rejeitada';
  }

  if (['cancelado', 'cancelada', 'cancelled', 'canceled', 'cancelamento',
       'cancellation', 'cancelado_homologado', 'cancelamento_homologado'].includes(s)) {
    return 'cancelada';
  }

  if (['contingencia', 'contingency', 'offline'].includes(s)) {
    return 'contingencia';
  }

  return s;
}

// ─── Testes ───

describe('Webhook Fiscal — Validação de Origem', () => {
  it('deve validar Focus NFe com HMAC correto', () => {
    const body = { status: 'autorizado', chave_nfe: '12345678901234567890123456789012345678901234' };
    const bodyStr = JSON.stringify(body);
    const signature = crypto.createHmac('sha256', WEBHOOK_SECRET).update(bodyStr).digest('hex');

    const req = {
      headers: { 'x-focus-signature': signature },
      body: body,
    };

    const result = validarOrigem(req, 'focus_nfe');
    assert.strictEqual(result.valido, true);
  });

  it('deve rejeitar Focus NFe com HMAC inválido', () => {
    const req = {
      headers: { 'x-focus-signature': 'assinatura_invalida' },
      body: { status: 'autorizado' },
    };

    const result = validarOrigem(req, 'focus_nfe');
    assert.strictEqual(result.valido, false);
    assert.strictEqual(result.motivo, 'HMAC invalido');
  });

  it('deve validar PlugNotas com API Key válida', () => {
    const req = {
      headers: { 'x-api-key': 'chave_valida_1234567890' },
      body: {},
    };

    const result = validarOrigem(req, 'plug_notas');
    assert.strictEqual(result.valido, true);
  });

  it('deve rejeitar PlugNotas sem API Key', () => {
    const req = { headers: {}, body: {} };
    const result = validarOrigem(req, 'plug_notas');
    assert.strictEqual(result.valido, false);
  });

  it('deve validar Enotas com Bearer Token', () => {
    const req = {
      headers: { authorization: 'Bearer token_valido_12345678901234567890' },
      body: {},
    };

    const result = validarOrigem(req, 'enotas');
    assert.strictEqual(result.valido, true);
  });

  it('deve rejeitar Enotas sem Authorization header', () => {
    const req = { headers: {}, body: {} };
    const result = validarOrigem(req, 'enotas');
    assert.strictEqual(result.valido, false);
  });

  it('deve validar Nuvem Fiscal com Bearer Token', () => {
    const req = {
      headers: { authorization: 'Bearer token_valido_nuvem_1234567890' },
      body: {},
    };

    const result = validarOrigem(req, 'nuvem_fiscal');
    assert.strictEqual(result.valido, true);
  });

  it('deve validar Webmania BR (sem validação específica)', () => {
    const req = { headers: {}, body: {} };
    const result = validarOrigem(req, 'webmania_br');
    assert.strictEqual(result.valido, true);
  });

  it('deve validar Custom (sem validação específica)', () => {
    const req = { headers: {}, body: {} };
    const result = validarOrigem(req, 'custom');
    assert.strictEqual(result.valido, true);
  });

  it('deve validar webhook genérico com HMAC com secret configurado', () => {
    const body = { evento: 'teste' };
    const bodyStr = JSON.stringify(body);
    const signature = crypto.createHmac('sha256', WEBHOOK_SECRET).update(bodyStr).digest('hex');

    const req = {
      headers: { 'x-webhook-signature': signature },
      body: body,
    };

    const result = validarOrigem(req, 'provedor_desconhecido');
    assert.strictEqual(result.valido, true);
  });

  it('deve rejeitar webhook genérico com HMAC inválido', () => {
    const req = {
      headers: { 'x-webhook-signature': 'invalida' },
      body: { evento: 'teste' },
    };

    const result = validarOrigem(req, 'provedor_desconhecido');
    assert.strictEqual(result.valido, false);
  });
});

describe('Webhook Fiscal — Mapeamento de Status', () => {
  it('deve mapear autorizado para autorizada', () => {
    assert.strictEqual(mapearStatus('autorizado'), 'autorizada');
  });

  it('deve mapear aprovado para autorizada', () => {
    assert.strictEqual(mapearStatus('aprovado'), 'autorizada');
  });

  it('deve mapear success para autorizada', () => {
    assert.strictEqual(mapearStatus('success'), 'autorizada');
  });

  it('deve mapear processing para processando', () => {
    assert.strictEqual(mapearStatus('processing'), 'processando');
  });

  it('deve mapear pending para processando', () => {
    assert.strictEqual(mapearStatus('pending'), 'processando');
  });

  it('deve mapear rejected para rejeitada', () => {
    assert.strictEqual(mapearStatus('rejected'), 'rejeitada');
  });

  it('deve mapear failed para rejeitada', () => {
    assert.strictEqual(mapearStatus('failed'), 'rejeitada');
  });

  it('deve mapear cancelled para cancelada', () => {
    assert.strictEqual(mapearStatus('cancelled'), 'cancelada');
  });

  it('deve mapear canceled para cancelada', () => {
    assert.strictEqual(mapearStatus('canceled'), 'cancelada');
  });

  it('deve mapear contingencia para contingencia', () => {
    assert.strictEqual(mapearStatus('contingencia'), 'contingencia');
  });

  it('deve manter status desconhecido inalterado', () => {
    assert.strictEqual(mapearStatus('status_desconhecido'), 'status_desconhecido');
  });

  it('deve tratar case insensitive', () => {
    assert.strictEqual(mapearStatus('AUTORIZADO'), 'autorizada');
    assert.strictEqual(mapearStatus('ReJeItAdO'), 'rejeitada');
  });

  it('deve tratar undefined como string vazia', () => {
    assert.strictEqual(mapearStatus(undefined), '');
  });
});
