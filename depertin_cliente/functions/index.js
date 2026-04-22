// Arquivo function/index.js
// Carrega functions/.env (SMTP e pepper — não fazer commit do .env)
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") });

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Inicializa o acesso do Robô ao seu Firebase
if (!admin.apps.length) {
    admin.initializeApp();
}

const notificationDispatcher = require("./notification_dispatcher");
const repasseFinanceiro = require("./repasse_financeiro");

/** Novo pedido → apenas loja (segmento loja), payload completo. */
async function enviarFcmNovoPedidoLoja(lojaId, pedidoId, pedido) {
    const db = admin.firestore();
    await notificationDispatcher.enviarNovoPedidoParaLoja(db, lojaId, pedidoId, pedido);
}

// ==========================================
// FUNÇÃO 1: AVISAR O LOJISTA DE UM NOVO PEDIDO
// ==========================================
exports.notificarNovoPedido = functions.firestore
    .document('pedidos/{pedidoId}')
    .onCreate(async (snap, context) => {
        const pedido = snap.data();
        if (pedido.status === 'aguardando_pagamento') {
            console.log("Pedido aguardando PIX — loja será notificada após confirmação do pagamento.");
            return null;
        }
        const lojaId = pedido.loja_id || pedido.lojista_id;

        // Se por algum motivo o pedido não tiver a ID da loja, ele para aqui.
        if (!lojaId) {
            console.log("Erro: Pedido criado sem loja_id / lojista_id");
            return null;
        }

        try {
            await enviarFcmNovoPedidoLoja(lojaId, context.params.pedidoId, pedido);
            return null;
        } catch (error) {
            console.error("❌ Erro ao enviar a notificação:", error);
            return null;
        }
    });

// PIX confirmado → FCM “novo pedido” à loja: enviado em mercadopago_webhook.processarPagamentoMercadoPago
// (evita depender só do trigger onUpdate e duplicar push).

// Cliente cancela pedido em andamento (motivo em cancelado_cliente_*).
exports.notificarLojaClienteCancelouPedido = functions.firestore
    .document('pedidos/{pedidoId}')
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        if (antes.status === 'cancelado' || depois.status !== 'cancelado') {
            return null;
        }
        if (depois.cancelado_motivo !== 'cliente_solicitou') {
            return null;
        }
        const lojaId = depois.loja_id || depois.lojista_id;
        if (!lojaId) return null;
        try {
            const db = admin.firestore();
            await notificationDispatcher.enviarClienteCancelouPedidoParaLoja(
                db,
                lojaId,
                context.params.pedidoId,
                depois,
            );
            const entId = depois.entregador_id || antes.entregador_id;
            if (entId) {
                await notificationDispatcher.enviarClienteCancelouPedidoParaEntregador(
                    db,
                    String(entId),
                    context.params.pedidoId,
                    depois,
                );
            }
            return null;
        } catch (error) {
            console.error('❌ Erro ao notificar loja (cliente cancelou pedido):', error);
            return null;
        }
    });

// ==========================================
// MISSÃO 2: ENTREGADORES — raio progressivo (ver logistica_entregador.js)
// ==========================================
const logisticaEntregador = require("./logistica_entregador");
exports.notificarEntregadoresPedidoPronto = logisticaEntregador.notificarEntregadoresPedidoPronto;
exports.expandirBuscaEntregador = logisticaEntregador.expandirBuscaEntregador;
exports.aceitarOfertaCorrida = logisticaEntregador.aceitarOfertaCorrida;
exports.entregadorValidarCodigoEntrega = logisticaEntregador.entregadorValidarCodigoEntrega;
exports.recusarOfertaCorrida = logisticaEntregador.recusarOfertaCorrida;
exports.entregadorCancelarCorridaERedespachar = logisticaEntregador.entregadorCancelarCorridaERedespachar;
exports.lojistaRedespacharEntregador = logisticaEntregador.lojistaRedespacharEntregador;
exports.lojistaCancelarChamadaEntregador = logisticaEntregador.lojistaCancelarChamadaEntregador;
exports.lojistaContinuarBuscaEntregadores = logisticaEntregador.lojistaContinuarBuscaEntregadores;
exports.lojistaSolicitarDespachoEntregador = logisticaEntregador.lojistaSolicitarDespachoEntregador;

const notificacoesPedidoCliente = require("./notificacoes_pedido_cliente");
exports.notificarClienteStatusPedido = notificacoesPedidoCliente.notificarClienteStatusPedido;
exports.notificarClienteConfirmacaoCancelamento =
    notificacoesPedidoCliente.notificarClienteConfirmacaoCancelamento;

const avaliacaoPedido = require("./avaliacao_pedido");
exports.atualizarRatingLojaAposAvaliacao = avaliacaoPedido.atualizarRatingLojaAposAvaliacao;

// ==========================================
// Entrega concluída → creditar saldos + notificar loja
// Dispara quando status muda para 'entregue'.
// O crédito de saldo é feito aqui (Admin SDK) porque o entregador
// não tem permissão para alterar o doc de outro usuário via rules.
// ==========================================
exports.processarEntregaConcluida = functions.firestore
    .document('pedidos/{pedidoId}')
    .onUpdate(async (change, context) => {
        const antes = change.before.data();
        const depois = change.after.data();
        const sa = antes.status || '';
        const sd = depois.status || '';
        if (sd !== 'entregue' || sa === 'entregue') return null;

        const pedidoId = context.params.pedidoId;
        const db = admin.firestore();
        const lojaId = depois.loja_id || depois.lojista_id;
        const entregadorId = depois.entregador_id;

        let veiculoEntregador = "";
        if (entregadorId) {
            try {
                const entregadorSnap = await db.collection("users").doc(String(entregadorId)).get();
                if (entregadorSnap.exists) {
                    const eu = entregadorSnap.data() || {};
                    veiculoEntregador = String(
                        eu.veiculoTipo || eu.veiculo || eu.tipo_veiculo || "",
                    ).trim();
                }
            } catch (e) {
                console.warn(`[entrega] Não foi possível carregar veículo do entregador uid=${entregadorId}: ${e.message || e}`);
            }
        }

        // 1. Creditar saldo do entregador (valor líquido após comissão da plataforma sobre frete)
        let valorLiquidoEntregador = 0;
        if (entregadorId) {
            try {
                const camposRecalculados = await repasseFinanceiro.calcularCamposFinanceirosPedido(
                    db,
                    depois,
                    { veiculoEntregador },
                );
                valorLiquidoEntregador = Number(camposRecalculados.valor_liquido_entregador || 0);
                await change.after.ref.set({
                    taxa_entregador: camposRecalculados.taxa_entregador,
                    valor_liquido_entregador: camposRecalculados.valor_liquido_entregador,
                    valor_plataforma: camposRecalculados.valor_plataforma,
                    plano_taxa_entregador_id: camposRecalculados.plano_taxa_entregador_id,
                    financeiro_version: 3,
                    financeiro_recalculado_na_entrega_em: admin.firestore.FieldValue.serverTimestamp(),
                    financeiro_veiculo_entregador: veiculoEntregador || null,
                }, { merge: true });
            } catch (e) {
                // Fallback prioriza valor_liquido_entregador já gravado no
                // onCreate (com comissão sobre frete aplicada). Só se nada
                // disso existir, usa taxa_entrega cheia (compat retroativa).
                const liquidoExistente = Number(
                    depois.valor_liquido_entregador != null && depois.valor_liquido_entregador !== ""
                        ? depois.valor_liquido_entregador
                        : 0,
                );
                if (liquidoExistente > 0) {
                    valorLiquidoEntregador = liquidoExistente;
                    console.warn(`[entrega] Erro cálculo repasse entregador pedido=${pedidoId}: ${e.message} (fallback valor_liquido_entregador=${liquidoExistente.toFixed(2)})`);
                } else {
                    valorLiquidoEntregador = Number(depois.taxa_entrega || 0);
                    console.error(`[entrega] Erro cálculo repasse entregador pedido=${pedidoId}: ${e.message} (fallback taxa_entrega)`);
                }
            }
        }
        if (entregadorId && valorLiquidoEntregador > 0) {
            try {
                await db.collection('users').doc(String(entregadorId)).update({
                    saldo: admin.firestore.FieldValue.increment(valorLiquidoEntregador),
                });
                console.log(`[entrega] Saldo entregador +R$${valorLiquidoEntregador.toFixed(2)} uid=${entregadorId}`);
            } catch (e) {
                console.error(`[entrega] Erro saldo entregador uid=${entregadorId}:`, e.message);
            }
        }

        // 2. Creditar saldo do lojista (valor líquido após comissão da plataforma sobre produtos)
        let valorLiquidoLojista = 0;
        try {
            valorLiquidoLojista = await repasseFinanceiro.obterValorLiquidoParaCredito(db, depois);
        } catch (e) {
            console.error(`[entrega] Erro cálculo repasse loja pedido=${pedidoId}:`, e.message);
        }
        if (lojaId && valorLiquidoLojista > 0) {
            try {
                await db.collection('users').doc(String(lojaId)).update({
                    saldo: admin.firestore.FieldValue.increment(valorLiquidoLojista),
                });
                console.log(`[entrega] Saldo loja +R$${valorLiquidoLojista.toFixed(2)} uid=${lojaId}`);
            } catch (e) {
                console.error(`[entrega] Erro saldo loja uid=${lojaId}:`, e.message);
            }
        }

        // 3. Notificar lojista: "Pedido entregue"
        if (lojaId) {
            try {
                await notificationDispatcher.enviarPedidoEntregueParaLoja(db, lojaId, pedidoId, depois);
            } catch (e) {
                console.error(`[entrega] Erro notif loja uid=${lojaId}:`, e.message);
            }
        }

        return null;
    });

// Pedido criado → persiste campos financeiros (split completo) + incrementa uso do cupom.
exports.processarFinanceiroPedidoOnCreate = functions.firestore
    .document("pedidos/{pedidoId}")
    .onCreate(async (snap, context) => {
        const db = admin.firestore();
        const d = snap.data();
        const pedidoId = context.params.pedidoId;
        try {
            const campos = await repasseFinanceiro.calcularCamposFinanceirosPedido(db, d);

            // Incrementa usos_atual do cupom — REGRA: 1 uso por COMPRA do cliente,
            // mesmo que a compra envolva várias lojas (multi-sacola). Em pedidos
            // multi-loja, apenas o pedido-LÍDER do grupo (`checkout_grupo_lider`)
            // incrementa o contador. Single-store (sem `checkout_grupo_id`)
            // sempre incrementa.
            const cupomCodigo = d.cupom_codigo || campos.cupom_codigo;
            const grupoId = d.checkout_grupo_id ? String(d.checkout_grupo_id) : "";
            const ehLider = d.checkout_grupo_lider === true;
            const deveContarUso = !grupoId || ehLider;

            if (cupomCodigo && deveContarUso) {
                try {
                    const cupomSnap = await db
                        .collection("cupons")
                        .where("codigo", "==", String(cupomCodigo).toUpperCase())
                        .limit(1)
                        .get();
                    if (!cupomSnap.empty) {
                        const cupomRef = db.collection("cupons").doc(cupomSnap.docs[0].id);
                        // Idempotência por checkout: se já marcamos esse grupo (ou
                        // esse próprio pedidoId, no single-store), não incrementa de
                        // novo. Evita double-count em retries do trigger.
                        const chaveIdempotencia = grupoId || pedidoId;
                        await db.runTransaction(async (tx) => {
                            const cupomDoc = await tx.get(cupomRef);
                            if (!cupomDoc.exists) return;
                            const usos = cupomDoc.data().checkouts_contabilizados || {};
                            if (usos[chaveIdempotencia]) {
                                console.log(
                                    `[financeiro] cupom "${cupomCodigo}" já contabilizado para ` +
                                    `${grupoId ? "grupo" : "pedido"}=${chaveIdempotencia} (skip)`,
                                );
                                return;
                            }
                            tx.update(cupomRef, {
                                usos_atual: admin.firestore.FieldValue.increment(1),
                                [`checkouts_contabilizados.${chaveIdempotencia}`]:
                                    admin.firestore.FieldValue.serverTimestamp(),
                            });
                        });
                        console.log(
                            `[financeiro] cupom "${cupomCodigo}" usos +1 ` +
                            `(${grupoId ? `grupo=${grupoId}` : `pedido=${pedidoId}`})`,
                        );
                    }
                } catch (cupomErr) {
                    console.error(`[financeiro] Erro incrementar cupom: ${cupomErr.message}`);
                }
            } else if (cupomCodigo && grupoId && !ehLider) {
                console.log(
                    `[financeiro] cupom "${cupomCodigo}" não conta ` +
                    `(pedido ${pedidoId} é membro do grupo ${grupoId}, não líder)`,
                );
            }

            await snap.ref.update({
                ...campos,
                financeiro_servidor_ok: true,
                financeiro_version: 2,
                financeiro_processado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(
                `[financeiro] pedido ${pedidoId}` +
                ` lojista=R$${campos.valor_liquido_lojista.toFixed(2)}` +
                ` entregador=R$${campos.valor_liquido_entregador.toFixed(2)}` +
                ` plataforma=R$${campos.valor_plataforma.toFixed(2)}` +
                (campos.desconto_cupom > 0 ? ` cupom=-R$${campos.desconto_cupom.toFixed(2)}` : ""),
            );
        } catch (e) {
            console.error(`[financeiro] onCreate pedido ${pedidoId}:`, e);
        }
        return null;
    });

// Novo documento em users → carteira usa o campo `saldo` (não existe "balance" em inglês).
exports.usersInicializarSaldoOnCreate = functions.firestore
    .document("users/{uid}")
    .onCreate(async (snap) => {
        const d = snap.data() || {};
        if (d.saldo !== undefined && d.saldo !== null) return null;
        await snap.ref.set({ saldo: 0 }, { merge: true });
        return null;
    });

// Estorno de saque PIX recusado (master) — aviso push com motivo (lojista ou entregador).
exports.notificarEstornoCreditoSaqueRecusado = functions.firestore
    .document("estornos/{estornoId}")
    .onCreate(async (snap, context) => {
        const d = snap.data() || {};
        if (String(d.tipo_operacao || "") !== "credito_saque_recusado") {
            return null;
        }
        const uid = String(d.loja_id || "").trim();
        if (!uid) {
            console.log("[estorno-saque] sem loja_id, ignorando FCM");
            return null;
        }
        const db = admin.firestore();
        try {
            await notificationDispatcher.enviarEstornoCreditoSaqueRecusado(
                db,
                uid,
                context.params.estornoId,
                d,
            );
        } catch (e) {
            console.error("[estorno-saque] erro FCM:", e);
        }
        return null;
    });

// ==========================================
// Central de ajuda — push FCM para o cliente (support_tickets)
// Disparo automático: criação do chamado, mensagem do atendente (painel), encerramento pelo painel.
// O nome do app no dispositivo (Android: android:label "DiPertin") aparece como remetente da notificação.
// ==========================================

const SUPORTE_FCM_ANDROID = {
    priority: 'high',
    notification: {
        channelId: 'high_importance_channel',
        sound: 'default',
        defaultVibrateTimings: true,
        visibility: 'public',
    },
};

/** iOS: alertas com app em background ou encerrado (APNS). */
const SUPORTE_FCM_APNS = {
    headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
    },
    payload: {
        aps: {
            sound: 'default',
            badge: 1,
        },
    },
};

function suporteTruncar(str, max) {
    if (!str || typeof str !== 'string') return '';
    const t = str.trim();
    if (t.length <= max) return t;
    return `${t.slice(0, max - 1)}…`;
}

async function suporteEnviarFcmParaUsuario(userId, payload) {
    if (!userId) return;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (!userDoc.exists) return;
    const token = userDoc.data().fcm_token;
    if (!token) {
        console.log(`[suporte] Sem fcm_token para user=${userId}`);
        return;
    }
    try {
        await admin.messaging().send({ ...payload, token });
        console.log(`[suporte] FCM enviado user=${userId}`);
    } catch (e) {
        console.error('[suporte] Erro FCM:', e);
    }
}

/**
 * "Novo atendimento iniciado" — disparada APENAS depois que o cliente
 * escolhe a categoria (campo `categoria_suporte` passa a ser preenchido).
 *
 * Motivo: o ticket é criado como `waiting` antes mesmo da primeira mensagem.
 * Enviar push no `onCreate` gerava notificação prematura. Agora seguimos o
 * fluxo real do cliente: primeira mensagem → escolha de categoria → aviso.
 */
exports.notificarSuporteCategoriaEscolhida = functions.firestore
    .document('support_tickets/{ticketId}')
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const catAntes = (antes.categoria_suporte || '').toString().trim();
        const catDepois = (depois.categoria_suporte || '').toString().trim();

        // Só dispara quando a categoria passa de vazia → preenchida.
        if (catDepois === '' || catAntes !== '') return null;
        // E apenas em chamados que ainda estão na fila.
        if (depois.status !== 'waiting') return null;

        const userId = depois.user_id;
        const ticketId = context.params.ticketId;
        if (!userId) return null;

        await suporteEnviarFcmParaUsuario(userId, {
            notification: {
                title: 'Novo atendimento iniciado',
                body: 'Seu atendimento foi iniciado. Por favor, aguarde que um de nossos atendentes irá lhe atender.',
            },
            android: {
                ...SUPORTE_FCM_ANDROID,
                collapseKey: `suporte_${ticketId}`,
            },
            apns: SUPORTE_FCM_APNS,
            data: {
                tipoNotificacao: 'suporte_inicio',
                ticketId: String(ticketId),
            },
        });
        return null;
    });

/** Atendente envia mensagem pelo painel web (sender_type === agent). */
exports.notificarSuporteMensagemAgente = functions.firestore
    .document('support_tickets/{ticketId}/mensagens/{msgId}')
    .onCreate(async (snap, context) => {
        const msg = snap.data();
        if (msg.sender_type !== 'agent') return null;

        const ticketId = context.params.ticketId;
        const ticketSnap = await admin.firestore()
            .collection('support_tickets')
            .doc(ticketId)
            .get();
        if (!ticketSnap.exists) return null;
        const userId = ticketSnap.data().user_id;
        if (!userId) return null;

        const textoOriginal = suporteTruncar(msg.mensagem || '', 400);
        let nomeAtendente = 'Atendente';
        const sid = msg.sender_id;
        if (sid) {
            const u = await admin.firestore().collection('users').doc(sid).get();
            if (u.exists) {
                const n = u.data().nome;
                if (n && String(n).trim()) nomeAtendente = String(n).trim();
            }
        }

        const corpo = suporteTruncar(`${nomeAtendente}: ${textoOriginal}`, 200);

        await suporteEnviarFcmParaUsuario(userId, {
            notification: {
                title: 'Nova Mensagem',
                body: corpo,
            },
            android: {
                ...SUPORTE_FCM_ANDROID,
                collapseKey: `suporte_${ticketId}`,
            },
            apns: SUPORTE_FCM_APNS,
            data: {
                tipoNotificacao: 'suporte_mensagem',
                ticketId: String(ticketId),
            },
        });
        return null;
    });

/**
 * Painel: "Iniciar Atendimento" (waiting → in_progress) ou
 * "Reabrir atendimento" (closed/finished/cancelled → in_progress).
 * Usa fcm_token do cliente em users/{user_id}.
 */
exports.notificarSuporteAtendimentoIniciadoPeloPainel = functions.firestore
    .document('support_tickets/{ticketId}')
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        if (depois.status !== 'in_progress') return null;
        if (antes.status === 'in_progress') return null;

        const ehReabertura = ['closed', 'finished', 'cancelled'].includes(antes.status);

        const userId = depois.user_id;
        const ticketId = context.params.ticketId;
        let nomeAtendente = (depois.agent_nome && String(depois.agent_nome).trim())
            ? String(depois.agent_nome).trim()
            : 'Atendente';
        nomeAtendente = suporteTruncar(nomeAtendente, 80);

        const titulo = ehReabertura ? 'Atendimento reaberto' : 'Atendimento iniciado';
        const corpo = ehReabertura
            ? `${nomeAtendente} reabriu seu atendimento. Volte ao chat para continuar.`
            : `Seu atendimento foi iniciado por ${nomeAtendente}`;

        await suporteEnviarFcmParaUsuario(userId, {
            notification: { title: titulo, body: corpo },
            android: {
                ...SUPORTE_FCM_ANDROID,
                collapseKey: `suporte_${ticketId}`,
            },
            apns: SUPORTE_FCM_APNS,
            data: {
                tipo: ehReabertura
                    ? 'atendimento_reaberto'
                    : 'atendimento_iniciado',
                atendimento_id: String(ticketId),
            },
        });
        return null;
    });

/** Atendente encerra pelo painel (status closed + closed_by support). */
exports.notificarSuporteEncerradoPeloPainel = functions.firestore
    .document('support_tickets/{ticketId}')
    .onUpdate(async (change, context) => {
        const antes = change.before.data();
        const depois = change.after.data();
        if (antes.status === 'closed' || depois.status !== 'closed') return null;
        if (depois.closed_by !== 'support') return null;

        const userId = depois.user_id;
        const ticketId = context.params.ticketId;

        await suporteEnviarFcmParaUsuario(userId, {
            notification: {
                title: 'Atendimento finalizado',
                body: 'Seu atendimento foi finalizado.',
            },
            android: {
                ...SUPORTE_FCM_ANDROID,
                collapseKey: `suporte_${ticketId}`,
            },
            apns: SUPORTE_FCM_APNS,
            data: {
                tipoNotificacao: 'suporte_encerrado',
                ticketId: String(ticketId),
            },
        });
        return null;
    });

// ==========================================
// CHAT DO PEDIDO — push FCM para cliente ↔ loja (subcoleção `mensagens`)
// ==========================================
const chatPedidoNotificacao = require("./chat_pedido_notificacao");
exports.notificarChatMensagemPedido = chatPedidoNotificacao.notificarChatMensagemPedido;

// ==========================================
// EXCLUSÃO DE CLIENTE PELO MASTER (hard delete imediato)
// ==========================================
const excluirClienteAdmin = require("./excluir_cliente_admin");
exports.excluirClienteAdminMaster = excluirClienteAdmin.excluirClienteAdminMaster;

// ==========================================
// EXCLUSÃO DE CONTA — soft delete com retenção de 30 dias (servidor)
// ==========================================
exports.solicitarExclusaoConta = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "É necessário estar autenticado."
        );
    }
    const uid = context.auth.uid;
    const ref = admin.firestore().collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Perfil não encontrado.");
    }
    const existente = snap.data();
    if (existente.status_conta === "exclusao_pendente") {
        return { ok: true, jaPendente: true };
    }
    const now = admin.firestore.Timestamp.now();
    const trintaDiasMs = 30 * 24 * 60 * 60 * 1000;
    const prevista = admin.firestore.Timestamp.fromMillis(now.toMillis() + trintaDiasMs);
    await ref.update({
        status_conta: "exclusao_pendente",
        exclusao_solicitada: true,
        exclusao_solicitada_em: now,
        exclusao_definitiva_prevista_em: prevista,
        exclusao_cancelada_por_reativacao: false,
    });
    return { ok: true };
});

/**
 * Diariamente: contas ainda em exclusao_pendente cuja data prevista já passou
 * passam a elegivel_exclusao_definitiva (remoção física Auth/Firestore pode ser feita depois pelo admin ou outro job).
 */
exports.marcarContasElegiveisExclusaoDefinitiva = functions.pubsub
    .schedule("every day 03:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        const db = admin.firestore();
        const snap = await db.collection("users")
            .where("status_conta", "==", "exclusao_pendente")
            .get();
        if (snap.empty) {
            console.log("[exclusao] Nenhuma conta em exclusao_pendente.");
            return null;
        }
        const agora = Date.now();
        let batch = db.batch();
        let ops = 0;
        let atualizados = 0;
        for (const doc of snap.docs) {
            const prev = doc.data().exclusao_definitiva_prevista_em;
            if (!prev || !prev.toMillis) continue;
            if (prev.toMillis() > agora) continue;
            batch.update(doc.ref, {
                status_conta: "elegivel_exclusao_definitiva",
                exclusao_elegivel_definitiva_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            ops++;
            atualizados++;
            if (ops >= 400) {
                await batch.commit();
                batch = db.batch();
                ops = 0;
            }
        }
        if (ops > 0) {
            await batch.commit();
        }
        console.log(`[exclusao] Verificados: ${snap.size}. Marcados elegivel_exclusao_definitiva: ${atualizados}.`);
        return null;
    });

// Recuperação de senha (OTP + SMTP) — ver functions/env.recuperacao.example
const recuperacaoSenha = require("./recuperacao_senha");
exports.recuperacaoSenhaSolicitar = recuperacaoSenha.recuperacaoSenhaSolicitar;
exports.recuperacaoSenhaVerificarOtp = recuperacaoSenha.recuperacaoSenhaVerificarOtp;
exports.recuperacaoSenhaDefinirNovaSenha = recuperacaoSenha.recuperacaoSenhaDefinirNovaSenha;
exports.recuperacaoSenhaPosAlteracao = recuperacaoSenha.recuperacaoSenhaPosAlteracao;

// E-mail de boas-vindas (SMTP igual à recuperação)
const boasVindas = require("./boas_vindas");
exports.onUsuarioCriadoBoasVindas = boasVindas.onUsuarioCriadoBoasVindas;

// AdminCity — CRUD de usuários master_city a partir do painel master
const admincityUsuarios = require("./admincity_usuarios");
exports.adminCityCadastrarUsuario = admincityUsuarios.adminCityCadastrarUsuario;
exports.adminCityAtualizarUsuario = admincityUsuarios.adminCityAtualizarUsuario;
exports.adminCityBloquearUsuario = admincityUsuarios.adminCityBloquearUsuario;
exports.adminCityExcluirUsuario = admincityUsuarios.adminCityExcluirUsuario;

// AdminCity — importação em massa de cidades do IBGE
const admincityCidadesIbge = require("./admincity_cidades_ibge");
exports.adminCityImportarCidadesIbge = admincityCidadesIbge.adminCityImportarCidadesIbge;

// Contato do site institucional (SMTP)
const contatoSite = require("./contato_site");
exports.enviarContatoSite = contatoSite.enviarContatoSite;

// Avaliações públicas para o site (GET JSON, sem App Check no browser)
const avaliacoesSitePublico = require("./avaliacoes_site_publico");
exports.avaliacoesSitePublicas = avaliacoesSitePublico.avaliacoesSitePublicas;

// Painel web: validação server-side após login Google (perfil lojista + token Google)
const painelGoogleLogin = require("./painel_google_login");
exports.painelValidarPosLoginGoogle = painelGoogleLogin.painelValidarPosLoginGoogle;

// Saque — apenas callable (transação + validações); cliente não grava mais em saques_solicitacoes.
const saqueSolicitar = require("./saque_solicitar");
exports.solicitarSaque = saqueSolicitar.solicitarSaque;

const saqueNotificacaoPago = require("./saque_notificacao_pago");
exports.onSaqueSolicitacaoAtualizado = saqueNotificacaoPago.onSaqueSolicitacaoAtualizado;

const lojistaStatusNotificacao = require("./lojista_status_notificacao");
exports.onLojistaStatusCadastroAtualizado =
    lojistaStatusNotificacao.onLojistaStatusCadastroAtualizado;

const entregadorStatusNotificacao = require("./entregador_status_notificacao");
exports.onEntregadorStatusCadastroAtualizado =
    entregadorStatusNotificacao.onEntregadorStatusCadastroAtualizado;

// Fase 3 (Configurações do entregador) — mantém campos planos em `users`
// sincronizados com a subcoleção `veiculos/{vid}` para compat do painel.
const veiculosEntregador = require("./veiculos_entregador");
exports.sincronizarVeiculoAtivoCampoPlano =
    veiculosEntregador.sincronizarVeiculoAtivoCampoPlano;
exports.sincronizarCrlvVeiculoAtivo =
    veiculosEntregador.sincronizarCrlvVeiculoAtivo;

// Fase 4 (Configurações do entregador) — agrega ganhos brutos, taxas e
// líquido por ano/mês para a tela de Informações Fiscais.
const fiscalEntregador = require("./fiscal_entregador");
exports.agregarFiscalEntregadorOnEntrega =
    fiscalEntregador.agregarFiscalEntregadorOnEntrega;

// Fase 3G.1 — mirror público de lojas (coleção `lojas_public` alimentada por
// allowlist). Ver docs e allowlist em `sincronizar_lojas_public.js`.
const sincronizarLojasPublic = require("./sincronizar_lojas_public");
exports.sincronizarLojaPublicOnWrite =
    sincronizarLojasPublic.sincronizarLojaPublicOnWrite;

// Fase 3G.3 — sincroniza nome + foto do cliente/loja nos pedidos ativos
// quando o usuário altera perfil. Permite que a rule de `users` fique fechada
// sem quebrar a exibição nas telas de lojista/entregador.
const sincronizarIdentidadePedidos = require(
    "./sincronizar_identidade_pedidos",
);
exports.sincronizarIdentidadePedidosOnUpdate =
    sincronizarIdentidadePedidos.sincronizarIdentidadePedidosOnUpdate;

// Fase 3G.3 — estorno de frete quando cliente retira na loja. Substitui o
// `users.saldo` que o app do lojista fazia direto; isso permite fechar a rule
// de `users` contra escritas cruzadas entre autenticados.
const lojistaEstornoFrete = require("./lojista_estorno_frete");
exports.lojistaConfirmarRetiradaNaLojaComEstorno =
    lojistaEstornoFrete.lojistaConfirmarRetiradaNaLojaComEstorno;

// Mercado Pago — webhook + callable vínculo PIX
const mercadopago = require("./mercadopago_webhook");
exports.webhookMercadoPago = mercadopago.webhookMercadoPago;
exports.mpCriarPagamentoPix = mercadopago.mpCriarPagamentoPix;
exports.mpVincularPagamentoPix = mercadopago.mpVincularPagamentoPix;
exports.mpProcessarPagamentoCartao = mercadopago.mpProcessarPagamentoCartao;
exports.estornarPagamentoPedidoCancelado = mercadopago.estornarPagamentoPedidoCancelado;
exports.cancelarPedidosPixExpirados = mercadopago.cancelarPedidosPixExpirados;
exports.cancelarPedidoPixExpirado = mercadopago.cancelarPedidoPixExpirado;
exports.processarEstornoPainel = mercadopago.processarEstornoPainel;

function motivoRecusaIndicaOperacionalJs(motivo) {
    const s = String(motivo || "").toLowerCase();
    return /pagamento|inadimpl|financeir|suspens|falta de pagamento|produtos suspens|cobran|mensalidade|plano|pend(ência|encia) financeira|regulariz|débito|debito/.test(
        s,
    );
}

function lojistaRecusaSoCadastroJs(d) {
    if (d.recusa_cadastro === true) return true;
    const sl = String(d.status_loja || "");
    if (sl !== "bloqueada" && sl !== "bloqueado") return false;
    if (Object.prototype.hasOwnProperty.call(d, "block_active")) return false;
    const motivo = String(d.motivo_recusa || "").trim();
    if (!motivo) return false;
    return !motivoRecusaIndicaOperacionalJs(motivo);
}

/** Alinhado a ContaBloqueioLojistaService (bloqueio operacional, não recusa cadastral). */
function lojistaDocumentoBloqueadoJs(d) {
    if (!d) return false;
    const role = String(d.role || d.tipoUsuario || "").toLowerCase();
    if (role !== "lojista") return false;
    if (lojistaRecusaSoCadastroJs(d)) return false;

    const sl = String(d.status_loja || "");
    const temBlockActive = Object.prototype.hasOwnProperty.call(d, "block_active");

    if (sl === "bloqueado") return true;
    if (sl === "bloqueio_temporario" && d.block_end_at) {
        const end = d.block_end_at.toDate
            ? d.block_end_at.toDate()
            : new Date(d.block_end_at._seconds * 1000);
        if (Date.now() > end.getTime()) return false;
        return true;
    }
    if (sl === "bloqueada" || sl === "bloqueado") {
        if (!temBlockActive) return true;
    }
    if (!d.block_active) return false;
    if (d.block_type === "BLOCK_TEMPORARY" && d.block_end_at) {
        const end = d.block_end_at.toDate
            ? d.block_end_at.toDate()
            : new Date(d.block_end_at._seconds * 1000);
        if (Date.now() > end.getTime()) return false;
    }
    return true;
}

exports.validarLojistaOperacional = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária."
        );
    }
    const uid = context.auth.uid;
    const doc = await admin.firestore().collection("users").doc(uid).get();
    if (!doc.exists) {
        return { ok: true };
    }
    const d = doc.data();
    if (lojistaDocumentoBloqueadoJs(d)) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Conta bloqueada. Regularize para continuar.",
            { code: "ACCOUNT_BLOCKED" }
        );
    }
    return { ok: true };
});

// Colaboradores do painel web (lojista): dono ou nível III cadastram e-mail/senha via Admin SDK.
// TODO: reativar enforceAppCheck após corrigir Secret Key do reCAPTCHA no console.
exports.cadastrarColaboradorPainelLojista = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária."
        );
    }
    const callerUid = context.auth.uid;
    const email = String(data?.email ?? "").trim().toLowerCase();
    const password = String(data?.password ?? "");
    const nomeCompleto = String(data?.nomeCompleto ?? "").trim();
    const dataNascimento = String(data?.dataNascimento ?? "").trim();
    const cpfRaw = String(data?.cpf ?? "");
    const nivel = Number(data?.nivel);

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        throw new functions.https.HttpsError("invalid-argument", "E-mail inválido.");
    }
    if (password.length < 6) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "A senha deve ter pelo menos 6 caracteres."
        );
    }
    if (nomeCompleto.length < 3) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Informe o nome completo."
        );
    }
    if (!dataNascimento) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Informe a data de nascimento."
        );
    }
    const cpf = cpfRaw.replace(/\D/g, "");
    if (cpf.length !== 11) {
        throw new functions.https.HttpsError("invalid-argument", "CPF inválido (11 dígitos).");
    }
    if (![1, 2, 3].includes(nivel)) {
        throw new functions.https.HttpsError("invalid-argument", "Nível de acesso inválido.");
    }

    const db = admin.firestore();
    const callerRef = db.collection("users").doc(callerUid);
    const callerSnap = await callerRef.get();
    if (!callerSnap.exists) {
        throw new functions.https.HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const c = callerSnap.data();
    const roleCaller = String(c.role || c.tipoUsuario || "").toLowerCase();
    if (roleCaller !== "lojista") {
        throw new functions.https.HttpsError("permission-denied", "Apenas contas de lojista.");
    }

    let ownerUid = callerUid;
    const refDono = c.lojista_owner_uid;
    if (refDono && String(refDono).trim() !== "") {
        ownerUid = String(refDono).trim();
        const nivelCaller = Number(c.painel_colaborador_nivel || 0);
        if (nivelCaller < 3) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "Apenas utilizadores com nível III podem cadastrar colaboradores."
            );
        }
    }

    const ownerSnap = await db.collection("users").doc(ownerUid).get();
    if (!ownerSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Loja (dono) não encontrada.");
    }
    if (lojistaDocumentoBloqueadoJs(ownerSnap.data())) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "A loja está bloqueada. Não é possível cadastrar colaboradores."
        );
    }

    let newUid;
    try {
        const userRecord = await admin.auth().createUser({
            email: email,
            password: password,
            displayName: nomeCompleto,
        });
        newUid = userRecord.uid;
    } catch (e) {
        const code = e.code || "";
        if (code === "auth/email-already-exists") {
            throw new functions.https.HttpsError(
                "already-exists",
                "Este e-mail já está cadastrado."
            );
        }
        console.error("cadastrarColaboradorPainelLojista createUser", e);
        throw new functions.https.HttpsError(
            "internal",
            "Não foi possível criar o utilizador. Tente outro e-mail."
        );
    }

    const ts = admin.firestore.FieldValue.serverTimestamp();
    try {
        await db.collection("users").doc(newUid).set({
            nome: nomeCompleto,
            nome_completo: nomeCompleto,
            email: email,
            cpf: cpf,
            data_nascimento: dataNascimento,
            role: "lojista",
            tipoUsuario: "lojista",
            lojista_owner_uid: ownerUid,
            painel_colaborador_nivel: nivel,
            acesso_app_mobile: false,
            primeiro_acesso: true,
            ativo: true,
            dataCadastro: ts,
            cadastro_painel_colaborador: true,
            cadastrado_por_uid: callerUid,
        });
    } catch (e) {
        console.error("cadastrarColaboradorPainelLojista set user doc", e);
        try {
            await admin.auth().deleteUser(newUid);
        } catch (_) { }
        throw new functions.https.HttpsError(
            "internal",
            "Utilizador criado no auth mas falhou ao gravar o perfil. Tente novamente."
        );
    }

    return { ok: true, uid: newUid };
});

/** Dono ou colaborador nível III da mesma loja. */
async function assertGerirColaboradoresPainel(db, callerUid) {
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (!callerSnap.exists) {
        throw new functions.https.HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const c = callerSnap.data();
    const roleCaller = String(c.role || c.tipoUsuario || "").toLowerCase();
    if (roleCaller !== "lojista") {
        throw new functions.https.HttpsError("permission-denied", "Apenas contas de lojista.");
    }
    let ownerUid = callerUid;
    const refDono = c.lojista_owner_uid;
    if (refDono && String(refDono).trim() !== "") {
        ownerUid = String(refDono).trim();
        const nivelCaller = Number(c.painel_colaborador_nivel || 0);
        if (nivelCaller < 3) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "Apenas utilizadores com nível III podem gerir colaboradores."
            );
        }
    }
    const ownerSnap = await db.collection("users").doc(ownerUid).get();
    if (!ownerSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Loja (dono) não encontrada.");
    }
    if (lojistaDocumentoBloqueadoJs(ownerSnap.data())) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "A loja está bloqueada. Não é possível alterar colaboradores."
        );
    }
    return { ownerUid, callerSnap };
}

async function assertColaboradorDaLoja(db, ownerUid, targetUid) {
    if (targetUid === ownerUid) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Não é possível usar esta ação sobre o dono da loja."
        );
    }
    const targetRef = db.collection("users").doc(targetUid);
    const targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Utilizador não encontrado.");
    }
    const t = targetSnap.data();
    if (String(t.lojista_owner_uid || "").trim() !== ownerUid) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Este utilizador não pertence à sua loja."
        );
    }
    return { targetRef, targetSnap, t };
}

exports.atualizarColaboradorPainelLojista = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const callerUid = context.auth.uid;
    const targetUid = String(data?.targetUid ?? "").trim();
    if (!targetUid) {
        throw new functions.https.HttpsError("invalid-argument", "Utilizador inválido.");
    }

    const db = admin.firestore();
    const { ownerUid } = await assertGerirColaboradoresPainel(db, callerUid);
    const { targetRef, t } = await assertColaboradorDaLoja(db, ownerUid, targetUid);

    const patch = {};
    if (data.nomeCompleto != null) {
        const nome = String(data.nomeCompleto).trim();
        if (nome.length < 3) {
            throw new functions.https.HttpsError("invalid-argument", "Informe o nome completo.");
        }
        patch.nome = nome;
        patch.nome_completo = nome;
    }
    if (data.dataNascimento != null) {
        const dn = String(data.dataNascimento).trim();
        if (!dn) {
            throw new functions.https.HttpsError("invalid-argument", "Informe a data de nascimento.");
        }
        patch.data_nascimento = dn;
    }
    if (data.cpf != null) {
        const cpf = String(data.cpf).replace(/\D/g, "");
        if (cpf.length !== 11) {
            throw new functions.https.HttpsError("invalid-argument", "CPF inválido (11 dígitos).");
        }
        patch.cpf = cpf;
    }
    if (data.nivel != null) {
        const nivel = Number(data.nivel);
        if (![1, 2, 3].includes(nivel)) {
            throw new functions.https.HttpsError("invalid-argument", "Nível de acesso inválido.");
        }
        patch.painel_colaborador_nivel = nivel;
    }

    if (Object.keys(patch).length > 0) {
        await targetRef.update(patch);
    }

    const emailNovo = data.email != null ? String(data.email).trim().toLowerCase() : null;
    if (emailNovo && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailNovo)) {
        const atual = String(t.email || "").trim().toLowerCase();
        if (emailNovo !== atual) {
            try {
                await admin.auth().updateUser(targetUid, { email: emailNovo });
            } catch (e) {
                const code = e.code || "";
                if (code === "auth/email-already-exists") {
                    throw new functions.https.HttpsError(
                        "already-exists",
                        "Este e-mail já está em uso."
                    );
                }
                console.error("atualizarColaboradorPainelLojista updateEmail", e);
                throw new functions.https.HttpsError(
                    "internal",
                    "Não foi possível atualizar o e-mail."
                );
            }
            await targetRef.update({ email: emailNovo });
        }
    }

    const senha = data.password != null ? String(data.password) : "";
    if (senha.length > 0) {
        if (senha.length < 6) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "A senha deve ter pelo menos 6 caracteres."
            );
        }
        try {
            await admin.auth().updateUser(targetUid, { password: senha });
        } catch (e) {
            console.error("atualizarColaboradorPainelLojista updatePassword", e);
            throw new functions.https.HttpsError("internal", "Não foi possível atualizar a senha.");
        }
    }

    return { ok: true };
});

exports.removerColaboradorPainelLojista = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const callerUid = context.auth.uid;
    const targetUid = String(data?.targetUid ?? "").trim();
    if (!targetUid) {
        throw new functions.https.HttpsError("invalid-argument", "Utilizador inválido.");
    }
    if (targetUid === callerUid) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Não pode remover a sua própria conta por aqui."
        );
    }

    const db = admin.firestore();
    const { ownerUid } = await assertGerirColaboradoresPainel(db, callerUid);
    await assertColaboradorDaLoja(db, ownerUid, targetUid);

    try {
        await admin.auth().deleteUser(targetUid);
    } catch (e) {
        const code = e.code || "";
        if (code !== "auth/user-not-found") {
            console.error("removerColaboradorPainelLojista deleteUser", e);
            throw new functions.https.HttpsError(
                "internal",
                "Não foi possível remover o acesso do utilizador."
            );
        }
    }
    try {
        await db.collection("users").doc(targetUid).delete();
    } catch (e) {
        console.error("removerColaboradorPainelLojista deleteDoc", e);
    }
    return { ok: true };
});

// ==========================================
// CAMPANHA DE NOTIFICAÇÕES PUSH (painel web)
// Dispara quando uma campanha é criada em notificacoes_campanhas/{campanhaId}
// Envia FCM para todos os tokens dos usuários com o role/cidade selecionados.
//
// Paginação + streaming: carrega users em páginas e já envia os batches FCM
// de cada página, sem acumular todos os tokens em memória. Isso evita OOM
// na Cloud Function e reduz uso de memória para campanhas em bases grandes.
// ==========================================
exports.enviarCampanhaNotificacao = functions
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .firestore
    .document('notificacoes_campanhas/{campanhaId}')
    .onCreate(async (snap, context) => {
        const campanha = snap.data();
        const campanhaId = context.params.campanhaId;

        if (campanha.status !== 'pendente') return null;

        const db = admin.firestore();
        const titulo = campanha.titulo || 'DiPertin';
        const mensagem = campanha.mensagem || '';
        const publicoAlvo = campanha.publico_alvo || 'todos';
        const cidade = (campanha.cidade || 'todas').toLowerCase().trim();

        /** Tamanho da página ao varrer users (lido do Firestore por vez). */
        const PAGE_SIZE = 1000;
        /** Limite FCM multicast por chamada. */
        const FCM_BATCH_SIZE = 500;
        /** Trava de segurança: máximo de docs processados por campanha. */
        const MAX_USERS_PROCESSADOS = 200000;

        const notificationPayload = {
            notification: { title: titulo, body: mensagem },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'high_importance_channel',
                    sound: 'default',
                    priority: 'max',
                    visibility: 'public',
                    defaultSound: false,
                    defaultVibrateTimings: true,
                    notificationCount: 1,
                },
            },
            apns: {
                headers: { 'apns-priority': '10' },
                payload: { aps: { sound: 'default' } },
            },
            data: {
                tipoNotificacao: 'campanha_marketing',
                campanhaId: String(campanhaId),
            },
        };

        // Tokens inválidos detectados durante o envio. Removidos do Firestore
        // ao final para não acumular lixo e parar de "enviar pra ninguém".
        const tokensInvalidos = new Set();
        // tokenUidMap: lookup reverso pra apagar o `fcm_token` certo do user.
        const tokenUidMap = new Map();

        const ERROS_TOKEN_INVALIDO = new Set([
            'messaging/registration-token-not-registered',
            'messaging/invalid-registration-token',
            'messaging/invalid-argument',
            'messaging/mismatched-credential',
        ]);

        async function enviarLoteFcm(tokens) {
            if (tokens.length === 0) return { sucesso: 0, falhas: 0 };
            const response = await admin.messaging().sendEachForMulticast({
                ...notificationPayload,
                tokens,
            });
            // Inspeciona individualmente — successCount sozinho engana
            // (FCM "aceita" tokens stale e o device nunca recebe).
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    const code = resp.error?.code || 'unknown';
                    const tok = tokens[idx];
                    if (ERROS_TOKEN_INVALIDO.has(code)) {
                        tokensInvalidos.add(tok);
                    } else {
                        console.warn(
                            `[campanha] Falha FCM token=${String(tok).slice(0, 12)}... code=${code} msg=${resp.error?.message || ''}`,
                        );
                    }
                }
            });
            return {
                sucesso: response.successCount,
                falhas: response.failureCount,
            };
        }

        try {
            await snap.ref.update({ status: 'processando' });

            // Query base de users com filtro server-side de role quando possível.
            // (filtro de cidade segue em memória porque a cidade no Firestore
            // pode estar em formatos variados — ex.: "Toledo - PR" vs "Toledo".)
            let query = db.collection('users')
                .orderBy(admin.firestore.FieldPath.documentId())
                .limit(PAGE_SIZE);
            if (publicoAlvo !== 'todos') {
                query = db.collection('users')
                    .where('role', '==', publicoAlvo)
                    .orderBy(admin.firestore.FieldPath.documentId())
                    .limit(PAGE_SIZE);
            }

            let totalEnviado = 0;
            let totalFalhas = 0;
            let totalLidos = 0;
            let totalComToken = 0;
            let lastDoc = null;
            const tokensBuffer = [];
            // tokens_pendentes_lote: paralelo ao buffer, mantém uid pra remoção
            // quando o token falhar com código de "não registrado".
            const uidsBuffer = [];

            while (true) {
                let pageQuery = query;
                if (lastDoc) pageQuery = pageQuery.startAfter(lastDoc);
                const pageSnap = await pageQuery.get();
                if (pageSnap.empty) break;

                for (const userDoc of pageSnap.docs) {
                    totalLidos++;
                    const u = userDoc.data();
                    if (!u.fcm_token) continue;
                    if (cidade !== 'todas') {
                        const userCidade = (u.cidade || '').toLowerCase().trim();
                        if (userCidade !== cidade) continue;
                    }
                    const tok = String(u.fcm_token);
                    totalComToken++;
                    tokensBuffer.push(tok);
                    uidsBuffer.push(userDoc.id);
                    tokenUidMap.set(tok, userDoc.id);

                    // Drena o buffer em lotes de 500 conforme vai enchendo
                    // — não acumula mais que FCM_BATCH_SIZE em memória.
                    if (tokensBuffer.length >= FCM_BATCH_SIZE) {
                        const batch = tokensBuffer.splice(0, FCM_BATCH_SIZE);
                        uidsBuffer.splice(0, FCM_BATCH_SIZE);
                        const r = await enviarLoteFcm(batch);
                        totalEnviado += r.sucesso;
                        totalFalhas += r.falhas;
                    }
                }

                lastDoc = pageSnap.docs[pageSnap.docs.length - 1];
                if (pageSnap.docs.length < PAGE_SIZE) break;
                if (totalLidos >= MAX_USERS_PROCESSADOS) {
                    console.warn(`[campanha] Limite de segurança ${MAX_USERS_PROCESSADOS} atingido em ${campanhaId}.`);
                    break;
                }
            }

            // Envia o resto do buffer que ficou abaixo do lote completo.
            if (tokensBuffer.length > 0) {
                const r = await enviarLoteFcm(tokensBuffer);
                totalEnviado += r.sucesso;
                totalFalhas += r.falhas;
                tokensBuffer.length = 0;
                uidsBuffer.length = 0;
            }

            // Limpa tokens inválidos do Firestore — evita ficar "enviando" pra
            // instalações apagadas/reinstaladas que nunca recebem.
            let tokensRemovidos = 0;
            if (tokensInvalidos.size > 0) {
                const uidsParaLimpar = new Set();
                tokensInvalidos.forEach((t) => {
                    const uid = tokenUidMap.get(t);
                    if (uid) uidsParaLimpar.add(uid);
                });
                // Batch de até 500 writes; se houver mais, divide em chunks.
                const uidsArr = Array.from(uidsParaLimpar);
                for (let i = 0; i < uidsArr.length; i += 450) {
                    const chunk = uidsArr.slice(i, i + 450);
                    const batch = db.batch();
                    chunk.forEach((uid) => {
                        batch.update(db.collection('users').doc(uid), {
                            fcm_token: admin.firestore.FieldValue.delete(),
                            fcm_token_invalidado_em:
                                admin.firestore.FieldValue.serverTimestamp(),
                        });
                    });
                    try {
                        await batch.commit();
                        tokensRemovidos += chunk.length;
                    } catch (errLimpeza) {
                        console.error(
                            `[campanha] Falha limpando tokens inválidos: ${errLimpeza.message}`,
                        );
                    }
                }
                console.warn(
                    `[campanha] ${campanhaId}: ${tokensRemovidos} tokens inválidos removidos do Firestore`,
                );
            }

            if (totalComToken === 0) {
                await snap.ref.update({
                    status: 'enviado',
                    total_enviado: 0,
                    total_falhas: 0,
                    total_users_lidos: totalLidos,
                    total_users_com_token: 0,
                    tokens_invalidos_removidos: 0,
                    enviado_em: admin.firestore.FieldValue.serverTimestamp(),
                    observacao: 'Nenhum usuário com FCM token encontrado para os filtros.',
                });
                return null;
            }

            const observacao = totalEnviado === 0
                ? `Nenhuma notificação aceita pelo FCM (${totalFalhas} falhas, ${tokensRemovidos} tokens inválidos removidos). Provável causa: tokens stale.`
                : tokensRemovidos > 0
                    ? `${tokensRemovidos} tokens inválidos foram removidos. Próximas campanhas terão melhor entrega.`
                    : null;

            await snap.ref.update({
                status: 'enviado',
                total_enviado: totalEnviado,
                total_falhas: totalFalhas,
                total_users_lidos: totalLidos,
                total_users_com_token: totalComToken,
                tokens_invalidos_removidos: tokensRemovidos,
                enviado_em: admin.firestore.FieldValue.serverTimestamp(),
                ...(observacao ? { observacao } : {}),
            });
            console.log(
                `[campanha] ${campanhaId}: enviado=${totalEnviado}/${totalComToken} ` +
                `falhas=${totalFalhas} tokens_removidos=${tokensRemovidos} ` +
                `users_lidos=${totalLidos}`,
            );
        } catch (error) {
            console.error(`[campanha] Erro campanha ${campanhaId}:`, error);
            await snap.ref.update({
                status: 'erro',
                erro_mensagem: String(error.message || error),
            });
        }
        return null;
    });

// Candidatura a vaga de emprego — envia e-mail para a empresa
const candidaturaVaga = require("./candidatura_vaga");
exports.enviarCandidaturaVaga = candidaturaVaga.enviarCandidaturaVaga;

// Validação de cupons (callable para o app)
const validarCupomModule = require("./validar_cupom");
exports.validarCupom = validarCupomModule.validarCupom;

// Painel web — Gestão de Entregadores → aba Atualizações (lista via Admin SDK)
const painelEntregadoresAtualizacoes = require("./painel_entregadores_atualizacoes");
exports.painelEntregadoresAtualizacoesPendentes =
    painelEntregadoresAtualizacoes.painelEntregadoresAtualizacoesPendentes;

// ==========================================
// DESATIVAÇÃO AUTOMÁTICA DE PUBLICAÇÕES VENCIDAS (3+ dias)
// ==========================================
exports.desativarPublicacoesVencidas = functions.pubsub
    .schedule("every day 04:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        const db = admin.firestore();
        const colecoes = [
            { nome: "servicos_destaque", campoVenc: "data_fim" },
            { nome: "telefones_premium", campoVenc: "data_fim" },
            { nome: "vagas", campoVenc: "data_fim" },
            { nome: "eventos", campoVenc: "data_fim" },
            { nome: "achados", campoVenc: "data_fim" },
        ];

        const limite = new Date();
        limite.setDate(limite.getDate() - 3);

        let totalDesativados = 0;

        for (const col of colecoes) {
            const snap = await db.collection(col.nome)
                .where("ativo", "==", true)
                .get();
            if (snap.empty) continue;

            let batch = db.batch();
            let ops = 0;

            for (const doc of snap.docs) {
                const dados = doc.data();
                const tsFim = dados[col.campoVenc] || dados["data_vencimento"];
                if (!tsFim || !tsFim.toDate) continue;
                const venc = tsFim.toDate();
                if (venc >= limite) continue;

                batch.update(doc.ref, {
                    ativo: false,
                    desativado_automaticamente: true,
                    desativado_em: admin.firestore.FieldValue.serverTimestamp(),
                });
                ops++;
                totalDesativados++;
                if (ops >= 400) {
                    await batch.commit();
                    batch = db.batch();
                    ops = 0;
                }
            }
            if (ops > 0) {
                await batch.commit();
            }
        }
        console.log(`[publicacoes] Desativadas automaticamente: ${totalDesativados}`);
        return null;
    });