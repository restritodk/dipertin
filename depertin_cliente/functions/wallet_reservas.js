/**
 * Gerenciamento Transacional de Saldo da Carteira
 * 
 * Sistema de reserva para garantir que saldo só seja debitado após
 * confirmação de pagamento externo (PIX/Cartão).
 * 
 * Funciona em 3 etapas:
 * 1. RESERVAR: bloqueia saldo, não debita ainda
 * 2. CONFIRMAR: após sucesso do pagamento, debita de fato
 * 3. CANCELAR: se pagamento falhar, libera saldo reservado
 * 
 * Collection: users/{uid}/wallet_reservas
 * - reservado: valor bloqueado
 * - pedidoId: referência ao pedido
 * - status: PENDENTE | CONFIRMADO | CANCELADO
 * - criado_em: timestamp de criação
 * - confirmado_em: timestamp de confirmação (se confirmado)
 */

const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const COLLECTION_WALLETS = "users";
const COLLECTION_RESERVAS = "wallet_reservas";

/**
 * ETAPA 1: RESERVAR saldo (não debita, apenas bloqueia)
 * 
 * Chamada ANTES de processar PIX/Cartão
 * Retorna: { success: true, reservaId: "..." }
 */
exports.walletReservarSaldo = onCall(async (request) => {
  const data = request.data || {};
  const uid = String(data.uid || "").trim();
  const pedidoId = String(data.pedidoId || "").trim();
  const valorReserva = parseFloat(data.valorReserva) || 0;

  if (!uid || !pedidoId || valorReserva <= 0) {
    throw new HttpsError("invalid-argument", "Dados inválidos para reserva.");
  }

  if (uid !== request.auth.uid && request.auth.uid !== "admin") {
    throw new HttpsError("permission-denied", "Sem permissão.");
  }

  const db = admin.firestore();
  const userRef = db.collection(COLLECTION_WALLETS).doc(uid);

  return db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Usuário não encontrado.");
    }

    const saldoAtual = (userSnap.data().saldo || 0.0);
    const saldoReservadoTotal = (userSnap.data().saldo_reservado || 0.0);
    const saldoDisponivel = saldoAtual - saldoReservadoTotal;

    // Valida se há saldo disponível
    if (saldoDisponivel < valorReserva) {
      throw new HttpsError(
        "invalid-argument",
        `Saldo insuficiente. Disponível: R$ ${saldoDisponivel.toFixed(2)}`
      );
    }

    // Cria documento de reserva
    const reservaId = `${pedidoId}_${Date.now()}`;
    const reservaRef = userRef.collection(COLLECTION_RESERVAS).doc(reservaId);

    transaction.set(reservaRef, {
      pedido_id: pedidoId,
      valor_reservado: valorReserva,
      status: "PENDENTE",
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
      confirmado_em: null,
    });

    // Incrementa flag de saldo_reservado do usuário
    transaction.update(userRef, {
      saldo_reservado: admin.firestore.FieldValue.increment(valorReserva),
      // Não debita ainda! Apenas marca como reservado
    });

    // Log de transação
    const logsRef = db.collection("wallet_transaction_logs").doc();
    transaction.set(logsRef, {
      usuario_id: uid,
      pedido_id: pedidoId,
      tipo: "RESERVA",
      valor: valorReserva,
      status: "PENDENTE",
      reserva_id: reservaId,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      reservaId,
      saldoDisponivel: saldoDisponivel - valorReserva, // Atualizado
      mensagem: `Saldo reservado. Disponível: R$ ${(saldoDisponivel - valorReserva).toFixed(2)}`,
    };
  });
});

/**
 * ETAPA 2: CONFIRMAR débito após sucesso do pagamento
 * 
 * Chamada APÓS PIX/Cartão ser confirmado
 * Retorna: { success: true, saldoFinal: ... }
 */
exports.walletConfirmarDebito = onCall(async (request) => {
  const data = request.data || {};
  const uid = String(data.uid || "").trim();
  const reservaId = String(data.reservaId || "").trim();

  if (!uid || !reservaId) {
    throw new HttpsError("invalid-argument", "Dados inválidos para confirmação.");
  }

  if (uid !== request.auth.uid && request.auth.uid !== "admin") {
    throw new HttpsError("permission-denied", "Sem permissão.");
  }

  const db = admin.firestore();
  const userRef = db.collection(COLLECTION_WALLETS).doc(uid);
  const reservaRef = userRef.collection(COLLECTION_RESERVAS).doc(reservaId);

  return db.runTransaction(async (transaction) => {
    const reservaSnap = await transaction.get(reservaRef);
    if (!reservaSnap.exists) {
      throw new HttpsError("not-found", "Reserva não encontrada.");
    }

    const reserva = reservaSnap.data();
    if (reserva.status !== "PENDENTE") {
      throw new HttpsError(
        "invalid-argument",
        `Reserva já foi ${reserva.status.toLowerCase()}`
      );
    }

    const valor = reserva.valor_reservado || 0;
    const userSnap = await transaction.get(userRef);
    const saldoAtual = (userSnap.data().saldo || 0.0);

    // ⚠️ AQUI FINALMENTE DEBITAMOS O SALDO
    transaction.update(userRef, {
      saldo: admin.firestore.FieldValue.increment(-valor),
      saldo_reservado: admin.firestore.FieldValue.increment(-valor),
    });

    // Marca reserva como confirmada
    transaction.update(reservaRef, {
      status: "CONFIRMADO",
      confirmado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log de transação
    const logsRef = db.collection("wallet_transaction_logs").doc();
    transaction.set(logsRef, {
      usuario_id: uid,
      pedido_id: reserva.pedido_id,
      tipo: "CONFIRMADO",
      valor,
      status: "SUCESSO",
      reserva_id: reservaId,
      saldo_final: saldoAtual - valor,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      valor,
      saldoFinal: saldoAtual - valor,
      mensagem: `Saldo debitado com sucesso. Saldo final: R$ ${(saldoAtual - valor).toFixed(2)}`,
    };
  });
});

/**
 * ETAPA 3: CANCELAR reserva se pagamento falhar
 * 
 * Chamada quando PIX/Cartão é recusado ou falha
 * Retorna: { success: true, saldoRestaurado: ... }
 */
exports.walletCancelarReserva = onCall(async (request) => {
  const data = request.data || {};
  const uid = String(data.uid || "").trim();
  const reservaId = String(data.reservaId || "").trim();
  const motivo = String(data.motivo || "Pagamento recusado").trim();

  if (!uid || !reservaId) {
    throw new HttpsError("invalid-argument", "Dados inválidos para cancelamento.");
  }

  if (uid !== request.auth.uid && request.auth.uid !== "admin") {
    throw new HttpsError("permission-denied", "Sem permissão.");
  }

  const db = admin.firestore();
  const userRef = db.collection(COLLECTION_WALLETS).doc(uid);
  const reservaRef = userRef.collection(COLLECTION_RESERVAS).doc(reservaId);

  return db.runTransaction(async (transaction) => {
    const reservaSnap = await transaction.get(reservaRef);
    if (!reservaSnap.exists) {
      throw new HttpsError("not-found", "Reserva não encontrada.");
    }

    const reserva = reservaSnap.data();
    if (reserva.status !== "PENDENTE") {
      throw new HttpsError(
        "invalid-argument",
        `Não pode cancelar reserva com status ${reserva.status}`
      );
    }

    const valor = reserva.valor_reservado || 0;

    // ✅ LIBERA O SALDO (não debita, apenas remove a reserva)
    transaction.update(userRef, {
      saldo_reservado: admin.firestore.FieldValue.increment(-valor),
      // saldo continua intacto!
    });

    // Marca reserva como cancelada
    transaction.update(reservaRef, {
      status: "CANCELADO",
      motivo,
      cancelado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log de transação
    const logsRef = db.collection("wallet_transaction_logs").doc();
    transaction.set(logsRef, {
      usuario_id: uid,
      pedido_id: reserva.pedido_id,
      tipo: "CANCELADO",
      valor,
      status: "FALHA",
      motivo,
      reserva_id: reservaId,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      valor,
      saldoRestaurado: valor,
      mensagem: `Saldo restaurado. Valor liberado: R$ ${valor.toFixed(2)}`,
    };
  });
});

/**
 * Cleanup: Cancela automaticamente reservas pendentes há mais de 1 hora
 * (em caso de crash, timeout, etc)
 * 
 * Scheduled: executa a cada 15 minutos
 */
exports.walletLimparReservasExpiradas = onSchedule(
  "every 15 minutes",
  async (context) => {
    const db = admin.firestore();
    const agora = Date.now();
    const umHoraMsAtrás = agora - 60 * 60 * 1000;

    const lotsRef = db.collectionGroup(COLLECTION_RESERVAS);
    const batch = db.batch();
    let processadas = 0;

    const snapshot = await lotsRef
      .where("status", "==", "PENDENTE")
      .where("criado_em", "<", new Date(umHoraMsAtrás))
      .get();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const uid = doc.ref.parent.parent.id;
      const valor = data.valor_reservado || 0;

      // Cancela a reserva
      batch.update(doc.ref, {
        status: "CANCELADO",
        motivo: "Expirada automaticamente (1h sem confirmação)",
        cancelado_em: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Restaura o saldo
      batch.update(
        db.collection(COLLECTION_WALLETS).doc(uid),
        {
          saldo_reservado: admin.firestore.FieldValue.increment(-valor),
        }
      );

      // Log
      batch.set(db.collection("wallet_transaction_logs").doc(), {
        usuario_id: uid,
        pedido_id: data.pedido_id,
        tipo: "CANCELADO_AUTO",
        valor,
        status: "EXPIRADA",
        motivo: "Sem confirmação em 1h",
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
      });

      processadas++;
    }

    if (processadas > 0) {
      await batch.commit();
      console.log(
        `[wallet_reservas] Limpou ${processadas} reservas expiradas.`
      );
    }

    return { processadas };
  }
);
