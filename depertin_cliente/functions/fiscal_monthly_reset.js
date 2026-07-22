/**
 * Rotina Mensal Fiscal
 *
 * Responsabilidades:
 * 1. Resetar contador de NF-e do ciclo (lojista_integracao.notas_emitidas / notas_reservadas)
 * 2. Detectar certificados A1 próximos do vencimento e gerar alertas
 * 3. Registrar auditoria da execução
 *
 * Schedule: todo dia 1º de cada mês às 02:00 (America/Sao_Paulo)
 */
const functions = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const ALERTA_CERT_DIAS = parseInt(process.env.FISCAL_CERT_ALERTA_DIAS || '30', 10);

/**
 * Reset mensal do limite + verificação de certificados.
 * Executa no 1º dia de cada mês.
 *
 * Campos canônicos (snake_case): notas_emitidas, notas_reservadas, status == 'ativa'
 */
exports.fiscalRotinaMensalReset = functions.onSchedule(
  {
    schedule: '0 2 1 * *',
    timeZone: 'America/Sao_Paulo',
    memory: '256MiB',
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const mesRef = `${now.toDate().getFullYear()}-${String(now.toDate().getMonth() + 1).padStart(2, '0')}`;

    console.log(`[fiscal-rotina] Iniciando reset mensal para referencia: ${mesRef}`);

    try {
      // Docs usam status: 'ativa' (não boolean 'ativa')
      const integracoes = await db.collection('lojista_integracao')
        .where('status', '==', 'ativa')
        .get();

      let resetados = 0;
      let batch = db.batch();
      const LIMITE_BATCH = 450;
      let opCount = 0;

      const commitBatch = async () => {
        if (opCount === 0) return;
        await batch.commit();
        console.log(`[fiscal-rotina] Batch de ${opCount} resets concluido. Total: ${resetados}`);
        batch = db.batch();
        opCount = 0;
      };

      for (const doc of integracoes.docs) {
        batch.update(doc.ref, {
          notas_emitidas: 0,
          notas_reservadas: 0,
          mes_referencia: mesRef,
          ultimo_reset_em: admin.firestore.FieldValue.serverTimestamp(),
          // limpa aliases legados camelCase se existirem
          notasEmitidas: admin.firestore.FieldValue.delete(),
          notasRestantes: admin.firestore.FieldValue.delete(),
          mesReferencia: admin.firestore.FieldValue.delete(),
        });

        opCount++;
        resetados++;

        if (opCount >= LIMITE_BATCH) {
          await commitBatch();
        }
      }

      await commitBatch();

      console.log(`[fiscal-rotina] Reset concluido: ${resetados} lojistas atualizados para mes ${mesRef}`);

      await verificarCertificadosVencendo(db, now);

      await db.collection('fiscal_audit_logs').add({
        acao: 'rotina_mensal_reset',
        descricao: `Reset mensal de limite concluido: ${resetados} lojistas, referencia ${mesRef}`,
        lojistas_resetados: resetados,
        mes_referencia: mesRef,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log('[fiscal-rotina] Rotina mensal concluida com sucesso.');
    } catch (error) {
      console.error('[fiscal-rotina] Erro na rotina mensal:', error);

      await db.collection('fiscal_audit_logs').add({
        acao: 'rotina_mensal_erro',
        descricao: `Erro no reset mensal: ${error.message}`,
        erro: error.message,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * Verifica certificados A1 próximos do vencimento e gera alertas.
 */
async function verificarCertificadosVencendo(db, now) {
  const dataLimite = new Date(now.toDate().getTime() + ALERTA_CERT_DIAS * 24 * 60 * 60 * 1000);

  console.log(`[fiscal-rotina] Verificando certificados com vencimento ate ${dataLimite.toISOString()}`);

  const settings = await db.collection('store_fiscal_settings')
    .where('status', '==', 'active')
    .where('certificate_expires_at', '<=', dataLimite)
    .get();

  if (settings.empty) {
    console.log('[fiscal-rotina] Nenhum certificado proximo do vencimento.');
    return;
  }

  let alertas = 0;
  const batch = db.batch();

  for (const doc of settings.docs) {
    const data = doc.data();
    const expiresAt = data.certificate_expires_at?.toDate();
    if (!expiresAt) continue;

    const diasRestantes = Math.floor((expiresAt.getTime() - now.toDate().getTime()) / (1000 * 60 * 60 * 24));
    const certVencido = diasRestantes <= 0;

    batch.set(db.collection('fiscal_audit_logs').doc(), {
      loja_id: data.store_id || '',
      acao: certVencido ? 'certificado_vencido' : 'certificado_proximo_vencimento',
      descricao: certVencido
        ? `Certificado A1 vencido ha ${Math.abs(diasRestantes)} dias`
        : `Certificado A1 vence em ${diasRestantes} dias (${expiresAt.toISOString().split('T')[0]})`,
      certificate_expires_at: data.certificate_expires_at,
      store_id: data.store_id || '',
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Se vencido, marcar integração (campo canônico status + legado ativa)
    if (certVencido) {
      const lojaId = data.store_id;
      if (lojaId) {
        const snap = await db.collection('lojista_integracao')
          .where('store_id', '==', lojaId)
          .limit(1)
          .get();
        if (!snap.empty) {
          batch.set(snap.docs[0].ref, {
            status: 'inativa',
            ativa: false,
            motivo_desativacao: 'certificado_vencido',
          }, { merge: true });
        }
      }
    }

    alertas++;
  }

  await batch.commit();
  console.log(`[fiscal-rotina] ${alertas} alertas de certificado registrados.`);
}
