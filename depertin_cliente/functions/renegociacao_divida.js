// =============================================================================
// Renegociação de Dívida — Callable v2 (Admin SDK)
//
// Toda a lógica PESADA roda aqui no servidor:
//   - Lê parcelas do banco, valida status
//   - Recalcula juros/multa com base nas datas reais
//   - Recalcula desconto, juros, multa do lado do servidor
//   - Cria batch atômico com validação de integridade
//   - NUNCA confia cegamente nos valores do frontend
// =============================================================================

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

// ── Helpers ──

function parseDate(val) {
    if (!val) return new Date();
    if (typeof val === "string") return new Date(val);
    if (val.toDate && typeof val.toDate === "function") return val.toDate();
    if (val instanceof Date) return val;
    return new Date(val);
}

function roundMoney(v) {
    return Math.round(v * 100) / 100;
}

/**
 * Lê a config de juros/multa do cliente comercial.
 * Fallback: 1% juros, 2% multa.
 */
async function lerConfigJurosMulta(db, lojaId, clienteId) {
    try {
        const snap = await db
            .collection("users")
            .doc(lojaId)
            .collection("clientes_comercial")
            .doc(clienteId)
            .get();
        if (!snap.exists) return { juros_ao_dia: 0.01, multa_percentual: 0.02 };
        const d = snap.data() || {};
        return {
            juros_ao_dia: typeof d.juros_ao_dia === "number" ? d.juros_ao_dia : 0.01,
            multa_percentual: typeof d.multa_percentual === "number" ? d.multa_percentual : 0.02,
        };
    } catch (_) {
        return { juros_ao_dia: 0.01, multa_percentual: 0.02 };
    }
}

/** Calcula juros e multa para uma parcela vencida. */
function calcularJurosMultaParcela(valor, dataVencimento, config) {
    const hoje = new Date();
    const venc = parseDate(dataVencimento);
    const vencClean = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate());
    const hojeClean = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());

    const diasAtraso = Math.max(0, Math.floor((hojeClean - vencClean) / (1000 * 60 * 60 * 24)));
    if (diasAtraso <= 0) return { juros: 0, multa: 0, diasAtraso: 0 };

    const multa = roundMoney(valor * (config.multa_percentual / 100));
    const juros = roundMoney(valor * (config.juros_ao_dia / 100) * diasAtraso);
    return { juros, multa, diasAtraso };
}

// =============================================================================
// CALLABLE PRINCIPAL
// =============================================================================

exports.renegociarDividaCallable = functions.https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login para renegociar.");
        }

        const {
            lojaId,
            clienteId,
            clienteNome,
            parcelasIds,
            observacao,
            tipo,
            // Desconto (duas fontes: "À vista" → descontoPercentualAVista, "Desconto" → descontoPercentual)
            descontoPercentual = 0,
            descontoPercentualAVista = 0,
            // Juros
            jurosAction = "manter",
            jurosPercentual = 0,
            // Multa
            multaAction = "manter",
            multaPercentual = 0,
            // Valores enviados pelo frontend (usados como REFERÊNCIA apenas)
            valorOriginalSelecionado: _valorOriginalFrontend = 0,
            // Novas datas (para tipo "vencimento")
            novoVencimento,
            alterarTodasParcelas = true,
            // Parcelamento
            qtdParcelasNovas = 0,
            entradaValor = 0,
            primeiroVencimento = null,
            intervaloParcelas = "Mensal",
            cronograma = [],
            // Para auditoria
            descontoCalculadoFrontend = 0,
            jurosAplicadosFrontend = 0,
            multaAplicadaFrontend = 0,
            novoValorFinalFrontend = 0,
        } = data || {};

        // ── Validações básicas ──
        if (!lojaId || !clienteId || !Array.isArray(parcelasIds) || parcelasIds.length === 0) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "lojaId, clienteId e parcelasIds (não vazio) são obrigatórios."
            );
        }

        const obs = (observacao || "").trim();
        if (obs.length < 5) {
            throw new functions.https.HttpsError("invalid-argument", "Observação deve ter no mínimo 5 caracteres.");
        }

        const tiposValidos = ["avista", "parcelar", "vencimento", "desconto", "isentarJuros", "isentarMulta", "personalizada"];
        if (!tiposValidos.includes(tipo)) {
            throw new functions.https.HttpsError("invalid-argument", `Tipo de renegociação inválido: ${tipo}`);
        }

        const usuarioNome =
            (context.auth.token && context.auth.token.name) ||
            context.auth.token.email ||
            "Sistema";

        const agoraDate = new Date();
        const agora = admin.firestore.FieldValue.serverTimestamp();

        const dd = String(agoraDate.getDate()).padStart(2, "0");
        const mm = String(agoraDate.getMonth() + 1).padStart(2, "0");
        const yyyy = agoraDate.getFullYear();
        const ts = agoraDate.getTime();
        const codigoReneg = `RENEG-${dd}${mm}${yyyy}-${ts}`;

        const db = admin.firestore();

        const tipoRotulo = {
            avista: "À vista",
            parcelar: "Parcelar",
            vencimento: "Alterar vencimento",
            desconto: "Aplicar desconto",
            isentarJuros: "Isentar juros",
            isentarMulta: "Isentar multa",
            personalizada: "Personalizada",
        }[tipo] || tipo;

        // ── 1. LER parcelas do banco e VALIDAR ──
        const parcelasSnap = await Promise.all(
            parcelasIds.map((id) =>
                db.collection("users").doc(lojaId).collection("parcelas_cliente").doc(id).get()
            )
        );

        const parcelasValidas = [];
        for (const snap of parcelasSnap) {
            if (!snap.exists) {
                throw new functions.https.HttpsError("not-found", `Parcela ${snap.id} não encontrada no banco.`);
            }
            const d = snap.data() || {};
            const status = (d.status || "").toString().toLowerCase();
            // Só permite renegociar parcelas em aberto ou vencidas
            if (status !== "em_aberto" && status !== "vencido") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    `Parcela ${snap.id} está "${status}". Só é possível renegociar parcelas "em_aberto" ou "vencido".`
                );
            }
            parcelasValidas.push({ id: snap.id, data: d });
        }

        // ── 2. RECALCULAR valores no servidor ──
        const configJM = await lerConfigJurosMulta(db, lojaId, clienteId);

        // Soma dos valores originais
        let somaOriginal = 0;
        for (const p of parcelasValidas) {
            somaOriginal += (p.data.valor_em_aberto || p.data.valor_parcela || 0);
        }
        somaOriginal = roundMoney(somaOriginal);

        // Juros e multa recalculados
        let somaJuros = 0;
        let somaMulta = 0;
        for (const p of parcelasValidas) {
            const venc = p.data.data_vencimento;
            const valor = p.data.valor_em_aberto || p.data.valor_parcela || 0;
            if (valor > 0 && venc) {
                const calc = calcularJurosMultaParcela(valor, venc, configJM);
                somaJuros += calc.juros;
                somaMulta += calc.multa;
            }
        }
        somaJuros = roundMoney(somaJuros);
        somaMulta = roundMoney(somaMulta);

        // ── 3. APLICAR configurações de negociação ──

        // 3a. Juros finais
        let jurosFinais = somaJuros;
        switch (jurosAction) {
            case "remover":
                jurosFinais = 0;
                break;
            case "reduzir":
                // Reduz o JUROS ORIGINAL pelo percentual informado
                // Ex: juros=R$50, %=10 → reduz 10% de R$50 → R$5 → final=R$45
                if (jurosPercentual > 0 && jurosPercentual <= 100) {
                    const reducao = roundMoney(somaJuros * (jurosPercentual / 100));
                    jurosFinais = roundMoney(Math.max(0, somaJuros - reducao));
                } else {
                    jurosFinais = somaJuros;
                }
                break;
            case "novo":
                // Aplica NOVOS juros como percentual do principal
                if (jurosPercentual > 0) {
                    jurosFinais = roundMoney(somaOriginal * (jurosPercentual / 100));
                } else {
                    jurosFinais = 0;
                }
                break;
            default: // manter
                jurosFinais = somaJuros;
        }

        // 3b. Multa final
        let multaFinal = somaMulta;
        switch (multaAction) {
            case "remover":
                multaFinal = 0;
                break;
            case "reduzir":
                // Reduz a MULTA ORIGINAL pelo percentual informado
                if (multaPercentual > 0 && multaPercentual <= 100) {
                    const reducao = roundMoney(somaMulta * (multaPercentual / 100));
                    multaFinal = roundMoney(Math.max(0, somaMulta - reducao));
                } else {
                    multaFinal = somaMulta;
                }
                break;
            case "personalizada":
                // Aplica multa personalizada como percentual do principal
                if (multaPercentual > 0) {
                    multaFinal = roundMoney(somaOriginal * (multaPercentual / 100));
                } else {
                    multaFinal = 0;
                }
                break;
            default: // manter
                multaFinal = somaMulta;
        }

        // 3c. Qual desconto usar?
        const descPercentualEfetivo = (tipo === "avista" && descontoPercentualAVista > 0)
            ? descontoPercentualAVista
            : descontoPercentual;

        let descontoFinal = 0;
        if (tipo === "avista" || tipo === "desconto" || tipo === "personalizada") {
            if (descPercentualEfetivo > 0 && descPercentualEfetivo <= 100) {
                const baseDesconto = roundMoney(somaOriginal + jurosFinais + multaFinal);
                descontoFinal = roundMoney(baseDesconto * (descPercentualEfetivo / 100));
            }
        }

        // 3d. Valor final (sempre recalculado pelo servidor)
        const valorFinal = roundMoney(Math.max(0, somaOriginal + jurosFinais + multaFinal - descontoFinal));

        // ── 4. Validar divergência com frontend (log apenas, não bloqueia) ──
        const diff = Math.abs(valorFinal - novoValorFinalFrontend);
        if (diff > 0.05) {
            console.warn(
                `[renegociacao] Divergência de cálculo: frontend=${novoValorFinalFrontend} servidor=${valorFinal} ` +
                `diff=${diff} loja=${lojaId} cliente=${clienteId} tipo=${tipo}`
            );
        }

        // ── 5. MONTAR batch ──
        let batch = db.batch();
        let ops = 0;

        // Categorias de renegociação:
        //   - LIQUIDAÇÃO: parcela antiga é ENCERRADA (avista, parcelar)
        //   - ATUALIZAÇÃO: parcela antiga tem valor ATUALIZADO (desconto, isentarJuros, isentarMulta, personalizada)
        //   - VENCIMENTO: só altera data
        const tiposLiquidacao = ["avista", "parcelar"];
        const tiposAtualizacao = ["desconto", "isentarJuros", "isentarMulta", "personalizada"];
        const isLiquidacao = tiposLiquidacao.includes(tipo);
        const isAtualizacao = tiposAtualizacao.includes(tipo);

        // Para tipo "vencimento", data de vencimento nova
        const novaDataVenc = novoVencimento ? parseDate(novoVencimento) : null;

        for (const p of parcelasValidas) {
            const valorEmAberto = p.data.valor_em_aberto || p.data.valor_parcela || 0;
            const numParcela = p.data.numero_parcela || 0;
            const codVenda = p.data.codigo_venda || "";

            const ref = db
                .collection("users")
                .doc(lojaId)
                .collection("parcelas_cliente")
                .doc(p.id);

            if (tipo === "vencimento" && novaDataVenc) {
                // VENCIMENTO: só muda a data, mantém status e valor
                const updateData = {
                    data_vencimento: admin.firestore.Timestamp.fromDate(novaDataVenc),
                    observacao_vencimento_alterado: obs,
                    vencimento_alterado_em: agora,
                    vencimento_alterado_por: usuarioNome,
                    vencimento_alterado_codigo_renegociacao: codigoReneg,
                    updated_at: agora,
                };
                batch.update(ref, updateData);
                ops++;
            } else if (isLiquidacao) {
                // LIQUIDAÇÃO (à vista / parcelar): encerra a parcela antiga
                batch.update(ref, {
                    status: "renegociado",
                    valor_em_aberto: 0,
                    valor_pago: admin.firestore.FieldValue.increment(valorEmAberto),
                    renegociado_em: agora,
                    renegociado_observacao: obs,
                    renegociado_por: usuarioNome,
                    renegociado_tipo: tipo,
                    renegociado_valor_original: valorEmAberto,
                    renegociado_valor_final: valorFinal,
                    renegociado_codigo: codigoReneg,
                    updated_at: agora,
                });
                ops++;
            } else if (isAtualizacao) {
                // ATUALIZAÇÃO (desconto / juros / multa / personalizada):
                // Mantém a parcela VIVA, apenas recalcula valor_em_aberto proporcionalmente
                const proporcao = somaOriginal > 0 ? roundMoney(valorEmAberto / somaOriginal) : (1 / parcelasValidas.length);
                const novoValorParcela = roundMoney(proporcao * valorFinal);

                batch.update(ref, {
                    valor_em_aberto: Math.max(0, novoValorParcela),
                    valor_parcela: Math.max(0, novoValorParcela),
                    juros_aplicados: roundMoney(proporcao * jurosFinais),
                    multa_aplicada: roundMoney(proporcao * multaFinal),
                    desconto_aplicado: roundMoney(proporcao * descontoFinal),
                    renegociacao_observacao: obs,
                    renegociacao_codigo: codigoReneg,
                    renegociacao_em: agora,
                    // Se estava vencida, recalcula status
                    status: "em_aberto",
                    updated_at: agora,
                });
                ops++;
            }

            // Registrar recebimento SOMENTE para tipos de liquidação (pagamento via renegociação)
            if (isLiquidacao && tipo !== "vencimento") {
                const recRef = db
                    .collection("users")
                    .doc(lojaId)
                    .collection("recebimentos_cliente")
                    .doc();

                batch.set(recRef, {
                    cliente_id: clienteId,
                    parcela_id: p.id,
                    valor_pago: valorEmAberto,
                    forma_pagamento: "renegociacao",
                    data_pagamento: admin.firestore.Timestamp.fromDate(agoraDate),
                    observacao: `Renegociado (${tipoRotulo}) - ${obs}`,
                    usuario_id: context.auth.uid,
                    usuario_nome: usuarioNome,
                    numero_parcela: numParcela,
                    codigo_venda: codVenda,
                    codigo_renegociacao: codigoReneg,
                    created_at: agora,
                    loja_id: lojaId,
                });
                ops++;
            }
        }

        // 5b. Se for parcelamento, criar novas parcelas
        if (tipo === "parcelar" && qtdParcelasNovas > 0 && Array.isArray(cronograma) && cronograma.length > 0) {
            for (const parc of cronograma) {
                const venc = parseDate(parc.vencimento);
                const novaRef = db
                    .collection("users")
                    .doc(lojaId)
                    .collection("parcelas_cliente")
                    .doc();

                batch.set(novaRef, {
                    loja_id: lojaId,
                    cliente_id: clienteId,
                    venda_credito_id: codigoReneg,
                    venda_id: codigoReneg,
                    codigo_venda: codigoReneg,
                    numero_parcela: parc.numero || 0,
                    valor_parcela: parc.valor || 0,
                    valor_pago: 0,
                    valor_em_aberto: parc.valor || 0,
                    data_compra: agora,
                    data_vencimento: admin.firestore.Timestamp.fromDate(venc),
                    status: "em_aberto",
                    origem: "renegociacao",
                    renegociacao_observacao: obs,
                    renegociacao_codigo: codigoReneg,
                    renegociacao_original_em: agora,
                    created_at: agora,
                    updated_at: agora,
                    juros_aplicados: jurosFinais,
                    multa_aplicada: multaFinal,
                    desconto_aplicado: descontoFinal,
                });
                ops++;
            }
        }

        // 5c. Atualizar dados financeiros do cliente
        if (tipo !== "vencimento") {
            const clienteDoc = db
                .collection("users")
                .doc(lojaId)
                .collection("clientes_comercial")
                .doc(clienteId);

            // Para parcelamento, o novo total é a soma das novas parcelas
            let novoTotalAberto = valorFinal;
            if (tipo === "parcelar" && Array.isArray(cronograma) && cronograma.length > 0) {
                novoTotalAberto = cronograma.reduce((sum, p) => sum + (p.valor || 0), 0);
                novoTotalAberto = roundMoney(novoTotalAberto);
            }

            const updateCliente = {
                ultima_renegociacao: codigoReneg,
                ultima_renegociacao_em: agora,
                ultima_renegociacao_tipo: tipo,
                ultima_renegociacao_valor: valorFinal,
                updated_at: agora,
            };

            if (isLiquidacao) {
                // Liquidação: reduz o crédito utilizado
                updateCliente.credito_utilizado = admin.firestore.FieldValue.increment(-somaOriginal);
            }

            // Para parcelamento: armazena o novo total
            if (tipo === "parcelar" && novoTotalAberto > 0) {
                updateCliente.total_em_aberto_apos_renegociacao = novoTotalAberto;
                updateCliente.qtd_parcelas_apos_renegociacao = qtdParcelasNovas;
            }

            batch.update(clienteDoc, updateCliente);
            ops++;
        }

        // 5d. Salvar log de renegociação (histórico)
        const histRef = db
            .collection("users")
            .doc(lojaId)
            .collection("clientes_comercial")
            .doc(clienteId)
            .collection("renegociacoes_historico")
            .doc();

        batch.set(histRef, {
            codigo: codigoReneg,
            cliente_id: clienteId,
            cliente_nome: clienteNome || "",
            tipo,
            tipo_rotulo: tipoRotulo,
            observacao: obs,
            usuario_nome: usuarioNome,
            usuario_id: context.auth.uid,
            parcelas_originais_ids: parcelasIds,
            parcelas_originais_qtd: parcelasIds.length,
            // Valores RECALCULADOS pelo servidor
            valor_original: somaOriginal,
            juros_originais: somaJuros,
            multa_original: somaMulta,
            // Valores APÓS negociação
            desconto_aplicado: descontoFinal,
            juros_aplicados: jurosFinais,
            multa_aplicada: multaFinal,
            valor_final: valorFinal,
            // Config
            desconto_percentual: descPercentualEfetivo,
            juros_percentual: jurosAction === "reduzir" || jurosAction === "novo" ? jurosPercentual : 0,
            multa_percentual: multaAction === "reduzir" || multaAction === "personalizada" ? multaPercentual : 0,
            juros_action: jurosAction,
            multa_action: multaAction,
            // Parcelamento
            qtd_parcelas_novas: tipo === "parcelar" ? qtdParcelasNovas : 0,
            valor_entrada: entradaValor || 0,
            primeiro_vencimento: primeiroVencimento ? admin.firestore.Timestamp.fromDate(parseDate(primeiroVencimento)) : null,
            intervalo_parcelas: intervaloParcelas,
            // Novos vencimentos (para tipo "vencimento")
            novo_vencimento_aplicado: novoVencimento ? admin.firestore.Timestamp.fromDate(parseDate(novoVencimento)) : null,
            // Metadados
            created_at: agora,
            data_hora: admin.firestore.Timestamp.fromDate(agoraDate),
            // Valores do frontend (para auditoria de divergência)
            frontend_valor_original: _valorOriginalFrontend,
            frontend_valor_final: novoValorFinalFrontend,
            frontend_divergencia: diff > 0.05 ? diff : 0,
        });
        ops++;

        // ⚠️ Limite de 500 ops por batch no Firestore
        if (ops > 480) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Operação muito grande (${ops} operações). Máximo suportado é 480. Reduza a quantidade de parcelas.`
            );
        }

        await batch.commit();

        console.log(
            `[renegociacao] OK ${codigoReneg} loja=${lojaId} cliente=${clienteId} ` +
            `${parcelasIds.length} parcelas tipo=${tipo} ` +
            `original=${somaOriginal} final=${valorFinal} (frontend=${novoValorFinalFrontend})`
        );

        return {
            ok: true,
            codigo: codigoReneg,
            parcelasAfetadas: parcelasIds.length,
            valorOriginal: somaOriginal,
            valorFinal: valorFinal,
            desconto: descontoFinal,
            juros: jurosFinais,
            multa: multaFinal,
        };
    }
);

// =============================================================================
// REVERTER Renegociação (para testes / rollback)
// =============================================================================

exports.reverterRenegociacaoCallable = functions.https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login.");
        }

        const { lojaId, clienteId, codigoReneg } = data || {};
        if (!lojaId || !clienteId) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "lojaId e clienteId são obrigatórios."
            );
        }

        const db = admin.firestore();
        const agora = admin.firestore.FieldValue.serverTimestamp();

        // 1. Buscar parcelas renegociadas deste cliente
        let query = db
            .collection("users")
            .doc(lojaId)
            .collection("parcelas_cliente")
            .where("cliente_id", "==", clienteId)
            .where("status", "==", "renegociado");

        // Se um código específico foi informado, filtra por ele
        if (codigoReneg) {
            query = query.where("renegociado_codigo", "==", codigoReneg);
        }

        const parcelasSnap = await query.get();

        if (parcelasSnap.empty) {
            const msg = codigoReneg
                ? `Nenhuma parcela encontrada com o código ${codigoReneg}.`
                : "Nenhuma parcela renegociada encontrada para este cliente.";
            throw new functions.https.HttpsError("not-found", msg);
        }

        // Coletar códigos de renegociação únicos das parcelas encontradas
        const codigosUnicos = new Set();
        for (const snap of parcelasSnap.docs) {
            const cod = snap.data()?.renegociado_codigo;
            if (cod) codigosUnicos.add(cod);
        }
        const codigosArray = [...codigosUnicos];

        // 2. Buscar os históricos destas renegociações
        let historicoDocs = [];
        let valorOriginalTotal = 0;
        if (codigosArray.length > 0) {
            // Busca por cada código individualmente (sem array-contains para evitar índice)
            for (const cod of codigosArray) {
                const hSnap = await db
                    .collection("users")
                    .doc(lojaId)
                    .collection("clientes_comercial")
                    .doc(clienteId)
                    .collection("renegociacoes_historico")
                    .where("codigo", "==", cod)
                    .get();
                for (const d of hSnap.docs) {
                    historicoDocs.push(d);
                    valorOriginalTotal += (d.data()?.valor_original || 0);
                }
            }
        }

        // 2b. Buscar parcelas NOVAS criadas pelo parcelamento (origem "renegociacao")
        // para removê-las também durante a reversão
        const novasParcelasRefs = [];
        if (codigosArray.length > 0) {
            const novasPromises = codigosArray.map(cod =>
                db
                    .collection("users")
                    .doc(lojaId)
                    .collection("parcelas_cliente")
                    .where("cliente_id", "==", clienteId)
                    .where("renegociacao_codigo", "==", cod)
                    .where("status", "==", "em_aberto")
                    .get()
            );
            const novasSnaps = await Promise.all(novasPromises);
            for (const snap of novasSnaps) {
                for (const d of snap.docs) {
                    novasParcelasRefs.push(d.ref);
                }
            }
        }

        // 3. Montar batch para reverter
        let batch = db.batch();
        let ops = 0;

        // Marca parcelas criadas pelo parcelamento como canceladas
        for (const ref of novasParcelasRefs) {
            batch.update(ref, {
                status: "cancelado_reversao",
                valor_em_aberto: 0,
                reversao_em: agora,
                updated_at: agora,
            });
            ops++;
        }

        // Reverte cada parcela — restaura valor_em_aberto a partir do original gravado
        for (const snap of parcelasSnap.docs) {
            const d = snap.data() || {};
            const valorOriginal = d.renegociado_valor_original || d.valor_parcela || 0;

            const ref = db
                .collection("users")
                .doc(lojaId)
                .collection("parcelas_cliente")
                .doc(snap.id);

            batch.update(ref, {
                status: "em_aberto",
                valor_em_aberto: valorOriginal,
                valor_pago: 0,
                renegociado_em: admin.firestore.FieldValue.delete(),
                renegociado_observacao: admin.firestore.FieldValue.delete(),
                renegociado_por: admin.firestore.FieldValue.delete(),
                renegociado_tipo: admin.firestore.FieldValue.delete(),
                renegociado_valor_original: admin.firestore.FieldValue.delete(),
                renegociado_valor_final: admin.firestore.FieldValue.delete(),
                renegociado_codigo: admin.firestore.FieldValue.delete(),
                revertido_em: agora,
                revertido_por: context.auth.token?.email || "Sistema",
                updated_at: agora,
            });
            ops++;
        }

        // 4. Remover recebimentos_cliente destas renegociações
        let recebimentosRemovidos = 0;
        for (const cod of codigosArray) {
            const recSnap = await db
                .collection("users")
                .doc(lojaId)
                .collection("recebimentos_cliente")
                .where("codigo_renegociacao", "==", cod)
                .get();

            for (const snap of recSnap.docs) {
                batch.delete(snap.ref);
                ops++;
                recebimentosRemovidos++;
            }
        }

        // 5. Restaurar credito_utilizado
        if (valorOriginalTotal > 0) {
            const clienteDoc = db
                .collection("users")
                .doc(lojaId)
                .collection("clientes_comercial")
                .doc(clienteId);

            batch.update(clienteDoc, {
                credito_utilizado: admin.firestore.FieldValue.increment(valorOriginalTotal),
                ultima_reversao_em: agora,
                updated_at: agora,
            });
            ops++;
        }

        // 6. Marcar históricos como revertidos
        for (const snap of historicoDocs) {
            const histRef = db
                .collection("users")
                .doc(lojaId)
                .collection("clientes_comercial")
                .doc(clienteId)
                .collection("renegociacoes_historico")
                .doc(snap.id);

            batch.update(histRef, {
                revertido_em: agora,
                revertido_por: context.auth.token?.email || "Sistema",
                revertido: true,
            });
            ops++;
        }

        if (ops > 480) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `Operação muito grande (${ops}). Máximo 480.`
            );
        }

        await batch.commit();

        console.log(
            `[reverterRenegociacao] OK loja=${lojaId} cliente=${clienteId} ` +
            `${parcelasSnap.size} parcelas revertidas, ${recebimentosRemovidos} recebimentos`
        );

        return {
            ok: true,
            parcelasRevertidas: parcelasSnap.size,
            recebimentosRemovidos: recebimentosRemovidos,
            creditoRestaurado: valorOriginalTotal,
        };
    }
);
