import 'package:cloud_firestore/cloud_firestore.dart';
import 'fiscal_crypto_util.dart';

/// Serviço de auditoria para operações fiscais.
///
/// Registra todas as operações em `fiscal_audit_logs/{id}`
/// garantindo rastreabilidade completa.
///
/// NUNCA expõe dados sensíveis (credenciais, tokens, certificados).
/// Tudo é sanitizado antes do registro.
abstract final class FiscalAuditService {
  static const String _colecao = 'fiscal_audit_logs';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Registra um evento de auditoria.
  ///
  /// [lojaId] ID da loja que realizou a operação.
  /// [acao] Nome da ação (ex: 'emissao_nfe', 'cancelamento_nfe').
  /// [descricao] Descrição legível do evento.
  /// [documentoId] ID do documento fiscal relacionado (opcional).
  /// [chaveAcesso] Chave de acesso da NF-e (opcional).
  /// [provedor] Nome do provedor fiscal utilizado (opcional).
  /// [detalhesExtras] Mapa com detalhes adicionais (SANITIZADO).
  static Future<void> registrar({
    required String lojaId,
    required String acao,
    required String descricao,
    String? documentoId,
    String? chaveAcesso,
    String? provedor,
    Map<String, dynamic>? detalhesExtras,
    String? usuarioUid,
  }) async {
    try {
      final dados = <String, dynamic>{
        'store_id': lojaId,
        'user_uid': usuarioUid,
        'acao': acao,
        'descricao': descricao,
        if (documentoId != null) 'documento_id': documentoId,
        if (chaveAcesso != null) 'chave_acesso': chaveAcesso,
        if (provedor != null) 'provider': provedor,
        'criado_em': FieldValue.serverTimestamp(),
      };

      // Sanitiza detalhes extras (NUNCA salvar credenciais/tokens)
      if (detalhesExtras != null && detalhesExtras.isNotEmpty) {
        final sanitizado = FiscalCryptoUtil.sanitizarParaLog(detalhesExtras);
        dados['detalhes'] = sanitizado;
      }

      await _db.collection(_colecao).add(dados);
    } catch (_) {
      // Falha silenciosa — auditoria nunca deve quebrar o fluxo principal
    }
  }

  /// Lista os logs de auditoria de uma loja.
  static Stream<List<Map<String, dynamic>>> streamLogs(String lojaId) {
    return _db
        .collection(_colecao)
        .where('store_id', isEqualTo: lojaId)
        .orderBy('criado_em', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['__id'] = d.id;
              return data;
            }).toList());
  }

  /// Lista logs sem stream (one-shot).
  static Future<List<Map<String, dynamic>>> listarLogs(
    String lojaId, {
    int limite = 100,
    String? acao,
  }) async {
    try {
      var query = _db
          .collection(_colecao)
          .where('store_id', isEqualTo: lojaId)
          .orderBy('criado_em', descending: true)
          .limit(limite);

      if (acao != null) {
        query = query.where('acao', isEqualTo: acao);
      }

      final snap = await query.get();
      return snap.docs.map((d) {
        final data = d.data();
        data['__id'] = d.id;
        return data;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Ações de auditoria padronizadas.
  static const String acaoEmissao = 'emissao_nfe';
  static const String acaoCancelamento = 'cancelamento_nfe';
  static const String acaoCartaCorrecao = 'carta_correcao';
  static const String acaoInutilizacao = 'inutilizacao_numeracao';
  static const String acaoContingenciaAtivar = 'contingencia_ativada';
  static const String acaoContingenciaResolver = 'contingencia_resolvida';
  static const String acaoEmailEnviado = 'email_fiscal_enviado';
  static const String acaoConfiguracaoAlterada = 'configuracao_fiscal_alterada';
  static const String acaoIntegracaoTestada = 'integracao_testada';
  static const String acaoDownloadXml = 'download_xml';
  static const String acaoDownloadDanfe = 'download_danfe';
  static const String acaoConsultaSefaz = 'consulta_sefaz';
}
