// Arquivo function/index.js

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Inicializa o acesso do Robô ao seu Firebase
if (!admin.apps.length) {
    admin.initializeApp();
}

// ==========================================
// FUNÇÃO 1: AVISAR O LOJISTA DE UM NOVO PEDIDO
// ==========================================
exports.notificarNovoPedido = functions.firestore
    .document('pedidos/{pedidoId}')
    .onCreate(async (snap, context) => {
        const pedido = snap.data();
        const lojaId = pedido.loja_id;
        
        // O valor vem como número, então formatamos. Se não existir, fica 0.00
        const valorTotal = pedido.total ? Number(pedido.total).toFixed(2) : "0.00";

        // Se por algum motivo o pedido não tiver a ID da loja, ele para aqui.
        if (!lojaId) {
            console.log("Erro: Pedido criado sem loja_id");
            return null;
        }

        try {
            // 1. Vai buscar os dados do Lojista na coleção 'users'
            const lojaDoc = await admin.firestore().collection('users').doc(lojaId).get();
            
            if (!lojaDoc.exists) {
                console.log("Erro: Lojista não encontrado no banco de dados.");
                return null;
            }

            const lojaData = lojaDoc.data();
            const token = lojaData.fcm_token;

            // 2. Verifica se o lojista tem o telemóvel registado para receber avisos
            if (!token) {
                console.log("Aviso: O lojista não tem um fcm_token salvo.");
                return null;
            }

            // 3. Monta a Carta (Notificação) com o bilhete escondido (data)
            const mensagem = {
                notification: {
                    title: "🔔 Novo Pedido no DiPertin!",
                    body: `Você tem um novo pedido de R$ ${valorTotal}.`,
                },
                android: {
                    notification: {
                        sound: 'default'
                    }
                },
                data: {
                    tipo: "novo_pedido",
                    pedidoId: context.params.pedidoId
                },
                token: token
            };

            // 4. O Carteiro entrega a mensagem!
            await admin.messaging().send(mensagem);
            console.log(`✅ Notificação enviada com sucesso para a loja: ${lojaId}`);
            return null;

        } catch (error) {
            console.error("❌ Erro ao enviar a notificação:", error);
            return null;
        }
    });

// ==========================================
// MISSÃO 2: ROBÔ QUE AVISA ENTREGADORES
// ==========================================
exports.notificarEntregadoresPedidoPronto = functions.firestore
    .document('pedidos/{pedidoId}') 
    .onUpdate(async (change, context) => {
        
        // Pega os dados de "antes" e "depois" da alteração
        const pedidoAntes = change.before.data();
        const pedidoDepois = change.after.data();

        // 1. VERIFICAÇÃO: O status mudou exatamente para 'pronto'?
        if (pedidoAntes.status === 'a_caminho' || pedidoDepois.status !== 'a_caminho') {
            return null; 
        }

        const pedidoId = context.params.pedidoId;
        console.log(`Pedido ${pedidoId} liberado (a_caminho)! Buscando entregadores...`);

        try {
            // 2. BUSCAR ENTREGADORES: Vamos procurar na coleção 'users'
            // AJUSTE FEITO: Agora procuramos pelo campo 'role' igual a 'entregador'
            const entregadoresSnapshot = await admin.firestore()
                .collection('users')
                .where('role', '==', 'entregador') 
                .get();

            if (entregadoresSnapshot.empty) {
                console.log('Nenhum entregador encontrado.');
                return null;
            }

            // 3. RECOLHER OS TOKENS: Pega o fcm_token de cada entregador encontrado
            const tokens = [];
            entregadoresSnapshot.forEach(doc => {
                const dadosEntregador = doc.data();
                if (dadosEntregador.fcm_token) {
                    tokens.push(dadosEntregador.fcm_token);
                }
            });

            if (tokens.length === 0) {
                console.log('Nenhum entregador possui um token válido (não abriram o app ainda).');
                return null;
            }

            // 4. PREPARAR A MENSAGEM (AGORA COM MÁXIMA URGÊNCIA)
            const mensagem = {
                notification: {
                    title: '📦 Novo Pedido Pronto!',
                    body: `A loja já preparou o pedido. Toque para ver os detalhes e aceitar a corrida!`,
                },
                // ADICIONAMOS ESTE BLOCO AQUI PARA O ANDROID ACORDAR:
                android: {
                    priority: 'high',
                    notification: {
                        sound: 'default',
                        channelId: 'high_importance_channel' // O mesmo nome que usamos no main.dart!
                    }
                },
                data: {
                    pedidoId: pedidoId,
                    tipoNotificacao: 'nova_entrega'
                },
                tokens: tokens 
            };

            // 5. ENVIAR A NOTIFICAÇÃO PUSH MULTICAST
            const resposta = await admin.messaging().sendEachForMulticast(mensagem);
            
            console.log(`Sucesso! Notificações enviadas: ${resposta.successCount}`);
            console.log(`Falhas: ${resposta.failureCount}`);

            return null;

        } catch (erro) {
            console.error('Erro ao tentar notificar os entregadores:', erro);
            return null;
        }
    });

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