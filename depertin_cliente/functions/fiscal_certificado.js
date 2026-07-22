/**
 * Fiscal Certificado — Upload e remoção de certificados A1
 *
 * SEGURANÇA:
 * - Usuário autenticado + staff + App Check obrigatório
 * - Arquivo .pfx/.p12 validado e aberto com senha no backend (node-forge)
 * - Conteúdo criptografado salvo no Cloud Storage (NÃO no Firestore)
 * - Apenas metadados + senha criptografada (pequena) no Firestore
 * - certificate_info público propagado para store_fiscal_settings
 * - NUNCA retorna conteúdo, senha ou dados criptografados ao frontend
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");
const forge = require("node-forge");
const securityGuard = require("./fiscal_security_guard");

// ─── Secret Manager ───
const fiscalMasterKey = defineSecret("FISCAL_MASTER_KEY");

const CONFIG = {
  region: "us-east1",
  cpu: 1,
  memory: "512MiB",
  maxInstances: 10,
  timeoutSeconds: 60,
  // TODO: voltar para `enforceAppCheck: process.env.FUNCTIONS_EMULATOR ? false : true`
  // após corrigir a Secret Key do reCAPTCHA v3 no Firebase Console → App Check →
  // depertin_web. Mantido false (igual às functions do Mercado Pago) pois a Secret
  // Key inválida faz o exchangeRecaptchaV3Token retornar 400 e bloqueia o staff.
  // Proteção preservada: Firebase Auth + verificação de papel staff dentro da função.
  enforceAppCheck: false,
  secrets: [fiscalMasterKey],
};

// ─── Constantes ───
const CRYPTO_PREFIX = "DIP_AES256_v2";
const CRYPTO_ENCRYPTION_VERSION = "aes-256-gcm-v2";
const EXTENSOES_VALIDAS = ["pfx", "p12"];
const TAMANHO_MAXIMO_BYTES = 5 * 1024 * 1024; // 5 MB

// ═══════════════════════════════════════════════════════════════════════
// Helpers criptográficos
// ═══════════════════════════════════════════════════════════════════════

function obterChaveMestra() {
  const rawKey = process.env.FISCAL_MASTER_KEY;
  if (!rawKey || typeof rawKey !== "string" || rawKey.length < 32) {
    throw new Error("Configuração criptográfica fiscal indisponível.");
  }
  return crypto.createHash("sha256").update(rawKey, "utf8").digest();
}

/**
 * Criptografa texto (ex.: senha) e retorna no formato:
 * DIP_AES256_v2:{iv_hex}:{auth_tag_hex}:{ciphertext_hex}
 * Tamanho proporcional ao texto original — adequado para Firestore.
 */
function encryptAesGcm(plaintext, masterKey) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-gcm", masterKey, iv);
  let encrypted = cipher.update(plaintext, "utf8", "hex");
  encrypted += cipher.final("hex");
  const authTag = cipher.getAuthTag().toString("hex");
  return `${CRYPTO_PREFIX}:${iv.toString("hex")}:${authTag}:${encrypted}`;
}

/**
 * Criptografa Buffer (arquivo) e retorna Buffer concatenado:
 * [iv 16B][authTag 16B][ciphertext]
 * Formato otimizado para Storage — overhead fixo de 32 bytes.
 */
function encryptBuffer(content, masterKey) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-gcm", masterKey, iv);
  const encrypted = Buffer.concat([cipher.update(content), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return Buffer.concat([iv, authTag, encrypted]);
}

/**
 * Descriptografa Buffer criado por encryptBuffer.
 * Formato esperado: [iv 16B][authTag 16B][ciphertext]
 */
function decryptBuffer(encrypted, masterKey) {
  if (encrypted.length < 32) {
    throw new Error("Dados criptografados inválidos: muito curtos.");
  }
  const iv = encrypted.subarray(0, 16);
  const authTag = encrypted.subarray(16, 32);
  const ciphertext = encrypted.subarray(32);
  const decipher = crypto.createDecipheriv("aes-256-gcm", masterKey, iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

// ═══════════════════════════════════════════════════════════════════════
// Validação de perfil staff
// ═══════════════════════════════════════════════════════════════════════

async function validarStaff(userId) {
  if (!userId) {
    throw new HttpsError("unauthenticated", "Usuário não autenticado.");
  }
  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "Usuário não encontrado.");
  }
  const userData = userSnap.data();
  const role = (userData.role || userData.tipo || "").toLowerCase().trim();
  const isStaff = role === "master" || role === "master_city" || role === "superadmin";
  if (!isStaff) {
    throw new HttpsError(
      "permission-denied",
      "Apenas administradores podem gerenciar certificados fiscais."
    );
  }
  return userData;
}

// ═══════════════════════════════════════════════════════════════════════
// Extração de dados do PKCS#12 (node-forge)
// ═══════════════════════════════════════════════════════════════════════

function extrairDadosCertificado(p12Der, senha) {
  let p12;
  try {
    p12 = forge.pkcs12.pkcs12FromAsn1(
      forge.asn1.fromDer(forge.util.createBuffer(p12Der)),
      false,
      senha
    );
  } catch (e) {
    if (
      e.message &&
      (e.message.includes("password") || e.message.includes("PKCS12") || e.message.includes("MAC"))
    ) {
      return { erro: "senha_incorreta", detalhe: "Senha do certificado incorreta." };
    }
    return { erro: "arquivo_invalido", detalhe: "Arquivo PKCS#12 inválido ou corrompido." };
  }

  // Extrai dados do certificado
  const keyBag = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag];
  const certBag = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag];

  if (!certBag || certBag.length === 0) {
    return { erro: "certificado_nao_encontrado", detalhe: "Nenhum certificado encontrado no arquivo PKCS#12." };
  }

  const cert = certBag[0].cert;
  if (!cert) {
    return { erro: "certificado_invalido", detalhe: "Falha ao extrair certificado do arquivo." };
  }

  // Validade
  const validadeInicio = cert.validity.notBefore;
  const validadeFim = cert.validity.notAfter;
  const agora = new Date();

  // CNPJ (extraído do subject)
  let cnpj = "";
  if (cert.subject && cert.subject.attributes) {
    for (const attr of cert.subject.attributes) {
      if (attr.name === "serialNumber" || attr.shortName === "SN") {
        const val = String(attr.value || "");
        const match = val.match(/(\d{14})/);
        if (match) cnpj = match[1];
      }
    }
  }

  // Fallback: tentar do issuer
  if (!cnpj && cert.issuer && cert.issuer.attributes) {
    for (const attr of cert.issuer.attributes) {
      if (attr.name === "serialNumber" || attr.shortName === "SN") {
        const val = String(attr.value || "");
        const match = val.match(/(\d{14})/);
        if (match) cnpj = match[1];
      }
    }
  }

  // Nome do titular (commonName)
  let titular = "";
  if (cert.subject && cert.subject.attributes) {
    for (const attr of cert.subject.attributes) {
      if (attr.name === "commonName" || attr.shortName === "CN") {
        titular = String(attr.value || "");
        break;
      }
    }
  }

  // Emissor
  let emissor = "";
  if (cert.issuer && cert.issuer.attributes) {
    for (const attr of cert.issuer.attributes) {
      if (attr.name === "commonName" || attr.shortName === "CN") {
        emissor = String(attr.value || "");
        break;
      }
    }
  }

  return {
    cnpj,
    titular,
    emissor,
    valido_de: validadeInicio,
    valido_ate: validadeFim,
    expirado: validadeFim < agora,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers de Storage
// ═══════════════════════════════════════════════════════════════════════

/**
 * Salva buffer criptografado no Cloud Storage.
 * @param {string} storagePath - Caminho completo (ex: fiscal/certificados/storeId/certId.enc)
 * @param {Buffer} encryptedBuffer - Dados criptografados
 */
async function salvarNoStorage(storagePath, encryptedBuffer) {
  const bucket = admin.storage().bucket();
  await bucket.file(storagePath).save(encryptedBuffer, {
    metadata: {
      contentType: "application/octet-stream",
      created_at: new Date().toISOString(),
    },
  });
}

/**
 * Lê e descriptografa um certificado do Storage.
 * @param {string} storagePath - Caminho no Storage
 * @param {Buffer} masterKey - Chave mestra de 32 bytes
 * @returns {Buffer} Conteúdo descriptografado (.pfx/.p12 original)
 */
async function lerEDescriptografarDoStorage(storagePath, masterKey) {
  const bucket = admin.storage().bucket();
  const [encryptedBuffer] = await bucket.file(storagePath).download();
  return decryptBuffer(encryptedBuffer, masterKey);
}

/**
 * Exclui arquivo do Storage com idempotência.
 * @param {string} storagePath
 * @returns {boolean} true se excluiu, false se já não existia
 */
async function excluirDoStorage(storagePath) {
  if (!storagePath) return false;
  try {
    await admin.storage().bucket().file(storagePath).delete();
    return true;
  } catch (err) {
    if (err.code === 404 || err.message?.includes("not found") || err.message?.includes("404")) {
      return false; // Idempotente: já não existe
    }
    throw err;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper: structure d'expiration
// ═══════════════════════════════════════════════════════════════════════

function calcularExpiraEmBreve(validadeFim) {
  if (!validadeFim) return false;
  const fim = new Date(validadeFim);
  const agora = new Date();
  const diasRestantes = (fim.getTime() - agora.getTime()) / (1000 * 60 * 60 * 24);
  return diasRestantes <= 30; // Expira em 30 dias ou menos
}

// ═══════════════════════════════════════════════════════════════════════
// fiscalUploadCertificado — Upload de certificado A1
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalUploadCertificado = onCall(
  {
    ...CONFIG,
    timeoutSeconds: 60,
  },
  async (request) => {
    const log = [];
    const addLog = (msg) => {
      log.push(msg);
      console.log(`[fiscalUploadCertificado] ${msg}`);
    };

    try {
      // 1. Autenticação
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
      }

      // 2. Staff
      const staffData = await validarStaff(userId);

      // 3. Parâmetros
      const storeId = request.data?.store_id || "";
      if (!storeId) {
        throw new HttpsError("invalid-argument", "store_id é obrigatório.");
      }

      const arquivoBase64 = request.data?.arquivo_base64 || "";
      if (!arquivoBase64) {
        throw new HttpsError("invalid-argument", "Arquivo do certificado é obrigatório.");
      }

      const senha = request.data?.senha || "";
      if (!senha) {
        throw new HttpsError("invalid-argument", "Senha do certificado é obrigatória.");
      }

      const nomeArquivo = request.data?.nome_arquivo || "certificado.pfx";
      addLog(`storeId=${storeId} nomeArquivo=${nomeArquivo}`);

      // 4. Validar extensão
      const ext = nomeArquivo.split(".").pop()?.toLowerCase() || "";
      if (!EXTENSOES_VALIDAS.includes(ext)) {
        throw new HttpsError("invalid-argument", `Formato inválido: .${ext}. Use .pfx ou .p12.`);
      }

      // 5. Decodificar e validar tamanho
      let arquivoBytes;
      try {
        arquivoBytes = Buffer.from(arquivoBase64, "base64");
      } catch (e) {
        throw new HttpsError("invalid-argument", "Arquivo inválido (base64 malformado).");
      }

      if (arquivoBytes.length === 0) {
        throw new HttpsError("invalid-argument", "Arquivo vazio.");
      }
      if (arquivoBytes.length > TAMANHO_MAXIMO_BYTES) {
        throw new HttpsError(
          "invalid-argument",
          `Arquivo muito grande (máx ${TAMANHO_MAXIMO_BYTES / 1024 / 1024} MB).`
        );
      }

      // 6. Extrair dados do PKCS#12
      addLog("Extraindo dados do certificado...");
      const dadosCert = extrairDadosCertificado(arquivoBytes, senha);

      if (dadosCert.erro) {
        if (dadosCert.erro === "senha_incorreta") {
          throw new HttpsError("invalid-argument", dadosCert.detalhe);
        }
        throw new HttpsError("invalid-argument", dadosCert.detalhe || "Certificado inválido.");
      }

      addLog(`Certificado: cnpj=${dadosCert.cnpj || "n/d"} titular=${dadosCert.titular || "n/d"}`);

      // 7. Validar CNPJ contra a loja
      const db = admin.firestore();
      const lojaSnap = await db.collection("users").doc(storeId).get();
      if (lojaSnap.exists) {
        const lojaData = lojaSnap.data();
        const lojaCnpj = (lojaData.cnpj || lojaData.doc_receita_federal || "").replace(/\D/g, "");
        if (lojaCnpj && dadosCert.cnpj && dadosCert.cnpj !== lojaCnpj) {
          addLog(`CNPJ incompatível: certificado="${dadosCert.cnpj}" loja="${lojaCnpj}"`);
          throw new HttpsError(
            "invalid-argument",
            `CNPJ do certificado (${dadosCert.cnpj}) não corresponde ao CNPJ da loja (${lojaCnpj}).`
          );
        }
      } else {
        addLog("Loja não encontrada no Firestore — continuando sem validação de CNPJ.");
      }

      // 8. Validar expiração
      if (dadosCert.expirado) {
        const dataStr = dadosCert.valido_ate
          ? dadosCert.valido_ate.toISOString().split("T")[0]
          : "data desconhecida";
        throw new HttpsError(
          "invalid-argument",
          `Certificado digital expirou em ${dataStr}. Renove antes de enviar.`
        );
      }

      // 9. Criptografar com FISCAL_MASTER_KEY
      addLog("Criptografando certificado...");
      const masterKey = obterChaveMestra();

      // 9a. Criptografar arquivo → Buffer (vai para Storage)
      const arquivoCriptografadoBuffer = encryptBuffer(arquivoBytes, masterKey);

      // 9b. Criptografar senha → texto (vai para Firestore, é pequeno)
      const senhaCriptografadaTexto = encryptAesGcm(senha, masterKey);
      // Parse: "DIP_AES256_v2:{ivHex}:{authTagHex}:{ciphertextHex}"
      const senhaParts = senhaCriptografadaTexto.split(":");
      const senhaEncrypted = {
        version: CRYPTO_PREFIX,
        iv: senhaParts[1] || "",
        auth_tag: senhaParts[2] || "",
        ciphertext: senhaParts[3] || "",
      };

      // 10. Gerar ID do certificado (determinístico via UUID)
      const certId = crypto.randomUUID();
      const storagePath = `fiscal/certificados/${storeId}/${certId}.enc`;
      const contentSha256 = crypto.createHash("sha256").update(arquivoBytes).digest("hex");

      // 11. Salvar no Cloud Storage
      addLog(`Salvando no Storage: ${storagePath} (${arquivoBytes.length} bytes originais)`);
      await salvarNoStorage(storagePath, arquivoCriptografadoBuffer);
      addLog("Arquivo salvo no Storage com sucesso.");

      // 12. Salvar metadados em fiscal_certificates (APENAS metadados — sem conteúdo do arquivo)
      const validoDeStr = dadosCert.valido_de
        ? dadosCert.valido_de.toISOString().split("T")[0]
        : "";
      const validoAteStr = dadosCert.valido_ate
        ? dadosCert.valido_ate.toISOString().split("T")[0]
        : "";

      const certDoc = {
        store_id: storeId,
        storage_path: storagePath,
        encryption_version: CRYPTO_ENCRYPTION_VERSION,
        original_filename: nomeArquivo,
        original_size: arquivoBytes.length,
        encrypted_size: arquivoCriptografadoBuffer.length,
        content_sha256: contentSha256,
        encrypted_password: senhaEncrypted,
        certificate_subject: dadosCert.titular || "",
        certificate_cnpj: dadosCert.cnpj || "",
        certificate_issuer: dadosCert.emissor || "",
        valid_from: dadosCert.valido_de || null,
        valid_until: dadosCert.valido_ate || null,
        status: "valid",
        created_by: userId,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      };

      // Usa certId como doc ID (evita add() para previsibilidade)
      const certRef = db.collection("fiscal_certificates").doc(certId);
      await certRef.set(certDoc);
      addLog(`Certificado salvo: fiscal_certificates/${certId}`);

      // 13. Ler certificado antigo ANTES de atualizar settings (substituição segura)
      const settingsSnap = await db
        .collection("store_fiscal_settings")
        .where("store_id", "==", storeId)
        .limit(1)
        .get();

      let oldCertificateId = null;
      if (settingsSnap.docs.length > 0) {
        const existingData = settingsSnap.docs[0].data() || {};
        oldCertificateId = existingData.certificate_id || null;
      }

      const expiresSoon = calcularExpiraEmBreve(dadosCert.valido_ate);

      const certificateInfoPublic = {
        certificate_id: certId,
        configured: true,
        status: "valid",
        subject_name: dadosCert.titular || "",
        cnpj_masked: dadosCert.cnpj
          ? `${dadosCert.cnpj.slice(0, 2)}.***.***/${dadosCert.cnpj.slice(8, 12)}-**`
          : "",
        valid_until: dadosCert.valido_ate || null,
        expires_soon: expiresSoon,
        last_validated_at: FieldValue.serverTimestamp(),
      };

      const settingsUpdate = {
        certificate_id: certId,
        certificate_info: certificateInfoPublic,
        certificate_updated_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      };

      let settingsRef = null;
      if (settingsSnap.docs.length > 0) {
        settingsRef = settingsSnap.docs[0].ref;
        await settingsRef.update(settingsUpdate);
        addLog("store_fiscal_settings atualizado com certificate_info.");
      } else {
        settingsRef = await db.collection("store_fiscal_settings").add({
          store_id: storeId,
          ...settingsUpdate,
          status: "active",
          created_at: FieldValue.serverTimestamp(),
        });
        addLog("store_fiscal_settings criado com certificate_info.");
      }

      // 13b. Remover certificado antigo AGORA (novo já está validado, salvo e vinculado)
      if (oldCertificateId) {
        try {
          const oldCertSnap = await db.collection("fiscal_certificates").doc(oldCertificateId).get();
          if (oldCertSnap.exists) {
            const oldCertData = oldCertSnap.data();
            const oldStoragePath = oldCertData.storage_path || "";
            if (oldStoragePath) {
              await excluirDoStorage(oldStoragePath);
              addLog(`Certificado antigo removido do Storage: ${oldStoragePath}`);
            }
            await db.collection("fiscal_certificates").doc(oldCertificateId).delete();
            addLog(`Certificado antigo removido do Firestore: ${oldCertificateId}`);
          }
        } catch (cleanupErr) {
          // Falha na limpeza não deve bloquear — marca para limpeza posterior
          addLog(`Aviso: falha ao remover certificado antigo (${oldCertificateId}): ${cleanupErr.message}`);
          try {
            await db.collection("fiscal_certificates").doc(oldCertificateId).update({
              cleanup_pending: true,
              cleanup_failed_at: FieldValue.serverTimestamp(),
              cleanup_fail_reason: cleanupErr.message.slice(0, 200),
            });
          } catch (_) {
            // Se nem marcar cleanup_pending funcionar, seguir em frente
          }
        }
      }

      // 14. Retornar apenas metadados públicos (nunca o conteúdo)
      addLog("Upload concluído com sucesso.");
      const agora = new Date();
      return {
        sucesso: true,
        certificate_id: certId,
        certificate_info: {
          ...certificateInfoPublic,
          last_validated_at: agora.toISOString(),
          valid_until: dadosCert.valido_ate
            ? dadosCert.valido_ate.toISOString()
            : null,
        },
        mensagem: "Certificado digital enviado e validado com sucesso.",
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      addLog(`Erro: ${e.message}`);
      console.error("[fiscalUploadCertificado] Erro interno:", e.message);
      throw new HttpsError(
        "internal",
        "Erro interno ao processar certificado."
      );
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════
// fiscalRemoverCertificado — Remoção segura de certificado
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalRemoverCertificado = onCall(
  {
    ...CONFIG,
    timeoutSeconds: 30,
  },
  async (request) => {
    try {
      // 1. Autenticação
      const userId = request.auth?.uid;
      if (!userId) {
        throw new HttpsError("unauthenticated", "Usuário não autenticado.");
      }

      // 2. Staff
      await validarStaff(userId);

      // 3. Parâmetros
      const certificateId = request.data?.certificate_id || "";
      if (!certificateId) {
        throw new HttpsError("invalid-argument", "certificate_id é obrigatório.");
      }

      const db = admin.firestore();

      // 4. Buscar certificado
      const certSnap = await db.collection("fiscal_certificates").doc(certificateId).get();
      if (!certSnap.exists) {
        throw new HttpsError("not-found", "Certificado não encontrado.");
      }

      const certData = certSnap.data();
      const storeId = certData.store_id || "";
      const storagePath = certData.storage_path || "";

      console.log(
        `[fiscalRemoverCertificado] Removendo certificado: ${certificateId} store=${storeId}`
      );

      // 5. Excluir do Cloud Storage (idempotente)
      if (storagePath) {
        const excluido = await excluirDoStorage(storagePath);
        if (excluido) {
          console.log(`[fiscalRemoverCertificado] Arquivo excluído do Storage: ${storagePath}`);
        } else {
          console.log(`[fiscalRemoverCertificado] Arquivo já inexistente no Storage: ${storagePath}`);
        }
      }

      // 6. Excluir documento Firestore
      await db.collection("fiscal_certificates").doc(certificateId).delete();

      // 7. Limpar vínculo em store_fiscal_settings
      if (storeId) {
        const settingsSnap = await db
          .collection("store_fiscal_settings")
          .where("store_id", "==", storeId)
          .limit(1)
          .get();

        if (settingsSnap.docs.length > 0) {
          await settingsSnap.docs[0].ref.update({
            certificate_id: FieldValue.delete(),
            certificate_info: FieldValue.delete(),
            certificate_updated_at: FieldValue.serverTimestamp(),
            updated_at: FieldValue.serverTimestamp(),
          });
        }
      }

      // 8. Auditoria
      try {
        await db.collection("fiscal_logs").add({
          tipo: "certificado_removido",
          certificate_id: certificateId,
          store_id: storeId,
          storage_path: storagePath,
          removido_por: userId,
          removido_em: FieldValue.serverTimestamp(),
        });
      } catch (logErr) {
        console.error("[fiscalRemoverCertificado] Erro ao registrar auditoria:", logErr.message);
      }

      return {
        sucesso: true,
        mensagem: "Certificado removido com sucesso.",
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[fiscalRemoverCertificado] Erro interno:", e.message);
      throw new HttpsError("internal", "Erro interno ao remover certificado.");
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════
// Export auxiliar: lerEDescriptografarCertificado
// Usado internamente pela emissão (fiscal_nfe_proxy.js)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Lê o certificado A1 do Storage e descriptografa para uso na emissão.
 *
 * @param {string} certificateId - ID do documento em fiscal_certificates
 * @param {object} db - Firestore Admin instance
 * @param {string} expectedStoreId - store_id esperado (validação extra)
 * @returns {{ pfxBuffer: Buffer, senha: string, certData: object }}
 */
exports.carregarCertificadoParaEmissao = async (certificateId, db, expectedStoreId) => {
  const certSnap = await db.collection("fiscal_certificates").doc(certificateId).get();
  if (!certSnap.exists) {
    throw new Error("Certificado não encontrado no Firestore.");
  }

  const certData = certSnap.data();

  // Valida store_id
  if (certData.store_id && expectedStoreId && certData.store_id !== expectedStoreId) {
    throw new Error("Certificado não pertence à loja informada.");
  }

  // Valida status
  if (certData.status !== "valid") {
    throw new Error("Certificado não está ativo.");
  }

  // Valida validade
  if (certData.valid_until) {
    const validadeFim = certData.valid_until.toDate
      ? certData.valid_until.toDate()
      : new Date(certData.valid_until);
    if (validadeFim < new Date()) {
      throw new Error("Certificado expirou.");
    }
  }

  // Lê e descriptografa do Storage
  const storagePath = certData.storage_path;
  if (!storagePath) {
    throw new Error("Caminho do certificado no Storage não encontrado.");
  }

  const masterKey = obterChaveMestra();
  const pfxBuffer = await lerEDescriptografarDoStorage(storagePath, masterKey);

  // Valida hash de integridade
  if (certData.content_sha256) {
    const hashReal = crypto.createHash("sha256").update(pfxBuffer).digest("hex");
    if (hashReal !== certData.content_sha256) {
      throw new Error("Integridade do certificado comprometida (hash diverge).");
    }
  }

  // Descriptografa senha
  let senha = "";
  if (certData.encrypted_password) {
    const ep = certData.encrypted_password;
    const textoCriptografado = `${ep.version}:${ep.iv}:${ep.auth_tag}:${ep.ciphertext}`;
    // Reusa a função decryptAesGcm do fiscal_nfe_proxy.js ou implementa inline
    try {
      // Decriptografia inline: parse do formato DIP_AES256_v2:{iv}:{authTag}:{ciphertext}
      const payload = textoCriptografado.slice((CRYPTO_PREFIX + ":").length);
      const [ivHex, authTagHex, ciphertextHex] = payload.split(":");
      const iv = Buffer.from(ivHex, "hex");
      const authTag = Buffer.from(authTagHex, "hex");
      const ciphertext = Buffer.from(ciphertextHex, "hex");
      const decipher = crypto.createDecipheriv("aes-256-gcm", masterKey, iv);
      decipher.setAuthTag(authTag);
      let dec = decipher.update(ciphertext, "hex", "utf8");
      dec += decipher.final("utf8");
      senha = dec;
    } catch {
      throw new Error("Falha ao descriptografar senha do certificado.");
    }
  }

  return { pfxBuffer, senha, certData };
};

// ═══════════════════════════════════════════════════════════════════════
// fiscalLimparCertificadosPendentes — Processa certificados com cleanup_pending
// ═══════════════════════════════════════════════════════════════════════

/**
 * Callable para staff limpar certificados marcados como cleanup_pending.
 *
 * Fluxo:
 * 1. Localiza certificados com cleanup_pending: true
 * 2. Confirma que NÃO são o certificado ativo de nenhuma loja
 * 3. Exclui o objeto do Storage
 * 4. Exclui o documento Firestore
 * 5. Incrementa retry_count e registra auditoria
 */
exports.fiscalLimparCertificadosPendentes = onCall(
  {
    ...CONFIG,
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Usuário não autenticado.");
    }
    await validarStaff(request.auth.uid);

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const resultados = { processados: 0, erros: 0, ignorados: 0, detalhes: [] };

    try {
      const pendentes = await db
        .collection("fiscal_certificates")
        .where("cleanup_pending", "==", true)
        .limit(50)
        .get();

      for (const doc of pendentes.docs) {
        const certData = doc.data();
        const certId = doc.id;
        const storeId = certData.store_id || "";

        try {
          // Confirma que não é o certificado ativo
          if (storeId) {
            const settingsQuery = await db
              .collection("store_fiscal_settings")
              .where("store_id", "==", storeId)
              .where("certificate_id", "==", certId)
              .limit(1)
              .get();

            if (!settingsQuery.empty) {
              // Ainda é o ativo — não remover
              resultados.ignorados++;
              resultados.detalhes.push({
                certificate_id: certId,
                motivo: "cleanup_pending_mas_ainda_ativo",
              });
              continue;
            }
          }

          // Exclui do Storage (se houver caminho)
          const storagePath = certData.storage_path || "";
          if (storagePath) {
            const excluido = await excluirDoStorage(storagePath);
            if (excluido) {
              console.log(`[fiscalCleanup] Storage removido: ${storagePath}`);
            }
          }

          // Exclui documento Firestore
          await db.collection("fiscal_certificates").doc(certId).delete();
          console.log(`[fiscalCleanup] Documento removido: ${certId}`);

          resultados.processados++;
          resultados.detalhes.push({
            certificate_id: certId,
            motivo: "cleanup_executado",
          });
        } catch (err) {
          resultados.erros++;
          const retryAtual = (certData.cleanup_retry_count || 0) + 1;
          await db.collection("fiscal_certificates").doc(certId).update({
            cleanup_retry_count: retryAtual,
            cleanup_last_error: err.message.slice(0, 300),
            cleanup_last_error_at: FieldValue.serverTimestamp(),
          });
          resultados.detalhes.push({
            certificate_id: certId,
            motivo: "erro_no_cleanup",
            erro: err.message.slice(0, 200),
            retry: retryAtual,
          });
        }
      }

      return {
        sucesso: true,
        processados: resultados.processados,
        erros: resultados.erros,
        ignorados: resultados.ignorados,
        detalhes: resultados.detalhes,
      };
    } catch (err) {
      console.error(`[fiscalCleanup] Erro geral: ${err.message}`);
      return {
        sucesso: false,
        mensagem: err.message.slice(0, 500),
        processados: resultados.processados,
        erros: resultados.erros + 1,
        ignorados: resultados.ignorados,
      };
    }
  }
);
