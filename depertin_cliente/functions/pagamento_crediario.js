"use strict";

/**
 * Pagamento de crediário — Cloud Functions Gen2 (região South America).
 *
 * Funções:
 *   efetuarPagamentoCrediario         — Confirma pagamento e atualiza coleções
 *   gerarCobrancaPixCrediario         — Gera cobrança PIX via gateway ativo
 *   consultarCobrancaPixCrediario     — Polling status cobrança PIX
 *   processarPagamentoCartaoCrediario — Pagamento via cartão de crédito
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { v4: uuidv4 } = require("uuid");
const { carregarGatewayAtivo, criarProvider, criarWebhookUrl } = require("./payment_gateway_provider");
const {
    criarCobrancaPixGestaoComercial,
    criarCobrancaCartaoGestaoComercial,
} = require("./gestao_comercial_pagamento");
const { cpfPagadorValidoParaApi } = require("./pix_emv_validacao");

const CONFIG_PADRAO = {
    region: "southamerica-east1",
    cpu: 1,
    memory: "512MiB",
    maxInstances: 10,
    timeoutSeconds: 60,
};

const db = admin.firestore();

// =============================================================================
// HELPERS
// =============================================================================

/**
 * Valida autenticação e permissão de acesso à Gestão Comercial.
 * Proprietário: permitido. Colaborador: exige nivel >= 2.
 */
async function validarAutenticacao(request) {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (!callerSnap.exists) {
        throw new HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const caller = callerSnap.data() || {};
    const role = String(caller.role || caller.tipoUsuario || "").toLowerCase();
    if (role !== "lojista") {
        throw new HttpsError("permission-denied", "Apenas lojistas podem acessar a Gestão Comercial.");
    }
    const ownerUid = String(caller.lojista_owner_uid || "").trim();
    if (ownerUid) {
        const nivel = Number(caller.painel_colaborador_nivel || 0);
        if (nivel < 2) {
            throw new HttpsError("permission-denied", "Sem permissão para acessar a Gestão Comercial.");
        }
    }
    return request.auth.uid;
}

/**
 * Carrega o gateway ativo e cria o provider.
 * Se nenhum gateway configurado, lança erro.
 */
async function carregarProvider(lojaId) {
    const gatewayInfo = await carregarGatewayAtivo(db, lojaId);
    if (!gatewayInfo) {
        throw new HttpsError(
            "failed-precondition",
            "Nenhum gateway de pagamento ativo configurado. Configure em Banco e Pagamento."
        );
    }

    const provider = criarProvider(gatewayInfo.tipo, gatewayInfo.config);
    if (!provider) {
        throw new HttpsError(
            "failed-precondition",
            "Gateway \"" + gatewayInfo.tipo + "\" não suportado ou mal configurado."
        );
    }

    return { gateway: gatewayInfo, provider };
}

/**
 * Busca e-mail do cliente (marketplace exige e-mail real no payer PIX).
 */
async function buscarEmailCliente(db, clienteId) {
    try {
        const snap = await db.collection("users").doc(clienteId).get();
        if (snap.exists) {
            const d = snap.data() || {};
            const email = String(d.email || d.email_comercial || "").trim();
            if (email.includes("@")) return email;
        }
    } catch (_) {}
    return null;
}

/**
 * Gera um protocolo único para o pagamento.
 */
function gerarProtocolo() {
    const now = Date.now();
    const rand = Math.floor(Math.random() * 99999);
    return `PG-${now.toString(36).toUpperCase()}-${rand.toString(36).toUpperCase()}`;
}

/**
 * Busca o nome do lojista.
 */
async function buscarNomeLojista(lojaId) {
    try {
        const userDoc = await db.collection("users").doc(lojaId).get();
        if (userDoc.exists) {
            const data = userDoc.data() || {};
            return data.nome || data.nome_loja || data.displayName || lojaId;
        }
    } catch (_) {}
    return lojaId;
}

/** Coleção canônica de parcelas (mesma do painel web / PDV). */
function refParcelaLoja(db, lojaId, parcelaId) {
    return db.collection("users").doc(lojaId).collection("parcelas_cliente").doc(String(parcelaId));
}

function refClienteComercialLoja(db, lojaId, clienteId) {
    return db.collection("users").doc(lojaId).collection("clientes_comercial").doc(clienteId);
}

function lerValorAbertoParcela(pData) {
    if (pData.valor_em_aberto !== undefined && pData.valor_em_aberto !== null) {
        return Math.max(0, Number(pData.valor_em_aberto));
    }
    const vp = Number(pData.valor_parcela || pData.valor || 0);
    const pago = Number(pData.valor_pago || 0);
    return Math.max(0, vp - pago);
}

/** Remove campos pesados/inválidos antes de gravar no Firestore. */
function sanitizarDadosPagamentoFirestore(dados) {
    if (!dados || typeof dados !== "object") return {};
    const limpos = {};
    const bloqueados = new Set(["pixQrCodeBase64", "pixCopiaCola", "qr_code", "qr_code_base64"]);
    for (const [chave, valor] of Object.entries(dados)) {
        if (bloqueados.has(chave) || valor === undefined) continue;
        if (typeof valor === "string" && valor.length > 900) {
            limpos[chave] = valor.substring(0, 900);
            continue;
        }
        limpos[chave] = valor;
    }
    return limpos;
}

async function carregarParcelasLojaPorIds(db, lojaId, parcelasIds) {
    const ids = (parcelasIds || []).map(String).filter(Boolean);
    if (!ids.length) return [];
    const docs = [];
    for (let i = 0; i < ids.length; i += 10) {
        const chunk = ids.slice(i, i + 10);
        const refs = chunk.map(function (id) { return refParcelaLoja(db, lojaId, id); });
        const snaps = await db.getAll(...refs);
        for (const s of snaps) {
            if (s.exists) docs.push(s);
        }
    }
    return docs;
}

/**
 * Baixa contábil de parcelas em users/{lojaId}/parcelas_cliente (idempotente).
 */
async function aplicarBaixaCrediarioInterno(db, params) {
    const {
        lojaId,
        clienteId,
        parcelasIds = [],
        valorPago = 0,
        valorOriginal = 0,
        jurosCobrados = 0,
        multaCobrada = 0,
        dadosPagamento = {},
        forma = "dinheiro",
        usuarioNome = "Sistema",
        usuarioUid = "sistema",
        origem = "painel_web",
    } = params;

    if (!lojaId || !clienteId || !parcelasIds.length || valorPago <= 0) {
        throw new HttpsError(
            "invalid-argument",
            "lojaId, clienteId, parcelasIds e valorPago são obrigatórios."
        );
    }

    const protocolo = gerarProtocolo();
    const agora = admin.firestore.Timestamp.now();
    const dataRef = new Date();
    const mesAnoRef = dataRef.getFullYear() + "-" + String(dataRef.getMonth() + 1).padStart(2, "0");

    const parcelasDocs = await carregarParcelasLojaPorIds(db, lojaId, parcelasIds);
    if (parcelasDocs.length === 0) {
        throw new HttpsError("not-found", "Nenhuma parcela encontrada em parcelas_cliente para os IDs informados.");
    }

    const encontrados = parcelasDocs.map(function (d) { return d.id; });
    const naoEncontrados = parcelasIds.filter(function (id) { return !encontrados.includes(String(id)); });
    if (naoEncontrados.length > 0) {
        throw new HttpsError(
            "not-found",
            "Parcelas não encontradas: " + naoEncontrados.join(", ")
        );
    }

    const todasJaPagas = parcelasDocs.every(function (d) {
        const p = d.data() || {};
        return String(p.status || "").toLowerCase() === "pago" || lerValorAbertoParcela(p) <= 0.009;
    });
    if (todasJaPagas) {
        const primeira = parcelasDocs[0].data() || {};
        const det = primeira.pagamento_detalhe || {};
        return {
            ok: true,
            already: true,
            protocolo: primeira.protocolo_pagamento || "",
            transacaoId: det.transacaoId || dadosPagamento.transacaoId || "",
            forma: primeira.forma_pagamento || forma,
            parcelas_pagas: parcelasIds.length,
            valor_pago: valorPago,
        };
    }

    const resultado = await db.runTransaction(async function (transaction) {
        const parcelasLidas = [];
        for (const id of parcelasIds) {
            const ref = refParcelaLoja(db, lojaId, id);
            const snap = await transaction.get(ref);
            if (!snap.exists) {
                throw new Error("Parcela não encontrada: " + id);
            }
            parcelasLidas.push(snap);
        }

        // Firestore exige TODAS as leituras antes de qualquer escrita.
        const clienteRef = refClienteComercialLoja(db, lojaId, clienteId);
        const clienteSnap = await transaction.get(clienteRef);

        let clienteNome = "";
        for (const snap of parcelasLidas) {
            const pData = snap.data() || {};
            const aberto = lerValorAbertoParcela(pData);
            const valorParcela = Number(pData.valor_parcela || pData.valor || aberto);
            const valorPagoParcela = Number(pData.valor_pago || 0) + aberto;

            transaction.update(snap.ref, {
                status: "pago",
                valor_em_aberto: 0,
                valor_pago: Math.min(valorParcela, valorPagoParcela),
                data_pagamento: agora,
                protocolo_pagamento: protocolo,
                forma_pagamento: forma,
                pagamento_detalhe: sanitizarDadosPagamentoFirestore(dadosPagamento),
                pago_por: usuarioNome,
                pago_uid: usuarioUid,
                updated_at: agora,
                atualizado_em: agora,
            });

            if (!clienteNome && pData.codigo_venda) {
                clienteNome = String(pData.codigo_venda);
            }
        }

        if (clienteSnap.exists) {
            const clienteData = clienteSnap.data() || {};
            const limite = Number(clienteData.limite_credito || 0);
            let utilizado = Number(clienteData.credito_utilizado || 0);
            utilizado = Math.max(0, utilizado - valorPago);
            if (limite > 0) utilizado = Math.min(utilizado, limite);
            transaction.update(clienteRef, {
                credito_utilizado: utilizado,
                updated_at: agora,
                atualizado_em: agora,
            });
            clienteNome = clienteData.nome || clienteData.nome_completo || clienteNome;
        }

        const dadosPagamentoSanitizado = sanitizarDadosPagamentoFirestore(dadosPagamento);

        const recebimentoRef = db.collection("users").doc(lojaId).collection("recebimentos_cliente").doc();
        transaction.set(recebimentoRef, {
            loja_id: lojaId,
            cliente_id: clienteId,
            parcelas_ids: parcelasIds,
            qtd_parcelas: parcelasIds.length,
            valor_pago: valorPago,
            valor: valorPago,
            valor_original: valorOriginal,
            juros_cobrados: jurosCobrados,
            multa_cobrada: multaCobrada,
            forma_pagamento: forma,
            dados_pagamento: dadosPagamentoSanitizado,
            protocolo: protocolo,
            data_pagamento: agora,
            tipo: "recebimento_crediario",
            status: "confirmado",
            usuario_nome: usuarioNome,
            usuario_uid: usuarioUid,
            origem: origem,
            created_at: agora,
            criado_em: agora,
        });

        const gcRecebRef = db.collection("gestao_comercial_recebimentos").doc();
        transaction.set(gcRecebRef, {
            loja_id: lojaId,
            cliente_id: clienteId,
            cliente_nome: clienteNome || "",
            parcelas_ids: parcelasIds,
            qtd_parcelas: parcelasIds.length,
            valor_original: valorOriginal || valorPago,
            valor_recebido: valorPago,
            valor_multa: multaCobrada || 0,
            valor_juros: jurosCobrados || 0,
            forma_pagamento: forma,
            recebido_por_nome: usuarioNome,
            recebido_por_id: usuarioUid,
            data_recebimento: agora,
            status: "confirmado",
            origem: origem,
            protocolo: protocolo,
            created_at: agora,
            updated_at: agora,
        });

        const historicoRef = db.collection("historico_financeiro_cliente").doc();
        transaction.set(historicoRef, {
            cliente_id: clienteId,
            loja_id: lojaId,
            tipo: "pagamento_crediario",
            descricao: "Pagamento de crediário - " + parcelasIds.length + " parcela(s)",
            valor: valorPago,
            valor_original: valorOriginal,
            juros: jurosCobrados,
            multa: multaCobrada,
            forma_pagamento: forma,
            protocolo: protocolo,
            parcelas_ids: parcelasIds,
            data: agora,
            mes_referencia: mesAnoRef,
            usuario_nome: usuarioNome,
            criado_em: agora,
        });

        const auditRef = db.collection("audit_logs").doc();
        transaction.set(auditRef, {
            acao: "pagamento_crediario",
            categoria: "financeiro",
            origem: origem,
            ator_uid: usuarioUid,
            ator_nome: usuarioNome,
            criado_em: agora,
            detalhe: {
                cliente_id: clienteId,
                loja_id: lojaId,
                valor: valorPago,
                forma: forma,
                protocolo: protocolo,
                parcelas: parcelasIds.length,
            },
        });

        return {
            protocolo: protocolo,
            parcelas_pagas: parcelasIds.length,
            valor_pago: valorPago,
        };
    });

    return Object.assign({ ok: true, already: false }, resultado);
}

exports.aplicarBaixaCrediarioInterno = aplicarBaixaCrediarioInterno;

/** Serializa Timestamp Firestore para o painel web (evita Int64 no dart2js). */
function serializarCriadoEm(ts) {
    if (!ts) return { criado_em_ms: null, criado_em_iso: null };
    const ms = ts.toMillis
        ? ts.toMillis()
        : (ts.seconds != null ? ts.seconds * 1000 + Math.floor((ts.nanoseconds || 0) / 1e6) : null);
    return {
        criado_em_ms: ms,
        criado_em_iso: ms != null ? new Date(ms).toISOString() : null,
    };
}

/**
 * Executa baixa contábil do crediário após PIX aprovado no gateway (idempotente).
 */
async function executarBaixaCrediarioPixSeNecessario(request, cobrancaRef, cobranca, cobrancaId, paymentId) {
    // Só pula se a baixa contábil já foi gravada (status "approved" sozinho NÃO garante baixa).
    if (cobranca.baixa_processada === true) {
        return { ok: true, already: true };
    }

    const parcelasIds = cobranca.parcelas_ids || [];
    if (!cobranca.loja_id || !cobranca.cliente_id || !parcelasIds.length) {
        return { ok: false, motivo: "dados_incompletos" };
    }

    try {
        await aplicarBaixaCrediarioInterno(db, {
            lojaId: cobranca.loja_id,
            clienteId: cobranca.cliente_id,
            parcelasIds: parcelasIds,
            valorPago: Number(cobranca.valor || 0),
            valorOriginal: Number(cobranca.valor_original || cobranca.valor || 0),
            jurosCobrados: Number(cobranca.juros_cobrados || 0),
            multaCobrada: Number(cobranca.multa_cobrada || 0),
            dadosPagamento: {
                forma: "pix",
                cobrancaId: cobrancaId,
                transacaoId: String(paymentId || cobranca.payment_id || ""),
            },
            forma: "pix",
            usuarioNome: (request.auth && request.auth.token && request.auth.token.name) || "PIX",
            usuarioUid: (request.auth && request.auth.uid) || "pix_polling",
            origem: "pix_crediario_polling",
        });

        await cobrancaRef.update({
            status: "approved",
            baixa_processada: true,
            confirmado_em: admin.firestore.Timestamp.now(),
            transacao_id: String(paymentId || cobranca.payment_id || ""),
            mp_payment_id: Number(paymentId) || cobranca.mp_payment_id || null,
        });

        return { ok: true, already: false };
    } catch (err) {
        console.error("[PIX Crediário] Baixa automática:", err.message || err);
        if (err instanceof HttpsError && err.message && err.message.includes("já")) {
            await cobrancaRef.update({
                status: "approved",
                baixa_processada: true,
                transacao_id: String(paymentId || cobranca.payment_id || ""),
            });
            return { ok: true, already: true };
        }
        throw err;
    }
}

// =============================================================================
// EFETUAR PAGAMENTO CREDIÁRIO
// =============================================================================

/**
 * Callable: efetuarPagamentoCrediario
 *
 * Marca parcelas como pagas, atualiza saldo do cliente, gera histórico,
 * recebimentos, vendas e atualiza o dashboard.
 * (Não depende do gateway — é a baixa contábil após confirmação)
 */
exports.efetuarPagamentoCrediario = onCall(
    CONFIG_PADRAO,
    async (request) => {
        validarAutenticacao(request);

        const uid = request.auth.uid;
        const data = request.data || {};

        const {
            lojaId,
            clienteId,
            parcelasIds = [],
            valorPago = 0,
            valorOriginal = 0,
            jurosCobrados = 0,
            multaCobrada = 0,
            dadosPagamento = {},
            usuarioNome = uid,
        } = data;

        if (!lojaId || !clienteId || !parcelasIds.length || valorPago <= 0) {
            throw new HttpsError(
                "invalid-argument",
                "Dados inválidos: lojaId, clienteId, parcelasIds e valorPago são obrigatórios."
            );
        }

        const forma = String(dadosPagamento.forma || "dinheiro");
        const formasValidas = ["dinheiro", "pix", "cartao_credito", "cartao_debito"];
        if (!formasValidas.includes(forma)) {
            throw new HttpsError("invalid-argument", "Forma de pagamento inválida: " + forma);
        }

        try {
            const resultado = await aplicarBaixaCrediarioInterno(db, {
                lojaId,
                clienteId,
                parcelasIds,
                valorPago,
                valorOriginal,
                jurosCobrados,
                multaCobrada,
                dadosPagamento: sanitizarDadosPagamentoFirestore(dadosPagamento),
                forma,
                usuarioNome: usuarioNome || uid,
                usuarioUid: uid,
                origem: "painel_web",
            });

            return {
                sucesso: true,
                ok: true,
                already: resultado.already === true,
                protocolo: resultado.protocolo,
                mensagem: resultado.already
                    ? "Pagamento já havia sido registrado."
                    : "Pagamento confirmado com sucesso.",
                parcelas_pagas: resultado.parcelas_pagas,
                valor_pago: resultado.valor_pago,
                transacaoId: dadosPagamento.transacaoId || "",
                forma: forma,
            };
        } catch (err) {
            console.error("[efetuarPagamentoCrediario]", err);
            if (err instanceof HttpsError) throw err;
            const msg = String(err && err.message ? err.message : err);
            if (msg.includes("Parcela não encontrada") || msg.includes("Parcelas não encontradas")) {
                throw new HttpsError("not-found", msg);
            }
            throw new HttpsError("internal", "Erro ao registrar baixa: " + msg.substring(0, 300));
        }
    }
);

// =============================================================================
// GERAR COBRANÇA PIX CREDIÁRIO
// =============================================================================

/**
 * Callable: gerarCobrancaPixCrediario
 *
 * Gera uma cobrança PIX via gateway ativo para pagamento de crediário.
 * Suporta Mercado Pago, Asaas e API Personalizada.
 */
exports.gerarCobrancaPixCrediario = onCall(
    CONFIG_PADRAO,
    async (request) => {
        validarAutenticacao(request);

        const data = request.data || {};
        const { lojaId, clienteId, clienteNome, clienteCpf, valor, descricao,
                parcelasIds, valorOriginal, jurosCobrados, multaCobrada } = data;

        if (!lojaId || !clienteId || !valor || valor <= 0) {
            throw new HttpsError(
                "invalid-argument",
                "lojaId, clienteId e valor são obrigatórios."
            );
        }

        // Carrega gateway ativo da loja
        const cobrancaId = "crediario_" + uuidv4().substring(0, 8);
        const cpfPagador = cpfPagadorValidoParaApi(clienteCpf);
        const gatewayAtivo = await carregarGatewayAtivo(db, lojaId);
        const clienteEmail = await buscarEmailCliente(db, clienteId);

        if (gatewayAtivo && gatewayAtivo.tipo === "asaas" && !cpfPagador) {
            throw new HttpsError("failed-precondition", "CPF_OBRIGATORIO");
        }

        let pixResult;
        try {
            pixResult = await criarCobrancaPixGestaoComercial(db, {
                lojaId,
                valor,
                descricao: descricao || "Pagamento crediário",
                externalReference: cobrancaId,
                idempotencyKey: cobrancaId,
                clienteNome: clienteNome || "Cliente",
                clienteEmail: clienteEmail || undefined,
            });
        } catch (error) {
            console.error("[PIX Crediário] Erro no gateway:", error.message || error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Erro ao gerar cobrança PIX: " + (error.message || error));
        }

        const chargeResult = pixResult.chargeResult;
        const gateway = pixResult.gatewayInfo;

        // Salva referência da cobrança no Firestore
        const agora = admin.firestore.Timestamp.now();
        await db.collection("cobrancas_pix_crediario").doc(cobrancaId).set({
            loja_id: lojaId,
            cliente_id: clienteId,
            cliente_nome: clienteNome || "",
            cliente_cpf: cpfPagador || String(clienteCpf || "").replace(/\D/g, "").substring(0, 11),
            cliente_email: clienteEmail || "",
            valor: valor,
            valor_original: valorOriginal || 0,
            juros_cobrados: jurosCobrados || 0,
            multa_cobrada: multaCobrada || 0,
            parcelas_ids: parcelasIds || [],
            descricao: descricao || "Pagamento crediário",
            gateway_tipo: gateway.tipo,
            gateway_nome: gateway.nome || gateway.tipo,
            payment_id: String(pixResult.paymentId),
            mp_payment_id: Number(pixResult.paymentId) || null,
            qr_code: pixResult.pixCopiaECola,
            qr_code_base64: pixResult.qrCodeBase64,
            status: pixResult.status || "pending",
            pix_validacao: pixResult.validacao.br || null,
            criado_em: agora,
            idempotency_key: cobrancaId,
            baixa_processada: false,
        });

        const criadoSerial = serializarCriadoEm(agora);
        return Object.assign({
            id: cobrancaId,
            payment_id: String(pixResult.paymentId),
            mp_payment_id: Number(pixResult.paymentId) || null,
            status: pixResult.status || "pending",
            copia_cola: pixResult.pixCopiaECola,
            qr_code: pixResult.qrCodeBase64,
            ticket_url: chargeResult.ticketUrl || "",
            valor: valor,
            gateway: gateway.tipo,
        }, criadoSerial);
    }
);

// =============================================================================
// CONSULTAR COBRANÇA PIX CREDIÁRIO
// =============================================================================

/**
 * Callable: consultarCobrancaPixCrediario
 *
 * Consulta o status de uma cobrança PIX usando o provider do gateway ativo.
 */
exports.consultarCobrancaPixCrediario = onCall(
    CONFIG_PADRAO,
    async (request) => {
        validarAutenticacao(request);

        const { cobrancaId } = request.data || {};
        if (!cobrancaId) {
            throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        }

        // Busca no Firestore
        const cobrancaRef = db.collection("cobrancas_pix_crediario").doc(cobrancaId);
        const cobrancaSnap = await cobrancaRef.get();

        if (!cobrancaSnap.exists) {
            return { status: "nao_encontrada" };
        }

        const cobranca = cobrancaSnap.data() || {};
        const criadoEm = cobranca.criado_em;
        const criadoSerial = serializarCriadoEm(criadoEm);

        // Calcula expiração: 5 minutos a partir da criação
        const TEMPO_EXPIRACAO_MS = 5 * 60 * 1000;
        let expirado = false;
        if (criadoSerial.criado_em_ms != null) {
            expirado = (Date.now() - criadoSerial.criado_em_ms) > TEMPO_EXPIRACAO_MS;
        }

        // Baixa já concluída anteriormente
        if (cobranca.baixa_processada === true) {
            return Object.assign({
                id: cobrancaId,
                payment_id: String(cobranca.payment_id || ""),
                status: "aprovado",
                transacaoId: cobranca.transacao_id || String(cobranca.payment_id || ""),
                expirado: expirado,
                baixa_processada: true,
            }, criadoSerial);
        }

        // PIX aprovado no doc mas baixa pendente (webhook marcou approved sem baixar parcelas)
        if (cobranca.status === "approved") {
            try {
                const baixa = await executarBaixaCrediarioPixSeNecessario(
                    request,
                    cobrancaRef,
                    cobranca,
                    cobrancaId,
                    String(cobranca.payment_id || cobranca.transacao_id || ""),
                );
                const atualizada = (await cobrancaRef.get()).data() || cobranca;
                return Object.assign({
                    id: cobrancaId,
                    payment_id: String(atualizada.payment_id || cobranca.payment_id || ""),
                    status: "aprovado",
                    transacaoId: atualizada.transacao_id || String(atualizada.payment_id || ""),
                    expirado: expirado,
                    baixa_processada: baixa.ok === true || atualizada.baixa_processada === true,
                }, criadoSerial);
            } catch (retryErr) {
                console.error("[PIX Crediário] Retry baixa (approved sem baixa_processada):", retryErr.message || retryErr);
                return Object.assign({
                    id: cobrancaId,
                    payment_id: String(cobranca.payment_id || ""),
                    status: "aprovado",
                    transacaoId: cobranca.transacao_id || String(cobranca.payment_id || ""),
                    expirado: expirado,
                    baixa_processada: false,
                    erro_baixa: String(retryErr.message || retryErr).substring(0, 200),
                }, criadoSerial);
            }
        }
        if (cobranca.status === "rejected" || cobranca.status === "cancelled") {
            return Object.assign({
                id: cobrancaId,
                payment_id: String(cobranca.payment_id || ""),
                status: cobranca.status === "rejected" ? "recusado" : "cancelado",
                transacaoId: cobranca.transacao_id || "",
                expirado: expirado,
            }, criadoSerial);
        }

        // Verifica expiração local (5 min)
        if (expirado) {
            await cobrancaRef.update({ status: "expired" });
            return Object.assign({ status: "expirado" }, criadoSerial);
        }

        // Consulta gateway ativo para status atualizado
        try {
            const paymentId = String(cobranca.payment_id || "").trim();
            if (!paymentId) {
                return Object.assign({
                    id: cobrancaId,
                    payment_id: "",
                    status: "aguardando",
                    expirado,
                }, criadoSerial);
            }

            const lojaId = cobranca.loja_id || "";
            const { provider } = await carregarProvider(lojaId);

            if (!provider || !provider.getPaymentStatus) {
                return Object.assign({
                    id: cobrancaId,
                    payment_id: paymentId,
                    status: "aguardando",
                    transacaoId: paymentId,
                    expirado,
                }, criadoSerial);
            }

            const statusResult = await provider.getPaymentStatus(paymentId);

            let baixaProcessada = cobranca.baixa_processada === true;

            // Pagamento aprovado no gateway → baixa automática no backend
            if (statusResult.aprovado && !baixaProcessada) {
                const baixa = await executarBaixaCrediarioPixSeNecessario(
                    request,
                    cobrancaRef,
                    cobranca,
                    cobrancaId,
                    paymentId,
                );
                baixaProcessada = baixa.ok === true;
            }

            const cobrancaAtualizada = (await cobrancaRef.get()).data() || cobranca;

            // Atualiza Firestore se status mudou (sem sobrescrever approved)
            if (statusResult.status && statusResult.status !== cobrancaAtualizada.status
                && cobrancaAtualizada.status !== "approved") {
                const updateData = {
                    status: statusResult.status,
                    payment_id: String(statusResult.paymentId || paymentId),
                };
                if (statusResult.aprovado) {
                    updateData.confirmado_em = admin.firestore.Timestamp.now();
                    updateData.transacao_id = String(statusResult.paymentId || paymentId);
                    updateData.mp_payment_id = Number(statusResult.paymentId) || null;
                }
                await cobrancaRef.update(updateData);
            }

            const statusMap = {
                approved: "aprovado",
                pending: "aguardando",
                in_process: "aguardando",
                waiting_payment: "aguardando",
                rejected: "recusado",
                cancelled: "cancelado",
                expired: "expirado",
            };

            const statusFrontend = statusResult.aprovado
                ? "aprovado"
                : (statusMap[statusResult.status] || statusResult.status || "aguardando");

            const baixaFinal = baixaProcessada === true
                || cobrancaAtualizada.baixa_processada === true;

            return Object.assign({
                id: cobrancaId,
                payment_id: String(statusResult.paymentId || paymentId),
                status: statusFrontend,
                transacaoId: String(statusResult.paymentId || paymentId),
                expirado: expirado,
                baixa_processada: baixaFinal,
                gateway_status: statusResult.status,
            }, criadoSerial);
        } catch (error) {
            console.error("[consultarCobrancaPixCrediario] Erro:", error.message || error);
            return Object.assign({
                id: cobrancaId,
                payment_id: String(cobranca.payment_id || ""),
                status: "aguardando",
                expirado: expirado,
                erro_consulta: String(error.message || error).substring(0, 200),
            }, criadoSerial);
        }
    }
);

// =============================================================================
// PROCESSAR PAGAMENTO CARTÃO DE CRÉDITO
// =============================================================================

/**
 * Callable: processarPagamentoCartaoCrediario
 *
 * Processa pagamento via cartão de crédito usando o gateway ativo.
 * Cobrança única (sem parcelamento).
 * Retorna aprovação/rejeição imediata.
 */
exports.processarPagamentoCartaoCrediario = onCall(
    CONFIG_PADRAO,
    async (request) => {
        validarAutenticacao(request);

        const data = request.data || {};
        const {
            lojaId,
            clienteId,
            clienteNome,
            clienteCpf,
            clienteEmail,
            valor,
            cardToken,
            cardHolderName,
            cardNumber,
            cardExpiryMonth,
            cardExpiryYear,
            cardCvv,
            descricao,
            parcelasIds,
            valorOriginal,
            jurosCobrados,
            multaCobrada,
        } = data;

        if (!lojaId || !clienteId || !valor || valor <= 0) {
            throw new HttpsError(
                "invalid-argument",
                "lojaId, clienteId e valor são obrigatórios."
            );
        }

        const protocolo = "CARD-" + uuidv4().substring(0, 8).toUpperCase();
        const cpfPagador = cpfPagadorValidoParaApi(clienteCpf);

        let cardWrap;
        try {
            cardWrap = await criarCobrancaCartaoGestaoComercial(db, {
                lojaId,
                valor,
                descricao: descricao || "Pagamento crediário cartão",
                externalReference: protocolo,
                clienteNome,
                clienteCpf: cpfPagador || undefined,
                clienteEmail: clienteEmail || protocolo.toLowerCase() + "@pg.dipertin.com.br",
                cardToken,
                cardHolderName,
                cardNumber,
                cardExpiryMonth,
                cardExpiryYear,
                cardCvv,
            });
        } catch (error) {
            console.error("[Cartão Crediário] Erro no gateway:", error.message || error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Erro ao processar pagamento com cartão: " + (error.message || error));
        }

        const gateway = cardWrap.gatewayInfo;
        const cardResult = cardWrap.cardResult;

        // Registra transação no Firestore
        const agora = admin.firestore.Timestamp.now();
        const transacaoId = "crediario_card_" + uuidv4().substring(0, 8);
        await db.collection("cobrancas_pix_crediario").doc(transacaoId).set({
            loja_id: lojaId,
            cliente_id: clienteId,
            cliente_nome: clienteNome || "",
            cliente_cpf: cpfPagador || "",
            valor: valor,
            valor_original: valorOriginal || 0,
            juros_cobrados: jurosCobrados || 0,
            multa_cobrada: multaCobrada || 0,
            parcelas_ids: parcelasIds || [],
            descricao: descricao || "Pagamento crediário cartão",
            gateway_tipo: gateway.tipo,
            gateway_nome: gateway.nome || gateway.tipo,
            forma_pagamento: "cartao_credito",
            payment_id: cardResult.paymentId,
            status: cardResult.status,
            authorization_code: cardResult.authorizationCode || "",
            criado_em: agora,
        });

        // Se aprovado, efetua baixa automaticamente
        if (cardResult.aprovado && parcelasIds && parcelasIds.length > 0) {
            try {
                const baixaRequest = {
                    data: {
                        lojaId,
                        clienteId,
                        parcelasIds,
                        valorPago: valor,
                        valorOriginal: valorOriginal || 0,
                        jurosCobrados: jurosCobrados || 0,
                        multaCobrada: multaCobrada || 0,
                        dadosPagamento: {
                            forma: "cartao_credito",
                            transacaoId: String(cardResult.paymentId),
                            authorization: cardResult.authorizationCode || "",
                            gateway: gateway.tipo,
                        },
                        usuarioNome: (request.auth.token?.name || ""),
                    },
                    auth: request.auth,
                };
                await exports.efetuarPagamentoCrediario.run(baixaRequest);
            } catch (baixaErr) {
                console.error("[Cartão] Pagamento aprovado mas baixa falhou:", baixaErr);
            }
        }

        return {
            sucesso: cardResult.aprovado,
            aprovado: cardResult.aprovado,
            payment_id: cardResult.paymentId,
            status: cardResult.status,
            statusDetail: cardResult.statusDetail || "",
            authorizationCode: cardResult.authorizationCode || "",
            protocolo: cardResult.aprovado ? protocolo : "",
            transacaoId: cardResult.aprovado ? transacaoId : "",
            mensagem: cardResult.aprovado
                ? "Pagamento aprovado com sucesso."
                : "Pagamento recusado pela operadora do cartão.",
        };
    }
);
