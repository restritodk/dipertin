/**
 * Excluir conta de cliente (hard delete) — uso exclusivo do MASTER no painel.
 *
 * Diferente de `solicitarExclusaoConta`, que aplica retenção de 30 dias por LGPD,
 * esta função apaga IMEDIATAMENTE:
 *   - documento `users/{uid}`
 *   - subcoleções: `enderecos`, `tokens_fcm`, etc. (quando existirem)
 *   - usuário do Firebase Auth
 *
 * Bloqueios de segurança:
 *   - Apenas role === "master" pode chamar.
 *   - Bloqueia exclusão de outros master / master_city / lojista / entregador (somente clientes).
 *   - Bloqueia se houver pedidos em andamento (status que não esteja concluído/cancelado).
 *   - Bloqueia se houver saldo positivo (`saldo > 0`) — proteger valor a sacar.
 *   - Não permite o master excluir a si mesmo.
 *
 * Mantém os pedidos antigos do cliente (registros financeiros/fiscais), apenas
 * marca `cliente_excluido_em` e `cliente_excluido_por` em cada pedido para auditoria.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const STATUS_CONCLUIDOS = new Set([
    "entregue",
    "cancelado",
    "recusado",
    "estornado",
    "pix_expirado",
]);

async function apagarSubcolecaoEmLote(db, refDoc, nomeSub, lote = 200) {
    const colRef = refDoc.collection(nomeSub);
    while (true) {
        const snap = await colRef.limit(lote).get();
        if (snap.empty) return;
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (snap.docs.length < lote) return;
    }
}

exports.excluirClienteAdminMaster = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária."
        );
    }

    const adminUid = context.auth.uid;
    const targetUid = (data && data.uid ? String(data.uid) : "").trim();
    if (!targetUid) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Parâmetro `uid` é obrigatório."
        );
    }

    if (adminUid === targetUid) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Você não pode excluir a sua própria conta."
        );
    }

    const db = admin.firestore();

    // 1) Verifica que quem chamou é master.
    const meSnap = await db.collection("users").doc(adminUid).get();
    if (!meSnap.exists) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Conta administrativa não encontrada."
        );
    }
    const me = meSnap.data() || {};
    const meuPerfil = String(me.role || me.tipo || me.tipoUsuario || "")
        .trim()
        .toLowerCase();
    if (meuPerfil !== "master") {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Apenas usuários master podem excluir clientes."
        );
    }

    // 2) Carrega o alvo e valida que é cliente.
    const tgtRef = db.collection("users").doc(targetUid);
    const tgtSnap = await tgtRef.get();
    if (!tgtSnap.exists) {
        // Tenta apagar o Auth órfão por garantia (idempotente).
        try {
            await admin.auth().deleteUser(targetUid);
        } catch (_) { /* ignore */ }
        return { ok: true, alreadyDeleted: true };
    }
    const tgt = tgtSnap.data() || {};
    const perfilAlvo = String(tgt.role || tgt.tipo || tgt.tipoUsuario || "cliente")
        .trim()
        .toLowerCase();

    if (perfilAlvo !== "cliente") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Esta função só exclui contas de cliente. Conta alvo é "${perfilAlvo}".`
        );
    }

    // 3) Bloqueio: pedidos em andamento.
    const pedidosAtivos = await db
        .collection("pedidos")
        .where("cliente_id", "==", targetUid)
        .get();
    let pendentes = 0;
    pedidosAtivos.forEach((d) => {
        const st = String((d.data() || {}).status || "").toLowerCase();
        if (st && !STATUS_CONCLUIDOS.has(st)) pendentes += 1;
    });
    if (pendentes > 0) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Cliente possui ${pendentes} pedido(s) em andamento. Conclua/cancele antes de excluir.`
        );
    }

    // 4) Bloqueio: saldo positivo.
    const saldoNum = Number(tgt.saldo || 0);
    if (Number.isFinite(saldoNum) && saldoNum > 0.0099) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Cliente possui saldo de R$ ${saldoNum.toFixed(2)}. Devolva o saldo antes de excluir.`
        );
    }

    // 5) Marca pedidos antigos para auditoria (mantém os pedidos no Firestore).
    if (pedidosAtivos.size > 0) {
        const lotes = [];
        let batch = db.batch();
        let conta = 0;
        pedidosAtivos.forEach((doc) => {
            batch.set(
                doc.ref,
                {
                    cliente_excluido_em: admin.firestore.FieldValue.serverTimestamp(),
                    cliente_excluido_por: adminUid,
                },
                { merge: true }
            );
            conta += 1;
            if (conta >= 400) {
                lotes.push(batch.commit());
                batch = db.batch();
                conta = 0;
            }
        });
        if (conta > 0) lotes.push(batch.commit());
        await Promise.all(lotes);
    }

    // 6) Apaga subcoleções conhecidas de `users/{uid}`.
    for (const sub of ["enderecos", "tokens_fcm", "notificacoes_lidas"]) {
        try {
            await apagarSubcolecaoEmLote(db, tgtRef, sub);
        } catch (e) {
            console.warn(`[excluirClienteAdminMaster] erro apagando sub ${sub}:`, e.message);
        }
    }

    // 7) Apaga doc principal do cliente.
    await tgtRef.delete();

    // 8) Apaga usuário do Firebase Auth (não falha se já não existir).
    try {
        await admin.auth().deleteUser(targetUid);
    } catch (e) {
        const code = e.code || "";
        if (code !== "auth/user-not-found") {
            console.warn("[excluirClienteAdminMaster] deleteUser:", code, e.message);
        }
    }

    // 9) Auditoria global.
    await db.collection("audit_exclusoes_clientes").add({
        target_uid: targetUid,
        target_email: tgt.email || null,
        target_nome: tgt.nome || tgt.nome_completo || null,
        executor_uid: adminUid,
        executor_email: me.email || null,
        em: admin.firestore.FieldValue.serverTimestamp(),
        pedidos_marcados: pedidosAtivos.size,
    });

    console.log(
        `[excluirClienteAdminMaster] OK uid=${targetUid} por=${adminUid} pedidos=${pedidosAtivos.size}`
    );

    return {
        ok: true,
        pedidosMarcados: pedidosAtivos.size,
    };
});
