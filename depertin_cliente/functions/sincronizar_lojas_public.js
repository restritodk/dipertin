// Fase 3G.1 — mirror de leitura pública `lojas_public/{uid}`.
//
// Objetivo: separar os dados "de fachada" do lojista (nome, foto, endereço,
// horários, rating) dos dados pessoais/sensíveis que hoje ficam no mesmo doc
// em `users/{uid}` (CPF, saldo, email, documentos, fcm_token, block_*).
//
// Funcionamento:
//   onWrite users/{uid} → se o doc é de um lojista, espelhamos em
//   lojas_public/{uid} SOMENTE os campos públicos (allowlist). Se o doc deixa
//   de ser lojista (role muda, conta excluída, ou doc deletado), removemos o
//   espelho.
//
// Segurança:
//   - `lojas_public` tem `read: if true` (vitrine sem login) e `write: if false`
//     (ninguém escreve direto do cliente — só o Admin SDK deste trigger e do
//     script de backfill bypassam a rule).
//   - O espelho SÓ contém dados que já eram exibidos publicamente na UI do
//     app cliente (vitrine/busca/perfil da loja/produto).
//
// Próximos passos (sub-fases 3G.2 e 3G.3):
//   - 3G.2: migrar queries `users.where('role','lojista')` no app mobile para
//           `lojas_public`.
//   - 3G.3: apertar a rule de `users` (remover o `|| role == lojista` que
//           hoje permite leitura anônima).

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

/**
 * Campos "de fachada" do lojista que são exibidos pela UI pública (vitrine,
 * busca, perfil da loja, detalhe do produto, carrinho). Valores `undefined`
 * são ignorados no merge; valores `null` apagam o campo.
 *
 * IMPORTANTE: NÃO incluir aqui CPF, CNPJ, email, telefone pessoal, saldo,
 * fcm_token, documentos, block_*, lojista_owner_uid, colaboradores, termos,
 * data_nascimento ou qualquer outro dado pessoal do dono da loja.
 */
const CAMPOS_PUBLICOS_LOJA = [
    // Identidade/fachada
    "loja_nome",
    "nome_loja",
    "nome_fantasia",
    "nome",
    "descricao",
    "categoria",
    // Imagens
    "foto",
    "foto_capa",
    "foto_perfil",
    "foto_logo",
    "imagem",
    // Localização (cidade/UF usados em filtros; endereço textual mostrado no perfil)
    "cidade",
    "cidade_normalizada",
    "endereco_cidade",
    "uf",
    "estado",
    "endereco",
    "latitude",
    "longitude",
    // Contato comercial (telefone exposto pelo lojista pro cliente falar com ele)
    "telefone",
    // Operação (vitrine filtra status aprovada; LojaPausa.lojaEstaAberta usa horários + pausa)
    "status_loja",
    "loja_aberta",
    "pausado_manualmente",
    "pausa_motivo",
    "pausa_volta_at",
    "horarios",
    // Social proof
    "rating_media",
    "total_avaliacoes",
    // Logística (tipos de entrega aceitos pela loja — usado pelo carrinho
    // para escolher a tabela de frete e pelo backend para filtrar
    // entregadores compatíveis). Lista de strings canônicas — ver
    // functions/tipos_entrega.js.
    "tipos_entrega_permitidos",
    "tipos_entrega_atualizado_em",
];

function ehLojista(data) {
    if (!data) return false;
    const role = String(data.role || data.tipoUsuario || data.tipo || "").toLowerCase();
    return role === "lojista";
}

function extrairCamposPublicos(data) {
    const patch = {};
    for (const campo of CAMPOS_PUBLICOS_LOJA) {
        if (Object.prototype.hasOwnProperty.call(data, campo)) {
            patch[campo] = data[campo];
        }
    }
    // Marcador: sempre útil pra debug/filtro.
    patch.role = "lojista";
    patch.sincronizado_em = admin.firestore.FieldValue.serverTimestamp();
    return patch;
}

/**
 * Trigger: sincroniza `lojas_public/{uid}` sempre que `users/{uid}` muda.
 *
 * - `onWrite` cobre create, update e delete.
 * - Doc novo sem ser lojista → no-op.
 * - Doc virou lojista (role mudou) → cria espelho.
 * - Doc deixou de ser lojista (role mudou) ou foi deletado → apaga espelho.
 * - Lojista existente teve campos públicos alterados → atualiza espelho.
 * - Lojista teve apenas campos privados alterados (ex.: saldo, fcm_token) →
 *   ainda rodamos o set com merge, mas como o patch só contém campos
 *   permitidos, não vaza nada.
 */
exports.sincronizarLojaPublicOnWrite = functions.firestore
    .document("users/{uid}")
    .onWrite(async (change, context) => {
        const uid = context.params.uid;
        const db = admin.firestore();
        const ref = db.collection("lojas_public").doc(uid);

        const antes = change.before.exists ? change.before.data() : null;
        const depois = change.after.exists ? change.after.data() : null;

        const eraLojista = ehLojista(antes);
        const ehLojistaAgora = ehLojista(depois);

        if (!ehLojistaAgora) {
            if (eraLojista) {
                try {
                    await ref.delete();
                    console.log(`[lojas_public] Removido espelho de ${uid} (deixou de ser lojista).`);
                } catch (e) {
                    console.error(`[lojas_public] Falha ao remover espelho ${uid}:`, e);
                }
            }
            return null;
        }

        const patch = extrairCamposPublicos(depois);
        try {
            await ref.set(patch, { merge: true });
            if (!eraLojista) {
                console.log(`[lojas_public] Criado espelho de ${uid} (novo lojista).`);
            }
            return null;
        } catch (e) {
            console.error(`[lojas_public] Falha ao sincronizar ${uid}:`, e);
            return null;
        }
    });

// Expostos pra reuso no script de backfill (functions/scripts/backfill_lojas_public.js)
exports.CAMPOS_PUBLICOS_LOJA = CAMPOS_PUBLICOS_LOJA;
exports.ehLojista = ehLojista;
exports.extrairCamposPublicos = extrairCamposPublicos;
