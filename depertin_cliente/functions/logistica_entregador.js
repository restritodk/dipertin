"use strict";

/**
 * Despacho tipo Uber: fila por proximidade à loja, oferta 10s por entregador,
 * FCM de alta prioridade + som dedicado (canal Android corrida_chamada).
 * Redespacho pela loja: despacho_abort_flag + callable lojistaRedespacharEntregador.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { dataSoStrings } = require("./notification_dispatcher");
const TIPOS_ENTREGA = require("./tipos_entrega");

const OFERTA_SEGUNDOS = 15;
const RAIO_KM_ETAPA_1 = 3;
const RAIO_KM_ETAPA_2 = 5;
/** Se 3 km e 5 km não acharem ninguém, última tentativa no mesmo ciclo (cidade pequena / GPS). */
const RAIO_KM_ETAPA_AMPLA = 35;
const POLL_MS = 1000;
/** Quantas vezes repetir o par 3 km → 5 km (reiniciando a fila por proximidade) antes de pedir decisão ao lojista. */
const CICLOS_MACRO_PRIMARIO = 5;
/** Se o lojista optar por continuar, mais este número de ciclos antes de encerrar sozinho. */
const CICLOS_MACRO_EXTENDIDO = 5;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/** ID da loja no pedido: `loja_id` ou legado `lojista_id` (string ou referência). */
function lojaIdStr(p) {
    if (!p) return "";
    const raw = p.loja_id != null ? p.loja_id : p.lojista_id;
    if (raw == null) return "";
    if (typeof raw === "string") return raw;
    if (typeof raw === "object" && typeof raw.id === "string") return raw.id;
    return String(raw);
}

/**
 * Dono da loja (auth.uid == loja_id) ou colaborador com users.lojista_owner_uid == loja_id.
 */
async function assertAuthEhLojaDoPedido(db, pedido, authUid) {
    const lid = lojaIdStr(pedido);
    if (!lid) {
        throw new functions.https.HttpsError("failed-precondition", "Pedido sem loja.");
    }
    if (String(lid) === String(authUid)) {
        return;
    }
    const udoc = await db.collection("users").doc(String(authUid)).get();
    const u = udoc.exists ? udoc.data() : {};
    const owner = u.lojista_owner_uid;
    if (owner != null && String(owner) === String(lid)) {
        return;
    }
    throw new functions.https.HttpsError("permission-denied", "Apenas a loja do pedido pode usar esta ação.");
}

function haversineKm(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const toRad = (d) => (d * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function obterCoordenadasLoja(db, pedido) {
    const lojaId = lojaIdStr(pedido);
    if (!lojaId) {
        return { lat: null, lon: null };
    }
    const lojaDoc = await db.collection("users").doc(lojaId).get();
    const ld = lojaDoc.exists ? lojaDoc.data() : {};
    let lat = ld.latitude != null ? Number(ld.latitude) : null;
    let lon = ld.longitude != null ? Number(ld.longitude) : null;
    if ((lat == null || lon == null) && pedido.loja_latitude != null && pedido.loja_longitude != null) {
        lat = Number(pedido.loja_latitude);
        lon = Number(pedido.loja_longitude);
    }
    if (Number.isNaN(lat) || Number.isNaN(lon)) {
        return { lat: null, lon: null };
    }
    return { lat, lon };
}

function entregadorMarcadoOnline(d) {
    if (!d) return false;
    const v = d.is_online;
    return v === true || v === "true" || v === 1;
}

/** Token FCM persistido no doc do entregador (snake ou camel). */
function fcmTokenDoUsuario(d) {
    if (!d) return "";
    const a = d.fcm_token != null ? String(d.fcm_token).trim() : "";
    if (a) return a;
    const b = d.fcmToken != null ? String(d.fcmToken).trim() : "";
    return b || "";
}

function perfilEntregadorAtivo(d) {
    if (!d) return false;
    const r = d.role;
    const tipo = d.tipoUsuario || d.tipo;
    const ok =
        r === "entregador" ||
        tipo === "entregador" ||
        (typeof r === "string" && r.toLowerCase() === "entregador") ||
        (typeof tipo === "string" && tipo.toLowerCase() === "entregador");
    const est = String(d.entregador_status || "").toLowerCase();
    const aprovado = est === "aprovado" || est === "ativo";
    return ok && aprovado && fcmTokenDoUsuario(d) !== "" && entregadorMarcadoOnline(d);
}

const STATUS_DISPATCH_ANALISE = [
    "aguardando_entregador",
    "entregador_indo_loja",
    "saiu_entrega",
    "em_rota",
    "a_caminho",
];
const STATUS_INDO_LOJA = new Set(["entregador_indo_loja"]);
const STATUS_INDO_CLIENTE = new Set(["saiu_entrega", "em_rota", "a_caminho"]);

function resumoOperacionalVazio() {
    return {
        totalAtribuidas: 0,
        indoParaLoja: 0,
        indoParaCliente: 0,
        ofertasReservadas: 0,
    };
}

function classificarEstadoOperacional(resumo) {
    if (!resumo) return "DISPONIVEL";
    if (resumo.indoParaLoja > 0) return "INDO_PARA_LOJA";
    if (resumo.indoParaCliente > 0 &&
        (resumo.ofertasReservadas > 0 || resumo.totalAtribuidas > 1)) {
        return "PROXIMA_CORRIDA_RESERVADA";
    }
    if (resumo.indoParaCliente > 0) return "INDO_PARA_CLIENTE";
    if (resumo.totalAtribuidas === 0 && resumo.ofertasReservadas === 0) return "DISPONIVEL";
    return "INDISPONIVEL";
}

function podeReceberNovaCorridaPeloResumo(resumo) {
    const r = resumo || resumoOperacionalVazio();
    // Regra principal:
    // 1) Indo para loja => NÃO recebe novas corridas.
    if (r.indoParaLoja > 0) return false;
    // 2) Nunca mais de 2 corridas simultâneas (1 indo cliente + 1 indo loja).
    if (r.totalAtribuidas >= 2) return false;

    const temAtribuidaAntesColeta = r.totalAtribuidas - r.indoParaCliente > 0;
    if (temAtribuidaAntesColeta) return false;

    // 3) Se não está indo para cliente, só pode receber corrida quando está 100% livre.
    if (r.indoParaCliente === 0) {
        return r.totalAtribuidas === 0 && r.ofertasReservadas === 0;
    }
    // 4) Indo para cliente, pode receber no máximo uma próxima corrida.
    if (r.indoParaCliente === 1) {
        return r.totalAtribuidas === 1 && r.ofertasReservadas === 0;
    }
    return false;
}

function acumularResumoEntrega(resumo, docId, pedido, uid, ignorePedidoId) {
    const status = String(pedido.status || "");
    if (ignorePedidoId && String(docId) === String(ignorePedidoId)) {
        return;
    }
    if (String(pedido.entregador_id || "") === String(uid)) {
        resumo.totalAtribuidas += 1;
        if (STATUS_INDO_LOJA.has(status)) resumo.indoParaLoja += 1;
        if (STATUS_INDO_CLIENTE.has(status)) resumo.indoParaCliente += 1;
    }
    if (status === "aguardando_entregador" &&
        String(pedido.despacho_oferta_uid || "") === String(uid)) {
        resumo.ofertasReservadas += 1;
    }
}

async function construirResumoOperacionalPorEntregador(db, ignorePedidoId = "") {
    const snap = await db
        .collection("pedidos")
        .where("status", "in", STATUS_DISPATCH_ANALISE)
        .get();
    const porUid = new Map();
    const getResumo = (uid) => {
        if (!porUid.has(uid)) porUid.set(uid, resumoOperacionalVazio());
        return porUid.get(uid);
    };
    snap.forEach((doc) => {
        const p = doc.data() || {};
        const status = String(p.status || "");
        const entregadorUid = String(p.entregador_id || "");
        if (entregadorUid) {
            const r = getResumo(entregadorUid);
            if (!ignorePedidoId || String(doc.id) !== String(ignorePedidoId)) {
                r.totalAtribuidas += 1;
                if (STATUS_INDO_LOJA.has(status)) r.indoParaLoja += 1;
                if (STATUS_INDO_CLIENTE.has(status)) r.indoParaCliente += 1;
            }
        }
        const ofertaUid = String(p.despacho_oferta_uid || "");
        if (status === "aguardando_entregador" &&
            ofertaUid &&
            (!ignorePedidoId || String(doc.id) !== String(ignorePedidoId))) {
            const r = getResumo(ofertaUid);
            r.ofertasReservadas += 1;
        }
    });
    return porUid;
}

async function construirResumoOperacionalEntregador(db, uid, ignorePedidoId = "") {
    const resumo = resumoOperacionalVazio();
    const uidStr = String(uid || "").trim();
    if (!uidStr) return resumo;

    // Hot path do aceite: evitar scan global de pedidos (causava latência perceptível).
    // Consulta só docs relacionados ao entregador (atribuídos ou oferta reservada).
    const [snapAtribuidos, snapOfertas] = await Promise.all([
        db
            .collection("pedidos")
            .where("entregador_id", "==", uidStr)
            .get(),
        db
            .collection("pedidos")
            .where("despacho_oferta_uid", "==", uidStr)
            .get(),
    ]);

    const docsPorId = new Map();
    snapAtribuidos.forEach((doc) => docsPorId.set(String(doc.id), doc.data() || {}));
    snapOfertas.forEach((doc) => docsPorId.set(String(doc.id), doc.data() || {}));

    for (const [docId, pedido] of docsPorId.entries()) {
        const status = String(pedido.status || "");
        if (!STATUS_DISPATCH_ANALISE.includes(status)) continue;
        acumularResumoEntrega(resumo, docId, pedido, uidStr, ignorePedidoId);
    }
    return resumo;
}

async function construirResumoOperacionalEntregadorTx(t, db, uid, ignorePedidoId = "") {
    const resumo = resumoOperacionalVazio();
    const uidStr = String(uid || "").trim();
    if (!uidStr) return resumo;

    const [snapAtribuidos, snapOfertas] = await Promise.all([
        t.get(
            db
                .collection("pedidos")
                .where("entregador_id", "==", uidStr),
        ),
        t.get(
            db
                .collection("pedidos")
                .where("despacho_oferta_uid", "==", uidStr),
        ),
    ]);

    const docsPorId = new Map();
    snapAtribuidos.forEach((doc) => docsPorId.set(String(doc.id), doc.data() || {}));
    snapOfertas.forEach((doc) => docsPorId.set(String(doc.id), doc.data() || {}));

    for (const [docId, pedido] of docsPorId.entries()) {
        const status = String(pedido.status || "");
        if (!STATUS_DISPATCH_ANALISE.includes(status)) continue;
        acumularResumoEntrega(resumo, docId, pedido, uidStr, ignorePedidoId);
    }
    return resumo;
}

function raioKmLimiteSeguro(maxRaioKm, fallbackPositivoKm) {
    const n = Number(maxRaioKm);
    if (!Number.isFinite(n) || n <= 0) {
        return Number(fallbackPositivoKm) > 0 ? Number(fallbackPositivoKm) : RAIO_KM_ETAPA_2;
    }
    if (n >= 9000) return 1e12;
    return n;
}

async function construirFilaEntregadores(db, pedido, maxRaioKm) {
    const { lat: lojaLat, lon: lojaLon } = await obterCoordenadasLoja(db, pedido);
    const semCoordsLoja = lojaLat == null || lojaLon == null;
    const limite = raioKmLimiteSeguro(maxRaioKm, RAIO_KM_ETAPA_AMPLA);
    const recusados = Array.isArray(pedido?.despacho_recusados)
        ? new Set(pedido.despacho_recusados.map(String))
        : new Set();
    const bloqueados = Array.isArray(pedido?.despacho_bloqueados)
        ? new Set(pedido.despacho_bloqueados.map(String))
        : new Set();
    const resumoOperacional = await construirResumoOperacionalPorEntregador(db);

    // Resolve tipos_entrega_permitidos da loja — prioridade:
    //   1) snapshot persistido no próprio pedido (imutável para a corrida)
    //   2) lojas_public (público) ou users (privado) da loja
    //   3) fallback legado: se vazio, NÃO filtra por tipo (compat com lojas
    //      pré-migração). Log claro pra observabilidade.
    const tiposAceitosLoja = await obterTiposEntregaDaLoja(db, pedido);
    const lojaConfigurada = Array.isArray(tiposAceitosLoja) && tiposAceitosLoja.length > 0;

    // Categoria alvo **deste pedido** (`tipo_entrega_solicitado`). Quando
    // presente, a oferta é direcionada exclusivamente pra entregadores desse
    // tipo. Quando ausente mas a loja só aceita UM tipo, esse tipo é
    // implícito (auto-derivação). Quando ausente e a loja aceita múltiplos,
    // o dispatch fica em espera — exige nova decisão do lojista via UI.
    const tipoExplicito = TIPOS_ENTREGA.normalizarTipoSolicitado(
        pedido?.tipo_entrega_solicitado,
    );
    const categoriaEfetiva = tipoExplicito
        ? tipoExplicito
        : (lojaConfigurada && tiposAceitosLoja.length === 1
            ? tiposAceitosLoja[0]
            : null);

    // Lista efetiva de tipos elegíveis pra este pedido. Se houver categoria
    // efetiva, usamos apenas ela (filtro estrito). Senão, preservamos a
    // lista aceita pela loja (compat com pedidos pré-fluxo de escolha).
    const tiposElegiveis = categoriaEfetiva
        ? [categoriaEfetiva]
        : (lojaConfigurada ? tiposAceitosLoja : []);
    const filtrarPorTipo = tiposElegiveis.length > 0;

    // Se a loja aceita múltiplos tipos e o pedido não tem `tipo_entrega_solicitado`,
    // o dispatch precisa pausar até o lojista escolher. Em vez de fazer isso
    // aqui (que roda em várias rotas), a transição de status acima
    // (`notificarEntregadoresPedidoPronto`) já bloqueia o set de status.
    // Se por alguma rota chegamos aqui, retornamos fila vazia com aviso.
    const pedidoSemCategoriaDecidida =
        lojaConfigurada && tiposAceitosLoja.length > 1 && !tipoExplicito;
    if (pedidoSemCategoriaDecidida) {
        console.warn(
            "[fila] pedido sem `tipo_entrega_solicitado` mas loja aceita " +
                `múltiplos tipos (${tiposAceitosLoja.join(",")}). ` +
                "Fila suprimida — lojista deve escolher categoria.",
        );
        return [];
    }

    // Só entregadores usam `is_online` no app — consulta única evita fila vazia quando
    // o documento tem `tipoUsuario` em vez de `role` (índice composto role+is_online).
    const snap = await db.collection("users").where("is_online", "==", true).get();

    console.log(
        `[fila] loja coords: lat=${lojaLat} lon=${lojaLon} | raio=${limite}km | ` +
        `is_online docs: ${snap.size} | recusados: ${recusados.size} | bloqueados: ${bloqueados.size} | ` +
        `tipoExplicito: ${tipoExplicito || "(ausente)"} | ` +
        `tiposElegiveis: ${filtrarPorTipo ? JSON.stringify(tiposElegiveis) : "(legado: sem filtro)"}`,
    );

    const candidates = [];
    let descartePorTipo = 0;
    snap.forEach((doc) => {
        const d = doc.data();
        const docId = String(doc.id);
        if (recusados.has(docId) || bloqueados.has(docId)) {
            console.log(`[fila] ${docId} — skip: recusado/bloqueado`);
            return;
        }
        if (!perfilEntregadorAtivo(d)) {
            const r = d.role || d.tipoUsuario || d.tipo || "?";
            const est = d.entregador_status || "?";
            const tk = fcmTokenDoUsuario(d) ? "sim" : "NÃO";
            const on = entregadorMarcadoOnline(d) ? "sim" : "NÃO";
            console.log(
                `[fila] ${docId} — skip: perfilInativo ` +
                `(role=${r} status=${est} token=${tk} online=${on})`,
            );
            return;
        }
        const resumo = resumoOperacional.get(String(doc.id)) || resumoOperacionalVazio();
        if (!podeReceberNovaCorridaPeloResumo(resumo)) {
            console.log(
                `[fila] ${docId} — skip: bloqueioOperacional ` +
                `(atr=${resumo.totalAtribuidas} indoLoja=${resumo.indoParaLoja} ` +
                `indoCli=${resumo.indoParaCliente} reserv=${resumo.ofertasReservadas})`,
            );
            return;
        }

        // Filtro por tipo de veículo do entregador:
        //   - Quando o pedido tem `tipo_entrega_solicitado` (ou único tipo
        //     aceito pela loja), `tiposElegiveis` tem exatamente 1 item →
        //     apenas entregadores desse tipo passam.
        //   - Quando não tem (compat com pedidos legado de lojas multi-tipo
        //     sem escolha), cai no fallback: qualquer tipo na lista aceita
        //     pela loja passa.
        //   - Quando `filtrarPorTipo` é false, não filtra (legado puro).
        if (filtrarPorTipo) {
            const tipoCanonico = TIPOS_ENTREGA.normalizarTipoVeiculo(
                d.tipo_veiculo_canonico || d.veiculoTipo || d.veiculo || d.tipo_veiculo,
            );
            if (!tipoCanonico) {
                console.log(
                    `[fila] ${docId} — skip: veiculo indefinido (exige: ${tiposElegiveis.join(",")})`,
                );
                descartePorTipo++;
                return;
            }
            if (!TIPOS_ENTREGA.compativel(tipoCanonico, tiposElegiveis)) {
                console.log(
                    `[fila] ${docId} — skip: tipo incompatível ` +
                    `(ent=${tipoCanonico}, elegíveis=${tiposElegiveis.join(",")})`,
                );
                descartePorTipo++;
                return;
            }
        }

        const plat = d.latitude != null ? Number(d.latitude) : null;
        const plon = d.longitude != null ? Number(d.longitude) : null;
        let dist = 1e9;
        if (lojaLat != null && lojaLon != null && plat != null && plon != null) {
            dist = haversineKm(lojaLat, lojaLon, plat, plon);
        }
        if (!semCoordsLoja && dist > limite) {
            console.log(`[fila] ${docId} — skip: fora do raio (${dist.toFixed(1)}km > ${limite}km)`);
            return;
        }
        console.log(`[fila] ${docId} — ELEGÍVEL (dist=${dist.toFixed(1)}km)`);
        candidates.push({ id: doc.id, dist });
    });

    candidates.sort((a, b) => a.dist - b.dist);
    console.log(
        `[fila] Total elegíveis: ${candidates.length} (raio ${maxRaioKm}km) | ` +
        `descartePorTipoVeiculo: ${descartePorTipo}`,
    );
    return candidates.map((c) => c.id);
}

/**
 * Retorna a lista canônica de tipos de entrega aceitos pela loja do pedido.
 * Ordem de resolução:
 *   1. Snapshot no próprio pedido (`tipos_entrega_permitidos_loja`) — preserva
 *      a configuração vigente no momento do checkout.
 *   2. `lojas_public/{loja_id}.tipos_entrega_permitidos` (sincronizado pelo
 *      trigger `sincronizarLojaPublicOnWrite`).
 *   3. `users/{loja_id}.tipos_entrega_permitidos` (fonte de verdade privada).
 *   4. `[]` (loja legado sem config — a fila NÃO filtra por tipo nesse caso).
 */
async function obterTiposEntregaDaLoja(db, pedido) {
    try {
        // 1. Snapshot gravado no pedido.
        const snap = TIPOS_ENTREGA.normalizarLista(pedido?.tipos_entrega_permitidos_loja);
        if (snap.length > 0) return snap;

        const lid = lojaIdStr(pedido);
        if (!lid) return [];

        // 2. lojas_public
        try {
            const pub = await db.collection("lojas_public").doc(String(lid)).get();
            if (pub.exists) {
                const lista = TIPOS_ENTREGA.normalizarLista(
                    (pub.data() || {}).tipos_entrega_permitidos,
                );
                if (lista.length > 0) return lista;
            }
        } catch (e) {
            console.warn("[fila] lerTiposLojaPublic:", e);
        }

        // 3. users/{loja}
        try {
            const priv = await db.collection("users").doc(String(lid)).get();
            if (priv.exists) {
                const lista = TIPOS_ENTREGA.normalizarLista(
                    (priv.data() || {}).tipos_entrega_permitidos,
                );
                if (lista.length > 0) return lista;
            }
        } catch (e) {
            console.warn("[fila] lerTiposLojaPriv:", e);
        }

        // 4. Sem config — legado.
        return [];
    } catch (e) {
        console.warn("[fila] obterTiposEntregaDaLoja:", e);
        return [];
    }
}

async function obterTokenEntregador(db, uid) {
    const doc = await db.collection("users").doc(String(uid)).get();
    if (!doc.exists) return null;
    const t = fcmTokenDoUsuario(doc.data() || {});
    return t || null;
}

async function enviarFcmChamadaEntregador(db, token, pedidoId, pedido, entregadorUid, seq, expiraMs) {
    if (!token) return { ok: false };

    const { lat: lojaLat, lon: lojaLon } = await obterCoordenadasLoja(db, pedido);
    const numeroOuNull = (v) => {
        if (v == null || v === "") return null;
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    };
    const primeiroNumeroValido = (...values) => {
        for (const value of values) {
            const n = numeroOuNull(value);
            if (n != null) return n;
        }
        return null;
    };
    const primeiroTexto = (...values) => {
        for (const value of values) {
            if (value != null && String(value).trim() !== "") {
                return String(value).trim();
            }
        }
        return "";
    };

    let distAteLojaKm = "";
    let distLojaClienteKm = "";
    let distTotalKm = "";
    let tempoMin = "";

    const elatDoc = await db.collection("users").doc(String(entregadorUid)).get();
    const ed = elatDoc.exists ? elatDoc.data() : {};
    const eLat = ed.latitude != null ? Number(ed.latitude) : null;
    const eLon = ed.longitude != null ? Number(ed.longitude) : null;
    const lojaPedidoLat = pedido.loja_latitude != null ? Number(pedido.loja_latitude) : lojaLat;
    const lojaPedidoLon = pedido.loja_longitude != null ? Number(pedido.loja_longitude) : lojaLon;
    const clienteLat = pedido.entrega_latitude != null ? Number(pedido.entrega_latitude) : null;
    const clienteLon = pedido.entrega_longitude != null ? Number(pedido.entrega_longitude) : null;

    let tAte = 0;
    let tSeg = 0;

    console.log(`[despacho][distancias] pedido=${pedidoId} entregador=${entregadorUid} ` +
        `lojaCoords=(${lojaLat},${lojaLon}) entregadorCoords=(${eLat},${eLon}) ` +
        `lojaPedidoCoords=(${lojaPedidoLat},${lojaPedidoLon}) clienteCoords=(${clienteLat},${clienteLon})`);

    if (lojaLat != null && lojaLon != null && eLat != null && eLon != null) {
        const m = haversineKm(lojaLat, lojaLon, eLat, eLon);
        distAteLojaKm = m.toFixed(2);
        tAte = (m / 25) * 60;
    }
    if (lojaPedidoLat != null && lojaPedidoLon != null && clienteLat != null && clienteLon != null) {
        const dLc = haversineKm(lojaPedidoLat, lojaPedidoLon, clienteLat, clienteLon);
        distLojaClienteKm = dLc.toFixed(2);
        tSeg = (dLc / 25) * 60;
    }
    if (tAte > 0 || tSeg > 0) {
        tempoMin = String(Math.max(1, Math.round(tAte + tSeg)));
    }

    // Fallback para pedidos com campos já persistidos sem coordenadas completas.
    if (!distAteLojaKm) {
        const dFallback = primeiroNumeroValido(
            pedido.distancia_entregador_loja_km ||
            pedido.distance_to_store_km ||
            pedido.despacho_distancia_km ||
            pedido.distancia_ate_loja_km ||
            pedido.distance_to_store ||
            pedido?.distancias?.ate_loja_km ||
            pedido?.distancias?.to_store_km,
        );
        if (dFallback != null) {
            distAteLojaKm = dFallback.toFixed(2);
        }
    }
    if (!distLojaClienteKm) {
        const dFallback = primeiroNumeroValido(
            pedido.distancia_loja_cliente_km ||
            pedido.distance_store_to_customer_km ||
            pedido.distancia_rota_km ||
            pedido.distancia_cliente_km ||
            pedido.distance_customer_km ||
            pedido?.distancias?.loja_cliente_km ||
            pedido?.distancias?.store_to_customer_km,
        );
        if (dFallback != null) {
            distLojaClienteKm = dFallback.toFixed(2);
        }
    }
    const dAte = numeroOuNull(distAteLojaKm);
    const dLojaCliente = numeroOuNull(distLojaClienteKm);
    if (dAte != null && dLojaCliente != null) {
        distTotalKm = (dAte + dLojaCliente).toFixed(2);
    } else {
        const totalFallback = primeiroNumeroValido(
            pedido.distancia_total_km ||
            pedido.total_distance_km ||
            pedido.distancia_km ||
            pedido.distance_km ||
            pedido?.distancias?.total_km,
        );
        if (totalFallback != null) {
            distTotalKm = totalFallback.toFixed(2);
        }
    }

    const taxaBruta = Number(pedido.taxa_entrega || 0);
    const descontoPlataforma = Number(pedido.taxa_entregador || 0);
    const valorLiquido =
        pedido.valor_liquido_entregador != null
            ? Number(pedido.valor_liquido_entregador)
            : Math.max(0, taxaBruta - descontoPlataforma);

    const pickup = String(pedido.loja_endereco || pedido.loja_nome || "").slice(0, 500);
    const delivery = String(pedido.endereco_entrega || "").slice(0, 500);
    const lojaId = String(lojaIdStr(pedido) || "");
    let lojaNome = "";
    let lojaFotoUrl = primeiroTexto(
        pedido.loja_foto_url,
        pedido.loja_logo_url,
        pedido.loja_imagem_url,
        pedido.loja_foto,
        pedido.store_photo_url,
        pedido.store_logo_url,
        pedido.store_image_url,
    );

    if (lojaId) {
        try {
            const lojaDoc = await db.collection("users").doc(lojaId).get();
            if (lojaDoc.exists) {
                const lojaData = lojaDoc.data() || {};
                lojaNome = primeiroTexto(
                    lojaData.nome_loja,
                    lojaData.nomeFantasia,
                    lojaData.nome_fantasia,
                    lojaData.loja_nome,
                    lojaData.store_name,
                );
                lojaFotoUrl = primeiroTexto(
                    lojaFotoUrl,
                    lojaData.logo_url,
                    lojaData.foto_perfil,
                    lojaData.foto_url,
                    lojaData.imagem_url,
                    lojaData.foto,
                    lojaData.photoURL,
                );
            }
        } catch (e) {
            console.warn(`[despacho] Falha ao ler dados da loja ${lojaId}:`, e?.message || e);
        }
    }
    lojaNome = primeiroTexto(
        lojaNome,
        pedido.nome_loja,
        pedido.loja_nome,
        pedido.store_name,
        "Loja parceira",
    );

    console.log(`[despacho][distancias] pedido=${pedidoId} resultado: ` +
        `ateLojaKm="${distAteLojaKm}" lojaClienteKm="${distLojaClienteKm}" totalKm="${distTotalKm}" tempoMin="${tempoMin}"`);

    const data = dataSoStrings({
        type: "nova_corrida",
        tipoNotificacao: "nova_entrega",
        segmento: "entregador",
        evento: "dispatch_request",
        notif_title: "Nova corrida DiPertin",
        notif_body: "Toque para ver detalhes e aceitar em até 15 segundos.",
        orderId: String(pedidoId),
        order_id: String(pedidoId),
        loja_id: lojaId,
        loja_nome: lojaNome,
        loja_foto_url: lojaFotoUrl,
        cliente_id: String(pedido.cliente_id || ""),
        despacho_oferta_seq: String(seq),
        despacho_expira_em_ms: String(expiraMs),
        pickup_location: pickup,
        delivery_location: delivery,
        distance_to_store_km: distAteLojaKm,
        distance_store_to_customer_km: distLojaClienteKm,
        total_distance_km: distTotalKm,
        delivery_fee: String(taxaBruta.toFixed(2)),
        net_delivery_fee: String(valorLiquido.toFixed(2)),
        plataforma_fee: String(descontoPlataforma.toFixed(2)),
        tempo_estimado_min: tempoMin,
    });

    // Tag única por pedido — usada tanto pelo bloco notification (sistema)
    // quanto pelo NotificationCompat custom no Kotlin para que o segundo
    // SUBSTITUA a notif do sistema (mesma tag) em vez de duplicar.
    const sysTag = `corrida_${pedidoId}`;

    const mensagem = {
        // Android: payload HÍBRIDO (notification + data).
        // - Em foreground/processo vivo: onMessageReceived processa data e
        //   o IncomingDeliveryFirebaseService cancela a notif do sistema e
        //   exibe a UI de chamada custom (full-screen intent).
        // - Em Doze profundo / OEM agressiva (Xiaomi/Oppo/Realme), quando o
        //   serviço pode não acordar a tempo, o SO ainda desenha a notif do
        //   sistema no canal `corrida_chamada` (importance HIGH + som), o
        //   que garante que o entregador é avisado mesmo com tela bloqueada.
        // Sem ttl curto: 15s fazia o FCM descartar a mensagem antes de chegar.
        android: {
            priority: "high",
            collapseKey: sysTag,
            notification: {
                title: "Nova corrida DiPertin",
                body: "Toque para ver detalhes e aceitar em até 15 segundos.",
                channelId: "corrida_chamada",
                sound: "chamada_entregador",
                priority: "max",
                visibility: "public",
                defaultSound: false,
                defaultVibrateTimings: true,
                tag: sysTag,
                notificationCount: 1,
            },
        },
        data,
        token,
    };
    await admin.messaging().send(mensagem);
    return { ok: true };
}

/**
 * Ofertas sequenciais para uma fila já montada (3 km ou 5 km naquele momento).
 * @returns {"aceito"|"abort"|"saiu_status"|"fila_ok"}
 */
async function processarOfertasNaFila(ref, pedidoId, db, fila) {
    if (!fila || fila.length === 0) {
        return "fila_ok";
    }

    await ref.update({
        despacho_fila_ids: fila,
        despacho_indice_atual: 0,
    });

    for (let idx = 0; idx < fila.length; idx++) {
        const snapPre = await ref.get();
        const pre = snapPre.data();
        if (pre && pre.despacho_abort_flag === true) {
            await ref.update({
                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_abort_flag: admin.firestore.FieldValue.delete(),
            });
            console.log(`[despacho] Pedido ${pedidoId} — abortado (loja).`);
            return "abort";
        }

        const uid = fila[idx];
        const snapCheck = await ref.get();
        const cur = snapCheck.data();
        if (!cur || cur.entregador_id) {
            console.log(`[despacho] Pedido ${pedidoId} — já tem entregador, fim.`);
            await ref.update({
                despacho_job_lock: admin.firestore.FieldValue.delete(),
            });
            return "aceito";
        }
        if (cur.status !== "aguardando_entregador") {
            await ref.update({
                despacho_job_lock: admin.firestore.FieldValue.delete(),
            });
            return "saiu_status";
        }

        const resumoElegibilidade = await construirResumoOperacionalEntregador(
            db,
            uid,
            pedidoId,
        );
        if (!podeReceberNovaCorridaPeloResumo(resumoElegibilidade)) {
            console.log(
                `[despacho][bloqueio-operacional] pedido=${pedidoId} uid=${uid} ` +
                `estado=${classificarEstadoOperacional(resumoElegibilidade)} ` +
                `atr=${resumoElegibilidade.totalAtribuidas} ` +
                `indoLoja=${resumoElegibilidade.indoParaLoja} ` +
                `indoCliente=${resumoElegibilidade.indoParaCliente} ` +
                `fila=${resumoElegibilidade.ofertasReservadas}`,
            );
            await ref.update({
                despacho_recusados: admin.firestore.FieldValue.arrayUnion(uid),
                despacho_oferta_estado: "bloqueado_operacional",
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
            });
            continue;
        }

        const seq = (cur.despacho_oferta_seq || 0) + 1;
        const expiraMs = Date.now() + OFERTA_SEGUNDOS * 1000;
        const token = await obterTokenEntregador(db, uid);
        if (!token) {
            console.warn(
                `[despacho] Pedido ${pedidoId} — uid=${uid} sem fcm_token; ` +
                    "pula candidato (antes gravava oferta sem push).",
            );
            await ref.update({
                despacho_bloqueados: admin.firestore.FieldValue.arrayUnion(uid),
            });
            continue;
        }

        await ref.update({
            despacho_oferta_uid: uid,
            despacho_oferta_seq: seq,
            despacho_oferta_expira_em: admin.firestore.Timestamp.fromMillis(expiraMs),
            despacho_oferta_estado: "chamado_enviado",
            despacho_indice_atual: idx,
            busca_entregadores_notificados: admin.firestore.FieldValue.arrayUnion(uid),
        });

        const pedidoSnap = (await ref.get()).data() || {};
        try {
            const envio = await enviarFcmChamadaEntregador(
                db,
                token,
                pedidoId,
                pedidoSnap,
                uid,
                seq,
                expiraMs,
            );
            if (!envio || envio.ok !== true) {
                throw new Error("fcm_retorno_inesperado");
            }
            console.log(`[despacho] Pedido ${pedidoId} — oferta seq=${seq} para ${uid}`);
        } catch (fcmErr) {
            const code = fcmErr.errorInfo?.code || "";
            console.warn(
                `[despacho] FCM falhou para ${uid} (${code}): ${fcmErr.message || fcmErr}`,
            );
            if (code === "messaging/registration-token-not-registered" ||
                code === "messaging/invalid-registration-token") {
                try {
                    await db.collection("users").doc(uid).update({ fcm_token: admin.firestore.FieldValue.delete() });
                    console.log(`[despacho] Token inválido removido de users/${uid}`);
                } catch (_) {}
            }
            await ref.update({
                despacho_recusados: admin.firestore.FieldValue.arrayUnion(uid),
                despacho_oferta_estado: "fcm_falhou",
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
            });
            continue;
        }

        let saidaAntecipada = false;
        for (let t = 0; t < OFERTA_SEGUNDOS; t++) {
            await sleep(POLL_MS);
            const d = (await ref.get()).data();
            if (!d) return "saiu_status";
            if (d.despacho_abort_flag === true) {
                await ref.update({
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                    despacho_abort_flag: admin.firestore.FieldValue.delete(),
                });
                console.log(`[despacho] Pedido ${pedidoId} — abort durante oferta.`);
                return "abort";
            }
            if (d.entregador_id) {
                console.log(`[despacho] Pedido ${pedidoId} — aceito.`);
                await ref.update({
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                    despacho_oferta_estado: "aceito",
                });
                return "aceito";
            }
            if (d.status !== "aguardando_entregador") {
                await ref.update({
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                });
                return "saiu_status";
            }
            const rec = Array.isArray(d.despacho_recusados) ? d.despacho_recusados.map(String) : [];
            if (rec.includes(String(uid))) {
                saidaAntecipada = true;
                break;
            }
            if (String(d.despacho_oferta_uid || "") !== String(uid)) {
                saidaAntecipada = true;
                break;
            }
        }

        if (!saidaAntecipada) {
            const dFinal = (await ref.get()).data();
            if (dFinal && dFinal.despacho_abort_flag === true) {
                await ref.update({
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                    despacho_abort_flag: admin.firestore.FieldValue.delete(),
                });
                return "abort";
            }
            if (dFinal && dFinal.entregador_id) {
                await ref.update({
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                    despacho_oferta_estado: "aceito",
                });
                return "aceito";
            }
            if (dFinal && dFinal.status === "aguardando_entregador") {
                await ref.update({
                    despacho_recusados: admin.firestore.FieldValue.arrayUnion(uid),
                    despacho_oferta_estado: "expirado",
                    despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                    despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                    despacho_redirecionado_para_proximo: true,
                });
                console.log(`[despacho] Pedido ${pedidoId} — expirou para ${uid}, próximo.`);
            }
        }
    }

    return "fila_ok";
}

/**
 * Um “ciclo”: limpa recusados da sessão (opcional), oferece 3 km depois 5 km.
 * @returns {"aceito"|"abort"|"saiu_status"|"macro_ok"}
 */
async function executarMacroCicloUmPasso(ref, pedidoId, db, macroIndex, limparRecusadosNaAbertura) {
    const patch = {
        despacho_macro_ciclo_atual: macroIndex,
        despacho_oferta_uid: admin.firestore.FieldValue.delete(),
        despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
        despacho_oferta_estado: admin.firestore.FieldValue.delete(),
        despacho_fila_ids: [],
        despacho_indice_atual: 0,
    };
    if (limparRecusadosNaAbertura) {
        patch.despacho_recusados = [];
    }
    await ref.update(patch);

    let pedido = (await ref.get()).data();
    if (!pedido || pedido.status !== "aguardando_entregador") {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "saiu_status";
    }
    if (pedido.entregador_id) {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "aceito";
    }

    const fila3 = await construirFilaEntregadores(db, pedido, RAIO_KM_ETAPA_1);
    let r = await processarOfertasNaFila(ref, pedidoId, db, fila3);
    if (r === "aceito" || r === "abort" || r === "saiu_status") return r;

    pedido = (await ref.get()).data();
    if (!pedido || pedido.status !== "aguardando_entregador") {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "saiu_status";
    }
    if (pedido.entregador_id) {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "aceito";
    }

    const fila5 = await construirFilaEntregadores(db, pedido, RAIO_KM_ETAPA_2);
    r = await processarOfertasNaFila(ref, pedidoId, db, fila5);
    if (r === "aceito" || r === "abort" || r === "saiu_status") return r;

    pedido = (await ref.get()).data();
    if (!pedido || pedido.status !== "aguardando_entregador") {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "saiu_status";
    }
    if (pedido.entregador_id) {
        await ref.update({ despacho_job_lock: admin.firestore.FieldValue.delete() });
        return "aceito";
    }

    const coords = await obterCoordenadasLoja(db, pedido);
    if (coords.lat != null && coords.lon != null) {
        const filaAmpl = await construirFilaEntregadores(db, pedido, RAIO_KM_ETAPA_AMPLA);
        r = await processarOfertasNaFila(ref, pedidoId, db, filaAmpl);
        if (r === "aceito" || r === "abort" || r === "saiu_status") return r;
    }

    return "macro_ok";
}

async function limparDespachoVoltarEmPreparo(ref, pedidoId, marcarAutoEncerrada) {
    const patch = {
        status: "em_preparo",
        despacho_job_lock: admin.firestore.FieldValue.delete(),
        despacho_abort_flag: admin.firestore.FieldValue.delete(),
        despacho_fila_ids: [],
        despacho_indice_atual: 0,
        despacho_recusados: [],
        despacho_bloqueados: [],
        despacho_oferta_uid: admin.firestore.FieldValue.delete(),
        despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
        despacho_oferta_seq: 0,
        despacho_oferta_estado: admin.firestore.FieldValue.delete(),
        despacho_estado: admin.firestore.FieldValue.delete(),
        despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
        despacho_redespacho_loja_em: admin.firestore.FieldValue.delete(),
        despacho_redespacho_entregador_em: admin.firestore.FieldValue.delete(),
        despacho_redirecionado_para_proximo: admin.firestore.FieldValue.delete(),
        despacho_erro_msg: admin.firestore.FieldValue.delete(),
        despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
        despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
        despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
        busca_entregadores_notificados: [],
        busca_raio_km: admin.firestore.FieldValue.delete(),
        busca_entregador_inicio: admin.firestore.FieldValue.delete(),
    };
    if (marcarAutoEncerrada) {
        patch.despacho_auto_encerrada_sem_entregador = true;
        patch.despacho_msg_busca_entregador =
            "Nenhum entregador aceitou após várias rodadas (3 km / 5 km). " +
            "Toque em «Solicitar entregador» para tentar de novo.";
    } else {
        patch.despacho_auto_encerrada_sem_entregador = admin.firestore.FieldValue.delete();
        patch.despacho_msg_busca_entregador = admin.firestore.FieldValue.delete();
    }
    await ref.update(patch);
    console.log(`[despacho] Pedido ${pedidoId} — busca encerrada, status em_preparo.`);
}

/**
 * Núcleo do despacho sequencial (após lock no documento).
 * @param {"primario"|"estendido"} modo — primário: 5 ciclos 3→5 km depois pausa para o lojista; estendido: +5 ciclos e encerra em em_preparo se não aceitar.
 */
async function executarDespachoSequencial(ref, pedidoId, db, depois, modo = "primario") {
    const macroMax = modo === "estendido" ? CICLOS_MACRO_EXTENDIDO : CICLOS_MACRO_PRIMARIO;
    try {
        for (let macro = 1; macro <= macroMax; macro++) {
            // Regra operacional: quem recusou/cancelou nesta busca fica fora
            // até a loja iniciar um novo ciclo manual ("Solicitar entregador").
            const limparRecusadosNaAbertura = false;

            const resultado = await executarMacroCicloUmPasso(
                ref,
                pedidoId,
                db,
                macro,
                limparRecusadosNaAbertura,
            );
            if (resultado === "aceito" || resultado === "abort" || resultado === "saiu_status") {
                return null;
            }
        }

        if (modo === "primario") {
            await ref.update({
                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_aguarda_decisao_lojista: true,
                despacho_estado: "aguardando_decisao_lojista",
                despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
                despacho_msg_busca_entregador:
                    "Ainda não encontramos um entregador após 5 rodadas (3 km e 5 km). " +
                    "Você pode cancelar a chamada ou continuar buscando por mais 5 rodadas.",
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_fila_ids: [],
            });
            console.log(`[despacho] Pedido ${pedidoId} — aguardando decisão do lojista.`);
            return null;
        }

        await limparDespachoVoltarEmPreparo(ref, pedidoId, true);
    } catch (e) {
        console.error(`[despacho] Erro pedido ${pedidoId}:`, e);
        try {
            await ref.update({
                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_erro_msg: String(e.message || e),
            });
        } catch (_) {}
    }
    return null;
}

exports.notificarEntregadoresPedidoPronto = functions
    .runWith({
        timeoutSeconds: 540,
        memory: "512MB",
    })
    .firestore.document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data();
        const depois = change.after.data();
        if (depois.status !== "aguardando_entregador") {
            return null;
        }
        if (antes.status === "aguardando_entregador") {
            return null;
        }

        const pedidoId = context.params.pedidoId;
        const ref = change.after.ref;
        const db = admin.firestore();
        const eventId = context.eventId || `evt_${Date.now()}`;

        // `reverterPorFaltaDeCategoria`: se loja aceita múltiplos tipos e o
        // pedido não tem `tipo_entrega_solicitado`, NÃO despachamos — o
        // despacho exigiria escolha de categoria pelo lojista. Revertemos
        // para `em_preparo` com mensagem explicativa; o botão "Solicitar
        // entregador" do painel já faz o lojista escolher via modal.
        let reverterPorFaltaDeCategoria = false;

        const lockOk = await db.runTransaction(async (t) => {
            const snap = await t.get(ref);
            const d = snap.data();
            if (!d || d.status !== "aguardando_entregador") return false;
            if (d.despacho_job_lock) return false;
            const updates = {
                despacho_job_lock: eventId,
                despacho_estado: "aguardando_entregador",
            };
            // Se o pedido ainda não tem snapshot dos tipos aceitos da loja,
            // grava agora (antes de despachar) pra manter a lista imutável
            // durante toda a corrida e permitir reprocessamentos determinísticos.
            const snapshotAtual = TIPOS_ENTREGA.normalizarLista(
                d.tipos_entrega_permitidos_loja,
            );
            let listaTipos = snapshotAtual;
            if (snapshotAtual.length === 0) {
                try {
                    const resolvido = await obterTiposEntregaDaLoja(db, d);
                    if (resolvido && resolvido.length > 0) {
                        updates.tipos_entrega_permitidos_loja = resolvido;
                        updates.tipos_entrega_permitidos_loja_origem = "onUpdate_despacho";
                        listaTipos = resolvido;
                    }
                } catch (e) {
                    console.warn(`[despacho] snapshot tipos loja falhou ${pedidoId}:`, e);
                }
            }

            // Verifica a categoria efetiva do pedido.
            const tipoSolicitado = TIPOS_ENTREGA.normalizarTipoSolicitado(
                d.tipo_entrega_solicitado,
            );
            const lojaMultiTipo = Array.isArray(listaTipos) && listaTipos.length > 1;

            if (!tipoSolicitado && lojaMultiTipo) {
                // Reverte status e sinaliza ao lojista. Mantém o `despacho_job_lock`
                // limpo para que o novo clique possa re-disparar o trigger.
                reverterPorFaltaDeCategoria = true;
                t.update(ref, {
                    status: "em_preparo",
                    despacho_estado: admin.firestore.FieldValue.delete(),
                    despacho_job_lock: admin.firestore.FieldValue.delete(),
                    despacho_aguarda_decisao_lojista: true,
                    despacho_msg_busca_entregador:
                        "Escolha a categoria do entregador (ex: moto ou carro) antes de solicitar. " +
                        "Sua loja aceita mais de um tipo; por isso é preciso decidir qual chamar.",
                    despacho_motivo_reversao: "sem_tipo_entrega_solicitado",
                });
                return false;
            }

            // Auto-derivação: loja com 1 único tipo aceito e pedido sem escolha
            // explícita → assume esse tipo como `tipo_entrega_solicitado` pra
            // manter a propriedade de "todo pedido despachado tem categoria".
            if (!tipoSolicitado &&
                Array.isArray(listaTipos) && listaTipos.length === 1) {
                updates.tipo_entrega_solicitado = listaTipos[0];
                updates.tipo_entrega_solicitado_origem = "auto_tipo_unico";
            }

            t.update(ref, updates);
            return true;
        });

        if (reverterPorFaltaDeCategoria) {
            console.warn(
                `[despacho] Pedido ${pedidoId} revertido para em_preparo — ` +
                "loja multi-tipo sem tipo_entrega_solicitado. Lojista deve re-escolher.",
            );
            return null;
        }

        if (!lockOk) {
            console.log(`[despacho] Pedido ${pedidoId} — outro job já iniciou ou status inválido.`);
            return null;
        }

        // Reler o pedido pra pegar o snapshot de tipos gravado acima (se gravado).
        let pedidoAtualizado = depois;
        try {
            const fresh = await ref.get();
            if (fresh.exists) pedidoAtualizado = fresh.data();
        } catch (_) {
            // ignora; o fallback em construirFilaEntregadores lê do lojas_public/users
        }

        await executarDespachoSequencial(ref, pedidoId, db, pedidoAtualizado);
        return null;
    });

exports.recusarOfertaCorrida = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
    }
    const pedidoId = data && data.pedidoId ? String(data.pedidoId) : "";
    if (!pedidoId) {
        throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
    }
    const uid = context.auth.uid;
    const ref = admin.firestore().collection("pedidos").doc(pedidoId);
    let resultado = { ok: true, recusado: true };

    await admin.firestore().runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p = snap.data();
        if (p.status !== "aguardando_entregador") {
            resultado = {
                ok: true,
                recusado: false,
                motivo: "pedido_nao_aguardando_entregador",
            };
            return;
        }
        const alvoRecusa = String(p.despacho_oferta_uid || "");
        const updates = {
            despacho_recusados: admin.firestore.FieldValue.arrayUnion(uid),
        };
        if (alvoRecusa === String(uid)) {
            updates.despacho_oferta_uid = admin.firestore.FieldValue.delete();
            updates.despacho_oferta_expira_em = admin.firestore.FieldValue.delete();
            updates.despacho_oferta_estado = "recusado";
        }
        t.update(ref, updates);
    });

    return resultado;
});

exports.aceitarOfertaCorrida = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
    }
    const pedidoId = data && data.pedidoId ? String(data.pedidoId) : "";
    if (!pedidoId) {
        throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
    }

    const db = admin.firestore();
    const uid = context.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const pedidoRef = db.collection("pedidos").doc(pedidoId);
    const userSnap = await userRef.get();
    const ud = userSnap.exists ? userSnap.data() || {} : {};
    const nomeEntregador = String(ud.nome || "").trim() || "Entregador parceiro";
    const foto = String(ud.foto_perfil || "").trim();
    const tel = String(ud.telefone || "").trim();
    const veiculo = String(ud.veiculoTipo || "").trim();
    const audicaoRaw = ud.acessibilidade && typeof ud.acessibilidade === "object"
        ? String(ud.acessibilidade.audicao || "").trim().toLowerCase()
        : "";
    const audicao = ["surdo", "deficiencia", "deficiência", "normal"].includes(audicaoRaw)
        ? (audicaoRaw === "deficiência" ? "deficiencia" : audicaoRaw)
        : "";

    let resultado = { ok: true, aceito: true };

    await db.runTransaction(async (t) => {
        const snap = await t.get(pedidoRef);
        if (!snap.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p = snap.data();
        const status = String(p.status || "");
        if (status !== "aguardando_entregador" && status !== "a_caminho") {
            resultado = {
                ok: true,
                aceito: false,
                motivo: "pedido_indisponivel",
            };
            return;
        }
        if (p.entregador_id != null) {
            resultado = {
                ok: true,
                aceito: false,
                motivo: "corrida_ja_aceita",
            };
            return;
        }

        const alvo = String(p.despacho_oferta_uid || "");
        if (alvo && alvo !== String(uid)) {
            resultado = {
                ok: true,
                aceito: false,
                motivo: "oferta_nao_pertence_ao_entregador",
            };
            return;
        }

        const resumo = await construirResumoOperacionalEntregadorTx(t, db, uid, pedidoId);
        if (!podeReceberNovaCorridaPeloResumo(resumo)) {
            resultado = {
                ok: true,
                aceito: false,
                motivo: "bloqueado_por_estado_operacional",
            };
            return;
        }
        const totalDepoisAceite = (resumo.totalAtribuidas || 0) + 1;
        if (totalDepoisAceite > 2) {
            resultado = {
                ok: true,
                aceito: false,
                motivo: "limite_corridas_simultaneas",
            };
            return;
        }

        // Validação de compatibilidade entre veículo do entregador e
        // categoria aceita pela loja.
        //
        // POLÍTICA (atualizada 04/2026):
        //   A FILA é a autoridade do despacho. Se o backend gravou
        //   `despacho_oferta_uid === uid`, é porque `construirFilaEntregadores`
        //   considerou este entregador compatível no momento da oferta.
        //   Bloquear no aceite causa um bug visível ao entregador: a tela
        //   fullscreen aparece, ele clica "Aceitar", e a corrida some
        //   silenciosamente — comportamento confuso e que reduz a
        //   produtividade.
        //
        //   Por isso, quando há OFERTA DIRECIONADA (despacho_oferta_uid),
        //   confiamos na fila e DEIXAMOS PASSAR mesmo que a checagem
        //   diverja. Apenas logamos um warning estruturado para que possamos
        //   investigar a causa raiz (mudança de veículo ativo entre fila
        //   e aceite, snapshot defasado, etc.).
        //
        //   O bloqueio rígido é mantido apenas para o caso em que NÃO há
        //   oferta direcionada (rota legada/manual), onde a defesa de
        //   profundidade ainda faz sentido.
        //
        //   Quando a entrega for inviável (carga grande não cabe no
        //   veículo, etc.), o entregador tem o caminho não-punitivo
        //   `entregadorCancelarPorIncompatibilidade` — mesma lógica usada
        //   pelo botão "Produto incompatível" do dashboard.
        const tiposAceitosLoja = TIPOS_ENTREGA.normalizarLista(
            p.tipos_entrega_permitidos_loja,
        );
        const tipoSolicitado = TIPOS_ENTREGA.normalizarTipoSolicitado(
            p.tipo_entrega_solicitado,
        );
        const tipoEntregador = TIPOS_ENTREGA.normalizarTipoVeiculo(
            ud.tipo_veiculo_canonico || ud.veiculoTipo || ud.veiculo || ud.tipo_veiculo,
        );

        // Lista efetiva de tipos válidos para este pedido (1 item quando
        // houve escolha explícita ou apenas 1 aceito pela loja).
        let tiposElegiveisAceite;
        if (tipoSolicitado) {
            tiposElegiveisAceite = [tipoSolicitado];
        } else if (tiposAceitosLoja.length === 1) {
            tiposElegiveisAceite = [tiposAceitosLoja[0]];
        } else {
            tiposElegiveisAceite = tiposAceitosLoja;
        }

        const ofertaDirecionadaParaMim = String(p.despacho_oferta_uid || "") === String(uid);

        const incompativel =
            tiposElegiveisAceite.length > 0 &&
            tipoEntregador &&
            !TIPOS_ENTREGA.compativel(tipoEntregador, tiposElegiveisAceite);

        if (incompativel && ofertaDirecionadaParaMim) {
            console.warn(
                `[aceitarOferta][divergencia-fila-vs-aceite] pedido=${pedidoId} ` +
                `uid=${uid} ofertaDirecionada=true ` +
                `tipoEntregador=${tipoEntregador || "(vazio)"} ` +
                `tipoSolicitado=${tipoSolicitado || "(ausente)"} ` +
                `tiposElegiveis=${JSON.stringify(tiposElegiveisAceite)} ` +
                `tiposAceitosLojaSnapshot=${JSON.stringify(tiposAceitosLoja)} ` +
                `→ DEIXANDO PASSAR (fila já escolheu este entregador)`,
            );
            // Não bloqueia. Continua o fluxo de aceite normal abaixo.
        } else if (incompativel) {
            // Sem oferta direcionada (rota legada/manual): mantém defesa.
            const recusadosAtuais = Array.isArray(p.despacho_recusados)
                ? p.despacho_recusados.map(String)
                : [];
            const recusadosNovos = Array.from(
                new Set([...recusadosAtuais, String(uid)]),
            );
            t.update(pedidoRef, {
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_oferta_estado: "rejeitada_incompat",
                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_recusados: recusadosNovos,
            });
            resultado = {
                ok: true,
                aceito: false,
                motivo: "veiculo_incompativel_loja",
                detalhe:
                    "Esta loja não aceita seu tipo de veículo para este pedido. " +
                    "A corrida será oferecida a outro entregador compatível.",
                tipo_entregador: tipoEntregador,
                tipo_solicitado: tipoSolicitado || null,
                tipos_elegiveis: tiposElegiveisAceite,
                tipos_aceitos_loja: tiposAceitosLoja,
                redespachar: true,
            };
            return;
        }

        t.update(pedidoRef, {
            status: "entregador_indo_loja",
            entregador_id: uid,
            entregador_nome: nomeEntregador,
            entregador_foto_url: foto,
            entregador_telefone: tel,
            entregador_veiculo: veiculo,
            entregador_veiculo_canonico_aceite:
                tipoEntregador || admin.firestore.FieldValue.delete(),
            entregador_acessibilidade_audicao: audicao,
            entregador_aceito_em: admin.firestore.FieldValue.serverTimestamp(),
            despacho_oferta_uid: admin.firestore.FieldValue.delete(),
            despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
            despacho_oferta_estado: "aceito",
            despacho_job_lock: admin.firestore.FieldValue.delete(),
        });
        t.set(userRef, {
            entregador_operacao_status: "INDO_PARA_LOJA",
            entregador_corridas_pendentes: 0,
            entregador_estado_operacao_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            entregador_estado_operacao_origem: "aceitarOfertaCorrida",
            entregador_estado_operacao_pedido_id: pedidoId,
        }, { merge: true });
    });

    // Se o aceite foi rejeitado por incompatibilidade, refaz o despacho
    // fora da transação para encontrar um entregador compatível. O uid
    // atual já está em `despacho_recusados`, então não volta pra ele.
    if (resultado && resultado.redespachar) {
        try {
            const fresh = await pedidoRef.get();
            if (fresh.exists) {
                const pedidoAtualizado = fresh.data();
                if (pedidoAtualizado &&
                    pedidoAtualizado.status === "aguardando_entregador") {
                    await executarDespachoSequencial(
                        pedidoRef,
                        pedidoId,
                        db,
                        pedidoAtualizado,
                    );
                }
            }
        } catch (e) {
            console.warn(
                `[aceitarOferta] redespacho após incompat falhou ${pedidoId}:`,
                e,
            );
        }
    }

    return resultado;
});

function numeroSeguro(v) {
    if (v == null || v === "") return 0;
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
}

async function buscarProximaCorridaAtiva(db, uid, pedidoAtualId) {
    const snap = await db
        .collection("pedidos")
        .where("entregador_id", "==", String(uid))
        .limit(40)
        .get();
    const statusElegiveis = new Set([
        "entregador_indo_loja",
        "saiu_entrega",
        "em_rota",
        "a_caminho",
    ]);
    let candidata = null;
    for (const doc of snap.docs) {
        if (String(doc.id) === String(pedidoAtualId)) continue;
        const d = doc.data() || {};
        const st = String(d.status || "");
        if (!statusElegiveis.has(st)) continue;
        const ts = d.data_pedido && d.data_pedido.toMillis ? d.data_pedido.toMillis() : 0;
        if (!candidata || ts < candidata.ts) {
            candidata = { id: doc.id, status: st, ts };
        }
    }
    return candidata;
}

/**
 * Entregador valida token de 6 dígitos e finaliza entrega no backend.
 * Idempotente: se já estiver entregue, retorna sucesso com resumo.
 */
exports.entregadorValidarCodigoEntrega = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
    }
    const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
    const codigo = data && data.codigo ? String(data.codigo).trim().toUpperCase() : "";
    if (!pedidoId) {
        throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
    }
    if (!codigo || codigo.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Código de entrega inválido.");
    }

    const uid = context.auth.uid;
    const db = admin.firestore();
    const ref = db.collection("pedidos").doc(pedidoId);

    let resumo = null;
    let tokenValido = false;
    await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p = snap.data() || {};
        const status = String(p.status || "");
        const entregadorId = String(p.entregador_id || "");
        if (entregadorId && entregadorId !== String(uid)) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "Este pedido não pertence ao entregador autenticado.",
            );
        }

        const tokenRealDoc = String(p.token_entrega || "").trim().toUpperCase();
        const tokenFallback = pedidoId.length >= 6
            ? pedidoId.substring(pedidoId.length - 6).toUpperCase()
            : "";
        const tokenReal = tokenRealDoc || tokenFallback;
        tokenValido = tokenReal.length >= 6 && codigo === tokenReal;

        resumo = {
            pedido_id: pedidoId,
            status_anterior: status,
            valor_total_corrida: numeroSeguro(
                p.taxa_entrega != null ? p.taxa_entrega : p.valor_total_corrida,
            ),
            taxa_plataforma: numeroSeguro(
                p.taxa_entregador != null ? p.taxa_entregador : p.taxa_plataforma,
            ),
            valor_liquido_entregador: numeroSeguro(
                p.valor_liquido_entregador != null
                    ? p.valor_liquido_entregador
                    : numeroSeguro(p.taxa_entrega) - numeroSeguro(p.taxa_entregador),
            ),
            tipo_corrida: String(p.tipo_entrega || "entrega"),
        };

        if (!tokenValido) return;

        if (status !== "entregue") {
            t.update(ref, {
                status: "entregue",
                data_entregue: admin.firestore.FieldValue.serverTimestamp(),
                entrega_token_validado_em: admin.firestore.FieldValue.serverTimestamp(),
                entrega_confirmada_por_uid: uid,
            });
        }
    });

    if (!tokenValido) {
        return {
            ok: true,
            tokenValido: false,
            mensagem: "Token inválido. Confira o código de 6 dígitos do cliente.",
        };
    }

    const proxima = await buscarProximaCorridaAtiva(db, uid, pedidoId);
    return {
        ok: true,
        tokenValido: true,
        mensagem: "Entrega confirmada com sucesso.",
        ...resumo,
        tem_proxima_corrida: !!proxima,
        proxima_corrida_id: proxima ? proxima.id : "",
    };
});

/**
 * Entregador cancela corrida já aceita e força novo despacho excluindo a si mesmo.
 * Mantém experiência estilo apps de mobilidade: segue para próximos entregadores.
 */
exports.entregadorCancelarCorridaERedespachar = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
        }
        const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
        }

        const uid = context.auth.uid;
        const db = admin.firestore();
        const userRef = db.collection("users").doc(uid);
        const ref = db.collection("pedidos").doc(pedidoId);

        const snap0 = await ref.get();
        if (!snap0.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p0 = snap0.data() || {};
        const statusAtual = String(p0.status || "");

        if (statusAtual === "aguardando_entregador") {
            return { ok: true, jaLiberado: true };
        }

        const podeCancelar = [
            "entregador_indo_loja",
            "saiu_entrega",
            "em_rota",
            "a_caminho",
        ].includes(statusAtual);
        if (!podeCancelar) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Este pedido não está em uma etapa cancelável pelo entregador.",
            );
        }
        if (String(p0.entregador_id || "") !== String(uid)) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "A corrida não pertence ao entregador autenticado.",
            );
        }

        const lockOk = await db.runTransaction(async (t) => {
            const s = await t.get(ref);
            if (!s.exists) return false;
            const x = s.data() || {};
            const st = String(x.status || "");
            const pode = ["entregador_indo_loja", "saiu_entrega", "em_rota", "a_caminho"].includes(st);
            if (!pode) return false;
            if (String(x.entregador_id || "") !== String(uid)) return false;

            const recusadosAtuais = Array.isArray(x.despacho_recusados)
                ? x.despacho_recusados.map(String)
                : [];
            const recusadosComCancelador = Array.from(new Set([...recusadosAtuais, String(uid)]));

            t.update(ref, {
                status: "aguardando_entregador",
                cancelado_pelo_entregador: true,
                cancelado_pelo_entregador_uid: uid,
                cancelado_pelo_entregador_em: admin.firestore.FieldValue.serverTimestamp(),
                cancelado_pelo_entregador_status_anterior: st,

                entregador_id: admin.firestore.FieldValue.delete(),
                entregador_nome: admin.firestore.FieldValue.delete(),
                entregador_foto_url: admin.firestore.FieldValue.delete(),
                entregador_telefone: admin.firestore.FieldValue.delete(),
                entregador_veiculo: admin.firestore.FieldValue.delete(),
                entregador_aceito_em: admin.firestore.FieldValue.delete(),

                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_abort_flag: admin.firestore.FieldValue.delete(),
                despacho_fila_ids: [],
                despacho_indice_atual: 0,
                despacho_recusados: recusadosComCancelador,
                despacho_bloqueados: admin.firestore.FieldValue.arrayUnion(String(uid)),
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_oferta_seq: 0,
                despacho_oferta_estado: "reencaminhando_apos_cancelamento_entregador",
                despacho_estado: "aguardando_entregador",
                despacho_redespacho_entregador_em: admin.firestore.FieldValue.serverTimestamp(),
                despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
                despacho_redirecionado_para_proximo: admin.firestore.FieldValue.delete(),
                despacho_erro_msg: admin.firestore.FieldValue.delete(),
                busca_entregadores_notificados: [],
                despacho_auto_encerrada_sem_entregador: admin.firestore.FieldValue.delete(),
                despacho_msg_busca_entregador:
                    "Entrega cancelada pelo entregador. Buscando novo parceiro automaticamente.",
                despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
                busca_raio_km: admin.firestore.FieldValue.delete(),
                busca_entregador_inicio: admin.firestore.FieldValue.delete(),
            });
            t.set(userRef, {
                entregador_operacao_status: "DISPONIVEL",
                entregador_corridas_pendentes: 0,
                entregador_estado_operacao_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                entregador_estado_operacao_origem: "entregadorCancelarCorridaERedespachar",
                entregador_estado_operacao_pedido_id: pedidoId,
            }, { merge: true });
            return true;
        });

        if (!lockOk) {
            throw new functions.https.HttpsError(
                "aborted",
                "Não foi possível cancelar agora. Atualize a tela e tente novamente.",
            );
        }

        const fresh = (await ref.get()).data();
        await executarDespachoSequencial(ref, pedidoId, db, fresh);
        return { ok: true };
    });

/**
 * Entregador cancela corrida alegando que o produto é INCOMPATÍVEL com o
 * veículo ativo dele (ex.: geladeira/caixa volumosa quando está de moto).
 *
 * Diferenças vs. `entregadorCancelarCorridaERedespachar`:
 *   - NÃO penaliza o entregador (não entra em `despacho_bloqueados` no doc
 *     do pedido, não computa cancelamento "negativo" em métricas).
 *   - Registra o motivo no histórico do pedido e um alerta para o lojista
 *     revisar a configuração de `tipos_entrega_permitidos`.
 *   - Reabre a fila imediatamente e redespacha pra entregador compatível.
 *
 * A notificação push NÃO é alterada aqui — o fluxo padrão de redespacho
 * (`executarDespachoSequencial`) já dispara o FCM para o próximo entregador,
 * preservando a camada de notificações existente.
 */
exports.entregadorCancelarPorIncompatibilidade = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
        }
        const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
        }
        const observacaoRaw = data && data.observacao != null ? String(data.observacao) : "";
        const observacao = observacaoRaw.trim().slice(0, 400);

        const uid = context.auth.uid;
        const db = admin.firestore();
        const userRef = db.collection("users").doc(uid);
        const ref = db.collection("pedidos").doc(pedidoId);

        const snap0 = await ref.get();
        if (!snap0.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p0 = snap0.data() || {};
        const statusAtual = String(p0.status || "");

        const podeCancelar = [
            "aguardando_entregador",
            "entregador_indo_loja",
            "saiu_entrega",
            "em_rota",
            "a_caminho",
        ].includes(statusAtual);
        if (!podeCancelar) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Este pedido não está em uma etapa cancelável pelo entregador.",
            );
        }

        // Só exige ownership da corrida quando o pedido já foi aceito.
        if (statusAtual !== "aguardando_entregador" &&
            String(p0.entregador_id || "") !== String(uid)) {
            throw new functions.https.HttpsError(
                "permission-denied",
                "A corrida não pertence ao entregador autenticado.",
            );
        }

        // Busca dados do entregador para registrar tipo de veículo no histórico.
        const uSnap = await userRef.get();
        const ud = uSnap.exists ? uSnap.data() || {} : {};
        const tipoEntregador = TIPOS_ENTREGA.normalizarTipoVeiculo(
            ud.tipo_veiculo_canonico || ud.veiculoTipo || ud.veiculo || ud.tipo_veiculo,
        );
        const tiposAceitosLoja = TIPOS_ENTREGA.normalizarLista(
            p0.tipos_entrega_permitidos_loja,
        );

        const eventoHist = {
            entregador_uid: String(uid),
            entregador_tipo_veiculo: tipoEntregador || "",
            tipos_aceitos_loja: tiposAceitosLoja,
            status_anterior: statusAtual,
            observacao,
            criado_em: admin.firestore.Timestamp.now(),
        };

        const lockOk = await db.runTransaction(async (t) => {
            const s = await t.get(ref);
            if (!s.exists) return false;
            const x = s.data() || {};
            const st = String(x.status || "");
            const podeAgora = [
                "aguardando_entregador",
                "entregador_indo_loja",
                "saiu_entrega",
                "em_rota",
                "a_caminho",
            ].includes(st);
            if (!podeAgora) return false;
            if (st !== "aguardando_entregador" &&
                String(x.entregador_id || "") !== String(uid)) {
                return false;
            }

            const recusadosAtuais = Array.isArray(x.despacho_recusados)
                ? x.despacho_recusados.map(String)
                : [];
            // Adiciona ao despacho_recusados para NÃO receber a mesma oferta de
            // novo (evita loop). NÃO entra em despacho_bloqueados — cancelamento
            // por incompatibilidade não é uma falha do entregador.
            const recusadosComCancelador = Array.from(
                new Set([...recusadosAtuais, String(uid)]),
            );

            // POLÍTICA (atualizada 04/2026):
            //   Cancelamento por incompatibilidade volta o pedido para
            //   `em_preparo` e devolve o controle ao LOJISTA. Sem re-despacho
            //   automático — o lojista precisa ver a mensagem, eventualmente
            //   revisar `tipos_entrega_permitidos`, e clicar "Solicitar
            //   entregador" novamente.
            //
            //   Antes (até 04/2026) o backend mantinha `aguardando_entregador`
            //   e re-despachava automático, o que escondia do lojista o sinal
            //   de que a categoria cadastrada não era adequada. Agora o
            //   lojista é confrontado com a mensagem e toma a decisão.
            t.update(ref, {
                status: "em_preparo",
                cancelamento_incompat_ultimo: eventoHist,
                cancelamentos_incompat_historico:
                    admin.firestore.FieldValue.arrayUnion(eventoHist),
                alerta_lojista_tipos_entrega: {
                    ativo: true,
                    motivo: "veiculo_incompativel",
                    entregador_tipo_veiculo: tipoEntregador || "",
                    tipos_aceitos_loja: tiposAceitosLoja,
                    mensagem:
                        "Um entregador cancelou esta corrida por " +
                        "incompatibilidade de veículo. Revise os Tipos de " +
                        "entrega aceitos pela sua loja (ex.: produto grande " +
                        "não cabe na moto) e solicite um novo entregador.",
                    criado_em: admin.firestore.FieldValue.serverTimestamp(),
                },

                entregador_id: admin.firestore.FieldValue.delete(),
                entregador_nome: admin.firestore.FieldValue.delete(),
                entregador_foto_url: admin.firestore.FieldValue.delete(),
                entregador_telefone: admin.firestore.FieldValue.delete(),
                entregador_veiculo: admin.firestore.FieldValue.delete(),
                entregador_aceito_em: admin.firestore.FieldValue.delete(),

                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_abort_flag: admin.firestore.FieldValue.delete(),
                despacho_fila_ids: [],
                despacho_indice_atual: 0,
                // Ainda marca este entregador como "recusado" desta corrida
                // para garantir que se o lojista chamar de novo, a fila o
                // evite e sele outra pessoa.
                despacho_recusados: recusadosComCancelador,
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_oferta_seq: 0,
                despacho_oferta_estado: admin.firestore.FieldValue.delete(),
                despacho_estado: admin.firestore.FieldValue.delete(),
                despacho_redespacho_entregador_em:
                    admin.firestore.FieldValue.serverTimestamp(),
                despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
                despacho_redirecionado_para_proximo:
                    admin.firestore.FieldValue.delete(),
                despacho_erro_msg: admin.firestore.FieldValue.delete(),
                busca_entregadores_notificados: [],
                // Aguarda decisão do lojista — `despacho_auto_encerrada_*`
                // dispara o mesmo banner amarelo que já usamos pra "busca
                // encerrada" no painel web do lojista.
                despacho_auto_encerrada_sem_entregador: true,
                despacho_msg_busca_entregador:
                    "Entrega cancelada pelo entregador por incompatibilidade " +
                    "de veículo. Revise os Tipos de entrega aceitos pela " +
                    "loja e clique em «Solicitar entregador» para chamar " +
                    "outra pessoa compatível.",
                despacho_aguarda_decisao_lojista:
                    admin.firestore.FieldValue.delete(),
                despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                despacho_busca_extensao_usada:
                    admin.firestore.FieldValue.delete(),
                busca_raio_km: admin.firestore.FieldValue.delete(),
                busca_entregador_inicio: admin.firestore.FieldValue.delete(),
            });

            // NÃO marca penalidade no entregador. Apenas libera operação.
            t.set(userRef, {
                entregador_operacao_status: "DISPONIVEL",
                entregador_corridas_pendentes: 0,
                entregador_estado_operacao_atualizado_em:
                    admin.firestore.FieldValue.serverTimestamp(),
                entregador_estado_operacao_origem:
                    "entregadorCancelarPorIncompatibilidade",
                entregador_estado_operacao_pedido_id: pedidoId,
                entregador_ultimo_cancelamento_incompat_em:
                    admin.firestore.FieldValue.serverTimestamp(),
                entregador_cancelamentos_incompat_total:
                    admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            return true;
        });

        if (!lockOk) {
            throw new functions.https.HttpsError(
                "aborted",
                "Não foi possível cancelar agora. Atualize a tela e tente novamente.",
            );
        }

        // Alerta agregado no doc do lojista (pra dashboard/tela de acompanhamento).
        try {
            const lojaId = lojaIdStr(p0);
            if (lojaId) {
                await db.collection("users").doc(String(lojaId)).set({
                    alerta_tipos_entrega_incompat: {
                        total_ultimos_30d: admin.firestore.FieldValue.increment(1),
                        ultimo_em: admin.firestore.FieldValue.serverTimestamp(),
                        ultimo_pedido_id: pedidoId,
                        ultimo_tipo_entregador: tipoEntregador || "",
                        ultimo_tipos_aceitos_loja: tiposAceitosLoja,
                    },
                }, { merge: true });
            }
        } catch (e) {
            console.warn("[cancelarIncompat] alerta loja falhou:", e);
        }

        // IMPORTANTE: não executamos `executarDespachoSequencial` aqui.
        //   Política nova: o lojista é quem decide re-solicitar entregador
        //   depois de ler a mensagem do cancelamento. Re-despacho automático
        //   mascarava o problema de categoria mal configurada.
        return {
            ok: true,
            motivo: "veiculo_incompativel",
            proximo_passo: "aguardando_lojista_solicitar_novamente",
        };
    });

/**
 * Lojista cancela o despacho em andamento e inicia nova fila (mesmo status).
 */
exports.lojistaRedespacharEntregador = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
        }
        const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
        }

        const tipoSolicitadoBruto = data && data.tipoEntregaSolicitado != null
            ? String(data.tipoEntregaSolicitado)
            : "";
        const tipoSolicitado = TIPOS_ENTREGA.normalizarTipoSolicitado(
            tipoSolicitadoBruto,
        );

        const uid = context.auth.uid;
        const db = admin.firestore();
        const ref = db.collection("pedidos").doc(pedidoId);

        const snap0 = await ref.get();
        if (!snap0.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p0 = snap0.data();
        await assertAuthEhLojaDoPedido(db, p0, uid);
        if (p0.status !== "aguardando_entregador") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "O pedido não está buscando entregador.",
            );
        }
        if (p0.entregador_id) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Já há entregador atribuído a este pedido.",
            );
        }

        const tiposAceitosLoja = await obterTiposEntregaDaLoja(db, p0);
        if (tipoSolicitado && tiposAceitosLoja.length > 0 &&
            !tiposAceitosLoja.includes(tipoSolicitado)) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `A categoria '${TIPOS_ENTREGA.rotulo(tipoSolicitado)}' não está ` +
                "marcada como aceita no perfil da sua loja.",
                {
                    motivo: "tipo_entrega_solicitado_fora_da_lista",
                    tipo_solicitado: tipoSolicitado,
                    tipos_aceitos_loja: tiposAceitosLoja,
                },
            );
        }
        if (!tipoSolicitado && tiposAceitosLoja.length > 1) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Sua loja aceita mais de um tipo de entrega. Escolha qual " +
                "categoria chamar antes de redespachar.",
                {
                    motivo: "tipo_entrega_solicitado_obrigatorio",
                    tipos_aceitos_loja: tiposAceitosLoja,
                },
            );
        }
        const tipoEfetivo = tipoSolicitado ||
            (tiposAceitosLoja.length === 1 ? tiposAceitosLoja[0] : "");

        const comLock = (await ref.get()).data();
        if (comLock && comLock.despacho_job_lock) {
            await ref.update({ despacho_abort_flag: true });
            for (let i = 0; i < 16; i++) {
                await sleep(1000);
                const cur = (await ref.get()).data();
                if (!cur || !cur.despacho_job_lock) break;
            }
        }

        const eventId = `redesp_loja_${uid}_${Date.now()}`;
        const lockOk = await db.runTransaction(async (t) => {
            const s = await t.get(ref);
            const x = s.data();
            if (!x || x.status !== "aguardando_entregador") return false;
            if (x.entregador_id) return false;
            if (x.despacho_job_lock) return false;
            const updates = {
                despacho_job_lock: eventId,
                despacho_recusados: [],
                despacho_bloqueados: [],
                despacho_fila_ids: [],
                despacho_indice_atual: 0,
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_oferta_seq: 0,
                busca_entregadores_notificados: [],
                despacho_abort_flag: admin.firestore.FieldValue.delete(),
                despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                despacho_auto_encerrada_sem_entregador: admin.firestore.FieldValue.delete(),
                despacho_msg_busca_entregador: admin.firestore.FieldValue.delete(),
                despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
                despacho_motivo_reversao: admin.firestore.FieldValue.delete(),
                despacho_estado: "redespacho_loja",
                despacho_redespacho_loja_em: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (tipoEfetivo) {
                updates.tipo_entrega_solicitado = tipoEfetivo;
                updates.tipo_entrega_solicitado_origem = tipoSolicitado
                    ? "lojista_redesp"
                    : "auto_tipo_unico_redesp";
                updates.tipo_entrega_solicitado_em =
                    admin.firestore.FieldValue.serverTimestamp();
            }
            t.update(ref, updates);
            return true;
        });

        if (!lockOk) {
            throw new functions.https.HttpsError(
                "aborted",
                "O sistema ainda está finalizando a busca anterior. Aguarde alguns segundos e tente de novo.",
            );
        }

        const fresh = (await ref.get()).data();
        await executarDespachoSequencial(ref, pedidoId, db, fresh);
        return { ok: true };
    });

/**
 * Lojista cancela a busca: aborta o job em andamento (se houver) e volta o pedido
 * para em_preparo (botão "Solicitar entregador" de novo), sem reiniciar a fila.
 */
exports.lojistaCancelarChamadaEntregador = functions
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
        try {
            if (!context.auth) {
                throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
            }
            const payload = data || {};
            const pedidoId = payload.pedidoId ? String(payload.pedidoId).trim() : "";
            if (!pedidoId) {
                throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
            }
            const uid = context.auth.uid;
            const db = admin.firestore();
            const ref = db.collection("pedidos").doc(pedidoId);

            const snap0 = await ref.get();
            if (!snap0.exists) {
                throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
            }
            const p0 = snap0.data();
            await assertAuthEhLojaDoPedido(db, p0, uid);
            if (p0.status !== "aguardando_entregador") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "O pedido não está buscando entregador.",
                );
            }
            if (p0.entregador_id) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Já há entregador atribuído a este pedido.",
                );
            }

            const comLock = (await ref.get()).data();
            if (comLock && comLock.despacho_job_lock) {
                await ref.update({ despacho_abort_flag: true });
                for (let i = 0; i < 30; i++) {
                    await sleep(1000);
                    const cur = (await ref.get()).data();
                    if (!cur || !cur.despacho_job_lock) break;
                }
            }

            const ainda = (await ref.get()).data();
            if (!ainda || ainda.status !== "aguardando_entregador") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "O estado do pedido mudou. Atualize a tela.",
                );
            }
            if (ainda.entregador_id) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Já há entregador atribuído a este pedido.",
                );
            }
            if (ainda.despacho_job_lock) {
                throw new functions.https.HttpsError(
                    "aborted",
                    "O sistema ainda está finalizando a busca. Aguarde alguns segundos e tente de novo.",
                );
            }

            const limpar = {
                status: "em_preparo",
                despacho_job_lock: admin.firestore.FieldValue.delete(),
                despacho_abort_flag: admin.firestore.FieldValue.delete(),
                despacho_fila_ids: [],
                despacho_indice_atual: 0,
                despacho_recusados: [],
                despacho_bloqueados: [],
                despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                despacho_oferta_seq: 0,
                despacho_oferta_estado: admin.firestore.FieldValue.delete(),
                despacho_estado: admin.firestore.FieldValue.delete(),
                despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
                despacho_redespacho_loja_em: admin.firestore.FieldValue.delete(),
                despacho_redespacho_entregador_em: admin.firestore.FieldValue.delete(),
                despacho_redirecionado_para_proximo: admin.firestore.FieldValue.delete(),
                despacho_erro_msg: admin.firestore.FieldValue.delete(),
                despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                despacho_msg_busca_entregador: admin.firestore.FieldValue.delete(),
                despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
                despacho_auto_encerrada_sem_entregador: admin.firestore.FieldValue.delete(),
                busca_entregadores_notificados: [],
                busca_raio_km: admin.firestore.FieldValue.delete(),
                busca_entregador_inicio: admin.firestore.FieldValue.delete(),
            };

            try {
                await ref.update(limpar);
            } catch (fireErr) {
                console.error("[lojistaCancelarChamadaEntregador] ref.update", fireErr);
                const fm = fireErr && fireErr.message ? String(fireErr.message) : String(fireErr);
                throw new functions.https.HttpsError(
                    "internal",
                    `Não foi possível atualizar o pedido: ${fm}`,
                );
            }
            return { ok: true };
        } catch (e) {
            if (e instanceof functions.https.HttpsError) {
                throw e;
            }
            console.error("[lojistaCancelarChamadaEntregador]", e);
            const msg = e && e.message ? String(e.message) : String(e);
            throw new functions.https.HttpsError("internal", `Erro ao cancelar: ${msg}`);
        }
    });

/**
 * Lojista — após pausa automática (5 ciclos 3→5 km), continua a busca por mais 5 ciclos iguais.
 */
exports.lojistaContinuarBuscaEntregadores = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
        }
        const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
        }
        const authUid = context.auth.uid;
        const db = admin.firestore();
        const ref = db.collection("pedidos").doc(pedidoId);

        const snap0 = await ref.get();
        if (!snap0.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p0 = snap0.data();
        await assertAuthEhLojaDoPedido(db, p0, authUid);
        if (p0.status !== "aguardando_entregador") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "O pedido não está buscando entregador.",
            );
        }
        if (p0.entregador_id) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Já há entregador atribuído a este pedido.",
            );
        }
        if (!p0.despacho_aguarda_decisao_lojista) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Não há pausa de busca pendente para este pedido.",
            );
        }
        // Lock residual (timeout/crash do job anterior) bloqueava estes botões na UI.
        let curData = (await ref.get()).data() || {};
        if (curData.despacho_job_lock) {
            await ref.update({ despacho_abort_flag: true });
            for (let i = 0; i < 30; i++) {
                await sleep(1000);
                curData = (await ref.get()).data() || {};
                if (!curData.despacho_job_lock) break;
            }
        }
        if (curData.status !== "aguardando_entregador") {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "O estado do pedido mudou. Atualize a tela.",
            );
        }
        if (curData.entregador_id) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Já há entregador atribuído a este pedido.",
            );
        }
        if (!curData.despacho_aguarda_decisao_lojista) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Não há pausa de busca pendente para este pedido.",
            );
        }
        if (curData.despacho_job_lock) {
            throw new functions.https.HttpsError(
                "aborted",
                "O sistema ainda está finalizando a busca anterior. Aguarde ~30s e tente de novo.",
            );
        }

        const eventId = `cont_busca_${authUid}_${Date.now()}`;
        try {
            await db.runTransaction(async (t) => {
                const s = await t.get(ref);
                const x = s.data();
                if (!x || x.status !== "aguardando_entregador" || x.entregador_id) {
                    throw new Error("dip_invalid_state_continuar");
                }
                if (!x.despacho_aguarda_decisao_lojista) {
                    throw new Error("dip_sem_pausa");
                }
                if (x.despacho_job_lock) {
                    throw new Error("dip_lock_ocupado");
                }
                t.update(ref, {
                    despacho_job_lock: eventId,
                    despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                    despacho_estado: "aguardando_entregador",
                    despacho_busca_extensao_usada: true,
                    despacho_msg_busca_entregador:
                        "Buscando de novo: até 5 rodadas (3 km e 5 km). " +
                        "Se ninguém aceitar, a chamada encerra sozinha.",
                });
            });
        } catch (e) {
            if (e && e.message === "dip_invalid_state_continuar") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "O estado do pedido mudou. Atualize a tela.",
                );
            }
            if (e && e.message === "dip_sem_pausa") {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Não há pausa de busca pendente.",
                );
            }
            if (e && e.message === "dip_lock_ocupado") {
                throw new functions.https.HttpsError(
                    "aborted",
                    "Aguarde alguns segundos e tente de novo.",
                );
            }
            throw e;
        }

        const fresh = (await ref.get()).data();
        await executarDespachoSequencial(ref, pedidoId, db, fresh, "estendido");
        return { ok: true };
    });

/**
 * Lojista — «Solicitar entregador»: Admin SDK (ignora App Check / falhas de cliente no Firestore).
 * em_preparo → aguardando_entregador + despacho; aguardando_entregador → reinicia fila (como redespacho).
 */
exports.lojistaSolicitarDespachoEntregador = functions
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login novamente.");
        }
        const pedidoId = data && data.pedidoId ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new functions.https.HttpsError("invalid-argument", "pedidoId obrigatório.");
        }

        // Categoria explicitamente escolhida pelo lojista no painel. Pode vir
        // vazia para lojas com 1 único tipo aceito (auto-derivação backend).
        const tipoSolicitadoBruto = data && data.tipoEntregaSolicitado != null
            ? String(data.tipoEntregaSolicitado)
            : "";
        const tipoSolicitado = TIPOS_ENTREGA.normalizarTipoSolicitado(
            tipoSolicitadoBruto,
        );

        const authUid = context.auth.uid;
        const db = admin.firestore();
        const ref = db.collection("pedidos").doc(pedidoId);

        const snap0 = await ref.get();
        if (!snap0.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
        }
        const p0 = snap0.data();
        await assertAuthEhLojaDoPedido(db, p0, authUid);

        if (p0.entregador_id) {
            throw new functions.https.HttpsError("failed-precondition", "Já há entregador atribuído a este pedido.");
        }

        // Resolve a lista aceita pela loja já aqui pra validar a categoria
        // recebida e rejeitar lojas multi-tipo sem escolha — espelha o que
        // `notificarEntregadoresPedidoPronto` faria depois.
        const tiposAceitosLoja = await obterTiposEntregaDaLoja(db, p0);
        if (tiposAceitosLoja.length > 1 && !tipoSolicitado) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Sua loja aceita mais de um tipo de entrega. Escolha qual " +
                "categoria chamar (ex.: moto ou carro) e tente de novo.",
                {
                    motivo: "tipo_entrega_solicitado_obrigatorio",
                    tipos_aceitos_loja: tiposAceitosLoja,
                },
            );
        }
        if (tipoSolicitado && tiposAceitosLoja.length > 0 &&
            !tiposAceitosLoja.includes(tipoSolicitado)) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                `A categoria '${TIPOS_ENTREGA.rotulo(tipoSolicitado)}' não está ` +
                "marcada como aceita no perfil da sua loja. Atualize a configuração " +
                "antes de tentar novamente.",
                {
                    motivo: "tipo_entrega_solicitado_fora_da_lista",
                    tipo_solicitado: tipoSolicitado,
                    tipos_aceitos_loja: tiposAceitosLoja,
                },
            );
        }

        // Tipo efetivo: explícito se veio do cliente, ou único tipo aceito
        // como auto-derivação. Caso contrário (loja sem config) deixamos vazio
        // pra preservar o fallback legado dentro do dispatch.
        const tipoEfetivo = tipoSolicitado ||
            (tiposAceitosLoja.length === 1 ? tiposAceitosLoja[0] : "");

        const st = p0.status;

        if (st === "em_preparo") {
            const eventId = `sol_${authUid}_${Date.now()}`;
            try {
                await db.runTransaction(async (t) => {
                    const s = await t.get(ref);
                    const x = s.data();
                    if (!x || x.status !== "em_preparo" || x.entregador_id) {
                        throw new Error("dip_invalid_state_em_preparo");
                    }
                    const updates = {
                        status: "aguardando_entregador",
                        busca_raio_km: 0.5,
                        busca_entregador_inicio: admin.firestore.FieldValue.serverTimestamp(),
                        busca_entregadores_notificados: [],
                        despacho_job_lock: eventId,
                        despacho_estado: "aguardando_entregador",
                        despacho_abort_flag: admin.firestore.FieldValue.delete(),
                        despacho_fila_ids: [],
                        despacho_indice_atual: 0,
                        despacho_recusados: [],
                        despacho_bloqueados: [],
                        despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                        despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                        despacho_oferta_seq: 0,
                        despacho_oferta_estado: admin.firestore.FieldValue.delete(),
                        despacho_sem_entregadores: admin.firestore.FieldValue.delete(),
                        despacho_redespacho_loja_em: admin.firestore.FieldValue.delete(),
                        despacho_redespacho_entregador_em: admin.firestore.FieldValue.delete(),
                        despacho_redirecionado_para_proximo: admin.firestore.FieldValue.delete(),
                        despacho_erro_msg: admin.firestore.FieldValue.delete(),
                        despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                        despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                        despacho_msg_busca_entregador: admin.firestore.FieldValue.delete(),
                        despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
                        despacho_auto_encerrada_sem_entregador: admin.firestore.FieldValue.delete(),
                        despacho_motivo_reversao: admin.firestore.FieldValue.delete(),
                        // Limpa o alerta de incompatibilidade quando o lojista
                        // re-solicita (ou ele tomou ciência do problema ou já
                        // ajustou `tipos_entrega_permitidos`). Mantém o
                        // `cancelamento_incompat_ultimo` para histórico.
                        alerta_lojista_tipos_entrega: admin.firestore.FieldValue.delete(),
                    };
                    if (tipoEfetivo) {
                        updates.tipo_entrega_solicitado = tipoEfetivo;
                        updates.tipo_entrega_solicitado_origem = tipoSolicitado
                            ? "lojista_web"
                            : "auto_tipo_unico";
                        updates.tipo_entrega_solicitado_em =
                            admin.firestore.FieldValue.serverTimestamp();
                    }
                    t.update(ref, updates);
                });
            } catch (e) {
                if (e && e.message === "dip_invalid_state_em_preparo") {
                    throw new functions.https.HttpsError(
                        "failed-precondition",
                        "O pedido não está mais em preparo ou já tem entregador. Atualize a tela.",
                    );
                }
                throw e;
            }
            const fresh = (await ref.get()).data();
            await executarDespachoSequencial(ref, pedidoId, db, fresh);
            return { ok: true };
        }

        if (st === "aguardando_entregador") {
            const comLock = (await ref.get()).data();
            if (comLock && comLock.despacho_job_lock) {
                await ref.update({ despacho_abort_flag: true });
                for (let i = 0; i < 16; i++) {
                    await sleep(1000);
                    const cur = (await ref.get()).data();
                    if (!cur || !cur.despacho_job_lock) break;
                }
            }

            const eventId = `redesp_loja_${authUid}_${Date.now()}`;
            const lockOk = await db.runTransaction(async (t) => {
                const s = await t.get(ref);
                const x = s.data();
                if (!x || x.status !== "aguardando_entregador") return false;
                if (x.entregador_id) return false;
                if (x.despacho_job_lock) return false;
                const updates = {
                    despacho_job_lock: eventId,
                    despacho_recusados: [],
                    despacho_bloqueados: [],
                    despacho_fila_ids: [],
                    despacho_indice_atual: 0,
                    despacho_oferta_uid: admin.firestore.FieldValue.delete(),
                    despacho_oferta_expira_em: admin.firestore.FieldValue.delete(),
                    despacho_oferta_seq: 0,
                    busca_entregadores_notificados: [],
                    despacho_abort_flag: admin.firestore.FieldValue.delete(),
                    despacho_aguarda_decisao_lojista: admin.firestore.FieldValue.delete(),
                    despacho_macro_ciclo_atual: admin.firestore.FieldValue.delete(),
                    despacho_msg_busca_entregador: admin.firestore.FieldValue.delete(),
                    despacho_busca_extensao_usada: admin.firestore.FieldValue.delete(),
                    despacho_auto_encerrada_sem_entregador: admin.firestore.FieldValue.delete(),
                    despacho_motivo_reversao: admin.firestore.FieldValue.delete(),
                    despacho_estado: "redespacho_loja",
                    despacho_redespacho_loja_em: admin.firestore.FieldValue.serverTimestamp(),
                };
                if (tipoEfetivo) {
                    updates.tipo_entrega_solicitado = tipoEfetivo;
                    updates.tipo_entrega_solicitado_origem = tipoSolicitado
                        ? "lojista_web_redesp"
                        : "auto_tipo_unico_redesp";
                    updates.tipo_entrega_solicitado_em =
                        admin.firestore.FieldValue.serverTimestamp();
                }
                t.update(ref, updates);
                return true;
            });

            if (!lockOk) {
                throw new functions.https.HttpsError(
                    "aborted",
                    "O sistema ainda está finalizando a busca anterior. Aguarde alguns segundos e tente de novo.",
                );
            }

            const fresh = (await ref.get()).data();
            await executarDespachoSequencial(ref, pedidoId, db, fresh);
            return { ok: true };
        }

        throw new functions.https.HttpsError(
            "failed-precondition",
            "Coloque o pedido em preparo antes de solicitar entregador.",
        );
    });

exports.expandirBuscaEntregador = functions.pubsub
    .schedule("every 1 minutes")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        return null;
    });
