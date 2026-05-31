"use strict";

/**
 * Negociação de compras por encomenda — escrita apenas via Admin SDK.
 * Avisos: mapas alerta_encomenda / alerta_encomenda_cliente nos docs users + FCM (notification_dispatcher).
 */
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
    enviarEncomendaParaCliente,
    enviarEncomendaParaLoja,
} = require("./notification_dispatcher");

// App Check obrigatório aqui fazia o cliente ver «Unauthenticated» com Auth OK:
// no Android o manifest desliga refresh automático do token Play Integrity e o SDK
// pode falhar com FirebaseException «Too many attempts» — sem token, v2 onCall
// rejeita antes do handler. Auth continua obrigatória em cada callable (assertAuth).
// Paridade: saque_solicitar, recuperacao_senha, MP callables (enforceAppCheck false).
const CALL_OPTS = {
    region: "us-central1",
    enforceAppCheck: false,
};

const ST = {
    AGUARDANDO_NEGOCIACAO: "aguardando_negociacao",
    NEGOCIACAO_EM_ANDAMENTO: "negociacao_em_andamento",
    PROPOSTA_ENVIADA: "proposta_enviada",
    AGUARDANDO_LOJA_CONTRA: "aguardando_resposta_loja_contraproposta",
    PROPOSTA_ACEITA_PENDENTE_ENTRADA: "proposta_aceita_pendente_entrada",
    ENTRADA_AGUARDANDO_PGTO: "entrada_aguardando_pagamento",
    /** Fase 2 — entrada (PIX/cartão) confirmada; loja produz antes do saldo. */
    ENTRADA_PAGA_EM_PRODUCAO: "entrada_paga_em_producao",
    /** Aguardando cliente pagar o pedido `saldo_final`. */
    SALDO_FINAL_AGUARDANDO_PGTO: "saldo_final_aguardando_pgto",
    /** Saldo pago — mesmo ciclo logístico de pedido normal (`pedidos` em pendente+). */
    EM_EXECUCAO_LOGISTICA: "em_execucao_logistica",
    ENCERRADA_RECUSADA: "encerrada_recusada_loja",
    ENCERRADA_CANCELADA_CLIENTE: "encerrada_cancelada_cliente",
    ENCERRADA_CANCELADA_LOJA: "encerrada_cancelada_loja",
};

function roundMoney(n) {
    return Math.round(Number(n) * 100) / 100;
}

/** Até o pagamento da entrada confirmado — depois disso não cancela por aqui. */
function statusPermiteCancelarNegociacaoAntesEntrada(st) {
    const s = String(st || "");
    return (
        s === ST.AGUARDANDO_NEGOCIACAO ||
        s === ST.NEGOCIACAO_EM_ANDAMENTO ||
        s === ST.PROPOSTA_ENVIADA ||
        s === ST.AGUARDANDO_LOJA_CONTRA ||
        s === ST.PROPOSTA_ACEITA_PENDENTE_ENTRADA ||
        s === ST.ENTRADA_AGUARDANDO_PGTO
    );
}

/**
 * Cancela pedido de entrada (PIX/cartão pendente) dentro da transação.
 * Ignora se já estiver cancelado ou inexistente.
 * Vincula pelo `encomenda_id` do pedido (evita bloqueio por campos legados ausentes).
 */
async function cancelarPedidoEntradaAbertoNaTx(tx, db, pedidoId, canceladoMotivo, encId) {
    const pid = String(pedidoId || "").trim();
    const enc = String(encId || "").trim();
    if (!pid || !enc) {
        return;
    }
    const pref = db.collection("pedidos").doc(pid);
    const psnap = await tx.get(pref);
    if (!psnap.exists) {
        return;
    }
    const p = psnap.data() || {};
    if (String(p.encomenda_id || "").trim() !== enc) {
        throw new HttpsError(
            "failed-precondition",
            "Pedido de entrada não corresponde a esta encomenda.",
        );
    }
    const pst = String(p.status || "");
    if (pst === "cancelado") {
        return;
    }
    if (pst !== "aguardando_pagamento") {
        throw new HttpsError(
            "failed-precondition",
            "O pagamento da entrada já foi iniciado ou concluído — não é possível cancelar a negociação.",
        );
    }
    tx.update(pref, {
        status: "cancelado",
        cancelado_motivo: String(canceladoMotivo || "").slice(0, 120),
        cancelado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
}

function assertAuth(request) {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login necessário.");
    }
}

async function uidLojaOperacional(db, authUid) {
    const snap = await db.collection("users").doc(authUid).get();
    if (!snap.exists) {
        return null;
    }
    const d = snap.data() || {};
    const owner = String(d.lojista_owner_uid || "").trim();
    if (owner) {
        return owner;
    }
    return authUid;
}

async function gravarAlertaEncomendaLoja(db, lojaUid, encomendaId, texto) {
    if (!lojaUid) {
        return;
    }
    await db.collection("users").doc(lojaUid).set(
        {
            alerta_encomenda: {
                ultimo_em: admin.firestore.FieldValue.serverTimestamp(),
                encomenda_id: encomendaId,
                texto,
                dispensado_em: null,
            },
        },
        { merge: true },
    );
}

async function gravarAlertaEncomendaCliente(db, clienteUid, encomendaId, texto) {
    if (!clienteUid) {
        return;
    }
    await db.collection("users").doc(clienteUid).set(
        {
            alerta_encomenda_cliente: {
                ultimo_em: admin.firestore.FieldValue.serverTimestamp(),
                encomenda_id: encomendaId,
                texto,
                dispensado_em: null,
            },
        },
        { merge: true },
    );
}

function truncHistorico(arr, max = 40) {
    if (!Array.isArray(arr)) {
        return [];
    }
    if (arr.length <= max) {
        return arr;
    }
    return arr.slice(arr.length - max);
}

async function appendHistorico(ref, tipo, texto) {
    const snap = await ref.get();
    const prev = (snap.exists && snap.data().historico) || [];
    const linha = {
        em: admin.firestore.Timestamp.now(),
        tipo,
        texto: String(texto || "").slice(0, 500),
    };
    const novo = truncHistorico([...prev, linha]);
    await ref.update({
        historico: novo,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function validarItensEncomenda(db, itens, lojaIdEsperada) {
    const lista = Array.isArray(itens) ? itens : [];
    if (!lista.length) {
        throw new HttpsError("invalid-argument", "Lista de itens vazia.");
    }
    const refs = [];
    for (const it of lista) {
        const pid = String(it.id_produto || it.id || "").trim();
        if (!pid) {
            throw new HttpsError("invalid-argument", "Item sem id_produto.");
        }
        refs.push(db.collection("produtos").doc(pid));
    }
    const snaps = await db.getAll(...refs);
    let lojaRef = null;
    let valorCatalogo = 0;
    const sanitizados = [];
    for (let i = 0; i < snaps.length; i++) {
        const s = snaps[i];
        if (!s.exists) {
            throw new HttpsError("not-found", `Produto inexistente: ${lista[i].id_produto}`);
        }
        const d = s.data() || {};
        const lojaP =
            String(d.loja_id || d.lojista_id || "").trim();
        const tipo = String(d.tipo_venda || "").trim().toLowerCase();
        if (tipo !== "encomenda") {
            throw new HttpsError(
                "failed-precondition",
                "Todos os itens devem ser cadastrados como encomenda.",
            );
        }
        if (!lojaP) {
            throw new HttpsError("failed-precondition", "Produto sem loja.");
        }
        if (lojaRef == null) {
            lojaRef = lojaP;
        } else if (lojaRef !== lojaP) {
            throw new HttpsError(
                "invalid-argument",
                "Itens de mais de uma loja — finalize uma loja por vez.",
            );
        }
        const q = Number(lista[i].quantidade || 1);
        const preco = Number(
            lista[i].preco_ref != null
                ? lista[i].preco_ref
                : d.precoOferta || d.preco || d.preco_original || 0,
        );
        if (!Number.isFinite(q) || q < 1 || q > 99) {
            throw new HttpsError("invalid-argument", "Quantidade inválida.");
        }
        valorCatalogo += roundMoney(preco * q);
        sanitizados.push({
            id_produto: s.id,
            nome: String(lista[i].nome || d.nome || "Produto"),
            preco_ref: roundMoney(preco),
            quantidade: Math.floor(q),
            imagem: String(lista[i].imagem || ""),
            variacoes: lista[i].variacoes && typeof lista[i].variacoes === "object"
                ? {
                    ...(lista[i].variacoes.cor
                        ? { cor: String(lista[i].variacoes.cor).trim().slice(0, 80) }
                        : {}),
                    ...(lista[i].variacoes.tamanho
                        ? { tamanho: String(lista[i].variacoes.tamanho).trim().slice(0, 80) }
                        : {}),
                }
                : {},
            variacoes_resumo: String(lista[i].variacoes_resumo || "").trim().slice(0, 180),
            tipo_venda: "encomenda",
        });
    }
    if (lojaRef !== lojaIdEsperada) {
        throw new HttpsError("permission-denied", "Inconsistência de loja nos produtos.");
    }
    return { lojaId: lojaRef, itensSanitizados: sanitizados, valorCatalogo };
}

exports.encomendaClienteCriar = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const data = request.data || {};
    const itensRaw = data.itens;
    const lojaIdCliente = String(data.loja_id || "").trim();
    const mensagemCliente = String(data.mensagem_cliente || "").trim().slice(0, 1200);
    const tipoEntrega = String(data.tipo_entrega || "entrega").trim().toLowerCase();
    const enderecoEntrega = String(data.endereco_entrega || "").trim().slice(0, 500);
    const taxaSnap = roundMoney(Number(data.taxa_entrega_snapshot || 0));

    if (!lojaIdCliente) {
        throw new HttpsError("invalid-argument", "loja_id obrigatório.");
    }
    if (tipoEntrega !== "entrega" && tipoEntrega !== "retirada") {
        throw new HttpsError("invalid-argument", "tipo_entrega inválido.");
    }
    if (tipoEntrega === "entrega" && enderecoEntrega.length < 8) {
        throw new HttpsError("invalid-argument", "Informe um endereço de entrega válido.");
    }

    const { itensSanitizados, valorCatalogo } = await validarItensEncomenda(
        db,
        itensRaw,
        lojaIdCliente,
    );

    const ref = db.collection("encomendas").doc();

    // Snapshots para exibição (cliente vê o nome da loja; loja vê o telefone do cliente).
    const clienteSnap = await db.collection("users").doc(uid).get();
    const cd = clienteSnap.exists ? clienteSnap.data() || {} : {};
    const nomeCliente = String(
        cd.nome || cd.nome_completo || cd.display_name || cd.displayName || "Cliente",
    ).trim() || "Cliente";
    const telefoneCliente = String(cd.telefone || cd.phone || cd.celular || "").trim();
    const cidadeEntrega = String(
        cd.cidade || cd.endereco_cidade || cd.cidade_normalizada || "",
    ).trim();
    const ufEntrega = String(cd.uf || cd.estado || cd.endereco_estado || "").trim();

    let lojaNomeSnapshot = "";
    try {
        const lojaPbSnap = await db.collection("lojas_public").doc(lojaIdCliente).get();
        if (lojaPbSnap.exists) {
            const ld = lojaPbSnap.data() || {};
            lojaNomeSnapshot = String(
                ld.loja_nome || ld.nome_loja || ld.nome_fantasia || ld.nome || "",
            ).trim();
        }
    } catch (_) {
        // fallback silencioso — a tela do cliente também resolve o nome da loja.
    }

    const batch = db.batch();
    batch.set(ref, {
        cliente_id: uid,
        cliente_nome_snapshot: nomeCliente,
        cliente_telefone_snapshot: telefoneCliente,
        loja_id: lojaIdCliente,
        loja_nome_snapshot: lojaNomeSnapshot,
        status_negociacao: ST.AGUARDANDO_NEGOCIACAO,
        itens: itensSanitizados,
        valor_catalogo_referencia: valorCatalogo,
        mensagem_cliente: mensagemCliente || null,
        tipo_entrega: tipoEntrega,
        endereco_entrega:
            tipoEntrega === "retirada" ? "Retirada no balcão" : enderecoEntrega,
        cidade_entrega: cidadeEntrega,
        uf_entrega: ufEntrega,
        taxa_entrega_snapshot: taxaSnap >= 0 ? taxaSnap : 0,
        pedido_entrada_id: null,
        valor_total_referencia: null,
        valor_entrada_loja: null,
        observacoes_loja: null,
        entrada_contraproposta_cliente: null,
        mensagem_contraproposta_cliente: null,
        historico: [],
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();

    await appendHistorico(ref, "cliente_abriu", "Cliente iniciou solicitação de encomenda.");
    await gravarAlertaEncomendaLoja(
        db,
        lojaIdCliente,
        ref.id,
        "Nova solicitação de encomenda para negociar.",
    );
    await enviarEncomendaParaLoja(
        db,
        lojaIdCliente,
        ref.id,
        "nova_solicitacao",
        "Nova encomenda para negociar",
        "Um cliente iniciou uma solicitação de encomenda na sua loja.",
        uid,
    );

    return { ok: true, encomendaId: ref.id };
});

exports.encomendaLojaAceitarNegociacao = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const lojaOp = await uidLojaOperacional(db, uid);
    const data = request.data || {};
    const encId = String(data.encomendaId || "").trim();
    if (!encId || !lojaOp) {
        throw new HttpsError("invalid-argument", "Dados inválidos.");
    }

    const ref = db.collection("encomendas").doc(encId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.loja_id !== lojaOp) {
            throw new HttpsError("permission-denied", "Esta encomenda é de outra loja.");
        }
        if (e.status_negociacao !== ST.AGUARDANDO_NEGOCIACAO) {
            throw new HttpsError("failed-precondition", "Status não permite esta ação.");
        }
        tx.update(ref, {
            status_negociacao: ST.NEGOCIACAO_EM_ANDAMENTO,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    await appendHistorico(ref, "loja_aceitou", "Loja aceitou iniciar a negociação.");
    const clienteId = (await ref.get()).data()?.cliente_id;
    await gravarAlertaEncomendaCliente(
        db,
        clienteId,
        encId,
        "A loja aceitou iniciar a negociação da sua encomenda.",
    );
    await enviarEncomendaParaCliente(
        db,
        clienteId,
        encId,
        "loja_aceitou",
        "Encomenda",
        "A loja aceitou iniciar a negociação da sua encomenda.",
        lojaOp,
    );

    return { ok: true };
});

exports.encomendaLojaEnviarProposta = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const lojaOp = await uidLojaOperacional(db, uid);
    const data = request.data || {};
    const encId = String(data.encomendaId || "").trim();
    const valorTotal = roundMoney(Number(data.valor_total_referencia || 0));
    const valorEntrada = roundMoney(Number(data.valor_entrada_loja || 0));
    const observacoes = String(data.observacoes_loja || "").trim().slice(0, 1200);
    const formasEntradaRaw = Array.isArray(data.formas_pagamento_entrada_loja)
        ? data.formas_pagamento_entrada_loja
        : [];
    const formasEntrada = [...new Set(
        formasEntradaRaw
            .map((v) => String(v || "").trim().toLowerCase())
            .filter((v) => v === "pix" || v === "cartao"),
    )];

    if (!encId || !lojaOp) {
        throw new HttpsError("invalid-argument", "Dados inválidos.");
    }
    if (!(valorTotal > 0) || !(valorEntrada > 0)) {
        throw new HttpsError("invalid-argument", "Valores da proposta inválidos.");
    }
    if (valorEntrada > valorTotal) {
        throw new HttpsError("invalid-argument", "A entrada não pode ser maior que o total.");
    }
    if (!formasEntrada.length) {
        throw new HttpsError("invalid-argument", "Informe Pix, cartão ou as duas formas para a entrada.");
    }

    const ref = db.collection("encomendas").doc(encId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.loja_id !== lojaOp) {
            throw new HttpsError("permission-denied", "Esta encomenda é de outra loja.");
        }
        if (e.status_negociacao !== ST.NEGOCIACAO_EM_ANDAMENTO) {
            throw new HttpsError("failed-precondition", "Status não permite enviar proposta.");
        }
        tx.update(ref, {
            status_negociacao: ST.PROPOSTA_ENVIADA,
            valor_total_referencia: valorTotal,
            valor_entrada_loja: valorEntrada,
            formas_pagamento_entrada_loja: formasEntrada,
            observacoes_loja: observacoes || null,
            entrada_contraproposta_cliente: null,
            mensagem_contraproposta_cliente: null,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    await appendHistorico(
        ref,
        "loja_proposta",
        `Proposta: total R$ ${valorTotal.toFixed(2)}, entrada R$ ${valorEntrada.toFixed(2)}.`,
    );
    const clienteId = (await ref.get()).data()?.cliente_id;
    await gravarAlertaEncomendaCliente(
        db,
        clienteId,
        encId,
        "A loja enviou uma proposta para sua encomenda.",
    );
    await enviarEncomendaParaCliente(
        db,
        clienteId,
        encId,
        "loja_proposta",
        "Nova proposta da loja",
        "A loja enviou uma proposta para sua encomenda.",
        lojaOp,
    );

    return { ok: true };
});

exports.encomendaClienteEnviarContraproposta = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const data = request.data || {};
    const encId = String(data.encomendaId || "").trim();
    const entradaCliente = roundMoney(Number(data.valor_entrada_cliente || 0));
    const mensagem = String(data.mensagem || "").trim().slice(0, 1200);

    if (!encId) {
        throw new HttpsError("invalid-argument", "encomendaId obrigatório.");
    }
    if (!(entradaCliente > 0)) {
        throw new HttpsError("invalid-argument", "Informe o valor de entrada que pode pagar.");
    }

    const ref = db.collection("encomendas").doc(encId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Acesso negado.");
        }
        if (e.status_negociacao !== ST.PROPOSTA_ENVIADA) {
            throw new HttpsError("failed-precondition", "Não há proposta ativa para contrapor.");
        }
        const totalRef = Number(e.valor_total_referencia || 0);
        if (entradaCliente > totalRef) {
            throw new HttpsError("invalid-argument", "Valor acima do total da proposta.");
        }
        tx.update(ref, {
            status_negociacao: ST.AGUARDANDO_LOJA_CONTRA,
            entrada_contraproposta_cliente: entradaCliente,
            mensagem_contraproposta_cliente: mensagem || null,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    await appendHistorico(
        ref,
        "cliente_contraproposta",
        `Cliente propôs entrada de R$ ${entradaCliente.toFixed(2)}.`,
    );
    const lojaId = (await ref.get()).data()?.loja_id;
    await gravarAlertaEncomendaLoja(
        db,
        lojaId,
        encId,
        "O cliente enviou uma contraproposta na encomenda.",
    );
    await enviarEncomendaParaLoja(
        db,
        lojaId,
        encId,
        "cliente_contraproposta",
        "Contraproposta do cliente",
        "O cliente enviou uma contraproposta na encomenda.",
        uid,
    );

    return { ok: true };
});

exports.encomendaLojaResponderContraproposta = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const lojaOp = await uidLojaOperacional(db, uid);
    const data = request.data || {};
    const encId = String(data.encomendaId || "").trim();
    const decisao = String(data.decisao || "").trim().toLowerCase();
    const novoTotal = data.valor_total_referencia != null
        ? roundMoney(Number(data.valor_total_referencia))
        : null;
    const novaEntrada = data.valor_entrada_loja != null
        ? roundMoney(Number(data.valor_entrada_loja))
        : null;
    const observacoes = String(data.observacoes_loja || "").trim().slice(0, 1200);

    if (!encId || !lojaOp) {
        throw new HttpsError("invalid-argument", "Dados inválidos.");
    }

    const ref = db.collection("encomendas").doc(encId);
    let textoCliente = "";

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.loja_id !== lojaOp) {
            throw new HttpsError("permission-denied", "Esta encomenda é de outra loja.");
        }
        if (e.status_negociacao !== ST.AGUARDANDO_LOJA_CONTRA) {
            throw new HttpsError("failed-precondition", "Não há contraproposta pendente.");
        }

        if (decisao === "recusar") {
            tx.update(ref, {
                status_negociacao: ST.ENCERRADA_RECUSADA,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            textoCliente = "A loja encerrou a negociação da encomenda.";
            return;
        }

        if (decisao === "aceitar") {
            const total = Number(e.valor_total_referencia || 0);
            const entradaCli = Number(e.entrada_contraproposta_cliente || 0);
            if (!(entradaCli > 0) || entradaCli > total) {
                throw new HttpsError("failed-precondition", "Contraproposta inválida.");
            }
            tx.update(ref, {
                status_negociacao: ST.PROPOSTA_ACEITA_PENDENTE_ENTRADA,
                valor_entrada_loja: entradaCli,
                observacoes_loja:
                    observacoes ||
                    e.observacoes_loja ||
                    null,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            textoCliente = "A loja aceitou sua contraproposta. Você já pode pagar a entrada.";
            return;
        }

        if (decisao === "contrapor") {
            if (!(novoTotal > 0) || !(novaEntrada > 0)) {
                throw new HttpsError("invalid-argument", "Informe total e entrada na contraproposta.");
            }
            if (novaEntrada > novoTotal) {
                throw new HttpsError("invalid-argument", "Entrada maior que o total.");
            }
            tx.update(ref, {
                status_negociacao: ST.PROPOSTA_ENVIADA,
                valor_total_referencia: novoTotal,
                valor_entrada_loja: novaEntrada,
                observacoes_loja: observacoes || null,
                entrada_contraproposta_cliente: null,
                mensagem_contraproposta_cliente: null,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            textoCliente = "A loja enviou uma nova proposta para sua encomenda.";
            return;
        }

        throw new HttpsError("invalid-argument", "decisao inválida.");
    });

    const snapAfter = await ref.get();
    const eAfter = snapAfter.data() || {};
    const clienteId = eAfter.cliente_id;

    if (decisao === "recusar") {
        await appendHistorico(ref, "loja_recusou", "Loja encerrou a negociação.");
        await gravarAlertaEncomendaCliente(db, clienteId, encId, textoCliente);
        await enviarEncomendaParaCliente(
            db,
            clienteId,
            encId,
            "loja_recusou",
            "Encomenda encerrada",
            textoCliente,
            lojaOp,
        );
    } else if (decisao === "aceitar") {
        await appendHistorico(ref, "loja_aceitou_contra", "Loja aceitou a contraproposta do cliente.");
        await gravarAlertaEncomendaCliente(db, clienteId, encId, textoCliente);
        await enviarEncomendaParaCliente(
            db,
            clienteId,
            encId,
            "loja_aceitou_contra",
            "Contraproposta aceita",
            textoCliente,
            lojaOp,
        );
    } else if (decisao === "contrapor") {
        await appendHistorico(ref, "loja_contraproposta", "Loja enviou nova proposta.");
        await gravarAlertaEncomendaCliente(db, clienteId, encId, textoCliente);
        await enviarEncomendaParaCliente(
            db,
            clienteId,
            encId,
            "loja_nova_proposta",
            "Nova proposta da loja",
            textoCliente,
            lojaOp,
        );
    }

    return { ok: true };
});

exports.encomendaClienteAceitarPropostaECriarPedidoEntrada = onCall(
    CALL_OPTS,
    async (request) => {
        assertAuth(request);
        const db = admin.firestore();
        const uid = request.auth.uid;
        const data = request.data || {};
        const encId = String(data.encomendaId || "").trim();
        if (!encId) {
            throw new HttpsError("invalid-argument", "encomendaId obrigatório.");
        }

        const ref = db.collection("encomendas").doc(encId);
        let pedidoIdResult = null;
        let criouPedidoNestaExecucao = false;

        await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) {
                throw new HttpsError("not-found", "Encomenda não encontrada.");
            }
            const e = snap.data() || {};
            if (e.cliente_id !== uid) {
                throw new HttpsError("permission-denied", "Acesso negado.");
            }
            const ok =
                e.status_negociacao === ST.PROPOSTA_ENVIADA ||
                e.status_negociacao === ST.PROPOSTA_ACEITA_PENDENTE_ENTRADA ||
                (
                    e.status_negociacao === ST.ENTRADA_AGUARDANDO_PGTO &&
                    e.pedido_entrada_id
                );
            if (!ok) {
                throw new HttpsError(
                    "failed-precondition",
                    "Não há proposta aceitável neste momento.",
                );
            }
            if (e.pedido_entrada_id) {
                const pedEntradaRef = db.collection("pedidos").doc(String(e.pedido_entrada_id));
                const pedEntradaSnap = await tx.get(pedEntradaRef);
                const pedEntrada = pedEntradaSnap.exists ? pedEntradaSnap.data() || {} : null;
                if (
                    pedEntrada &&
                    pedEntrada.status === "aguardando_pagamento" &&
                    pedEntrada.cliente_id === uid
                ) {
                    pedidoIdResult = e.pedido_entrada_id;
                    return;
                }
            }
            criouPedidoNestaExecucao = true;

            const totalEnc = roundMoney(Number(e.valor_total_referencia || 0));
            const entrada = roundMoney(Number(e.valor_entrada_loja || 0));
            if (!(totalEnc > 0) || !(entrada > 0) || entrada > totalEnc) {
                throw new HttpsError("failed-precondition", "Valores da proposta incompletos.");
            }

            const clienteSnap = await tx.get(db.collection("users").doc(uid));
            const cd = clienteSnap.exists ? clienteSnap.data() || {} : {};
            const clienteNome = String(
                cd.nome ||
                    cd.nome_completo ||
                    cd.display_name ||
                    cd.displayName ||
                    "Cliente",
            ).trim();
            const clienteFoto = String(cd.foto_perfil || cd.foto || "").trim();
            const clienteTel = String(cd.telefone || cd.phone || "").trim();

            const lojaPb = await tx.get(
                db.collection("lojas_public").doc(String(e.loja_id)),
            );
            const ld = lojaPb.exists ? lojaPb.data() || {} : {};
            const lojaNome = String(ld.loja_nome || ld.nome_loja || ld.nome || "Loja").trim();
            const lojaFoto = String(
                ld.foto_perfil || ld.foto || ld.imagem || ld.foto_logo || "",
            ).trim();
            const lojaTel = String(ld.telefone || "").trim();
            const lojaEnd = String(ld.endereco || "").trim();
            let lojaLat = null;
            let lojaLng = null;
            if (ld.latitude != null && ld.longitude != null) {
                lojaLat = Number(ld.latitude);
                lojaLng = Number(ld.longitude);
            }

            const tokenGerado = String(Math.floor(100000 + Math.random() * 900000));

            const pedRef = db.collection("pedidos").doc();
            pedidoIdResult = pedRef.id;

            const itensPedido = (e.itens || []).map((it) => ({
                id_produto: String(it.id_produto || ""),
                nome: String(it.nome || ""),
                preco: Number(it.preco_ref || 0),
                quantidade: Number(it.quantidade || 1),
                imagem: String(it.imagem || ""),
                variacoes: it.variacoes || {},
                variacoes_resumo: String(it.variacoes_resumo || ""),
                tipo_venda: "encomenda",
            }));

            tx.set(pedRef, {
                cliente_id: uid,
                cliente_nome: clienteNome,
                cliente_foto_perfil: clienteFoto,
                cliente_telefone: clienteTel,
                loja_id: String(e.loja_id),
                loja_nome: lojaNome,
                loja_foto: lojaFoto,
                loja_telefone: lojaTel,
                loja_endereco: lojaEnd || "Endereço não cadastrado",
                ...(lojaLat != null &&
                    lojaLng != null &&
                    Number.isFinite(lojaLat) &&
                    Number.isFinite(lojaLng)
                    ? { loja_latitude: lojaLat, loja_longitude: lojaLng }
                    : {}),
                token_entrega: tokenGerado,
                itens: itensPedido,
                subtotal: entrada,
                total_produtos: roundMoney(
                    (e.itens || []).reduce(
                        (acc, it) =>
                            acc +
                            Number(it.preco_ref || 0) * Number(it.quantidade || 1),
                        0,
                    ),
                ),
                taxa_entrega: 0,
                desconto_saldo: 0,
                total: entrada,
                tipo_entrega:
                    e.tipo_entrega === "retirada" ? "retirada" : "entrega",
                endereco_entrega: String(e.endereco_entrega || ""),
                forma_pagamento: "Encomenda — entrada (PIX ou cartão)",
                status: "aguardando_pagamento",
                data_pedido: admin.firestore.FieldValue.serverTimestamp(),
                tipo_compra: "encomenda",
                encomenda_id: encId,
                encomenda_fase_financeira: "entrada",
                valor_total_encomenda_referencia: totalEnc,
                valor_entrada_acordado: entrada,
                valor_restante_estimado: roundMoney(totalEnc - entrada),
            });

            tx.update(ref, {
                pedido_entrada_id: pedidoIdResult,
                status_negociacao: ST.ENTRADA_AGUARDANDO_PGTO,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
        });

        if (criouPedidoNestaExecucao && pedidoIdResult) {
            await appendHistorico(
                ref,
                "pedido_entrada_criado",
                `Pedido ${pedidoIdResult} criado para pagamento da entrada.`,
            );
        }

        return { ok: true, pedidoEntradaId: pedidoIdResult };
    },
);

/**
 * MP/webhook — entrada da encomenda paga (pedido `encomenda_fase_financeira: entrada`).
 * Atualiza coleção `encomendas`, histórico, `alerta_*` e FCM.
 */
exports.sincronizarEncomendaAposPagamentoEntrada = async function sincronizarEncomendaAposPagamentoEntrada(
    db,
    pedidoId,
    ped,
) {
    const encId = String(ped.encomenda_id || "").trim();
    if (!encId) return;
    const ref = db.collection("encomendas").doc(encId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const e = snap.data() || {};
    if (String(e.pedido_entrada_id || "") !== String(pedidoId)) return;

    await ref.update({
        status_negociacao: ST.ENTRADA_PAGA_EM_PRODUCAO,
        entrada_paga_em: admin.firestore.FieldValue.serverTimestamp(),
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
    await appendHistorico(
        ref,
        "entrada_paga",
        `Entrada confirmada (pedido ${pedidoId}). Produção antes do saldo.`,
    );
    await gravarAlertaEncomendaLoja(
        db,
        String(e.loja_id || ""),
        encId,
        "Entrada da encomenda paga — produza e gere a cobrança do saldo quando estiver pronto.",
    );
    await gravarAlertaEncomendaCliente(
        db,
        String(e.cliente_id || ""),
        encId,
        "Sua entrada foi confirmada. A loja vai preparar e liberar o pagamento do saldo em seguida.",
    );
    const lojaUid = String(e.loja_id || "");
    const clienteUid = String(e.cliente_id || "");
    await enviarEncomendaParaLoja(
        db,
        lojaUid,
        encId,
        "entrada_paga",
        "Entrada da encomenda paga",
        "A entrada foi confirmada — produza e gere a cobrança do saldo quando estiver pronto.",
        clienteUid,
    );
    await enviarEncomendaParaCliente(
        db,
        clienteUid,
        encId,
        "entrada_confirmada",
        "Entrada confirmada",
        "Sua entrada foi confirmada. A loja vai preparar e liberar o pagamento do saldo em seguida.",
        lojaUid,
    );
};

/** MP/webhook — saldo final da encomenda pago; libera fluxo logístico normal no `pedidos`. */
exports.sincronizarEncomendaAposPagamentoSaldoFinal = async function sincronizarEncomendaAposPagamentoSaldoFinal(
    db,
    pedidoId,
    ped,
) {
    const encId = String(ped.encomenda_id || "").trim();
    if (!encId) return;
    const ref = db.collection("encomendas").doc(encId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const e = snap.data() || {};
    if (String(e.pedido_saldo_final_id || "") !== String(pedidoId)) return;

    await ref.update({
        status_negociacao: ST.EM_EXECUCAO_LOGISTICA,
        saldo_final_pago_em: admin.firestore.FieldValue.serverTimestamp(),
        pedido_logistica_id: pedidoId,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
    await appendHistorico(
        ref,
        "saldo_pago",
        `Saldo confirmado (pedido ${pedidoId}). Pedido em fluxo normal.`,
    );
};

exports.encomendaLojaCriarPedidoSaldoFinal = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const lojaOp = await uidLojaOperacional(db, request.auth.uid);
    const encId = String((request.data || {}).encomendaId || "").trim();
    if (!encId || !lojaOp) {
        throw new HttpsError("invalid-argument", "Dados inválidos.");
    }

    const ref = db.collection("encomendas").doc(encId);
    let pedSaldoId = null;
    let criou = false;
    let clienteUid = "";

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        clienteUid = String(e.cliente_id || "");
        if (e.loja_id !== lojaOp) {
            throw new HttpsError("permission-denied", "Esta encomenda é de outra loja.");
        }
        if (e.pedido_saldo_final_id) {
            pedSaldoId = String(e.pedido_saldo_final_id);
            return;
        }
        if (e.status_negociacao !== ST.ENTRADA_PAGA_EM_PRODUCAO) {
            throw new HttpsError(
                "failed-precondition",
                "Só é possível gerar o saldo quando a entrada já foi paga e a encomenda está em produção.",
            );
        }
        const entradaPedidoId = String(e.pedido_entrada_id || "").trim();
        if (!entradaPedidoId) {
            throw new HttpsError("failed-precondition", "Pedido de entrada ausente.");
        }
        const pedEntradaSnap = await tx.get(db.collection("pedidos").doc(entradaPedidoId));
        if (!pedEntradaSnap.exists) {
            throw new HttpsError("failed-precondition", "Pedido de entrada não encontrado.");
        }
        const pe = pedEntradaSnap.data() || {};
        if (String(pe.status || "") !== "encomenda_entrada_paga") {
            throw new HttpsError(
                "failed-precondition",
                "Confirme que o pagamento da entrada foi concluído antes de gerar o saldo.",
            );
        }

        const totalEnc = roundMoney(Number(e.valor_total_referencia || 0));
        const entrada = roundMoney(Number(e.valor_entrada_loja || 0));
        // Frete combinado na abertura da encomenda (0 em retirada no balcão).
        const tipoEntregaSaldo =
            (pe.tipo_entrega === "retirada" || e.tipo_entrega === "retirada")
                ? "retirada"
                : "entrega";
        const freteEnc = tipoEntregaSaldo === "retirada"
            ? 0
            : roundMoney(Number(e.taxa_entrega_snapshot || 0));
        // Restante de PRODUTOS (valor negociado - entrada já paga).
        const restanteProdutos = roundMoney(totalEnc - entrada);
        // O cliente paga o restante dos produtos + o frete neste pedido de saldo.
        const totalSaldoCliente = roundMoney(restanteProdutos + freteEnc);
        if (!(totalSaldoCliente > 0)) {
            throw new HttpsError("failed-precondition", "Não há valor de saldo para cobrar.");
        }

        const pedRef = db.collection("pedidos").doc();
        pedSaldoId = pedRef.id;
        criou = true;

        const itensPedido = (e.itens || []).map((it) => ({
            id_produto: String(it.id_produto || ""),
            nome: String(it.nome || ""),
            preco: Number(it.preco_ref || 0),
            quantidade: Number(it.quantidade || 1),
            imagem: String(it.imagem || ""),
            variacoes: it.variacoes || {},
            variacoes_resumo: String(it.variacoes_resumo || ""),
            tipo_venda: "encomenda",
        }));

        tx.set(pedRef, {
            cliente_id: pe.cliente_id,
            cliente_nome: pe.cliente_nome,
            cliente_foto_perfil: pe.cliente_foto_perfil,
            cliente_telefone: pe.cliente_telefone,
            loja_id: String(e.loja_id),
            loja_nome: pe.loja_nome,
            loja_foto: pe.loja_foto,
            loja_telefone: pe.loja_telefone,
            loja_endereco: pe.loja_endereco || "",
            ...(pe.loja_latitude != null && pe.loja_longitude != null
                ? {
                      loja_latitude: pe.loja_latitude,
                      loja_longitude: pe.loja_longitude,
                  }
                : {}),
            token_entrega:
                pe.token_entrega || String(Math.floor(100000 + Math.random() * 900000)),
            itens: itensPedido,
            subtotal: restanteProdutos,
            // Taxa da plataforma no produto incide só sobre o restante (entrada sem taxa).
            total_produtos: restanteProdutos,
            taxa_entrega: freteEnc,
            desconto_saldo: 0,
            total: totalSaldoCliente,
            tipo_entrega: tipoEntregaSaldo,
            endereco_entrega: String(pe.endereco_entrega || e.endereco_entrega || ""),
            forma_pagamento: "Encomenda — saldo (PIX ou cartão)",
            status: "aguardando_pagamento",
            data_pedido: admin.firestore.FieldValue.serverTimestamp(),
            tipo_compra: "encomenda",
            encomenda_id: encId,
            encomenda_fase_financeira: "saldo_final",
            valor_total_encomenda_referencia: totalEnc,
            valor_entrada_acordado: entrada,
            valor_total_produto: totalEnc,
            valor_entrada_produto: entrada,
            valor_restante_produto: restanteProdutos,
            valor_total_frete: freteEnc,
            valor_frete_encomenda: freteEnc,
            valor_restante_estimado: totalSaldoCliente,
            pedido_encomenda_entrada_id: entradaPedidoId,
        });

        tx.update(ref, {
            pedido_saldo_final_id: pedSaldoId,
            status_negociacao: ST.SALDO_FINAL_AGUARDANDO_PGTO,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    if (criou && pedSaldoId) {
        await appendHistorico(
            ref,
            "pedido_saldo_criado",
            `Pedido ${pedSaldoId} criado para pagamento do saldo.`,
        );
        await gravarAlertaEncomendaCliente(
            db,
            clienteUid,
            encId,
            "A loja gerou a cobrança do saldo da encomenda — conclua o pagamento no app.",
        );
        await enviarEncomendaParaCliente(
            db,
            clienteUid,
            encId,
            "saldo_cobranca",
            "Cobrança do saldo",
            "A loja gerou a cobrança do saldo da encomenda — conclua o pagamento no app.",
            lojaOp,
        );
    }

    return { ok: true, pedidoSaldoFinalId: pedSaldoId };
});

exports.encomendaClienteCancelarNegociacao = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const encId = String((request.data || {}).encomendaId || "").trim();
    if (!encId) {
        throw new HttpsError("invalid-argument", "encomendaId obrigatório.");
    }
    const ref = db.collection("encomendas").doc(encId);
    const motivoPedido = "encomenda_cancelada_cliente_antes_entrada";

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Acesso negado.");
        }
        if (!statusPermiteCancelarNegociacaoAntesEntrada(e.status_negociacao)) {
            throw new HttpsError(
                "failed-precondition",
                "Não é possível cancelar nesta etapa (entrada já paga ou negociação encerrada).",
            );
        }
        await cancelarPedidoEntradaAbertoNaTx(tx, db, e.pedido_entrada_id, motivoPedido, encId);
        tx.update(ref, {
            status_negociacao: ST.ENCERRADA_CANCELADA_CLIENTE,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    await appendHistorico(ref, "cliente_cancelou_negociacao", "Cliente cancelou a negociação antes da entrada.");
    const lojaId = (await ref.get()).data()?.loja_id;
    await gravarAlertaEncomendaLoja(
        db,
        String(lojaId || ""),
        encId,
        "O cliente cancelou a solicitação de encomenda.",
    );
    await enviarEncomendaParaLoja(
        db,
        String(lojaId || ""),
        encId,
        "cliente_cancelou",
        "Encomenda cancelada",
        "O cliente cancelou a solicitação de encomenda.",
        uid,
    );

    return { ok: true };
});

exports.encomendaLojaCancelarNegociacao = onCall(CALL_OPTS, async (request) => {
    assertAuth(request);
    const db = admin.firestore();
    const uid = request.auth.uid;
    const lojaOp = await uidLojaOperacional(db, uid);
    const encId = String((request.data || {}).encomendaId || "").trim();
    if (!encId || !lojaOp) {
        throw new HttpsError("invalid-argument", "Dados inválidos.");
    }
    const ref = db.collection("encomendas").doc(encId);
    const motivoPedido = "encomenda_cancelada_loja_antes_entrada";

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) {
            throw new HttpsError("not-found", "Encomenda não encontrada.");
        }
        const e = snap.data() || {};
        if (e.loja_id !== lojaOp) {
            throw new HttpsError("permission-denied", "Esta encomenda é de outra loja.");
        }
        if (!statusPermiteCancelarNegociacaoAntesEntrada(e.status_negociacao)) {
            throw new HttpsError(
                "failed-precondition",
                "Não é possível cancelar nesta etapa (entrada já paga ou negociação encerrada).",
            );
        }
        await cancelarPedidoEntradaAbertoNaTx(tx, db, e.pedido_entrada_id, motivoPedido, encId);
        tx.update(ref, {
            status_negociacao: ST.ENCERRADA_CANCELADA_LOJA,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    await appendHistorico(ref, "loja_cancelou_negociacao", "Loja cancelou a negociação antes da entrada.");
    const clienteId = (await ref.get()).data()?.cliente_id;
    await gravarAlertaEncomendaCliente(
        db,
        String(clienteId || ""),
        encId,
        "A loja cancelou a negociação da sua encomenda.",
    );
    await enviarEncomendaParaCliente(
        db,
        String(clienteId || ""),
        encId,
        "loja_cancelou",
        "Negociação cancelada",
        "A loja cancelou a negociação da sua encomenda.",
        lojaOp,
    );

    return { ok: true };
});
