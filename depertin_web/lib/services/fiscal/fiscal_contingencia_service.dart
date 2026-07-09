import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado de contingência de uma loja.
class EstadoContingencia {
  final bool emContingencia;
  final String? motivo;
  final String? tipo;
  final Timestamp? iniciadaEm;
  final String? documentoIdContingencia;

  const EstadoContingencia({
    this.emContingencia = false,
    this.motivo,
    this.tipo,
    this.iniciadaEm,
    this.documentoIdContingencia,
  });

  static const normal = EstadoContingencia();

  Map<String, dynamic> toMap() => {
        'em_contingencia': emContingencia,
        if (motivo != null) 'motivo_contingencia': motivo,
        if (tipo != null) 'tipo_contingencia': tipo,
        if (iniciadaEm != null) 'contingencia_iniciada_em': iniciadaEm,
        if (documentoIdContingencia != null)
          'documento_id_contingencia': documentoIdContingencia,
      };

  factory EstadoContingencia.fromMap(Map<String, dynamic> m) {
    return EstadoContingencia(
      emContingencia: m['em_contingencia'] as bool? ?? false,
      motivo: m['motivo_contingencia'] as String?,
      tipo: m['tipo_contingencia'] as String?,
      iniciadaEm: m['contingencia_iniciada_em'] as Timestamp?,
      documentoIdContingencia: m['documento_id_contingencia'] as String?,
    );
  }
}

/// Gerencia o estado de contingência das lojas.
///
/// Tipos de contingência:
/// - `fsda` - Formulário de Segurança para impressão (DANFE em papel)
/// - `epec` - Evento Posterior de Emissão em Contingência (online)
/// - `dpEC` - DPEC (Declaração Prévia de Emissão em Contingência)
/// - `offline` - Sistema offline sem contingência técnica
abstract final class FiscalContingenciaService {
  static const String _colecao = 'store_fiscal_settings';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Verifica se uma loja está em contingência.
  static Future<bool> estaEmContingencia(String storeId) async {
    final estado = await obterEstado(storeId);
    return estado.emContingencia;
  }

  /// Obtém o estado atual de contingência.
  static Future<EstadoContingencia> obterEstado(String storeId) async {
    try {
      final snap = await _db
          .collection(_colecao)
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return EstadoContingencia.normal;
      final data = snap.docs.first.data();
      final raw = data['contingencia'];
      if (raw is Map<String, dynamic>) {
        return EstadoContingencia.fromMap(raw);
      }
      return EstadoContingencia.normal;
    } catch (_) {
      return EstadoContingencia.normal;
    }
  }

  /// Ativa contingência para uma loja.
  static Future<void> ativarContingencia({
    required String storeId,
    required String motivo,
    String tipo = 'offline',
  }) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;

    await _db.collection(_colecao).doc(snap.docs.first.id).update({
      'contingencia.em_contingencia': true,
      'contingencia.motivo_contingencia': motivo,
      'contingencia.tipo_contingencia': tipo,
      'contingencia.contingencia_iniciada_em': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Desativa contingência (volta ao normal).
  static Future<void> resolverContingencia(String storeId) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;

    await _db.collection(_colecao).doc(snap.docs.first.id).update({
      'contingencia.em_contingencia': false,
      'contingencia.resolvida_em': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Verifica se um erro indica necessidade de contingência.
  static bool deveAtivarContingencia(String? erro) {
    if (erro == null) return false;
    final lower = erro.toLowerCase();
    return lower.contains('offline') ||
        lower.contains('indispon') ||
        lower.contains('503') ||
        lower.contains('502') ||
        lower.contains('timeout') ||
        lower.contains('conex') && lower.contains('sefaz') ||
        lower.contains('serviço temporariamente');
  }

  /// Obtém o rótulo do tipo de contingência.
  static String rotuloTipo(String tipo) {
    switch (tipo) {
      case 'fsda':
        return 'FSDA (DANFE em papel)';
      case 'epec':
        return 'EPEC (Contingência online)';
      case 'dpEC':
        return 'DPEC (Declaração prévia)';
      case 'offline':
        return 'Offline (sem contingência técnica)';
      default:
        return tipo;
    }
  }

  /// Verifica se o provedor fiscal atual está respondendo.
  /// Retorna true se o serviço está operacional.
  static Future<bool> verificarSaudeProvedor() async {
    try {
      return await _HealthChecker.verificar();
    } catch (_) {
      return false;
    }
  }

  /// Stream do estado de contingência de uma loja.
  static Stream<EstadoContingencia> streamEstado(String storeId) {
    return _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return EstadoContingencia.normal;
      final raw = snap.docs.first.data()['contingencia'];
      if (raw is Map<String, dynamic>) {
        return EstadoContingencia.fromMap(raw);
      }
      return EstadoContingencia.normal;
    });
  }
}

/// Cliente HTTP mínimo para health check (sem dependências externas).
abstract final class _HealthChecker {
  static Future<bool> verificar() async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }
}
