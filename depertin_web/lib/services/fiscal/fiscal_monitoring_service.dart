import 'package:cloud_firestore/cloud_firestore.dart';

/// Serviço de monitoramento do módulo fiscal NF-e.
///
/// Responsabilidades:
/// - Alertas de certificado próximo do vencimento
/// - Logs de erro por provedor
/// - Alertas de webhook com falha
/// - Notificações de limite próximo do fim
abstract final class FiscalMonitoringService {
  static const _auditLogsColl = 'fiscal_audit_logs';
  static const _settingsColl = 'store_fiscal_settings';
  static const _integracaoColl = 'lojista_integracao';
  static const _docsColl = 'fiscal_documents';

  static const _limiteAlertaPercentual = 0.85; // 85% do limite = alerta

  // ─── Certificados ───────────────────────────────────────────────────────

  /// Stream de certificados próximos do vencimento (staff).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCertificadosProximosVencimento({
    int diasLimite = 30,
  }) {
    final dataLimite = DateTime.now().add(Duration(days: diasLimite));
    return FirebaseFirestore.instance
        .collection(_settingsColl)
        .where('status', isEqualTo: 'active')
        .where('certificate_expires_at', isLessThanOrEqualTo: dataLimite)
        .snapshots();
  }

  /// Stream de certificados vencidos (staff).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCertificadosVencidos() {
    return FirebaseFirestore.instance
        .collection(_settingsColl)
        .where('status', isEqualTo: 'active')
        .where('certificate_expires_at', isLessThanOrEqualTo: DateTime.now())
        .snapshots();
  }

  // ─── Logs de erro por provedor ──────────────────────────────────────────

  /// Stream de logs de erro de emissão nos últimos [dias] dias.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamErrosEmissao({
    int dias = 7,
    String? provider,
  }) {
    final dataLimite = DateTime.now().subtract(Duration(days: dias));
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(_auditLogsColl)
        .where('acao', whereIn: ['emissao_rejeitada', 'webhook_recebido_erro'])
        .where('criado_em', isGreaterThanOrEqualTo: dataLimite)
        .orderBy('criado_em', descending: true);

    if (provider != null) {
      query = query.where('provider', isEqualTo: provider);
    }

    return query.limit(100).snapshots();
  }

  /// Stream de erros por provedor, agregados.
  static Stream<Map<String, int>> streamErrosPorProvedor({int dias = 7}) {
    return FirebaseFirestore.instance
        .collection(_auditLogsColl)
        .where('acao', whereIn: ['emissao_rejeitada', 'webhook_recebido_erro'])
        .where('criado_em', isGreaterThanOrEqualTo: DateTime.now().subtract(Duration(days: dias)))
        .snapshots()
        .map((snap) {
      final Map<String, int> contagem = {};
      for (final doc in snap.docs) {
        final provider = doc.data()['provider'] as String? ?? 'unknown';
        contagem[provider] = (contagem[provider] ?? 0) + 1;
      }
      return contagem;
    });
  }

  // ─── Webhooks com falha ─────────────────────────────────────────────────

  /// Stream de webhooks que falharam no processamento.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamWebhooksComFalha({int dias = 1}) {
    return FirebaseFirestore.instance
        .collection(_auditLogsColl)
        .where('acao', isEqualTo: 'webhook_erro')
        .where('criado_em', isGreaterThanOrEqualTo: DateTime.now().subtract(Duration(days: dias)))
        .orderBy('criado_em', descending: true)
        .limit(50)
        .snapshots();
  }

  // ─── Limite mensal próximo do fim ───────────────────────────────────────

  /// Stream de lojistas que atingiram [percentual]% do limite mensal.
  static Stream<List<Map<String, dynamic>>> streamLojistasProximosLimite({
    double percentual = _limiteAlertaPercentual,
  }) {
    return FirebaseFirestore.instance
        .collection(_integracaoColl)
        .where('ativa', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final resultado = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final limite = data['limiteMensal'] as int? ?? 200;
        final emitidas = data['notasEmitidas'] as int? ?? 0;
        if (limite > 0 && emitidas >= limite * percentual) {
          resultado.add({
            'store_id': data['store_id'] ?? doc.id,
            'limite_mensal': limite,
            'notas_emitidas': emitidas,
            'percentual': emitidas / limite,
            'notas_restantes': limite - emitidas,
          });
        }
      }
      return resultado;
    });
  }

  // ─── Totais de documentos por provedor ──────────────────────────────────

  /// Stream de total de documentos emitidos por provedor no mês atual.
  static Stream<Map<String, int>> streamDocumentosPorProvedor({int dias = 30}) {
    final dataLimite = DateTime.now().subtract(Duration(days: dias));
    return FirebaseFirestore.instance
        .collection(_docsColl)
        .where('created_at', isGreaterThanOrEqualTo: dataLimite)
        .snapshots()
        .map((snap) {
      final Map<String, int> contagem = {};
      for (final doc in snap.docs) {
        final provider = doc.data()['provider'] as String? ?? 'unknown';
        contagem[provider] = (contagem[provider] ?? 0) + 1;
      }
      return contagem;
    });
  }

  /// Contagem de erros nas últimas [horas] horas (para alertas).
  static Future<int> contarErrosRecentes({int horas = 24}) async {
    final dataLimite = DateTime.now().subtract(Duration(hours: horas));
    final snap = await FirebaseFirestore.instance
        .collection(_auditLogsColl)
        .where('acao', whereIn: [
          'emissao_rejeitada',
          'webhook_erro',
          'webhook_recebido_erro',
          'certificado_vencido',
        ])
        .where('criado_em', isGreaterThanOrEqualTo: dataLimite)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
