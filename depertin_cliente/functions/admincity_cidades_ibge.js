"use strict";

/**
 * AdminCity — importação em massa de cidades do IBGE.
 *
 * Callable: adminCityImportarCidadesIbge
 *   - Apenas master pode chamar.
 *   - Baixa a lista de municípios do IBGE e grava na coleção
 *     `cidades_atendidas` usando batches de 500 writes.
 *   - Cria somente docs inéditos; atualiza `nome_normalizada`/`uf_normalizada`
 *     nos existentes (sem mexer em `ativa` para não sobrescrever curadoria).
 *   - Por padrão, novas cidades são gravadas com `ativa: false` (curadoria
 *     manual decide o que aparece no dropdown de AdminCity). O master pode
 *     passar { ativarTodas: true } para importar tudo já ativo.
 */

const https = require("https");
const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

const IBGE_URL =
  "https://servicodados.ibge.gov.br/api/v1/localidades/municipios";
const BATCH_SIZE = 450; // margem para o limite de 500 do Firestore

function fetchJsonHttps(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error("HTTP " + res.statusCode + " ao buscar IBGE"));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on("error", reject);
    req.setTimeout(60000, () => {
      req.destroy(new Error("Timeout ao buscar IBGE"));
    });
  });
}

function normalizar(s) {
  if (!s) return "";
  return String(s)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ");
}

function extrairUf(mun) {
  const u =
    (mun && mun.microrregiao && mun.microrregiao.mesorregiao && mun.microrregiao.mesorregiao.UF) ||
    (mun && mun["regiao-imediata"] && mun["regiao-imediata"]["regiao-intermediaria"] && mun["regiao-imediata"]["regiao-intermediaria"].UF) ||
    null;
  if (!u) return null;
  return {
    sigla: String(u.sigla || "").toUpperCase(),
    nome: String(u.nome || ""),
  };
}

async function assertCallerMaster(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
  }
  const snap = await admin.firestore().collection("users").doc(context.auth.uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("failed-precondition", "Perfil não encontrado.");
  }
  const d = snap.data() || {};
  const role = String(d.role || d.tipoUsuario || d.tipo || "").trim().toLowerCase();
  if (role !== "master") {
    throw new functions.https.HttpsError("permission-denied", "Apenas contas master.");
  }
}

exports.adminCityImportarCidadesIbge = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    await assertCallerMaster(context);

    const ativarTodas = !!(data && data.ativarTodas);

    // 1) Busca municípios do IBGE
    let municipios;
    try {
      municipios = await fetchJsonHttps(IBGE_URL);
    } catch (e) {
      throw new functions.https.HttpsError(
        "internal",
        "Falha ao baixar lista do IBGE: " + (e.message || e)
      );
    }
    if (!Array.isArray(municipios) || municipios.length === 0) {
      throw new functions.https.HttpsError("internal", "Lista IBGE vazia.");
    }

    // 2) Deduplica por (nome_normalizada, uf_normalizada)
    const mapa = new Map();
    for (const m of municipios) {
      const nome = String((m && m.nome) || "").trim();
      if (!nome) continue;
      const uf = extrairUf(m);
      if (!uf || !uf.sigla) continue;
      const nn = normalizar(nome);
      const un = uf.sigla.toLowerCase();
      const chave = `${nn}__${un}`;
      if (mapa.has(chave)) continue;
      mapa.set(chave, {
        nome,
        uf: uf.sigla,
        nome_normalizada: nn,
        uf_normalizada: un,
        label: `${nome} — ${uf.sigla}`,
      });
    }

    // 3) Lê todos os docs atuais (em batches de 500) para evitar duplicar.
    const col = admin.firestore().collection("cidades_atendidas");
    const existentes = new Map(); // chave -> docId
    const snap = await col.get();
    for (const d of snap.docs) {
      const v = d.data() || {};
      const nn = String(v.nome_normalizada || normalizar(v.nome || ""));
      const un = String(v.uf_normalizada || String(v.uf || "").toLowerCase());
      if (!nn || !un) continue;
      existentes.set(`${nn}__${un}`, d.id);
    }

    // 4) Faz writes em batches.
    const novos = [];
    const atualizados = [];
    for (const [chave, payload] of mapa.entries()) {
      if (existentes.has(chave)) {
        atualizados.push({ id: existentes.get(chave), payload });
      } else {
        novos.push(payload);
      }
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    let batch = admin.firestore().batch();
    let counter = 0;
    const flushIfNeeded = async () => {
      if (counter >= BATCH_SIZE) {
        await batch.commit();
        batch = admin.firestore().batch();
        counter = 0;
      }
    };

    // INSERTS
    for (const c of novos) {
      const ref = col.doc();
      batch.set(ref, {
        ...c,
        ativa: ativarTodas ? true : false,
        origem: "ibge_import",
        criado_em: now,
        atualizado_em: now,
      });
      counter++;
      await flushIfNeeded();
    }
    // UPDATES (apenas normalizações/label, sem tocar em `ativa`)
    for (const u of atualizados) {
      const ref = col.doc(u.id);
      batch.set(
        ref,
        {
          nome: u.payload.nome,
          uf: u.payload.uf,
          nome_normalizada: u.payload.nome_normalizada,
          uf_normalizada: u.payload.uf_normalizada,
          label: u.payload.label,
          atualizado_em: now,
        },
        { merge: true }
      );
      counter++;
      await flushIfNeeded();
    }

    if (counter > 0) {
      await batch.commit();
    }

    return {
      ok: true,
      total_ibge: mapa.size,
      inseridas: novos.length,
      atualizadas: atualizados.length,
      ativar_todas: ativarTodas,
    };
  });
