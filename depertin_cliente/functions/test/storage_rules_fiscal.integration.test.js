/**
 * Testes de Storage Rules para o Módulo Fiscal
 *
 * Executar (de depertin_cliente/):
 *   firebase emulators:exec "cd functions && node --test-concurrency=1 test/storage_rules_fiscal.integration.test.js" --project demo-depertin-teste --only storage
 *
 * Requer: @firebase/rules-unit-testing, Firebase Storage Rules publicadas na emulator
 */
const { describe, it, before, after } = require("node:test");
const path = require("path");
const firebase = require("@firebase/rules-unit-testing");
const admin = require("firebase-admin");

const PROJECT_ID = "demo-depertin-teste";
const RULES_PATH = path.join(__dirname, "..", "..", "storage.rules");
const BUCKET = `${PROJECT_ID}.appspot.com`;

const LOJA_A_UID = "loja-a-uid";
const LOJA_B_UID = "loja-b-uid";
const CLIENTE_UID = "cliente-uid";

let testEnv;

describe("Storage Rules — Módulo Fiscal", () => {
  before(async () => {
    testEnv = await firebase.initializeTestEnvironment({
      projectId: PROJECT_ID,
      storage: {
        rules: require("fs").readFileSync(RULES_PATH, "utf8"),
        host: "localhost",
        port: 9199,
      },
    });
  });

  after(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  function getRef(uid, storagePath) {
    const ctx = uid
      ? testEnv.authenticatedContext(uid, { sub: uid, email: `${uid}@test.com` })
      : testEnv.unauthenticatedContext();
    return ctx.storage(BUCKET).ref(storagePath);
  }

  // Caminhos de teste
  const CERT = `fiscal/${LOJA_A_UID}/certificates/cert-a.pfx`;
  const XML = `fiscal/${LOJA_A_UID}/docs/doc-001/nfe.xml`;
  const DANFE = `fiscal/${LOJA_A_UID}/docs/doc-001/danfe.pdf`;

  it("1. Lojista NÃO lê certificado diretamente", async () => {
    let erro = null;
    try { await getRef(LOJA_A_UID, CERT).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Deveria ter negado acesso ao certificado");
  });

  it("2. Lojista NÃO faz upload de certificado diretamente", async () => {
    let erro = null;
    try {
      await getRef(LOJA_A_UID, `fiscal/${LOJA_A_UID}/certificates/novo.pfx`)
        .putString("dados-fake", "raw", { contentType: "application/x-pkcs12" });
    } catch (e) { erro = e; }
    if (!erro) throw new Error("Upload direto de certificado deveria ser negado");
  });

  it("3. Lojista NÃO lê XML diretamente", async () => {
    let erro = null;
    try { await getRef(LOJA_A_UID, XML).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Acesso direto a XML deveria ser negado");
  });

  it("4. Lojista NÃO lê DANFE diretamente", async () => {
    let erro = null;
    try { await getRef(LOJA_A_UID, DANFE).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Acesso direto a DANFE deveria ser negado");
  });

  it("5. Lojista B NÃO acessa XML da Loja A", async () => {
    let erro = null;
    try { await getRef(LOJA_B_UID, XML).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Isolamento entre lojas falhou");
  });

  it("6. Staff (Client SDK) NÃO acessa arquivo fiscal", async () => {
    let erro = null;
    try { await getRef("staff-master", XML).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Regra /fiscal é 'if false', até staff deve ser negado via Client SDK");
  });

  it("7. Anônimo NÃO lê XML", async () => {
    let erro = null;
    try { await getRef(null, XML).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Anônimo deveria ser negado");
  });

  it("8. Cliente NÃO lê XML", async () => {
    let erro = null;
    try { await getRef(CLIENTE_UID, XML).getDownloadURL(); }
    catch (e) { erro = e; }
    if (!erro) throw new Error("Cliente deveria ser negado");
  });
});
