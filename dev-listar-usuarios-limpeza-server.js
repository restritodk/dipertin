/**
 * ⚠️ FERRAMENTA DE DESENVOLVIMENTO — NÃO VAI PARA PRODUÇÃO
 *
 * Uso: execute dev-iniciar-limpeza.ps1 (ou node dev-listar-usuarios-limpeza-server.js)
 * Abra: http://127.0.0.1:8765  ou  http://localhost:8765
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const { exec } = require('child_process');

const PORT = Number(process.env.DEV_LIMPEZA_PORT || 8765);
const HOST = '127.0.0.1';
const KEEP_EMAIL = (
  process.env.DIPERTIN_KEEP_EMAIL || 'master@teste.com'
).trim().toLowerCase();
const KEEP_PASSWORD = process.env.DIPERTIN_KEEP_PASSWORD || 'master';
const PROJECT_ID = 'depertin-f940f';

const FUNCTIONS_DIR = path.join(__dirname, 'depertin_cliente', 'functions');
const HTML_FILE = path.join(__dirname, 'dev-listar-usuarios-limpeza.html');

// eslint-disable-next-line import/no-dynamic-require, global-require
const admin = require(path.join(FUNCTIONS_DIR, 'node_modules', 'firebase-admin'));
// eslint-disable-next-line import/no-dynamic-require, global-require
const limpezaTotal = require('./dev-limpeza-total-firestore');

function hostPermitido(hostHeader) {
  if (!hostHeader) return true;
  const host = hostHeader.split(':')[0].toLowerCase();
  return host === '127.0.0.1' || host === 'localhost' || host === '[::1]';
}

function inicializarFirebase() {
  if (admin.apps.length) return;
  const opts = { projectId: PROJECT_ID };
  try {
    opts.credential = admin.credential.applicationDefault();
  } catch (e) {
    console.warn('Credential applicationDefault:', e.message);
  }
  admin.initializeApp(opts);
}

try {
  inicializarFirebase();
} catch (e) {
  console.error('Falha ao inicializar Firebase Admin:', e.message);
  console.error('Defina GOOGLE_APPLICATION_CREDENTIALS com o caminho do serviceAccount.json');
}

const auth = admin.auth();
const db = admin.firestore();

function json(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(body));
}

function sseEvent(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8');
        resolve(raw ? JSON.parse(raw) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function roleGrupo(role) {
  const r = String(role || '').trim().toLowerCase();
  if (r === 'cliente') return 'cliente';
  if (r === 'lojista') return 'lojista';
  if (r === 'entregador') return 'entregador';
  return 'outros';
}

function docParaUsuario(doc, authMap) {
  const d = doc.data() || {};
  const uid = doc.id;
  const authUser = authMap.get(uid);
  const email = (d.email || d.email_contato || authUser?.email || '')
    .trim()
    .toLowerCase();
  const role = String(d.role || d.tipoUsuario || '—').trim();
  return {
    uid,
    email: email || '(sem e-mail)',
    nome:
      d.nome ||
      d.nome_completo ||
      d.nome_loja ||
      d.loja_nome ||
      authUser?.displayName ||
      '—',
    role,
    grupo: roleGrupo(role),
    cidade: d.cidade || d.endereco_cidade || '—',
    statusLoja: d.status_loja || null,
    statusEntregador: d.entregador_status || null,
    criadoEm: d.criado_em?.toDate?.()?.toISOString?.() || null,
    ehPreservado: email === KEEP_EMAIL,
    existeNoAuth: authMap.has(uid),
  };
}

async function carregarAuthMap() {
  const map = new Map();
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    res.users.forEach((u) => {
      map.set(u.uid, {
        email: u.email,
        displayName: u.displayName,
        disabled: u.disabled,
        creationTime: u.metadata?.creationTime || null,
      });
    });
    pageToken = res.pageToken;
  } while (pageToken);
  return map;
}

async function listarUsuarios() {
  const authMap = await carregarAuthMap();
  const snap = await db.collection('users').get();

  const grupos = { cliente: [], lojista: [], entregador: [], outros: [] };

  snap.docs
    .map((doc) => docParaUsuario(doc, authMap))
    .sort((a, b) => a.email.localeCompare(b.email, 'pt-BR'))
    .forEach((u) => grupos[u.grupo].push(u));

  authMap.forEach((info, uid) => {
    if (!snap.docs.some((d) => d.id === uid)) {
      grupos.outros.push({
        uid,
        email: info.email || '(sem e-mail)',
        nome: info.displayName || '—',
        role: '—',
        grupo: 'outros',
        cidade: '—',
        statusLoja: null,
        statusEntregador: null,
        criadoEm: info.creationTime,
        ehPreservado: (info.email || '').trim().toLowerCase() === KEEP_EMAIL,
        existeNoAuth: true,
        soAuth: true,
      });
    }
  });

  return {
    keepEmail: KEEP_EMAIL,
    projectId: PROJECT_ID,
    totais: {
      firestore: snap.size,
      auth: authMap.size,
      cliente: grupos.cliente.length,
      lojista: grupos.lojista.length,
      entregador: grupos.entregador.length,
      outros: grupos.outros.length,
    },
    grupos,
  };
}

async function apagarSelecionados(uids) {
  let keepUid = null;
  try {
    keepUid = (await auth.getUserByEmail(KEEP_EMAIL)).uid;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  const filtrados = uids.filter((uid) => uid && uid !== keepUid);
  let authOk = 0;
  let authFalha = 0;
  let firestoreOk = 0;

  for (const uid of filtrados) {
    try {
      await auth.deleteUser(uid);
      authOk += 1;
    } catch (e) {
      if (e.code !== 'auth/user-not-found') authFalha += 1;
    }
    try {
      await db.collection('users').doc(uid).delete();
      firestoreOk += 1;
    } catch (_) {
      /* ignora */
    }
  }

  return { authOk, authFalha, firestoreOk, ignoradosPreservado: uids.length - filtrados.length };
}

async function executarWipeComStream(res, dryRun, body) {
  if (!dryRun) {
    if (body.confirmacao !== 'SIM APAGAR MARKETPLACE INTEIRO') {
      json(res, 400, {
        erro: 'Confirmação inválida. Digite: SIM APAGAR MARKETPLACE INTEIRO',
      });
      return;
    }
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
  });
  res.write(': conectado\n\n');

  const send = (event, data) => {
    try {
      sseEvent(res, event, data);
    } catch (_) {
      /* cliente desconectou */
    }
  };

  send('etapas', { etapas: limpezaTotal.ETAPAS_UI });

  try {
    const result = await limpezaTotal.executarLimpezaTotal({
      auth,
      db,
      keepEmail: KEEP_EMAIL,
      keepPassword: KEEP_PASSWORD,
      dryRun,
      onProgress: (p) => send('progress', p),
      onLog: (msg) => send('log', { msg, ts: Date.now() }),
    });

    console.log(dryRun ? 'Dry-run concluído.' : 'Limpeza total concluída.');

    send('done', {
      ok: true,
      keepEmail: KEEP_EMAIL,
      senha: KEEP_PASSWORD,
      dryRun,
      keepUid: result.keepUid || null,
      etapas: result.etapas,
    });
  } catch (err) {
    console.error(err);
    send('error', {
      erro: err.message || String(err),
      dica: 'Verifique GOOGLE_APPLICATION_CREDENTIALS (service account JSON).',
    });
  }

  res.end();
}

const server = http.createServer(async (req, res) => {
  if (!hostPermitido(req.headers.host)) {
    json(res, 403, { erro: 'Acesso permitido apenas via localhost.' });
    return;
  }

  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  try {
    if (req.method === 'GET' && url.pathname === '/') {
      const html = fs.readFileSync(HTML_FILE, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/ping') {
      json(res, 200, {
        ok: true,
        projeto: PROJECT_ID,
        keepEmail: KEEP_EMAIL,
        credenciais: Boolean(
          process.env.GOOGLE_APPLICATION_CREDENTIALS ||
            process.env.GCLOUD_PROJECT ||
            fs.existsSync(
              path.join(
                process.env.APPDATA || '',
                'gcloud',
                'application_default_credentials.json',
              ),
            ),
        ),
        etapas: limpezaTotal.ETAPAS_UI,
      });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/usuarios') {
      const data = await listarUsuarios();
      json(res, 200, data);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/contagem-limpeza') {
      const data = await limpezaTotal.contarLimpeza(db, auth);
      json(res, 200, { keepEmail: KEEP_EMAIL, projectId: PROJECT_ID, ...data });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/wipe-stream') {
      const body = await readBody(req);
      await executarWipeComStream(res, body.dryRun === true, body);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/apagar-selecionados') {
      const body = await readBody(req);
      if (body.confirmacao !== 'APAGAR SELECIONADOS') {
        json(res, 400, { erro: 'Confirmação inválida.' });
        return;
      }
      const uids = Array.isArray(body.uids) ? body.uids : [];
      if (!uids.length) {
        json(res, 400, { erro: 'Nenhum UID selecionado.' });
        return;
      }
      const result = await apagarSelecionados(uids);
      json(res, 200, { ok: true, ...result });
      return;
    }

    json(res, 404, { erro: 'Rota não encontrada.' });
  } catch (err) {
    console.error(err);
    if (!res.headersSent) {
      json(res, 500, {
        erro: err.message || String(err),
        dica: 'Execute dev-iniciar-limpeza.ps1 na raiz do projeto.',
      });
    }
  }
});

server.listen(PORT, HOST, () => {
  const url = `http://127.0.0.1:${PORT}`;
  console.log('');
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  DiPertin — DEV limpeza total (NÃO PRODUÇÃO)');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`  URL:     ${url}`);
  console.log(`  Alt:     http://localhost:${PORT}`);
  console.log(`  Mantém:  ${KEEP_EMAIL}`);
  console.log(`  Projeto: ${PROJECT_ID}`);
  console.log(
    `  Cred:    ${process.env.GOOGLE_APPLICATION_CREDENTIALS ? 'OK' : 'FALTANDO — defina GOOGLE_APPLICATION_CREDENTIALS'}`,
  );
  console.log('');
  console.log('  NÃO feche esta janela enquanto usar o navegador.');
  console.log('  Ctrl+C para encerrar.');
  console.log('═══════════════════════════════════════════════════════════');
  console.log('');

  if (process.env.DEV_LIMPEZA_ABRIR_BROWSER !== '0') {
    const abrir =
      process.platform === 'win32'
        ? `start "" "${url}"`
        : process.platform === 'darwin'
          ? `open "${url}"`
          : `xdg-open "${url}"`;
    exec(abrir, () => {});
  }
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Porta ${PORT} em uso. Feche o outro servidor ou use DEV_LIMPEZA_PORT=8770`);
  } else {
    console.error(err);
  }
  process.exit(1);
});
