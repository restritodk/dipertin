import 'package:flutter/foundation.dart' show debugPrint;

import '../services/firebase_functions_config.dart' show callFirebaseFunctionSafe;
import '../models/audit_log_model.dart';
import '../models/audit_filtros_model.dart';

/// Fachada que chama os callables da tela de Auditoria no backend.
///
/// Mascaramento de campos sensíveis é responsabilidade do backend
/// (`audit_logs_query.js::sanitizarAuditLog`). O cliente **nunca** vê
/// CPF/CNPJ/email/cartão completos.
class AuditoriaService {
  /// Busca usuários (resumo, mascarado) para a barra de pesquisa.
  static Future<List<AuditUser>> pesquisarUsuarios({
    required String termo,
    String? categoria,
    int limite = 20,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'auditLogsPesquisarUsuarios',
        parameters: {
          'termo': termo,
          if (categoria != null) 'categoria': categoria,
          'limite': limite,
        },
        timeout: const Duration(seconds: 30),
      );
      final items = (result['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => AuditUser.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      return items;
    } catch (e) {
      debugPrint('[AuditoriaService] pesquisarUsuarios falhou: $e');
      rethrow;
    }
  }

  /// Lista eventos com paginação por cursor.
  static Future<AuditPage> listarEventos({
    AuditFiltros filtros = AuditFiltros.empty,
    String? cursorDocId,
    String direction = 'next',
    int pageSize = 25,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'auditLogsListarEventos',
        parameters: {
          'filtros': filtros.toCallablePayload(),
          'cursorDocId': cursorDocId,
          'direction': direction,
          'pageSize': pageSize,
        },
        timeout: const Duration(seconds: 30),
      );
      final items = (result['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => AuditLog.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      return AuditPage(
        items: items,
        hasMore: result['hasMore'] == true,
        lastDocId: result['lastDocId']?.toString(),
        firstDocId: result['firstDocId']?.toString(),
      );
    } catch (e) {
      debugPrint('[AuditoriaService] listarEventos falhou: $e');
      rethrow;
    }
  }

  /// Solicita exportação CSV (apenas master). Retorna URL temporária 24h.
  static Future<({String url, int totalRegistros, String expiraEm})> exportarCsv({
    AuditFiltros filtros = AuditFiltros.empty,
  }) async {
    final result = await callFirebaseFunctionSafe(
      'auditLogsExportar',
      parameters: {'filtros': filtros.toCallablePayload()},
      timeout: const Duration(seconds: 120),
    );
    return (
      url: (result['url'] ?? '').toString(),
      totalRegistros: (result['total_registros'] is int)
          ? result['total_registros'] as int
          : int.tryParse('${result['total_registros']}') ?? 0,
      expiraEm: (result['expira_em_iso'] ?? '').toString(),
    );
  }

  /// Estatísticas para KPI cards.
  static Future<AuditStats> estatisticas({
    AuditFiltros filtros = AuditFiltros.empty,
  }) async {
    final result = await callFirebaseFunctionSafe(
      'auditLogsEstatisticas',
      parameters: {'filtros': filtros.toCallablePayload()},
      timeout: const Duration(seconds: 30),
    );
    return AuditStats.fromMap(Map<String, dynamic>.from(result));
  }

  /// Loga (best-effort) o acesso à tela de auditoria.
  /// Falha silenciosa — não deve quebrar a UX.
  /// Usa trava de 5 minutos para evitar duplicatas em rebuilds/reentries.
  static DateTime? _ultimoLogAcesso;

  static Future<void> logAcessoTela() async {
    // Trava: no máximo 1 log a cada 5 minutos
    if (_ultimoLogAcesso != null &&
        DateTime.now().difference(_ultimoLogAcesso!).inMinutes < 5) {
      return;
    }
    try {
      await callFirebaseFunctionSafe(
        'auditLogAcessoTelaAuditoria',
        parameters: const {},
        timeout: const Duration(seconds: 10),
      );
      _ultimoLogAcesso = DateTime.now();
    } catch (e) {
      debugPrint('[AuditoriaService] logAcessoTela falhou: $e');
    }
  }
}
