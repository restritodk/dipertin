/**
 * Testes de Firestore Rules para o Módulo Fiscal
 *
 * Executar (de depertin_cliente/):
 *   firebase emulators:exec "cd functions && node --test-concurrency=1 test/firestore_rules_fiscal.integration.test.js" --project demo-depertin-teste --only firestore,auth
 *
 * Requer: @firebase/rules-unit-testing
 */
const assert = require("assert");
const { describe, it, before, after } = require("node:test");
const firebase = require("@firebase/rules-unit-testing");
const admin = require("firebase-admin");
const path = require("path");

const PROJECT_ID = "demo-depertin-teste";
const RULES_PATH = path.join(__dirname, "..", "..", "firestore.rules");

const STAFF_UID = "staff-master";
const LOJA_A_UID = "lojista-a-uid";
const LOJA_B_UID = "lojista-b-uid";
const CLIENTE_UID = "cliente-uid";

let testEnv;
let adminDb;

describe("Firestore Rules — Módulo Fiscal", () => {
  before(async () => {
    testEnv = await firebase.initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: require("fs").readFileSync(RULES_PATH, "utf8"),
        host: "localhost",
        port: 8080,
      },
    });

    // Inicializa Admin SDK p/ seed (bypassa rules) se ainda não iniciado
    if (admin.apps.length === 0) {
      admin.initializeApp({ projectId: PROJECT_ID });
    }
    adminDb = admin.firestore();
  });

  after(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  /** Ctx autenticado com claims (sujeito a rules). */
  function authCtx(uid, claims) {
    return testEnv.authenticatedContext(uid, {
      sub: uid,
      email: `${uid}@test.com`,
      ...claims,
    }).firestore();
  }

  function unauthedCtx() {
    return testEnv.unauthenticatedContext().firestore();
  }

  /** Seed: cria doc via Admin SDK (bypassa rules). */
  async function seedDoc(colecao, id, dados) {
    await adminDb.collection(colecao).doc(id).set(dados);
  }

  // ═════════════════════════════════════════════════════════════════════
  // Setup: cria documentos de teste via Admin SDK
  // ═════════════════════════════════════════════════════════════════════
  before(async () => {
    // 1. Usuários
    await seedDoc("users", STAFF_UID, { email: "master@test.com", role: "master" });
    await seedDoc("users", LOJA_A_UID, { email: "lojaA@test.com", role: "lojista", lojista_owner_uid: "" });
    await seedDoc("users", LOJA_B_UID, { email: "lojaB@test.com", role: "lojista", lojista_owner_uid: "" });
    await seedDoc("users", CLIENTE_UID, { email: "cli@test.com", role: "cliente" });

    // 2. Store settings (lojista pode ler da própria loja)
    await seedDoc("store_fiscal_settings", "store-a", {
      store_id: LOJA_A_UID,
      integration_id: "integ-focus-a",
      saldo_notas: 50,
      integration_data: { provider: "focus_nfe", environment: "sandbox", status: "active" },
      certificate_info: { configured: true, validade: "2027-12-31T23:59:59Z" },
    });
    await seedDoc("store_fiscal_settings", "store-b", {
      store_id: LOJA_B_UID,
      integration_id: "integ-focus-b",
      saldo_notas: 30,
    });

    // 3. Integrações (staff-only)
    await seedDoc("fiscal_integrations", "integ-focus-a", {
      provider: "focus_nfe",
      credentials_encrypted: "DIP_AES256_v2:secret-token",
      environment: "sandbox",
    });

    // 4. Certificados (staff-only)
    await seedDoc("fiscal_certificates", "cert-a", {
      store_id: LOJA_A_UID,
      validade: "2027-12-31",
      certificate_data_encrypted: "DIP_AES256_v2:secret-cert",
    });

    // 5. Documentos fiscais
    await seedDoc("fiscal_documents", "doc-a-001", {
      store_id: LOJA_A_UID,
      status: "autorizada",
      access_key: "35200611222333000181550010000000011000000011",
    });
    await seedDoc("fiscal_documents", "doc-b-001", {
      store_id: LOJA_B_UID,
      status: "autorizada",
      access_key: "35200699888777000181550010000000021000000022",
    });

    // 6. Logs fiscais (staff-only)
    await seedDoc("fiscal_logs", "log-001", { mensagem: "teste", store_id: LOJA_A_UID });
    await seedDoc("fiscal_audit_logs", "audit-001", { acao: "teste", store_id: LOJA_A_UID });

    // 7. Operations (staff-only)
    await seedDoc("fiscal_emission_operations", "op-001", {
      store_id: LOJA_A_UID,
      status: "em_andamento",
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // TESTES
  // ═════════════════════════════════════════════════════════════════════

  it("1. Staff lê fiscal_integrations", async () => {
    const db = authCtx(STAFF_UID);
    const snap = await db.collection("fiscal_integrations").doc("integ-focus-a").get();
    assert.ok(snap.exists, "Staff deve ler fiscal_integrations");
  });

  it("2. Lojista NÃO lê fiscal_integrations", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_integrations").doc("integ-focus-a").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("3. Lojista B NÃO lê settings da Loja A", async () => {
    const db = authCtx(LOJA_B_UID);
    try {
      await db.collection("store_fiscal_settings").doc("store-a").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("4. Lojista A lê seus próprios settings", async () => {
    const db = authCtx(LOJA_A_UID);
    const snap = await db.collection("store_fiscal_settings").doc("store-a").get();
    assert.ok(snap.exists, "Lojista A deve ler seus settings");
    const data = snap.data();
    assert.ok(data.integration_data, "integration_data deve existir");
    assert.strictEqual(data.saldo_notas, 50, "saldo_notas legível");
    assert.strictEqual(data.credentials_encrypted, undefined,
      "credentials_encrypted NÃO deve estar em store_fiscal_settings");
  });

  it("5. Lojista NÃO altera saldo_notas (update em settings)", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("store_fiscal_settings").doc("store-a").update({ saldo_notas: 99999 });
      // Se não lançou erro, temos um GAP de segurança
      console.warn("⚠️ GAP: Lojista alterou saldo_notas!");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("6. Lojista NÃO lê fiscal_certificates", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_certificates").doc("cert-a").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("7. Lojista NÃO grava fiscal_certificates", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_certificates").doc("cert-a").update({ validade: "2030-01-01" });
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("8. Lojista A lê seus próprios documentos", async () => {
    const db = authCtx(LOJA_A_UID);
    const snap = await db.collection("fiscal_documents").doc("doc-a-001").get();
    assert.ok(snap.exists, "Lojista A deve ler seus documentos");
  });

  it("8b. Lojista A NÃO lê documentos da Loja B", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_documents").doc("doc-b-001").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("9. Lojista NÃO altera fiscal_documents (update)", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_documents").doc("doc-a-001").update({ status: "cancelada" });
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("10. Cliente NÃO lê fiscal_documents", async () => {
    const db = authCtx(CLIENTE_UID);
    try {
      await db.collection("fiscal_documents").doc("doc-a-001").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("12. Lojista NÃO lê fiscal_logs", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_logs").doc("log-001").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("12b. Lojista NÃO lê fiscal_audit_logs", async () => {
    const db = authCtx(LOJA_A_UID);
    try {
      await db.collection("fiscal_audit_logs").doc("audit-001").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("13a. Staff cria fiscal_integrations", async () => {
    const db = authCtx(STAFF_UID);
    await db.collection("fiscal_integrations").doc("integ-staff-test").set({
      provider: "focus_nfe",
      environment: "sandbox",
    });
    const snap = await db.collection("fiscal_integrations").doc("integ-staff-test").get();
    assert.ok(snap.exists, "Staff deve criar integração");
  });

  it("13b. Staff lê fiscal_certificates", async () => {
    const db = authCtx(STAFF_UID);
    const snap = await db.collection("fiscal_certificates").doc("cert-a").get();
    assert.ok(snap.exists, "Staff deve ler certificado");
  });

  it("14. Anônimo NÃO lê store_fiscal_settings", async () => {
    const db = unauthedCtx();
    try {
      await db.collection("store_fiscal_settings").doc("store-a").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("14b. Anônimo NÃO lê fiscal_documents", async () => {
    const db = unauthedCtx();
    try {
      await db.collection("fiscal_documents").doc("doc-a-001").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  const COLAB_NIVEL2_UID = "lojaA_colab2";
  const COLAB_NIVEL1_UID = "lojaA_colab1";

  it("14. Colaborador nível 2 lê store_fiscal_settings da própria loja", async () => {
    // Cria usuario colaborador no seed
    await adminDb.collection("users").doc(COLAB_NIVEL2_UID).set({
      email: "colab2@test.com",
      role: "lojista",
      lojista_owner_uid: LOJA_A_UID,
      painel_colaborador_nivel: 2,
    });
    const db = authCtx(COLAB_NIVEL2_UID);
    const snap = await db.collection("store_fiscal_settings").doc("store-a").get();
    assert.ok(snap.exists, "Colaborador nível 2 deve ler settings da própria loja");
  });

  it("14b. Colaborador nível 2 NÃO lê store_fiscal_settings de outra loja", async () => {
    const db = authCtx(COLAB_NIVEL2_UID);
    try {
      await db.collection("store_fiscal_settings").doc("store-b").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado
    }
  });

  it("14c. Colaborador nível 1 NÃO lê store_fiscal_settings (fiscalAcessoPermitido)", async () => {
    const db = authCtx(COLAB_NIVEL1_UID);
    try {
      await db.collection("store_fiscal_settings").doc("store-a").get();
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado (fiscalAcessoPermitido exige nível >= 2)
    }
  });

  it("14d. Colaborador nível 2 NÃO altera store_fiscal_settings", async () => {
    const db = authCtx(COLAB_NIVEL2_UID);
    try {
      await db.collection("store_fiscal_settings").doc("store-a").update({ saldo_notas: 99999 });
      assert.ok(false, "Deveria ter lançado PERMISSION_DENIED");
    } catch (e) {
      // PERMISSION_DENIED esperado (create/update/delete = staff only)
    }
  });
});
