/**
 * Rotina Mensal Fiscal
 *
 * Responsabilidades:
 * 1. Resetar limite mensal de emissão de NF-e para todos os lojistas
 * 2. Detectar certificados A1 próximos do vencimento e gerar alertas
 * 3. Gerar relatório mensal de notas emitidas por loja
 *
 * Schedule: todo dia 1º de cada mês às 02:00 (America/Sao_Paulo)
 * Também executa alertas de certificado semanalmente (a cada 7 dias)
 */
const functions = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const ALERTA_CERT_DIAS = parseInt(process.env.FISCAL_CERT_ALERTA_DIAS || '30', 10);

/**
 * Reset mensal do limite + verificação de certificados.
 * Executa no 1º dia de cada mês.
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
      // 1. Resetar limite mensal de todas as integrações
      const integracoes = await db.collection('lojista_integracao')
        .where('ativa', '==', true)
        .get();

      let resetados = 0;
      const batch = db.batch();
      const LIMITE_BATCH = 500;
      let opCount = 0;

      for (const doc of integracoes.docs) {
        const data = doc.data();
        const limite = data.limiteMensal || 200;

        batch.update(doc.ref, {
          notasEmitidas: 0,
          notasRestantes: limite,
          mesReferencia: mesRef,
          ultimo_reset_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        opCount++;
        resetados++;

        if (opCount >= LIMITE_BATCH) {
          await batch.commit();
          console.log(`[fiscal-rotina] Batch de ${LIMITE_BATCH} resets concluido. Total: ${resetados}`);
          opCount = 0;
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      console.log(`[fiscal-rotina] Reset concluido: ${resetados} lojistas atualizados para mes ${mesRef}`);

      // 2. Verificar certificados próximos do vencimento
      await verificarCertificadosVencendo(db, now);

      // 3. Registrar execução da rotina
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

    // Registrar alerta no log de auditoria
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

    // Se vencido, desativar integração automaticamente
    if (certVencido) {
      const lojaId = data.store_id;
      if (lojaId) {
        const integracaoRef = db.collection('lojista_integracao').doc(lojaId);
        batch.set(integracaoRef, { ativa: false, motivo_desativacao: 'certificado_vencido' }, { merge: true });
      }
    }

    alertas++;
  }

  await batch.commit();
  console.log(`[fiscal-rotina] ${alertas} alertas de certificado registrados.`);
}
