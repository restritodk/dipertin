/**
 * Proxy Fiscal — WebmaniaBR e outros provedores com autenticacao complexa
 *
 * Fornece Cloud Functions onCall que atuam como proxy para provedores
 * que exigem autenticacao complexa no backend (OAuth 1.0a, etc.).
 *
 * O frontend envia os dados da nota + credenciais; esta function
 * monta a chamada HTTP com a assinatura adequada e retorna o resultado.
 */
const functions = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// Apenas para logging (nunca logar credentials)
const ALLOWED_LOG_FIELDS = ['sucesso', 'chave_acesso', 'protocolo', 'numero', 'status', 'mensagem', 'erro'];

/**
 * Proxy para emissao de NF-e na WebmaniaBR.
 *
 * Frontend envia:
 * {
 *   credentials: { consumer_key, consumer_secret, access_token, access_token_secret, environment },
 *   payload: { ... dados da NF-e no formato WebmaniaBR ... }
 * }
 */
exports.proxyWebmaniaEmitirNota = functions.onCall(
  { enforceAppCheck: false, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Autenticacao necessaria.');
    }

    const data = request.data;
    const credentials = data.credentials || {};
    const payload = data.payload || {};
    const env = credentials.environment || 'homologacao';

    const baseUrl = 'https://webmaniabr.com/api/1/nfe/';
    const body = {
      ...payload,
      ...montarAuthWebmania(credentials),
    };

    try {
      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(body),
      });

      const result = await response.json();

      return processarRespostaWebmania(result, response.status, payload);
    } catch (error) {
      console.error('[proxy-webmania] Erro emissao:', error.message);
      throw new functions.HttpsError('internal', `Erro ao comunicar com WebmaniaBR: ${error.message}`);
    }
  }
);

/**
 * Proxy para cancelamento de NF-e na WebmaniaBR.
 */
exports.proxyWebmaniaCancelarNota = functions.onCall(
  { enforceAppCheck: false, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Autenticacao necessaria.');
    }

    const data = request.data;
    const credentials = data.credentials || {};
    const chaveAcesso = data.chave_acesso;
    const motivo = data.motivo || 'Cancelamento solicitado pelo emitente';

    if (!chaveAcesso) {
      throw new functions.HttpsError('invalid-argument', 'Chave de acesso e obrigatoria.');
    }

    const baseUrl = 'https://webmaniabr.com/api/1/nfe/cancelar/';
    const body = {
      chave: chaveAcesso,
      motivo: motivo,
      ...montarAuthWebmania(credentials),
    };

    try {
      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(body),
      });

      const result = await response.json();

      return processarRespostaWebmania(result, response.status);
    } catch (error) {
      console.error('[proxy-webmania] Erro cancelamento:', error.message);
      throw new functions.HttpsError('internal', `Erro ao cancelar na WebmaniaBR: ${error.message}`);
    }
  }
);

/**
 * Proxy para Carta de Correcao na WebmaniaBR.
 */
exports.proxyWebmaniaCartaCorrecao = functions.onCall(
  { enforceAppCheck: false, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Autenticacao necessaria.');
    }

    const data = request.data;
    const credentials = data.credentials || {};
    const chaveAcesso = data.chave_acesso;
    const correcao = data.correcao;
    const sequencia = data.sequencia || 1;

    if (!chaveAcesso) {
      throw new functions.HttpsError('invalid-argument', 'Chave de acesso e obrigatoria.');
    }
    if (!correcao || correcao.length < 15) {
      throw new functions.HttpsError('invalid-argument', 'Correcao deve ter no minimo 15 caracteres.');
    }

    const baseUrl = 'https://webmaniabr.com/api/1/nfe/carta-correcao/';
    const body = {
      chave: chaveAcesso,
      correcao: correcao,
      sequencia: sequencia,
      ...montarAuthWebmania(credentials),
    };

    try {
      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(body),
      });

      const result = await response.json();
      return processarRespostaWebmania(result, response.status);
    } catch (error) {
      console.error('[proxy-webmania] Erro CC-e:', error.message);
      throw new functions.HttpsError('internal', `Erro ao enviar CC-e na WebmaniaBR: ${error.message}`);
    }
  }
);

/**
 * Proxy para inutilizar numeracao na WebmaniaBR.
 */
exports.proxyWebmaniaInutilizar = functions.onCall(
  { enforceAppCheck: false, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Autenticacao necessaria.');
    }

    const data = request.data;
    const credentials = data.credentials || {};
    const { serie, numero_inicial, numero_final, justificativa } = data;

    if (!serie || !numero_inicial || !numero_final || !justificativa) {
      throw new functions.HttpsError('invalid-argument', 'serie, numero_inicial, numero_final e justificativa sao obrigatorios.');
    }

    const baseUrl = 'https://webmaniabr.com/api/1/nfe/inutilizar/';
    const body = {
      sequencia: `${serie}-${numero_inicial}-${numero_final}`,
      motivo: justificativa,
      ...montarAuthWebmania(credentials),
    };

    try {
      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(body),
      });

      const result = await response.json();
      return processarRespostaWebmania(result, response.status);
    } catch (error) {
      console.error('[proxy-webmania] Erro inutilizar:', error.message);
      throw new functions.HttpsError('internal', `Erro ao inutilizar na WebmaniaBR: ${error.message}`);
    }
  }
);

/**
 * Proxy para testar conexao com WebmaniaBR.
 */
exports.proxyWebmaniaTestarConexao = functions.onCall(
  { enforceAppCheck: false, region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError('unauthenticated', 'Autenticacao necessaria.');
    }

    const data = request.data;
    const credentials = data.credentials || {};

    try {
      const response = await fetch('https://webmaniabr.com/api/1/nfe/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(montarAuthWebmania(credentials)),
      });

      return {
        sucesso: response.ok,
        mensagem: response.ok ? 'Conexao OK' : 'Falha na conexao',
        status: response.status,
      };
    } catch (error) {
      return { sucesso: false, mensagem: `Erro: ${error.message}` };
    }
  }
);

/**
 * Monta os parametros de autenticacao OAuth 1.0a para WebmaniaBR.
 *
 * A WebmaniaBR usa OAuth 1.0a simplificado: envia consumer_key,
 * consumer_secret, access_token e access_token_secret como campos
 * no body da requisicao (nao como header Authorization).
 *
 * Ver documentacao: https://webmaniabr.com/docs/rest-api-nfe/
 */
function montarAuthWebmania(credentials) {
  return {
    consumer_key: credentials.consumer_key || '',
    consumer_secret: credentials.consumer_secret || '',
    access_token: credentials.access_token || '',
    access_token_secret: credentials.access_token_secret || '',
  };
}

/**
 * Processa a resposta da WebmaniaBR e retorna no formato padrao.
 */
function processarRespostaWebmania(json, statusCode, payloadOriginal) {
  const resultado = {
    sucesso: false,
    status: 'erro',
  };

  // Webmania retorna { erro: true, error: 'mensagem' } em caso de erro
  if (json.erro === true || json.error) {
    resultado.erro = json.error || json.mensagem || 'Erro desconhecido na WebmaniaBR';
    resultado.codigo_rejeicao = json.codigo ? String(json.codigo) : String(statusCode);
    return resultado;
  }

  // Sucesso
  resultado.sucesso = true;
  resultado.status = statusCode === 200 ? 'autorizada' : 'processando';
  resultado.chave_acesso = json.chave || json.chave_acesso || null;
  resultado.protocolo = json.protocolo || null;
  resultado.numero = json.nfe || json.numero || (payloadOriginal ? payloadOriginal.numero : null);
  resultado.serie = json.serie || (payloadOriginal ? payloadOriginal.serie : null);
  resultado.xml_url = json.xml || null;
  resultado.pdf_url = json.danfe || null;
  resultado.mensagem = 'Operacao realizada com sucesso.';

  return resultado;
}
