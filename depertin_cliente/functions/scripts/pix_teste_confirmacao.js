/**
 * Teste PIX real — Gestão Comercial (Payments API = marketplace DiPertin)
 *
 * Cria cobrança, abre página com QR + polling e confirma pagamento no terminal.
 *
 * Uso:
 *   cd depertin_cliente/functions
 *   set MP_GC_TEST_TOKEN=APP_USR-seu-token-da-loja
 *   node scripts/pix_teste_confirmacao.js
 *
 * Opções:
 *   --token APP_USR-...     Access Token Mercado Pago da loja
 *   --valor 0.10            Valor da cobrança (padrão 0.10)
 *   --port 8777             Porta do servidor local
 *   --sem-abrir             Não abre o navegador
 *   --poll ID               Só consulta status de um payment_id existente
 */

"use strict";

const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const MP_API = "https://api.mercadopago.com";
const SCRIPTS_DIR = __dirname;
const REF_FILE = path.join(SCRIPTS_DIR, "pix_teste_confirmacao_referencia.json");
const HTML_FILE = path.join(SCRIPTS_DIR, "pix_teste_confirmacao.html");

const { analisarCopiaColaPixApi } = require("../pix_emv_validacao");

// ── CLI ─────────────────────────────────────────────────────────────────────

function loadTokenFromDevFallback() {
    /** Somente dev local: lê token do script legado se MP_GC_TEST_TOKEN não estiver no .env */
    const legado = path.join(SCRIPTS_DIR, "criar_pix_teste_corrigido.js");
    if (!fs.existsSync(legado)) return null;
    try {
        const txt = fs.readFileSync(legado, "utf8");
        const m = txt.match(/ACCESS_TOKEN\s*=\s*"((?:APP_USR|TEST-)[^"]+)"/);
        return m ? m[1] : null;
    } catch (_) {
        return null;
    }
}

function parseArgs(argv) {
    const out = { valor: 0.1, port: 8777, abrir: true, pollId: null, token: null };
    for (let i = 2; i < argv.length; i++) {
        const a = argv[i];
        if (a === "--token" && argv[i + 1]) {
            out.token = argv[++i];
        } else if (a === "--valor" && argv[i + 1]) {
            out.valor = Number(argv[++i]) || 0.1;
        } else if (a === "--port" && argv[i + 1]) {
            out.port = Number(argv[++i]) || 8777;
        } else if (a === "--sem-abrir") {
            out.abrir = false;
        } else if (a === "--poll" && argv[i + 1]) {
            out.pollId = String(argv[++i]).trim();
        }
    }
    out.token =
        out.token ||
        process.env.MP_GC_TEST_TOKEN ||
        process.env.MP_ACCESS_TOKEN ||
        loadTokenFromDevFallback() ||
        null;
    return out;
}

function httpRequest(url, options, body) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        const transport = urlObj.protocol === "https:" ? https : http;
        const req = transport.request(
            url,
            {
                method: options.method || "GET",
                headers: options.headers || { "Content-Type": "application/json" },
            },
            (res) => {
                let data = "";
                res.on("data", (c) => (data += c));
                res.on("end", () => {
                    let parsed;
                    try {
                        parsed = JSON.parse(data);
                    } catch (_) {
                        parsed = data;
                    }
                    resolve({
                        ok: res.statusCode >= 200 && res.statusCode < 300,
                        status: res.statusCode,
                        data: parsed,
                    });
                });
            }
        );
        req.on("error", reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

async function consultarPagamentoMp(accessToken, paymentId) {
    const resp = await httpRequest(MP_API + "/v1/payments/" + encodeURIComponent(String(paymentId)), {
        method: "GET",
        headers: { Authorization: "Bearer " + accessToken },
    });
    if (!resp.ok) {
        throw new Error("GET /v1/payments/" + paymentId + " → HTTP " + resp.status + ": " + JSON.stringify(resp.data));
    }
    return resp.data;
}

/**
 * Payload idêntico ao marketplace (mpCriarPagamentoPix) e ao GC (payment_gateway_provider).
 */
async function criarCobrancaPixMarketplace(accessToken, valor) {
    const cobrancaId = "gc_test_" + Date.now() + "_" + Math.random().toString(36).substring(2, 6);
    const externalRef = "gc_confirm_" + cobrancaId;
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
    const refSlug = externalRef.replace(/[^a-zA-Z0-9]/g, "").substring(0, 12);

    const payload = {
        transaction_amount: Math.round(valor * 100) / 100,
        description: "DiPertin GC - teste confirmacao " + new Date().toISOString(),
        payment_method_id: "pix",
        payer: { email: "pg." + refSlug + "@pg.dipertin.com.br" },
        external_reference: externalRef,
        // Marketplace (mpCriarPagamentoPix) NÃO envia date_of_expiration — MP define a validade.
    };

    console.log("\n[POST /v1/payments] Payload (marketplace):");
    console.log(JSON.stringify(payload, null, 2));

    const resp = await httpRequest(
        MP_API + "/v1/payments",
        {
            method: "POST",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
                "X-Idempotency-Key": cobrancaId,
            },
        },
        payload
    );

    if (!resp.ok) {
        console.error("\n[ERRO MP]", JSON.stringify(resp.data, null, 2));
        throw new Error("Falha ao criar PIX: HTTP " + resp.status);
    }

    const d = resp.data;
    const tx = (d.point_of_interaction && d.point_of_interaction.transaction_data) || {};
    const qrCode = String(tx.qr_code || "");
    const qrBase64 = String(tx.qr_code_base64 || "");

    const br = analisarCopiaColaPixApi(qrCode, { exigirPixDinamico: true });

    console.log("\n[Resposta MP] id=", d.id, "status=", d.status, "detail=", d.status_detail);
    console.log("[Validação EMV DiPertin]", br.ok ? "OK" : "FALHOU", br.codigo || "", br.motivo || "");

    if (!qrCode || !qrBase64) {
        throw new Error("MP não retornou qr_code ou qr_code_base64.");
    }

    const ref = {
        payment_id: d.id,
        external_reference: externalRef,
        cobranca_id: cobrancaId,
        valor,
        status: d.status,
        status_detail: d.status_detail,
        qr_code: qrCode,
        qr_code_base64: qrBase64,
        ticket_url: tx.ticket_url || "",
        date_of_expiration: d.date_of_expiration || expiresAt,
        date_created: d.date_created,
        live_mode: d.live_mode,
        collector_id: d.collector_id,
        emv_validacao: br,
        criado_em: new Date().toISOString(),
        post_response: d,
    };

    fs.writeFileSync(REF_FILE, JSON.stringify(ref, null, 2));
    console.log("\nReferência salva:", REF_FILE);

    return ref;
}

function gerarHtml(ref) {
    const safe = JSON.stringify({
        paymentId: ref.payment_id,
        externalRef: ref.external_reference,
        valor: ref.valor,
        expiresAt: ref.date_of_expiration,
        qrCodeBase64: ref.qr_code_base64,
        pixCopiaECola: ref.qr_code,
        ticketUrl: ref.ticket_url || "",
        port: ref._port || 8777,
    });

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PIX Teste — Confirmação GC</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: #F5F4F8; min-height: 100vh; display: flex; align-items: center;
  justify-content: center; padding: 16px;
}
.card {
  background: #fff; border-radius: 24px; padding: 32px 28px; max-width: 480px; width: 100%;
  box-shadow: 0 8px 40px rgba(106,27,154,0.12); text-align: center;
}
h1 { font-size: 22px; color: #1A1A2E; margin-bottom: 4px; }
.sub { color: #64748B; font-size: 14px; margin-bottom: 20px; }
.badge {
  display: inline-block; padding: 6px 16px; border-radius: 20px; font-size: 13px;
  font-weight: 600; margin-bottom: 16px;
}
.badge.aguardando { background: #FFF3E0; color: #FF8F00; }
.badge.aprovado { background: #E8F5E9; color: #16A34A; }
.badge.erro { background: #FEF2F2; color: #DC2626; }
.qr-wrap {
  border: 3px solid #6A1B9A; border-radius: 20px; padding: 14px;
  display: inline-block; margin-bottom: 16px;
}
.qr-wrap img { width: 260px; height: 260px; display: block; }
.timer { font-size: 28px; font-weight: 800; color: #6A1B9A; margin: 8px 0 16px; font-variant-numeric: tabular-nums; }
.copy {
  background: #F5F4F8; border-radius: 12px; padding: 12px; font-family: monospace;
  font-size: 11px; word-break: break-all; text-align: left; margin-bottom: 12px;
  max-height: 80px; overflow: auto;
}
.btn {
  background: #6A1B9A; color: #fff; border: none; border-radius: 12px;
  padding: 14px; width: 100%; font-size: 15px; font-weight: 600; cursor: pointer; margin-bottom: 8px;
}
.btn:hover { background: #4A148C; }
.btn.ok { background: #16A34A; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; text-align: left; margin-top: 16px; }
.cell { background: #F5F4F8; padding: 10px 12px; border-radius: 10px; }
.cell .l { font-size: 10px; color: #64748B; text-transform: uppercase; }
.cell .v { font-size: 13px; font-weight: 600; color: #1A1A2E; margin-top: 2px; word-break: break-all; }
.cell.full { grid-column: 1 / -1; }
.log {
  margin-top: 16px; padding: 12px; background: #1A1A2E; border-radius: 12px;
  color: #94A3B8; font-family: monospace; font-size: 11px; text-align: left;
  max-height: 140px; overflow-y: auto;
}
.success-panel { display: none; padding: 20px 0; }
.success-panel.show { display: block; }
.success-panel .icon {
  width: 64px; height: 64px; background: linear-gradient(135deg,#6A1B9A,#FF8F00);
  border-radius: 50%; display: flex; align-items: center; justify-content: center;
  margin: 0 auto 16px; font-size: 32px;
}
</style>
</head>
<body>
<div class="card">
  <h1>PIX Teste — Gestão Comercial</h1>
  <p class="sub">Payments API (igual marketplace) · confirmação em tempo real</p>

  <div id="painelAguardando">
    <div class="badge aguardando" id="badge">Aguardando pagamento</div>
    <div class="timer" id="timer">05:00</div>
    <div class="qr-wrap"><img id="qr" alt="QR PIX"></div>
    <p style="font-size:13px;color:#64748B;margin-bottom:12px">Escaneie ou use copia e cola</p>
    <div class="copy" id="copia"></div>
    <button class="btn" type="button" id="btnCopiar">Copiar código PIX</button>
  </div>

  <div class="success-panel" id="painelSucesso">
    <div class="icon">✓</div>
    <h2 style="color:#16A34A;margin-bottom:8px">Pagamento confirmado!</h2>
    <p style="color:#64748B;font-size:14px" id="msgSucesso">Status approved no Mercado Pago.</p>
  </div>

  <div class="success-panel" id="painelErro">
    <div class="icon" style="background:linear-gradient(135deg,#DC2626,#FF8F00)">✕</div>
    <h2 style="color:#DC2626;margin-bottom:8px" id="tituloErro">Pagamento não concluído</h2>
    <p style="color:#64748B;font-size:14px" id="msgErro"></p>
  </div>

  <div class="grid">
    <div class="cell"><div class="l">Payment ID</div><div class="v" id="pid"></div></div>
    <div class="cell"><div class="l">Valor</div><div class="v" id="val"></div></div>
    <div class="cell full"><div class="l">Status MP</div><div class="v" id="st"></div></div>
    <div class="cell full"><div class="l">Status detail</div><div class="v" id="std"></div></div>
  </div>
  <div class="log" id="log">Iniciando polling…</div>
</div>
<script>
const PIX = ${safe};
const TERMINAIS = new Set(['approved','authorized','refunded','cancelled','rejected','charged_back']);
let segRestantes = 300;
let pollTimer = null;
let countdownTimer = null;

function fmtMoeda(v) { return 'R$ ' + Number(v).toFixed(2).replace('.', ','); }
function fmtTimer(s) {
  if (s <= 0) return '00:00';
  const m = String(Math.floor(s/60)).padStart(2,'0');
  const sec = String(s%60).padStart(2,'0');
  return m + ':' + sec;
}
function log(msg) {
  const el = document.getElementById('log');
  const t = new Date().toLocaleTimeString('pt-BR');
  el.textContent = t + ' — ' + msg + '\\n' + el.textContent.split('\\n').slice(0,12).join('\\n');
}

document.getElementById('qr').src = 'data:image/png;base64,' + PIX.qrCodeBase64;
document.getElementById('copia').textContent = PIX.pixCopiaECola;
document.getElementById('pid').textContent = PIX.paymentId;
document.getElementById('val').textContent = fmtMoeda(PIX.valor);
document.getElementById('btnCopiar').onclick = function() {
  navigator.clipboard.writeText(PIX.pixCopiaECola).then(function() {
    document.getElementById('btnCopiar').textContent = 'Copiado!';
    setTimeout(function(){ document.getElementById('btnCopiar').textContent = 'Copiar código PIX'; }, 2500);
  });
};

function mostrarSucesso(data) {
  document.getElementById('painelAguardando').style.display = 'none';
  document.getElementById('painelErro').classList.remove('show');
  document.getElementById('painelSucesso').classList.add('show');
  document.getElementById('badge').className = 'badge aprovado';
  document.getElementById('badge').textContent = 'Pagamento aprovado';
  document.getElementById('msgSucesso').textContent =
    'ID ' + data.id + ' · ' + (data.status_detail || 'accredited');
}
function mostrarErro(status, detail) {
  document.getElementById('painelAguardando').style.display = 'none';
  document.getElementById('painelSucesso').classList.remove('show');
  document.getElementById('painelErro').classList.add('show');
  document.getElementById('tituloErro').textContent =
    status === 'refunded' ? 'Estornado pelo Mercado Pago' : 'Status: ' + status;
  document.getElementById('msgErro').textContent = detail || '';
  document.getElementById('badge').className = 'badge erro';
  document.getElementById('badge').textContent = status;
}

async function poll() {
  try {
    const r = await fetch('/api/status?paymentId=' + encodeURIComponent(PIX.paymentId));
    const j = await r.json();
    document.getElementById('st').textContent = j.status || '—';
    document.getElementById('std').textContent = j.status_detail || '—';
    log('Poll: ' + j.status + ' / ' + (j.status_detail || ''));
    if (j.aprovado) {
      clearInterval(pollTimer);
      clearInterval(countdownTimer);
      mostrarSucesso(j.raw || { id: PIX.paymentId, status_detail: j.status_detail });
      return;
    }
    if (TERMINAIS.has(String(j.status || '').toLowerCase())) {
      clearInterval(pollTimer);
      clearInterval(countdownTimer);
      mostrarErro(j.status, j.status_detail);
    }
  } catch (e) {
    log('Erro poll: ' + e.message);
  }
}

countdownTimer = setInterval(function() {
  segRestantes--;
  document.getElementById('timer').textContent = fmtTimer(segRestantes);
  if (segRestantes <= 0) {
    clearInterval(countdownTimer);
    document.getElementById('timer').textContent = 'Expirado';
  }
}, 1000);

poll();
pollTimer = setInterval(poll, 3000);
</script>
</body>
</html>`;
}

function criarServidor(accessToken, ref, port) {
    ref._port = port;
    fs.writeFileSync(HTML_FILE, gerarHtml(ref));

    const server = http.createServer(async (req, res) => {
        const url = new URL(req.url, "http://127.0.0.1:" + port);

        if (url.pathname === "/api/status") {
            const paymentId = url.searchParams.get("paymentId") || ref.payment_id;
            try {
                const data = await consultarPagamentoMp(accessToken, paymentId);
                const st = String(data.status || "").toLowerCase();
                res.writeHead(200, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
                res.end(
                    JSON.stringify({
                        ok: true,
                        status: data.status,
                        status_detail: data.status_detail,
                        aprovado: st === "approved" || st === "authorized",
                        raw: {
                            id: data.id,
                            status: data.status,
                            status_detail: data.status_detail,
                            transaction_amount: data.transaction_amount,
                            date_approved: data.date_approved,
                        },
                    })
                );
            } catch (e) {
                res.writeHead(500, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ ok: false, erro: String(e.message || e) }));
            }
            return;
        }

        if (url.pathname === "/" || url.pathname === "/index.html") {
            res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
            res.end(fs.readFileSync(HTML_FILE));
            return;
        }

        res.writeHead(404);
        res.end("Not found");
    });

    return new Promise((resolve) => {
        server.listen(port, "127.0.0.1", () => {
            console.log("\nServidor local: http://127.0.0.1:" + port + "/");
            console.log("HTML:", HTML_FILE);
            resolve(server);
        });
    });
}

function abrirNavegador(url) {
    const plat = process.platform;
    if (plat === "win32") {
        const tried = [
            ["cmd", ["/c", "start", "msedge", url]],
            ["cmd", ["/c", "start", "chrome", url]],
            ["cmd", ["/c", "start", "", url]],
            ["powershell", ["-NoProfile", "-Command", "Start-Process", url]],
        ];
        for (const [cmd, cmdArgs] of tried) {
            try {
                spawn(cmd, cmdArgs, { detached: true, stdio: "ignore", shell: false }).unref();
                return;
            } catch (_) {}
        }
        return;
    }
    if (plat === "darwin") {
        spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
    } else {
        spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).unref();
    }
}

function abrirHtmlLocal(htmlPath) {
    const fileUrl = "file:///" + htmlPath.replace(/\\/g, "/");
    abrirNavegador(fileUrl);
}

function simularConfirmacaoGc(payment) {
    console.log("\n" + "=".repeat(72));
    console.log(">>> CONFIRMAÇÃO SIMULADA (Gestão Comercial)");
    console.log("=".repeat(72));
    console.log("  Webhook/polling detectaria: status = approved");
    console.log("  Ações equivalentes no backend:");
    console.log("    1. gestao_comercial_cobrancas / cobrancas_pix_crediario → status approved");
    console.log("    2. processarConfirmacaoPagamentoGestaoComercial(paymentId)");
    console.log("    3. Baixa parcelas + recebimento + atualização saldo cliente");
    console.log("  payment_id:", payment.id);
    console.log("  valor:", payment.transaction_amount);
    console.log("  aprovado_em:", payment.date_approved || payment.date_last_updated);
    console.log("  external_reference:", payment.external_reference);
    console.log("=".repeat(72) + "\n");
}

async function pollTerminal(accessToken, paymentId, intervalMs, criadoEmMs) {
    let ultimoStatus = "";
    let resolvido = false;
    const terminais = new Set(["approved", "authorized", "refunded", "cancelled", "rejected", "charged_back"]);
    const criado = criadoEmMs || Date.now();

    return new Promise((resolve) => {
        const finalizar = (resultado) => {
            if (resolvido) return;
            resolvido = true;
            clearInterval(intervalId);
            clearTimeout(timeoutId);
            resolve(resultado);
        };

        const tick = async () => {
            const data = await consultarPagamentoMp(accessToken, paymentId);
            const st = String(data.status || "").toLowerCase();
            const detail = String(data.status_detail || "").toLowerCase();
            const segDesdeCriacao = (Date.now() - criado) / 1000;

            if (st !== ultimoStatus) {
                ultimoStatus = st;
                console.log("\n[GET /v1/payments/" + paymentId + "] status=" + st + " detail=" + detail);
                if (st === "pending" || st === "in_process") {
                    console.log("  → Aguardando pagamento… (" + Math.floor(segDesdeCriacao) + "s)");
                } else {
                    console.log(JSON.stringify(data, null, 2));
                }
            }

            if (st === "approved" || st === "authorized") {
                simularConfirmacaoGc(data);
                finalizar({ ok: true, status: st, data });
                return;
            }

            // cancelled/expired antes de 4,5 min: MP pode oscilar — manter servidor e QR abertos
            if ((st === "cancelled" || st === "rejected" || st === "refunded") && segDesdeCriacao < 270) {
                if (detail === "expired" && segDesdeCriacao < 270) {
                    console.warn(
                        "  [aviso] MP retornou cancelled/expired cedo (" +
                            Math.floor(segDesdeCriacao) +
                            "s). Mantendo página aberta até 5 min — tente pagar pelo QR/copia e cola."
                    );
                }
                return;
            }

            if (terminais.has(st)) {
                console.log("\n[FINAL] Status terminal:", st, "—", data.status_detail);
                finalizar({ ok: false, status: st, data });
            }
        };

        tick().catch((e) => console.warn("[poll]", e.message || e));
        const intervalId = setInterval(() => {
            tick().catch((e) => console.warn("[poll]", e.message || e));
        }, intervalMs);

        const timeoutId = setTimeout(() => {
            console.log("\n[TIMEOUT] 6 minutos — encerrando polling no terminal.");
            finalizar({ ok: false, status: "timeout" });
        }, 6 * 60 * 1000);
    });
}

async function main() {
    const args = parseArgs(process.argv);

    if (!args.token) {
        console.error(
            "Informe o Access Token da loja:\n" +
                "  set MP_GC_TEST_TOKEN=APP_USR-...\n" +
                "  node scripts/pix_teste_confirmacao.js\n" +
                "  ou: node scripts/pix_teste_confirmacao.js --token APP_USR-..."
        );
        process.exit(1);
    }

    if (args.pollId) {
        console.log("Consultando payment_id:", args.pollId);
        const data = await consultarPagamentoMp(args.token, args.pollId);
        console.log(JSON.stringify(data, null, 2));
        if (data.status === "approved" || data.status === "authorized") {
            simularConfirmacaoGc(data);
        }
        process.exit(0);
    }

    console.log("=".repeat(72));
    console.log("TESTE PIX + CONFIRMAÇÃO — Gestão Comercial (Payments API)");
    console.log("Valor: R$", args.valor.toFixed(2));
    console.log("=".repeat(72));

    const ref = await criarCobrancaPixMarketplace(args.token, args.valor);

    console.log("\n--- Copia e cola ---");
    console.log(ref.qr_code);
    console.log("--- Payment ID:", ref.payment_id, "---\n");

    await criarServidor(args.token, ref, args.port);

    const url = "http://127.0.0.1:" + args.port + "/";
    if (args.abrir) {
        // Aguarda servidor subir antes de abrir o navegador
        await new Promise((r) => setTimeout(r, 800));
        abrirNavegador(url);
        await new Promise((r) => setTimeout(r, 400));
        abrirHtmlLocal(HTML_FILE);
        console.log("Navegador aberto:", url);
        console.log("Fallback HTML:", HTML_FILE);
    } else {
        console.log("Abra manualmente:", url);
    }

    console.log("\nAguardando pagamento (polling a cada 3s no terminal)…");
    console.log("Pague o QR na página ou copie o código acima.");
    console.log("Servidor ativo por até 6 min. Ctrl+C para encerrar.\n");

    const criadoEmMs = Date.now();
    const resultado = await pollTerminal(args.token, ref.payment_id, 3000, criadoEmMs);

    if (resultado.ok) {
        console.log("✓ Teste concluído com pagamento CONFIRMADO.");
    } else {
        console.log("✗ Teste encerrado sem confirmação. Status:", resultado.status);
    }
    console.log("Encerrando servidor.");
    process.exit(resultado.ok ? 0 : 0);
}

main().catch((err) => {
    console.error("ERRO:", err.message || err);
    process.exit(1);
});
