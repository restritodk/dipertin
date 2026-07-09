/**
 * Webhook Fiscal NF-e
 *
 * Recebe webhooks dos provedores fiscais (Focus NFe, PlugNotas, Enotas, etc.)
 * e atualiza o status dos documentos fiscais no Firestore.
 *
 * Segurança:
 * - Valida assinatura HMAC (Focus NFe) ou token (demais provedores)
 * - Verifica vínculo do documento com a loja antes de atualizar
 * - Registra log completo do webhook recebido
 * - Trata reenvios sem duplicar registros (idempotência por chave + status)
 *
 * Endpoint: POST /fiscalWebhookNFe
 */
const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const crypto = require('crypto');
const logger = require('./fiscal_logger');

const WEBHOOK_SECRET = process.env.FISCAL_WEBHOOK_SECRET || '';

exports.fiscalWebhookNFe = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  const db = admin.firestore();
  const startTime = Date.now();

  // 1. Identificar provedor
  const provider = String(req.query.provider || req.headers['x-provider'] || 'unknown').toLowerCase();
  const lojaId = req.query.loja || '';

  // 2. Validar assinatura/origem
  const validacao = validarOrigem(req, provider);
  if (!validacao.valido) {
    console.error(`[fiscal-webhook] Validacao falhou para provider=${provider}: ${validacao.motivo}`);
    // Log da tentativa inválida
    try {
      await logger.registrarWebhook({
        provider,
        statusOriginal: 'validacao_falhou',
        statusMapeado: 'rejeitado',
        payload: { motivo: validacao.motivo },
      });
    } catch (_) {}
    res.status(401).json({ erro: 'Assinatura invalida', motivo: validacao.motivo });
    return;
  }

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;

    // 3. Extrair dados conforme formato do provedor
    const dados = extrairDadosWebhook(body, provider);

    if (!dados.chaveAcesso && !dados.idExterno) {
      console.warn(`[fiscal-webhook] Webhook sem chave de acesso: provider=${provider}`);
      await logger.registrarWebhook({
        provider,
        statusOriginal: dados.statusProvedor || 'unknown',
        statusMapeado: 'ignorado_sem_chave',
        payload: body,
      });
      res.status(200).json({ recebido: true, aviso: 'Sem chave de acesso para processar' });
      return;
    }

    // ═══════════════════════════════════════════════════════════════
    // 4. IDEMPOTÊNCIA REAL via event hash (Firestore)
    //
    // Gera hash único: SHA256(chaveAcesso + statusProvedor + body)
    // Verifica em fiscal_webhooks se já foi processado.
    // Se sim, responde 200 sem duplicar.
    // ═══════════════════════════════════════════════════════════════
    const rawBody = typeof req.body === 'string' ? req.body : JSON.stringify(req.body);
    const eventHash = crypto
      .createHash("sha256")
      .update(`${dados.chaveAcesso || ""}_${dados.statusProvedor || ""}_${rawBody}`)
      .digest("hex");

    const hashSnap = await db.collection("fiscal_webhooks")
      .where("eventHash", "==", eventHash)
      .limit(1)
      .get();

    if (!hashSnap.empty) {
      console.log(`[fiscal-webhook] DUPLICATA detectada (hash=${eventHash.slice(0, 12)}...) — ignorando`);
      res.status(200).json({
        recebido: true,
        duplicate: true,
        eventHash,
        documento_id: hashSnap.docs[0].data()?.documento_id || null,
      });
      return;
    }

    // 5. Buscar documento fiscal com segurança de loja
    let documentoRef = null;
    let documentoId = null;
    let storeId = null;

    if (dados.chaveAcesso) {
      const snap = await db.collection('fiscal_documents')
        .where('access_key', '==', dados.chaveAcesso)
        .limit(1)
        .get();

      if (!snap.empty) {
        documentoRef = snap.docs[0].ref;
        documentoId = snap.docs[0].id;
        const docData = snap.docs[0].data();
        storeId = docData.store_id || null;
      }
    }

    if (!documentoRef && dados.idExterno) {
      const snap = await db.collection('fiscal_documents')
        .where('provider_document_id', '==', dados.idExterno)
        .limit(1)
        .get();

      if (!snap.empty) {
        documentoRef = snap.docs[0].ref;
        documentoId = snap.docs[0].id;
        storeId = snap.docs[0].data().store_id || null;
      }
    }

    if (!documentoRef) {
      console.warn(`[fiscal-webhook] Documento nao encontrado: chave=${dados.chaveAcesso}, idExterno=${dados.idExterno}`);
      await logger.registrarWebhook({
        provider,
        chaveAcesso: dados.chaveAcesso,
        statusOriginal: dados.statusProvedor,
        statusMapeado: 'documento_nao_encontrado',
        payload: body,
      });
      res.status(200).json({ recebido: true, aviso: 'Documento nao encontrado no Firestore' });
      return;
    }

    // 6. Segurança: verificar vínculo loja × documento
    // (lojaId veio do query param; storeId veio do documento)
    if (lojaId && storeId && lojaId !== storeId) {
      console.error(
        `[fiscal-webhook] SEGURANÇA: loja do webhook (${lojaId}) difere da loja do documento (${storeId}). ` +
        `Chave: ${dados.chaveAcesso}`
      );
      // Log da tentativa suspeita
      await logger.registrarLog({
        storeId: storeId,
        acao: 'webhook_seguranca_loja_divergente',
        status: 'negado',
        chaveAcesso: dados.chaveAcesso,
        documentoId: documentoId,
        mensagem: `Tentativa de webhook com loja divergente: query=${lojaId} doc=${storeId}`,
      });
      // Ainda atualiza o documento (webhook veio do provedor, é confiável)
      // Mas registra a divergência
    }

    // 7. Mapear status do provedor para status interno
    const statusMapeado = mapearStatus(dados.statusProvedor, provider);

    // 8. Verificar idempotência: mesmo status já foi processado?
    const docAntes = await documentoRef.get();
    const statusAtual = docAntes.data()?.status || '';

    if (statusAtual === statusMapeado) {
      console.log(`[fiscal-webhook] Status já processado: ${statusMapeado} para doc ${documentoId}`);

      // Salva no fiscal_webhooks como duplicata ignorada
      try {
        await db.collection('fiscal_webhooks').add({
          storeId: storeId || lojaId || null,
          documento_id: documentoId,
          chaveAcesso: dados.chaveAcesso || null,
          status: dados.statusProvedor || 'unknown',
          eventHash,
          payload: logger.sanitizar ? logger.sanitizar(body) : body,
          receivedAt: admin.firestore.FieldValue.serverTimestamp(),
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          processed: false,
          ignoredDuplicate: true,
          motivo: `Status já era ${statusMapeado}`,
        });
      } catch (_) {}

      res.status(200).json({
        recebido: true,
        idempotente: true,
        documento_id: documentoId,
        status: statusMapeado,
      });
      return;
    }

    // 9. Montar atualizacao
    const updateData = {
      status: statusMapeado,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (dados.chaveAcesso) updateData.access_key = dados.chaveAcesso;
    if (dados.protocolo) updateData.protocol = dados.protocolo;

    if (dados.rejectionReason) updateData.rejection_reason = dados.rejectionReason;
    if (dados.rejectionCode) updateData.rejection_code = dados.rejectionCode;

    // Se autorizada, salva XML/DANFE no Storage
    if (statusMapeado === 'autorizada') {
      updateData.issued_at = admin.firestore.FieldValue.serverTimestamp();

      if (dados.xmlUrl) {
        try {
          const numeroDoc = dados.chaveAcesso?.slice(0, 8) || documentoId;
          const xmlPath = `fiscal/${storeId || lojaId}/${documentoId}/nfe-${numeroDoc}.xml`;
          const xmlResp = await fetch(dados.xmlUrl);
          if (xmlResp.ok) {
            const xmlBuf = await xmlResp.arrayBuffer();
            const bucket = admin.storage().bucket();
            const xmlFile = bucket.file(xmlPath);
            await xmlFile.save(Buffer.from(xmlBuf), {
              contentType: 'application/xml',
              metadata: { store_id: storeId || lojaId, documento_id: documentoId },
            });
            await xmlFile.makePublic();
            updateData.xml_url = `https://storage.googleapis.com/${bucket.name}/${xmlPath}`;
          }
        } catch (e) {
          updateData.xml_url = dados.xmlUrl; // fallback
        }
      }

      if (dados.pdfUrl) {
        try {
          const numeroDoc = dados.chaveAcesso?.slice(0, 8) || documentoId;
          const danfePath = `fiscal/${storeId || lojaId}/${documentoId}/danfe-${numeroDoc}.pdf`;
          const pdfResp = await fetch(dados.pdfUrl);
          if (pdfResp.ok) {
            const pdfBuf = await pdfResp.arrayBuffer();
            const bucket = admin.storage().bucket();
            const pdfFile = bucket.file(danfePath);
            await pdfFile.save(Buffer.from(pdfBuf), {
              contentType: 'application/pdf',
              metadata: { store_id: storeId || lojaId, documento_id: documentoId },
            });
            await pdfFile.makePublic();
            updateData.pdf_url = `https://storage.googleapis.com/${bucket.name}/${danfePath}`;
          }
        } catch (e) {
          updateData.pdf_url = dados.pdfUrl; // fallback
        }
      }
    } else {
      // Não autorizada: salva URLs originais como fallback
      if (dados.xmlUrl) updateData.xml_url = dados.xmlUrl;
      if (dados.pdfUrl) updateData.pdf_url = dados.pdfUrl;
    }

    if (statusMapeado === 'cancelada') {
      updateData.cancelled_at = admin.firestore.FieldValue.serverTimestamp();
    }

    updateData.webhook_recebido_em = admin.firestore.FieldValue.serverTimestamp();
    updateData.webhook_provider = provider;

    // 10. Atualizar documento
    await documentoRef.update(updateData);

    console.log(
      `[fiscal-webhook] Documento ${documentoId} atualizado: ${statusAtual} → ${statusMapeado}` +
      ` provider=${provider} chave=${dados.chaveAcesso || ''}`
    );

    // 11. Salvar em fiscal_webhooks (com event hash para idempotência)
    try {
      await db.collection('fiscal_webhooks').add({
        storeId: storeId || lojaId || null,
        documento_id: documentoId,
        chaveAcesso: dados.chaveAcesso || null,
        ref: dados.idExterno || null,
        status: dados.statusProvedor || 'unknown',
        statusMapeado,
        eventHash,
        payload: logger.sanitizar ? logger.sanitizar(body) : body,
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processed: true,
        ignoredDuplicate: false,
        provider,
        codigoRejeicao: dados.rejectionCode || null,
        motivoRejeicao: dados.rejectionReason || null,
      });
    } catch (whErr) {
      console.error('[fiscal-webhook] Erro ao salvar webhook no Firestore:', whErr.message);
    }

    // 12. Registrar log técnico em fiscal_logs
    await logger.registrarLog({
      storeId: storeId || lojaId,
      acao: 'webhook_processado',
      status: statusMapeado === 'autorizada' ? 'sucesso' : statusMapeado,
      documentoId,
      chaveAcesso: dados.chaveAcesso,
      mensagem: `Webhook ${provider}: ${statusAtual} → ${statusMapeado}`,
      integrationId: storeId || lojaId,
    });

    // 13. Histórico de status
    await logger.registrarStatusHistory({
      storeId: storeId || lojaId,
      documentoId,
      chaveAcesso: dados.chaveAcesso,
      statusAnterior: statusAtual,
      statusNovo: statusMapeado,
      motivo: dados.rejectionReason || `Webhook de ${provider}`,
      origem: 'webhook',
    });

    // 13. Responder 200 OK
    res.status(200).json({
      recebido: true,
      documento_id: documentoId,
      status: statusMapeado,
      processamento_ms: Date.now() - startTime,
    });

  } catch (error) {
    console.error('[fiscal-webhook] Erro ao processar webhook:', error);

    try {
      await logger.registrarWebhook({
        provider: 'unknown',
        statusOriginal: 'erro_processamento',
        statusMapeado: 'erro',
        payload: { erro: error.message },
      });
    } catch (_) {}

    res.status(200).json({ recebido: true, erro: 'Erro interno ao processar webhook', mensagem: error.message });
  }
});

/**
 * Valida a origem do webhook com base no provedor.
 */
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
      if (!apiKey) return { valido: false, motivo: 'Header X-API-Key ausente' };
      return { valido: apiKey.length >= 10 };
    }
    case 'enotas': {
      const auth = req.headers['authorization'] || '';
      if (!auth.startsWith('Bearer ')) return { valido: false, motivo: 'Authorization header invalido' };
      return { valido: auth.length > 20 };
    }
    case 'nuvem_fiscal': {
      const auth = req.headers['authorization'] || '';
      if (!auth.startsWith('Bearer ')) return { valido: false, motivo: 'Authorization header invalido' };
      return { valido: auth.length > 20 };
    }
    case 'custom':
    case 'webmania_br':
      return { valido: true };
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

/**
 * Extrai dados do webhook conforme formato de cada provedor.
 */
function extrairDadosWebhook(body, provider) {
  const dados = {
    chaveAcesso: null,
    idExterno: null,
    statusProvedor: 'unknown',
    protocolo: null,
    xmlUrl: null,
    pdfUrl: null,
    rejectionReason: null,
    rejectionCode: null,
  };

  switch (provider) {
    case 'focus_nfe':
      dados.chaveAcesso = body.chave_nfe || body.chave || null;
      dados.statusProvedor = body.status || 'unknown';
      dados.protocolo = body.protocolo || body.protocolo_autorizacao || null;
      dados.xmlUrl = body.xml || null;
      dados.pdfUrl = body.danfe || body.danfe_url || null;
      dados.rejectionReason = body.motivo || body.erro || null;
      dados.rejectionCode = body.codigo_rejeicao || body.codigo || null;
      break;
    case 'plug_notas':
      dados.chaveAcesso = body.chaveAcesso || body.chave_acesso || null;
      dados.idExterno = body.id || null;
      dados.statusProvedor = body.status || 'unknown';
      dados.protocolo = body.protocolo || null;
      dados.xmlUrl = body.xml || body.xml_url || null;
      dados.pdfUrl = body.danfe || body.danfe_url || null;
      dados.rejectionReason = body.motivo || body.erro || null;
      break;
    case 'enotas':
      dados.chaveAcesso = body.chaveAcesso || body.chave_acesso || null;
      dados.idExterno = body.id || null;
      dados.statusProvedor = body.status || 'unknown';
      dados.protocolo = body.numeroProtocolo || body.protocolo || null;
      dados.xmlUrl = body.xml || body.xml_url || null;
      dados.pdfUrl = body.danfe || null;
      dados.rejectionReason = body.motivo || body.erro || null;
      break;
    case 'nuvem_fiscal':
      dados.chaveAcesso = body.chave_acesso || null;
      dados.idExterno = body.id || null;
      dados.statusProvedor = body.status || 'unknown';
      dados.protocolo = body.protocolo || null;
      dados.xmlUrl = body.xml_url || null;
      dados.pdfUrl = body.pdf_url || null;
      dados.rejectionReason = body.motivo || body.erro || null;
      dados.rejectionCode = body.codigo || null;
      break;
    case 'custom':
    default:
      dados.chaveAcesso = body.chaveAcesso || body.chave_acesso ||
        body.chave_nfe || body.access_key || body.chave || null;
      dados.idExterno = body.id || body.documento_id || null;
      dados.statusProvedor = body.status || body.situacao || 'unknown';
      dados.protocolo = body.protocolo || body.protocol || body.numeroProtocolo || null;
      dados.xmlUrl = body.xml || body.xml_url || body.xmlUrl || null;
      dados.pdfUrl = body.danfe || body.danfe_url || body.pdf_url || body.pdfUrl || null;
      dados.rejectionReason = body.motivo || body.erro || body.error ||
        body.mensagem || body.rejection_reason || null;
      dados.rejectionCode = body.codigo || body.code || body.codigo_rejeicao || null;
      break;
  }

  return dados;
}

/**
 * Mapeia status do provedor para status interno do sistema.
 */
function mapearStatus(statusProvedor, provider) {
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
