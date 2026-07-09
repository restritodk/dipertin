import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../firebase_functions_config.dart';
import '../../models/fiscal_document_model.dart';

/// Service para operações pós-emissão de NF-e:
/// - Consulta e atualização automática de status
/// - Download de XML e DANFE
/// - Cancelamento de notas
/// - Histórico de status
abstract final class FiscalPosEmissaoService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Constantes de status
  static const String statusProcessando = 'processando';
  static const String statusAguardando = 'aguardando_processamento';
  static const String statusAutorizada = 'autorizada';
  static const String statusRejeitada = 'rejeitada';
  static const String statusCancelada = 'cancelada';
  static const String statusErro = 'erro';

  static const String _region = 'southamerica-east1';
  static const Duration _timeout = Duration(seconds: 120);

  /// Mapa de status para cores (frontend)
  static Color statusCor(String status) {
    switch (status) {
      case 'autorizada':
      case 'success':
      case 'sucesso':
        return const Color(0xFF22C55E);
      case 'processando':
      case 'processing':
      case 'aguardando_processamento':
        return const Color(0xFFFF8F00);
      case 'rejeitada':
      case 'rejected':
      case 'erro':
      case 'error':
      case 'erro_consulta':
        return const Color(0xFFEF4444);
      case 'cancelada':
      case 'cancelled':
      case 'cancelamento_homologado':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF64748B);
    }
  }

  /// Label amigável do status
  static String statusLabel(String status) {
    switch (status) {
      case 'autorizada':
        return 'Autorizada';
      case 'processando':
        return 'Processando';
      case 'aguardando_processamento':
        return 'Aguardando processamento';
      case 'rejeitada':
        return 'Rejeitada';
      case 'cancelada':
        return 'Cancelada';
      case 'cancelamento_homologado':
        return 'Cancelamento homologado';
      case 'erro':
        return 'Erro';
      case 'contingencia':
        return 'Contingência';
      case 'contingencia_resolvida':
        return 'Cont. resolvida';
      case 'cc_e_enviada':
        return 'CC-e enviada';
      case 'numeracao_inutilizada':
        return 'Numeração inutilizada';
      default:
        return status;
    }
  }

  static IconData statusIcon(String status) {
    switch (status) {
      case 'autorizada':
        return Icons.check_circle;
      case 'processando':
      case 'aguardando_processamento':
        return Icons.hourglass_top;
      case 'rejeitada':
      case 'erro':
        return Icons.cancel;
      case 'cancelada':
      case 'cancelamento_homologado':
        return Icons.block;
      case 'contingencia':
        return Icons.warning_amber;
      default:
        return Icons.help_outline;
    }
  }

  /// Indica se o status é final (não muda mais sozinho)
  static bool isStatusFinal(String status) {
    return ['autorizada', 'rejeitada', 'cancelada', 'cancelamento_homologado', 'erro']
        .contains(status);
  }

  static bool isAutorizada(String status) => status == 'autorizada';
  static bool isRejeitada(String status) => status == 'rejeitada';
  static bool isCancelada(String status) =>
      status == 'cancelada' || status == 'cancelamento_homologado';
  static bool isProcessando(String status) =>
      status == 'processando' || status == 'aguardando_processamento';

  /// Consulta automática pós-emissão: chama o backend com retry progressivo.
  static Future<Map<String, dynamic>> consultarEAtualizarStatus({
    required String integrationId,
    required String storeId,
    required String chaveAcesso,
    required String documentoId,
  }) async {
    try {
      return await callFirebaseFunctionSafe(
        'fiscalConsultarEAtualizarStatus',
        parameters: {
          'integration_id': integrationId,
          'store_id': storeId,
          'chave_acesso': chaveAcesso,
          'documento_id': documentoId,
        },
        region: _region,
        timeout: _timeout,
      );
    } catch (e) {
      debugPrint('[FiscalPosEmissao] Erro consultarStatus: $e');
      return {
        'sucesso': false,
        'status': 'erro_consulta',
        'mensagem': 'Erro ao consultar: $e',
        'documento_id': documentoId,
      };
    }
  }

  /// Executa consulta automática com retry progressivo.
  /// Retorna o resultado da última tentativa.
  static Future<Map<String, dynamic>> consultarComRetry({
    required String integrationId,
    required String storeId,
    required String chaveAcesso,
    required String documentoId,
  }) async {
    final delays = [
      const Duration(seconds: 5),
      const Duration(seconds: 15),
      const Duration(seconds: 30),
    ];
    Map<String, dynamic>? ultimoResultado;

    for (int i = 0; i < delays.length; i++) {
      await Future.delayed(delays[i]);

      ultimoResultado = await consultarEAtualizarStatus(
        integrationId: integrationId,
        storeId: storeId,
        chaveAcesso: chaveAcesso,
        documentoId: documentoId,
      );

      final status = ultimoResultado['status'] as String? ?? '';
      final sucesso = ultimoResultado['sucesso'] as bool? ?? false;

      // Se já finalizou (autorizada, rejeitada, cancelada, erro), para
      if (isStatusFinal(status) || sucesso) {
        debugPrint(
            '[FiscalPosEmissao] Retry concluído na tentativa ${i + 1}: $status');
        return ultimoResultado;
      }
    }

    return ultimoResultado ??
        {
          'sucesso': false,
          'status': 'processando',
          'mensagem':
              'Tempo limite excedido após ${delays.length} tentativas.',
          'documento_id': documentoId,
        };
  }

  /// Stream de documentos fiscais de uma loja.
  static Stream<List<FiscalDocumentModel>> streamDocumentos(String storeId) {
    return _db
        .collection('fiscal_documents')
        .where('store_id', isEqualTo: storeId)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map(FiscalDocumentModel.fromFirestore)
            .toList());
  }

  /// Stream de todos os documentos fiscais (admin).
  static Stream<List<FiscalDocumentModel>> streamDocumentosAdmin() {
    return _db
        .collection('fiscal_documents')
        .orderBy('created_at', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map(FiscalDocumentModel.fromFirestore)
            .toList());
  }

  /// Stream do histórico de status de um documento.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamHistoricoStatus(
    String documentoId,
  ) {
    return _db
        .collection('fiscal_status_history')
        .where('fiscalDocumentId', isEqualTo: documentoId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Busca logs webhook de um documento.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamWebhookLogs(
    String chaveAcesso,
  ) {
    return _db
        .collection('fiscal_webhooks')
        .where('chaveAcesso', isEqualTo: chaveAcesso)
        .orderBy('receivedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Baixa o conteúdo de XML ou DANFE de uma URL pública.
  static Future<Map<String, dynamic>> baixarConteudoUrl({
    required String url,
    required String nomeArquivo,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return {
          'sucesso': true,
          'conteudo': response.bodyBytes,
          'nome': nomeArquivo,
        };
      }
      return {'sucesso': false, 'erro': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'sucesso': false, 'erro': 'Erro: $e'};
    }
  }
}
