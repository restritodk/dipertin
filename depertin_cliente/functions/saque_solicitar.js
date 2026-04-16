"use strict";

/**
 * Saque (PIX) — única entrada autorizada: callable.
 * Cria `saques_solicitacoes` e debita `users.saldo` em transação atômica.
 * Integração Mercado Pago payout: TODO (motor manual até lá).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REGION = "us-central1";

/** Valor mínimo em BRL (ajuste por regra de negócio). */
const MIN_SAQUE_BRL = 1;

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

function lojistaDocumentoBloqueadoJs(d) {
    if (!d) return false;
    if (!docIndicaLojista(d)) return false;
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

/** Alinhado às regras Firestore: prioridade role → tipo → tipoUsuario (evita mismatch com só `tipo`). */
function roleOf(d) {
    const parts = [d.role, d.tipo, d.tipoUsuario];
    for (const p of parts) {
        if (p == null) continue;
        const s = String(p).trim();
        if (s !== "") return s.toLowerCase();
    }
    return "";
}

/**
 * O app usa `perfilAdministrativoPainel` (melhor privilégio entre campos).
 * Muitos lojistas têm `role: "cliente"` legado e `tipoUsuario: "lojista"` — o primeiro
 * campo de [roleOf] ganhava e o saque falhava com "Tipo não confere" sem criar doc.
 */
function docIndicaLojista(u) {
    if (!u) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(u[k] || "").toLowerCase().trim() === "lojista") return true;
    }
    return false;
}

function docIndicaEntregador(u) {
    if (!u) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(u[k] || "").toLowerCase().trim() === "entregador") return true;
    }
    return false;
}

function usuarioCompativelComTipoSaque(u, tipoSolicitado) {
    const t = String(tipoSolicitado).toLowerCase().trim();
    if (t === "lojista") return docIndicaLojista(u);
    if (t === "entregador") return docIndicaEntregador(u);
    return false;
}

function motivoPareceFinanceiro(motivo) {
    const s = String(motivo).toLowerCase();
    return /pagamento|inadimpl|financeir|suspens|falta de pagamento|cobran|mensalidade|plano|pend(ência|encia) financeira|regulariz|débito|debito/.test(
        s,
    );
}

function entregadorRecusadoSomenteCorrecaoCadastro(d) {
    if (d.recusa_cadastro === true) return true;
    const sl = String(d.entregador_status || "");
    if (sl !== "bloqueado" && sl !== "bloqueada") return false;
    if (Object.prototype.hasOwnProperty.call(d, "block_active")) return false;
    const motivo = String(d.motivo_recusa || "").trim();
    if (!motivo) return false;
    if (motivoPareceFinanceiro(motivo)) return false;
    return true;
}

function toDateMaybe(ts) {
    if (!ts) return null;
    if (typeof ts.toDate === "function") return ts.toDate();
    if (ts._seconds != null) return new Date(ts._seconds * 1000);
    return null;
}

/** Alinhado a ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes */
function entregadorBloqueadoOperacionalJs(d) {
    if (!docIndicaEntregador(d)) return false;
    if (entregadorRecusadoSomenteCorrecaoCadastro(d)) return false;
    const sl = String(d.entregador_status || "");

    if (sl === "bloqueado") return true;

    if (sl === "bloqueio_temporario") {
        const end = toDateMaybe(d.block_end_at);
        if (end && Date.now() > end.getTime()) return false;
        return true;
    }

    if (sl === "bloqueado" || sl === "bloqueada") {
        if (!Object.prototype.hasOwnProperty.call(d, "block_active")) return true;
    }

    if (d.block_active !== true) return false;

    if (String(d.block_type) === "BLOCK_TEMPORARY") {
        const end = toDateMaybe(d.block_end_at);
        if (end && Date.now() > end.getTime()) return false;
    }
    return true;
}

function roundMoney(v) {
    const n = Number(v);
    if (Number.isNaN(n)) return NaN;
    return Math.round(n * 100) / 100;
}

function maskPix(chave) {
    const s = String(chave || "").trim();
    if (s.length <= 4) return "****";
    return `${"*".repeat(Math.min(8, s.length - 4))}${s.slice(-4)}`;
}

exports.solicitarSaque = onCall(
    {
        region: REGION,
        enforceAppCheck: false,
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }

        const uid = request.auth.uid;
        const data = request.data || {};

        const tipoUsuario = String(data.tipo_usuario || "").toLowerCase().trim();
        if (tipoUsuario !== "lojista" && tipoUsuario !== "entregador") {
            throw new HttpsError(
                "invalid-argument",
                "tipo_usuario deve ser lojista ou entregador.",
            );
        }

        const valor = roundMoney(data.valor);
        if (Number.isNaN(valor) || valor < MIN_SAQUE_BRL) {
            throw new HttpsError(
                "invalid-argument",
                `Valor mínimo para saque: R$ ${MIN_SAQUE_BRL.toFixed(2).replace(".", ",")}.`,
            );
        }

        const chavePix = String(data.chave_pix || "").trim();
        const titular = String(data.titular_conta || "").trim();
        const banco = String(data.banco || "").trim();

        if (!chavePix || !titular) {
            throw new HttpsError(
                "invalid-argument",
                "chave_pix e titular_conta são obrigatórios.",
            );
        }

        const db = admin.firestore();
        const userRef = db.collection("users").doc(uid);

        const saqueId = await db.runTransaction(async (t) => {
            const snap = await t.get(userRef);
            if (!snap.exists) {
                throw new HttpsError("failed-precondition", "Usuário não encontrado.");
            }
            const u = snap.data();

            if (!usuarioCompativelComTipoSaque(u, tipoUsuario)) {
                throw new HttpsError(
                    "permission-denied",
                    "Tipo de usuário não confere com o cadastro (verifica role, tipo e tipoUsuario em users).",
                );
            }

            if (tipoUsuario === "lojista" && lojistaDocumentoBloqueadoJs(u)) {
                throw new HttpsError(
                    "permission-denied",
                    "Conta bloqueada. Regularize para solicitar saque.",
                    { code: "ACCOUNT_BLOCKED" },
                );
            }
            if (tipoUsuario === "entregador" && entregadorBloqueadoOperacionalJs(u)) {
                throw new HttpsError(
                    "permission-denied",
                    "Conta bloqueada. Regularize para solicitar saque.",
                    { code: "ACCOUNT_BLOCKED" },
                );
            }

            const saldo = roundMoney(u.saldo ?? 0);
            if (valor > saldo) {
                throw new HttpsError(
                    "failed-precondition",
                    "Saldo insuficiente para este valor.",
                    { saldo_disponivel: saldo },
                );
            }

            // KYC automático (stub): expandir com campos reais e MP quando houver payout.
            const kycOk = u.kyc_saque_liberado === true || u.documento_validado === true;
            if (process.env.EXIGIR_KYC_SAQUE === "true" && !kycOk) {
                throw new HttpsError(
                    "failed-precondition",
                    "Complete a validação de identidade para solicitar saque.",
                    { code: "KYC_REQUIRED" },
                );
            }

            const saqueRef = db.collection("saques_solicitacoes").doc();
            const novoSaldo = roundMoney(saldo - valor);

            const payload = {
                user_id: uid,
                tipo_usuario: tipoUsuario,
                chave_pix: chavePix,
                titular_conta: titular,
                banco: banco,
                valor: valor,
                status: "pendente",
                data_solicitacao: admin.firestore.FieldValue.serverTimestamp(),
                motor: "cloud_function",
                versao_motor: 1,
                chave_pix_mascarada: maskPix(chavePix),
                validacoes: {
                    saldo_antes: saldo,
                    saldo_depois_previsto: novoSaldo,
                    role_ok: true,
                    bloqueio_ok: true,
                },
            };

            const clientRequestId =
                data.client_request_id != null
                    ? String(data.client_request_id).trim()
                    : "";
            if (clientRequestId) {
                payload.client_request_id = clientRequestId;
            }

            t.set(saqueRef, payload);
            t.update(userRef, { saldo: novoSaldo });

            return saqueRef.id;
        });

        console.log(
            JSON.stringify({
                event: "saque_solicitado",
                user_id: uid,
                tipo: tipoUsuario,
                valor,
                destino_mascarado: maskPix(chavePix),
                saque_id: saqueId,
            }),
        );

        return {
            ok: true,
            saqueId,
            message: "Saque registrado. Processamento conforme fila operacional / futuro payout automático.",
        };
    },
);
