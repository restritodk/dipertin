"use strict";

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * MÓDULO DE CONTROLE DE SALDO PARA EMISSÕES FISCAIS
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * CONTROLADORES TRANSACIONAIS:
 * - Reserva (hold): impede oversell antes do POST
 * - Confirmação: consome de forma definitiva após autorização SEFAZ
 * - Estorno: libera hold (ou devolve saldo v1) em rejeição/falha
 * - Cancelamento fiscal: NÃO devolve crédito já confirmado
 *
 * FONTE DE VERDADE DO LIMITE:
 * - `assinaturas_clientes.saldo_notas` — plano Gestão Comercial (hold na reserva = v1)
 * - `lojista_integracao` — plano admin (v2):
 *     · `notas_emitidas` = autorizadas no ciclo (exibido no card "X de Y")
 *     · `notas_reservadas` = holds em andamento (não entram no card)
 *     · consumo definitivo só em confirmarConsumo / webhook autorizado
 * - Quando a assinatura GC está cancelada/inativa, emissão usa integração admin se ativa
 *
 * REGRAS DE IDEMPOTÊNCIA (obrigatórias):
 * 1. Mesma idempotency_key → MESMA operação (nunca cria nova)
 * 2. Mesma provider_ref → mesma requisição (não envia novamente)
 * 3. Retry usa mesma provider_ref (não gera nova nota)
 * 4. Nova tentativa após rejeição → EXIGE:
 *    - Mesmo source_id (pedido_id original)
 *    - attempt = tentativa anterior + 1
 *    - previous_operation_id apontando para a operação rejeitada
 *    - Nova chave derivada: storeId_docType_sourceId_t{attempt}
 *
 * COLEÇÃO DE CONTROLE: `fiscal_emission_operations`
 */

const admin = require("firebase-admin");
const { Timestamp: FirebaseTimestamp, FieldValue: FirebaseFieldValue } = require("firebase-admin/firestore");

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTES
// ═══════════════════════════════════════════════════════════════════════════════

const COLECAO_OPERACOES = "fiscal_emission_operations";
const COLECAO_ASSINATURAS = "assinaturas_clientes";
const COLECAO_LOJISTA_INTEGRACAO = "lojista_integracao";
const COLECAO_FISCAL_DOCS = "fiscal_documents";

// Status da operação - lifecycle completo
const STATUS = {
  // Estados de transição
  RESERVANDO: "reservando",
  RESERVADO: "reservado",
  ENVIADO: "enviado",
  PROCESSANDO: "processando",

  // Estados finais
  AUTORIZADO: "autorizado",
  REJEITADO: "rejeitado",
  FALHA_ANTES_ENVIO: "falha_antes_envio",
  AGUARDANDO_CONSULTA: "aguardando_consulta",
  ESTORNADO: "estornado",

  // Estados especiais
  CANCELADO: "cancelado", // Cancelamento fiscal (não estorna saldo)
};

// Tipos de resultado de confirmação
const RESULTADO_CONFIRMACAO = {
  JA_CONFIRMADA: "ja_confirmada",
  JA_ESTORNADA: "ja_estornada",
  CONFIRMADA: "confirmada",
  OPERACAO_NAO_ENCONTRADA: "operacao_nao_encontrada",
};

/** Mensagem canônica quando o limite do plano é atingido. */
const MSG_LIMITE_PLANO =
  "Você atingiu o limite de emissões do seu plano. Aguarde a renovação do plano ou faça um upgrade para continuar emitindo NF-e.";

/** quota_version nas operações: 2 = consumo só na autorização (lojista_integracao). */
const QUOTA_VERSION_CONFIRMACAO = 2;

/**
 * Disponibilidade do plano admin (não conta holds no "utilizadas", mas bloqueia oversell).
 * @returns {{ disponivel: number, emitidas: number, reservadas: number, limite: number }}
 */
function calcularDisponivelIntegracao(integracaoData) {
  const limite = Number(integracaoData?.limite_mensal || 0);
  const emitidas = Math.max(0, Number(integracaoData?.notas_emitidas || 0));
  const reservadas = Math.max(0, Number(integracaoData?.notas_reservadas || 0));
  if (limite <= 0) {
    return { disponivel: Number.POSITIVE_INFINITY, emitidas, reservadas, limite: 0 };
  }
  return {
    disponivel: Math.max(0, limite - emitidas - reservadas),
    emitidas,
    reservadas,
    limite,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS DE VALIDAÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Valida se a idempotency_key é estável e rastreável.
 *
 * NÃO permite fallback aleatório. Se não houver chave estável, retorna erro.
 *
 * Prioridades:
 * 1. pedido_id / venda_id / order_id (identificador real da operação)
 * 2. request_id (persistido pelo frontend)
 * 3. provider_ref existente (para retry)
 *
 * @param {object} data - Dados da requisição
 * @returns {object} { valida: boolean, chave: string|null, erro: string|null }
 */
function validarIdempotencyKey(data) {
  // 1. Identificador real da operação comercial
  const sourceId = data.pedido_id || data.venda_id || data.order_id ||
                   data.transaction_id || data.source_id || data.origem_id ||
                   data.lancamento_id;

  if (sourceId) {
    return { valida: true, chave: String(sourceId), tipo: "source_id" };
  }

  // 2. Request ID persistido (deve ser enviado pelo frontend)
  const requestId = data.request_id;
  if (requestId && typeof requestId === "string" && requestId.length >= 8) {
    return { valida: true, chave: String(requestId), tipo: "request_id" };
  }

  // 3. Provider ref existente (para retry)
  const providerRef = data.provider_ref || data.ref;
  if (providerRef && typeof providerRef === "string" && providerRef.length > 0) {
    return { valida: true, chave: String(providerRef), tipo: "provider_ref" };
  }

  // NENHUMA CHAVE ESTÁVEL - ERRO!
  return {
    valida: false,
    chave: null,
    erro: "idempotency_key_required",
    mensagem: "Identificador de operação não fornecido. Use pedido_id, request_id ou provider_ref.",
  };
}

/**
 * Gera chave idempotente para uma operação de emissão (tentativa 1).
 *
 * @param {string} storeId - ID da loja
 * @param {string} documentType - Tipo do documento (nfe, nfce, nfs-e)
 * @param {string} idempotencyKey - Chave de idempotência validada
 * @returns {string} Chave idempotente formatada
 */
function gerarChaveIdempotente(storeId, documentType, idempotencyKey) {
  if (!storeId || !documentType || !idempotencyKey) {
    throw new Error("Parâmetros obrigatórios para chave idempotente");
  }
  return `${storeId}_${documentType}_${idempotencyKey}`;
}

/**
 * Gera chave para nova tentativa de emissão.
 *
 * Formato: storeId_documentType_sourceId_t{attempt}
 *
 * @param {string} storeId - ID da loja
 * @param {string} documentType - Tipo do documento
 * @param {string} sourceId - ID original da operação (pedido_id)
 * @param {number} attempt - Número da tentativa (>= 2)
 * @returns {string} Chave formatada da nova tentativa
 */
function gerarChaveNovaTentativa(storeId, documentType, sourceId, attempt) {
  if (!storeId || !documentType || !sourceId || !attempt) {
    throw new Error("Parâmetros obrigatórios para chave de nova tentativa");
  }
  if (attempt < 2) {
    throw new Error("Nova tentativa só é válida a partir da tentativa 2");
  }
  return `${storeId}_${documentType}_${sourceId}_t${attempt}`;
}

/**
 * Verifica se o plano é ilimitado.
 *
 * @param {object} assinatura - Dados da assinatura
 * @returns {boolean} true se ilimitado
 */
function isPlanoIlimitado(assinatura) {
  if (assinatura.saldo_notas === undefined || assinatura.saldo_notas === null) {
    return true;
  }
  return false;
}

/**
 * Verifica se o status é um estado final (não permite transição).
 *
 * @param {string} status - Status atual
 * @returns {boolean} true se for estado final
 */
function isStatusFinal(status) {
  return [STATUS.AUTORIZADO, STATUS.CANCELADO].includes(status);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: VALIDAR E RESERVAR SALDO (PRIMEIRA TENTATIVA)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Valida e reserva saldo de forma transacional.
 *
 * ⚠️ REGRA DE IDEMPOTÊNCIA ESTRITA:
 * Se a operação já existe com esta chave, SEMPRE retorna a operação existente,
 * independentemente do status (autorizada, rejeitada, estornada, etc).
 *
 * Para criar uma NOVA tentativa após rejeição, use `criarNovaTentativa()`.
 *
 * @param {object} db - Instância do Firestore
 * @param {object} params - Parâmetros da reserva
 * @returns {object} Resultado da reserva
 */
async function validarEReservar(db, params) {
  const {
    storeId,
    assinaturaId,
    documentType,
    idempotencyKey,
    providerRef = null,
    userId,
    integrationId,
    fonteQuota = "assinaturas_clientes",
    integracaoId = null,
  } = params;

  const chaveIdempotente = gerarChaveIdempotente(storeId, documentType, idempotencyKey);
  const now = FirebaseTimestamp.now();
  const usaIntegracaoAdmin = fonteQuota === "lojista_integracao" && integracaoId;

  const resultado = await db.runTransaction(async (transaction) => {
    // 1. Buscar fonte de quota (assinatura GC ou integração admin)
    let assinaturaData = null;
    let assinaturaRef = null;
    let integracaoRef = null;
    let integracaoData = null;

    if (usaIntegracaoAdmin) {
      integracaoRef = db.collection(COLECAO_LOJISTA_INTEGRACAO).doc(integracaoId);
      const integracaoSnap = await transaction.get(integracaoRef);
      if (!integracaoSnap.exists) {
        return {
          sucesso: false,
          status: "integracao_nao_encontrada",
          operacao: null,
        };
      }
      integracaoData = integracaoSnap.data();
      if (integracaoData.store_id !== storeId) {
        return {
          sucesso: false,
          status: "integracao_store_divergente",
          operacao: null,
        };
      }
      if (String(integracaoData.status || "").toLowerCase() !== "ativa") {
        return {
          sucesso: false,
          status: "integracao_fiscal_inativa",
          operacao: null,
        };
      }
    } else {
      const assinaturaSnap = await transaction.get(
        db.collection(COLECAO_ASSINATURAS).where("store_id", "==", storeId).limit(1)
      );

      if (assinaturaSnap.empty) {
        return {
          sucesso: false,
          status: "assinatura_nao_encontrada",
          operacao: null,
        };
      }

      assinaturaData = assinaturaSnap.docs[0].data();
      assinaturaRef = assinaturaSnap.docs[0].ref;
    }

    // 2. Verificar se já existe operação com esta chave
    //    ⚠️ REGRA DE IDEMPOTÊNCIA: mesma chave → SEMPRE retorna a operação existente
    const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
    const opSnap = await transaction.get(opRef);

    if (opSnap.exists) {
      const opData = opSnap.data();

      if (opData.status === STATUS.AUTORIZADO) {
        return {
          sucesso: true,
          status: "ja_autorizada",
          operacao: opData,
          reutilizada: true,
          fiscal_document_id: opData.fiscal_document_id,
        };
      }

      // Qualquer outro status (RESERVADO, REJEITADO, ESTORNADO, etc.) →
      // retorna a operação existente. NUNCA cria nova com a mesma chave.
      const podeReutilizar = opData.status !== STATUS.CANCELADO;
      if (podeReutilizar) {
        return {
          sucesso: true,
          status: opData.status === STATUS.REJEITADO || opData.status === STATUS.ESTORNADO || opData.status === STATUS.FALHA_ANTES_ENVIO
            ? "existe_falha_consulte_nova_tentativa"
            : "ja_existe",
          operacao: opData,
          reutilizada: true,
          provider_ref: opData.provider_ref,
          mensagem: opData.status === STATUS.REJEITADO || opData.status === STATUS.ESTORNADO || opData.status === STATUS.FALHA_ANTES_ENVIO
            ? `Operação anterior ${opData.status}. Para reemitir, use criarNovaTentativa() com attempt=${(opData.tentativa || 1) + 1} e previousOperationId="${chaveIdempotente}".`
            : "Operação já existe em andamento.",
        };
      }
    }

    // 3. Verificar e decrementar saldo (se não for ilimitado)
    let saldoReservado = false;
    let saldoAnterior = null;

    if (usaIntegracaoAdmin) {
      const { disponivel, limite } = calcularDisponivelIntegracao(integracaoData);
      if (limite > 0) {
        saldoAnterior = disponivel;
        if (disponivel <= 0) {
          return {
            sucesso: false,
            status: "saldo_insuficiente",
            saldo_anterior: saldoAnterior,
            operacao: null,
            mensagem: MSG_LIMITE_PLANO,
          };
        }
        // v2: hold em notas_reservadas — notas_emitidas só sobe na autorização
        transaction.update(integracaoRef, {
          notas_reservadas: FirebaseFieldValue.increment(1),
          updated_at: now,
        });
        saldoReservado = true;
      }
    } else if (!isPlanoIlimitado(assinaturaData)) {
      saldoAnterior = Number(assinaturaData.saldo_notas || 0);

      if (saldoAnterior <= 0) {
        return {
          sucesso: false,
          status: "saldo_insuficiente",
          saldo_anterior: saldoAnterior,
          operacao: null,
        };
      }

      // Decrementar saldo atomicamente
      transaction.update(assinaturaRef, {
        saldo_notas: FirebaseFieldValue.increment(-1),
        updated_at: now,
      });
      saldoReservado = true;
    }

    // 4. Criar documento da operação (primeira tentativa)
    const operacaoData = {
      store_id: storeId,
      assinatura_id: assinaturaId,
      document_type: documentType,
      idempotency_key: idempotencyKey,
      source_id: idempotencyKey, // source_id = idempotencyKey na primeira tentativa
      provider_ref: providerRef,
      status: STATUS.RESERVADO,
      saldo_reservado: saldoReservado ? 1 : 0,
      saldo_confirmado: 0,
      saldo_estornado: 0,
      saldo_anterior: saldoAnterior,
      tentativa: 1,
      user_id: userId,
      integration_id: integrationId,
      fonte_quota: fonteQuota,
      integracao_id: integracaoId || null,
      previous_operation_id: null, // primeira tentativa não tem anterior
      // v2 só para integração admin; GC permanece hold-on-reserve (v1)
      quota_version: usaIntegracaoAdmin ? QUOTA_VERSION_CONFIRMACAO : 1,
      created_at: now,
      updated_at: now,
    };

    transaction.set(opRef, operacaoData);

    return {
      sucesso: true,
      status: "reservado",
      operacao: operacaoData,
      reutilizada: false,
      saldo_reservado: saldoReservado,
      saldo_anterior: saldoAnterior,
      provider_ref: providerRef,
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: CRIAR NOVA TENTATIVA APÓS REJEIÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Cria uma nova tentativa de emissão após rejeição definitiva.
 *
 * ⚠️ REGRAS ESTRITAS:
 * 1. OBRIGATÓRIO: previousOperationId (ID da operação rejeitada anterior)
 * 2. OBRIGATÓRIO: attempt = tentativa anterior + 1
 * 3. OBRIGATÓRIO: sourceId = mesmo identificador da venda original
 * 4. Gera chave NOVA e DIFERENTE: storeId_docType_sourceId_t{attempt}
 * 5. Valida que a operação anterior está em estado de falha/rejeição
 * 6. Vincula a nova operação à anterior via previous_operation_id
 * 7. Frontend NÃO pode enviar chave arbitrária — a chave é derivada pelo backend
 *
 * @param {object} db - Instância do Firestore
 * @param {object} params - Parâmetros
 * @returns {object} Resultado
 */
async function criarNovaTentativa(db, params) {
  const {
    storeId,
    assinaturaId,
    documentType,
    sourceId,
    attempt,
    userId,
    integrationId,
    previousOperationId,
    providerRef = null,
  } = params;

  // 1. Validar parâmetros obrigatórios
  if (!storeId || !sourceId || !attempt || !previousOperationId) {
    return {
      sucesso: false,
      status: "parametros_invalidos",
      mensagem: "storeId, sourceId, attempt e previousOperationId são obrigatórios.",
    };
  }

  if (attempt < 2) {
    return {
      sucesso: false,
      status: "tentativa_invalida",
      mensagem: "Nova tentativa deve ser >= 2.",
    };
  }

  const chaveNovaTentativa = gerarChaveNovaTentativa(storeId, documentType, sourceId, attempt);
  const now = FirebaseTimestamp.now();

  const resultado = await db.runTransaction(async (transaction) => {
    // 2. Validar operação anterior
    const prevOpRef = db.collection(COLECAO_OPERACOES).doc(previousOperationId);
    const prevOpSnap = await transaction.get(prevOpRef);

    if (!prevOpSnap.exists) {
      return {
        sucesso: false,
        status: "operacao_anterior_nao_encontrada",
        mensagem: `Operação anterior "${previousOperationId}" não encontrada.`,
      };
    }

    const prevOp = prevOpSnap.data();

    // 3. Verificar se a operação anterior foi rejeitada definitivamente
    const statusesRejeitados = [STATUS.REJEITADO, STATUS.ESTORNADO, STATUS.FALHA_ANTES_ENVIO];
    if (!statusesRejeitados.includes(prevOp.status)) {
      return {
        sucesso: false,
        status: "tentativa_anterior_nao_finalizada",
        mensagem: `A tentativa anterior está em "${prevOp.status}". Só é possível reemitir após rejeição definitiva.`,
        previousStatus: prevOp.status,
      };
    }

    // 4. Verificar que o attempt é o próximo da sequência
    const attemptEsperado = (prevOp.tentativa || 1) + 1;
    if (attempt !== attemptEsperado) {
      return {
        sucesso: false,
        status: "sequencia_tentativa_invalida",
        mensagem: `A nova tentativa deve ser a número ${attemptEsperado}. Fornecido: ${attempt}.`,
        attemptEsperado,
        attemptFornecido: attempt,
      };
    }

    // 5. Verificar se o source_id confere com a operação anterior
    const prevSourceId = prevOp.source_id || prevOp.idempotency_key;
    if (prevSourceId !== sourceId) {
      return {
        sucesso: false,
        status: "source_id_divergente",
        mensagem: `source_id "${sourceId}" não confere com a operação anterior ("${prevSourceId}").`,
      };
    }

    // 6. Verificar se a nova chave já existe (idempotência)
    const novaOpRef = db.collection(COLECAO_OPERACOES).doc(chaveNovaTentativa);
    const novaOpSnap = await transaction.get(novaOpRef);
    if (novaOpSnap.exists) {
      const data = novaOpSnap.data();
      return {
        sucesso: true,
        status: "ja_existe",
        operacao: data,
        reutilizada: true,
      };
    }

    // 7. Buscar assinatura para verificar saldo
    const assinaturaSnap = await transaction.get(
      db.collection(COLECAO_ASSINATURAS).where("store_id", "==", storeId).limit(1)
    );
    if (assinaturaSnap.empty) {
      return { sucesso: false, status: "assinatura_nao_encontrada" };
    }

    const assinaturaData = assinaturaSnap.docs[0].data();
    const assinaturaRef = assinaturaSnap.docs[0].ref;

    // 8. Verificar e decrementar saldo
    let saldoReservado = false;
    let saldoAnterior = null;

    if (!isPlanoIlimitado(assinaturaData)) {
      saldoAnterior = Number(assinaturaData.saldo_notas || 0);
      if (saldoAnterior <= 0) {
        return {
          sucesso: false,
          status: "saldo_insuficiente",
          saldo_anterior: saldoAnterior,
          operacao: null,
        };
      }
      transaction.update(assinaturaRef, {
        saldo_notas: FirebaseFieldValue.increment(-1),
        updated_at: now,
      });
      saldoReservado = true;
    }

    // 9. Criar nova operação com vínculo à anterior
    const operacaoData = {
      store_id: storeId,
      assinatura_id: assinaturaId,
      document_type: documentType,
      idempotency_key: sourceId,
      source_id: sourceId,
      provider_ref: providerRef,
      status: STATUS.RESERVADO,
      saldo_reservado: saldoReservado ? 1 : 0,
      saldo_confirmado: 0,
      saldo_estornado: 0,
      saldo_anterior: saldoAnterior,
      tentativa: attempt,
      user_id: userId,
      integration_id: integrationId,
      previous_operation_id: previousOperationId,
      created_at: now,
      updated_at: now,
    };

    transaction.set(novaOpRef, operacaoData);

    return {
      sucesso: true,
      status: "reservado",
      operacao: operacaoData,
      reutilizada: false,
      saldo_reservado: saldoReservado,
      saldo_anterior: saldoAnterior,
      provider_ref: providerRef,
      chave: chaveNovaTentativa,
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: CONFIRMAR CONSUMO DE SALDO
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Confirma o consumo de saldo de forma idempotente.
 *
 * Regras:
 * 1. Verifica se existe reserva para a chave
 * 2. Verifica se ainda não foi confirmada
 * 3. Verifica se não foi estornada
 * 4. quota_version >= 2 (lojista_integracao): libera hold e incrementa notas_emitidas
 * 5. Marca saldo_confirmado = 1 e status = AUTORIZADO
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente da operação
 * @param {string} fiscalDocumentId - ID do documento fiscal
 * @param {object} providerResponse - Resposta do provedor
 * @returns {object} Resultado da confirmação
 */
async function confirmarConsumo(db, chaveIdempotente, fiscalDocumentId, providerResponse = null) {
  const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
  const now = FirebaseTimestamp.now();

  const resultado = await db.runTransaction(async (transaction) => {
    const opSnap = await transaction.get(opRef);

    if (!opSnap.exists) {
      return {
        sucesso: false,
        status: RESULTADO_CONFIRMACAO.OPERACAO_NAO_ENCONTRADA,
      };
    }

    const opData = opSnap.data();

    // Se já foi confirmada, não fazer nada (idempotente)
    if (opData.saldo_confirmado > 0) {
      return {
        sucesso: true,
        status: RESULTADO_CONFIRMACAO.JA_CONFIRMADA,
        operacao: opData,
      };
    }

    // Se já foi estornada, não confirmar
    if (opData.saldo_estornado > 0) {
      return {
        sucesso: false,
        status: RESULTADO_CONFIRMACAO.JA_ESTORNADA,
        operacao: opData,
      };
    }

    const quotaVersion = Number(opData.quota_version || 1);

    // v2 admin: consumo definitivo só agora
    if (
      quotaVersion >= QUOTA_VERSION_CONFIRMACAO &&
      opData.saldo_reservado > 0 &&
      opData.fonte_quota === "lojista_integracao" &&
      opData.integracao_id
    ) {
      const integracaoRef = db.collection(COLECAO_LOJISTA_INTEGRACAO).doc(opData.integracao_id);
      const integSnap = await transaction.get(integracaoRef);
      if (integSnap.exists) {
        const integ = integSnap.data() || {};
        const reservadas = Math.max(0, Number(integ.notas_reservadas || 0));
        transaction.update(integracaoRef, {
          notas_emitidas: FirebaseFieldValue.increment(1),
          notas_reservadas: Math.max(0, reservadas - 1),
          updated_at: now,
        });
      }
    }

    // Preparar atualização
    const updateData = {
      status: STATUS.AUTORIZADO,
      saldo_confirmado: 1,
      updated_at: now,
    };

    if (fiscalDocumentId) {
      updateData.fiscal_document_id = fiscalDocumentId;
    }

    if (providerResponse) {
      updateData.provider_response_status = providerResponse.status || null;
      updateData.provider_response_message = providerResponse.message || null;
    }

    transaction.update(opRef, updateData);

    return {
      sucesso: true,
      status: RESULTADO_CONFIRMACAO.CONFIRMADA,
      operacao: { ...opData, ...updateData },
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: ESTORNAR SALDO
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Estorna o saldo de forma idempotente.
 *
 * Regras:
 * 1. Verifica se existe reserva para a chave
 * 2. Verifica se ainda não foi estornada
 * 3. Verifica se saldo foi reservado
 * 4. Devolve exatamente uma unidade se houver reserva
 * 5. Marca saldo_estornado = 1
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente da operação
 * @param {string} motivo - Motivo do estorno
 * @param {string} novoStatus - Novo status (falha_antes_envio, rejeitado)
 * @returns {object} Resultado do estorno
 */
async function estornarSaldo(db, chaveIdempotente, motivo, novoStatus = STATUS.ESTORNADO) {
  const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
  const now = FirebaseTimestamp.now();

  const resultado = await db.runTransaction(async (transaction) => {
    const opSnap = await transaction.get(opRef);

    if (!opSnap.exists) {
      return {
        sucesso: false,
        status: RESULTADO_CONFIRMACAO.OPERACAO_NAO_ENCONTRADA,
      };
    }

    const opData = opSnap.data();

    // Se já foi estornada, não fazer nada (idempotente)
    if (opData.saldo_estornado > 0) {
      return {
        sucesso: true,
        status: RESULTADO_CONFIRMACAO.JA_CONFIRMADA,
        operacao: opData,
      };
    }

    // Preparar atualização base
    const updateData = {
      status: novoStatus,
      motivo_estorno: motivo,
      updated_at: now,
    };

    // Se não tinha saldo reservado, apenas atualizar status
    if (!opData.saldo_reservado || opData.saldo_reservado <= 0) {
      transaction.update(opRef, updateData);
      return {
        sucesso: true,
        status: "estornado_sem_saldo",
        operacao: opData,
        saldo_devolvido: 0,
      };
    }

    // Se já foi confirmado, não pode estornar
    if (opData.saldo_confirmado > 0) {
      return {
        sucesso: false,
        status: "ja_confirmada_nao_pode_estornar",
        operacao: opData,
      };
    }

    // Buscar fonte de quota para liberar hold / devolver saldo
    const storeId = opData.store_id;
    const quotaVersion = Number(opData.quota_version || 1);

    if (opData.fonte_quota === "lojista_integracao" && opData.integracao_id) {
      const integracaoRef = db.collection(COLECAO_LOJISTA_INTEGRACAO).doc(opData.integracao_id);
      const integSnap = await transaction.get(integracaoRef);
      if (integSnap.exists) {
        if (quotaVersion >= QUOTA_VERSION_CONFIRMACAO) {
          // v2: só libera hold — notas_emitidas não foi incrementada
          const reservadas = Math.max(0, Number(integSnap.data()?.notas_reservadas || 0));
          transaction.update(integracaoRef, {
            notas_reservadas: Math.max(0, reservadas - 1),
            updated_at: now,
          });
        } else {
          // v1 legado: consumo já estava em notas_emitidas
          transaction.update(integracaoRef, {
            notas_emitidas: FirebaseFieldValue.increment(-1),
            updated_at: now,
          });
        }
      }
    } else {
      const assinaturaSnap = await transaction.get(
        db.collection(COLECAO_ASSINATURAS).where("store_id", "==", storeId).limit(1)
      );

      if (!assinaturaSnap.empty) {
        const assinaturaRef = assinaturaSnap.docs[0].ref;
        transaction.update(assinaturaRef, {
          saldo_notas: FirebaseFieldValue.increment(1),
          updated_at: now,
        });
      }
    }

    // Atualizar operação com marcação de estorno
    transaction.update(opRef, {
      ...updateData,
      saldo_estornado: 1,
    });

    return {
      sucesso: true,
      status: "estornado",
      operacao: opData,
      saldo_devolvido: 1,
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: WEBHOOK - PROCESSAR AUTORIZAÇÃO
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Processa resultado do webhook para autorização.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} providerRef - Referência do provedor (Focus NFe ref)
 * @param {string} status - Status recebido (autorizado, rejeitado, etc)
 * @param {string} fiscalDocumentId - ID do documento fiscal
 * @param {object} providerResponse - Resposta completa do provedor
 * @returns {object} Resultado do processamento
 */
async function processarWebhookAutorizacao(db, providerRef, status, fiscalDocumentId, providerResponse = null) {
  // Buscar operação pela provider_ref
  const operacoesSnap = await db
    .collection(COLECAO_OPERACOES)
    .where("provider_ref", "==", providerRef)
    .limit(1)
    .get();

  if (operacoesSnap.empty) {
    console.warn(`[webhook-saldo] Operação não encontrada para provider_ref=${providerRef}`);
    return {
      sucesso: false,
      status: "operacao_nao_encontrada",
      provider_ref: providerRef,
    };
  }

  const opData = operacoesSnap.docs[0].data();
  const chaveIdempotente = operacoesSnap.docs[0].id;

  // Se já autorizada, ignorar webhook duplicado
  if (opData.status === STATUS.AUTORIZADO) {
    return {
      sucesso: true,
      status: "ja_autorizada",
      operacao: opData,
      duplicado: true,
    };
  }

  // Se já estornada, não processar
  if (opData.saldo_estornado > 0) {
    return {
      sucesso: true,
      status: "ja_estornada_ignorada",
      operacao: opData,
    };
  }

  // Processar baseado no status
  if (status === STATUS.AUTORIZADO || status === "autorizada" || status === "success") {
    // Confirmar consumo (v2 incrementa notas_emitidas aqui)
    return confirmarConsumo(db, chaveIdempotente, fiscalDocumentId, providerResponse);
  }

  // Rejeição definitiva
  if (status === STATUS.REJEITADO || status === "rejeitada" || status === "rejected") {
    const resultado = await estornarSaldo(db, chaveIdempotente, "rejeicao_sefaz: " + (providerResponse?.message || status), STATUS.REJEITADO);
    return resultado;
  }

  // Status inconclusivo - manter reservado
  return {
    sucesso: true,
    status: "inconclusivo_mantido",
    operacao: opData,
    provider_status: status,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: POLLING - CONSULTAR STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Consulta status de uma operação via polling.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} providerRef - Referência do provedor
 * @param {string} statusProvedor - Status retornado pelo provedor
 * @param {string} fiscalDocumentId - ID do documento fiscal (se existir)
 * @param {object} providerResponse - Resposta do provedor
 * @returns {object} Resultado da consulta
 */
async function processarPolling(db, providerRef, statusProvedor, fiscalDocumentId, providerResponse) {
  // Usa o mesmo helper de webhook
  return processarWebhookAutorizacao(db, providerRef, statusProvedor, fiscalDocumentId, providerResponse);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: ATUALIZAR PROVIDER_REF
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Atualiza a provider_ref de uma operação existente.
 * Usado quando precisamos vincular uma provider_ref após retry.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente
 * @param {string} novaProviderRef - Nova referência do provedor
 * @returns {object} Resultado da atualização
 */
async function atualizarProviderRef(db, chaveIdempotente, novaProviderRef) {
  const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
  const now = FirebaseTimestamp.now();

  const resultado = await db.runTransaction(async (transaction) => {
    const opSnap = await transaction.get(opRef);

    if (!opSnap.exists) {
      return { sucesso: false, status: "operacao_nao_encontrada" };
    }

    const opData = opSnap.data();

    // Se já tem provider_ref, não sobrescrever
    if (opData.provider_ref && opData.provider_ref !== novaProviderRef) {
      return {
        sucesso: true,
        status: "provider_ref_ja_existe",
        provider_ref: opData.provider_ref,
      };
    }

    transaction.update(opRef, {
      provider_ref: novaProviderRef,
      updated_at: now,
    });

    return {
      sucesso: true,
      status: "atualizado",
      provider_ref: novaProviderRef,
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: OBTER OPERAÇÃO POR CHAVE
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Obtém uma operação pela chave idempotente.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente
 * @returns {object|null} Dados da operação ou null
 */
async function obterOperacao(db, chaveIdempotente) {
  const opSnap = await db.collection(COLECAO_OPERACOES).doc(chaveIdempotente).get();
  return opSnap.exists ? opSnap.data() : null;
}

/**
 * Obtém uma operação pela provider_ref.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} providerRef - Referência do provedor
 * @returns {object|null} Dados da operação ou null
 */
async function obterOperacaoPorProviderRef(db, providerRef) {
  const snap = await db
    .collection(COLECAO_OPERACOES)
    .where("provider_ref", "==", providerRef)
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].data();
}

/**
 * Obtém a operação mais recente para um source_id.
 *
 * Busca por idempotency_key (que armazena o source_id original).
 * Útil para localizar a tentativa anterior antes de criar nova tentativa.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} storeId - ID da loja
 * @param {string} sourceId - source_id da operação
 * @returns {object|null} Dados + id da operação ou null
 */
async function obterOperacaoPorSourceId(db, storeId, sourceId) {
  const snap = await db
    .collection(COLECAO_OPERACOES)
    .where("store_id", "==", storeId)
    .where("source_id", "==", sourceId)
    .orderBy("tentativa", "desc")
    .limit(1)
    .get();
  if (snap.empty) return null;
  return { id: snap.docs[0].id, ...snap.docs[0].data() };
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: INCREMENTAR TENTATIVA
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Incrementa o contador de tentativas de uma operação.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente
 * @returns {number} Número da nova tentativa
 */
async function incrementarTentativa(db, chaveIdempotente) {
  const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
  const now = FirebaseTimestamp.now();

  await opRef.update({
    tentativa: FirebaseFieldValue.increment(1),
    updated_at: now,
  });

  const opSnap = await opRef.get();
  return opSnap.data()?.tentativa || 1;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: ATUALIZAR STATUS (genérico)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Atualiza status da operação de forma idempotente.
 *
 * @param {object} db - Instância do Firestore
 * @param {string} chaveIdempotente - Chave idempotente
 * @param {string} novoStatus - Novo status
 * @param {object} extraData - Dados extras
 * @returns {object} Resultado
 */
async function atualizarStatus(db, chaveIdempotente, novoStatus, extraData = {}) {
  const opRef = db.collection(COLECAO_OPERACOES).doc(chaveIdempotente);
  const now = FirebaseTimestamp.now();

  const resultado = await db.runTransaction(async (transaction) => {
    const opSnap = await transaction.get(opRef);

    if (!opSnap.exists) {
      return { sucesso: false, status: "operacao_nao_encontrada" };
    }

    const opData = opSnap.data();

    // Não permite reverter autorização
    if (opData.status === STATUS.AUTORIZADO && novoStatus !== STATUS.AUTORIZADO) {
      return {
        sucesso: false,
        status: "ja_autorizada_nao_pode_alterar",
        operacao: opData,
      };
    }

    transaction.update(opRef, {
      status: novoStatus,
      updated_at: now,
      ...extraData,
    });

    return {
      sucesso: true,
      status: "atualizado",
      operacao: { ...opData, status: novoStatus },
    };
  });

  return resultado;
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

module.exports = {
  // Constantes
  STATUS,
  RESULTADO_CONFIRMACAO,
  COLECAO_OPERACOES,
  COLECAO_ASSINATURAS,
  MSG_LIMITE_PLANO,
  QUOTA_VERSION_CONFIRMACAO,

  // Helpers de validação
  validarIdempotencyKey,
  gerarChaveIdempotente,
  gerarChaveNovaTentativa,
  isPlanoIlimitado,
  isStatusFinal,
  calcularDisponivelIntegracao,

  // Helpers transacionais principais
  validarEReservar,
  criarNovaTentativa,
  confirmarConsumo,
  estornarSaldo,

  // Helpers de webhook/polling
  processarWebhookAutorizacao,
  processarPolling,
  atualizarProviderRef,

  // Helpers de consulta
  obterOperacao,
  obterOperacaoPorProviderRef,
  obterOperacaoPorSourceId,

  // Helpers de manipulação de status
  atualizarStatus,
  incrementarTentativa,
};
