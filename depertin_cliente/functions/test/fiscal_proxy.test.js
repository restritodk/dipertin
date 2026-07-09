/**
 * Testes para o Proxy Fiscal — fiscal_proxy.js
 *
 * Uso: node --test test/fiscal_proxy.test.js
 * Requer: Node 20+
 *
 * Testa a lógica de montagem de autenticação e processamento de resposta
 * sem chamar a API externa.
 */
const assert = require('node:assert');
const { describe, it } = require('node:test');

// ─── Código sob teste (extraído da fiscal_proxy.js) ───

function montarAuthWebmania(credentials) {
  return {
    consumer_key: credentials.consumer_key || '',
    consumer_secret: credentials.consumer_secret || '',
    access_token: credentials.access_token || '',
    access_token_secret: credentials.access_token_secret || '',
  };
}

function processarRespostaWebmania(json, statusCode) {
  const resultado = {
    sucesso: false,
    status: 'erro',
  };

  if (json.erro === true || json.error) {
    resultado.erro = json.error || json.mensagem || 'Erro desconhecido na WebmaniaBR';
    resultado.codigo_rejeicao = json.codigo ? String(json.codigo) : String(statusCode);
    return resultado;
  }

  resultado.sucesso = true;
  resultado.status = statusCode === 200 ? 'autorizada' : 'processando';
  resultado.chave_acesso = json.chave || json.chave_acesso || null;
  resultado.protocolo = json.protocolo || null;
  resultado.numero = json.nfe || json.numero || null;
  resultado.serie = json.serie || null;
  resultado.xml_url = json.xml || null;
  resultado.pdf_url = json.danfe || null;
  resultado.mensagem = 'Operacao realizada com sucesso.';

  return resultado;
}

// ─── Testes ───

describe('Proxy Fiscal — Autenticação WebmaniaBR', () => {
  it('deve montar auth com todas as credenciais', () => {
    const creds = {
      consumer_key: 'ck_123',
      consumer_secret: 'cs_456',
      access_token: 'at_789',
      access_token_secret: 'ats_012',
    };

    const auth = montarAuthWebmania(creds);
    assert.strictEqual(auth.consumer_key, 'ck_123');
    assert.strictEqual(auth.consumer_secret, 'cs_456');
    assert.strictEqual(auth.access_token, 'at_789');
    assert.strictEqual(auth.access_token_secret, 'ats_012');
  });

  it('deve usar string vazia para credenciais ausentes', () => {
    const auth = montarAuthWebmania({});
    assert.strictEqual(auth.consumer_key, '');
    assert.strictEqual(auth.consumer_secret, '');
    assert.strictEqual(auth.access_token, '');
    assert.strictEqual(auth.access_token_secret, '');
  });
});

describe('Proxy Fiscal — Processamento de Resposta', () => {
  it('deve processar resposta de sucesso', () => {
    const json = {
      chave: '12345678901234567890123456789012345678901234',
      protocolo: '123456789',
      nfe: '1001',
      serie: '1',
      xml: 'https://api.webmaniabr.com/xml/123.xml',
      danfe: 'https://api.webmaniabr.com/danfe/123.pdf',
    };

    const result = processarRespostaWebmania(json, 200);
    assert.strictEqual(result.sucesso, true);
    assert.strictEqual(result.status, 'autorizada');
    assert.strictEqual(result.chave_acesso, json.chave);
    assert.strictEqual(result.protocolo, json.protocolo);
    assert.strictEqual(result.numero, '1001');
  });

  it('deve processar resposta de erro', () => {
    const json = {
      erro: true,
      error: 'Certificado digital vencido',
      codigo: '301',
    };

    const result = processarRespostaWebmania(json, 403);
    assert.strictEqual(result.sucesso, false);
    assert.strictEqual(result.erro, 'Certificado digital vencido');
    assert.strictEqual(result.codigo_rejeicao, '301');
  });

  it('deve processar resposta de erro sem codigo', () => {
    const json = {
      erro: true,
      mensagem: 'Limite de emissao excedido',
    };

    const result = processarRespostaWebmania(json, 429);
    assert.strictEqual(result.sucesso, false);
    assert.strictEqual(result.erro, 'Limite de emissao excedido');
    assert.strictEqual(result.codigo_rejeicao, '429');
  });

  it('deve processar resposta processando (status 202)', () => {
    const json = {
      status: 'processando',
    };

    const result = processarRespostaWebmania(json, 202);
    assert.strictEqual(result.sucesso, true);
    assert.strictEqual(result.status, 'processando');
  });

  it('deve processar resposta de sucesso com campos alternativos', () => {
    const json = {
      chave_acesso: '35200601234567012345650123456781234567890123',
      status: 'autorizado',
    };

    const result = processarRespostaWebmania(json, 200);
    assert.strictEqual(result.sucesso, true);
    assert.strictEqual(result.chave_acesso, json.chave_acesso);
  });
});
