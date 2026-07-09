import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/fiscal_document_model.dart';

/// Resumo agregado de documentos fiscais para o admin.
class AdminFiscalResumo {
  const AdminFiscalResumo({
    required this.totalDocumentos,
    required this.totalAutorizadas,
    required this.totalRejeitadas,
    required this.totalCanceladas,
    required this.totalPendentes,
    required this.totalContingencia,
    required this.totalLojasComEmissao,
  });

  final int totalDocumentos;
  final int totalAutorizadas;
  final int totalRejeitadas;
  final int totalCanceladas;
  final int totalPendentes;
  final int totalContingencia;
  final int totalLojasComEmissao;
}

/// Agregado por loja.
class AdminFiscalLojaResumo {
  AdminFiscalLojaResumo({
    required this.storeId,
    this.storeName,
    this.total = 0,
    this.autorizadas = 0,
    this.rejeitadas = 0,
    this.canceladas = 0,
    this.pendentes = 0,
    this.ultimaEmissao,
    this.valorTotal = 0,
    this.provedor,
  });

  final String storeId;
  String? storeName;
  int total;
  int autorizadas;
  int rejeitadas;
  int canceladas;
  int pendentes;
  Timestamp? ultimaEmissao;
  double valorTotal;
  String? provedor;

  String get storeLabel => storeName ?? storeId;
}

/// Service para o dashboard fiscal do admin.
///
/// Lê dados da coleção `fiscal_documents` (visível ao admin pelas rules)
/// e agrega por loja para monitoramento.
abstract final class FiscalAdminService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Cache do nome das lojas (store_fiscal_settings).
  static final Map<String, String> _storeNameCache = {};

  /// Stream do resumo geral de documentos fiscais (admin).
  static Stream<AdminFiscalResumo> streamResumo() {
    return _db
        .collection('fiscal_documents')
        .snapshots()
        .map((snap) {
      final docs = snap.docs.map(FiscalDocumentModel.fromFirestore).toList();
      return _calcularResumo(docs);
    });
  }

  /// Stream da lista de lojas com emissão fiscal, agregada.
  static Stream<List<AdminFiscalLojaResumo>> streamLojasComEmissao() {
    return Stream.multi((controller) async {
      // 1. Carrega nomes das lojas das settings
      try {
        final settingsSnap =
            await _db.collection('store_fiscal_settings').get();
        for (final doc in settingsSnap.docs) {
          final data = doc.data();
          final storeId = data['store_id'] as String?;
          final name = data['store_name'] as String?;
          if (storeId != null && storeId.isNotEmpty) {
            _storeNameCache[storeId] =
                name ?? _storeNameCache[storeId] ?? storeId;
          }
        }
      } catch (_) {
        // fallback silencioso
      }

      // 2. Escuta documentos fiscais
      final sub = _db
          .collection('fiscal_documents')
          .orderBy('created_at', descending: true)
          .snapshots()
          .listen((snap) {
        final docs = snap.docs.map(FiscalDocumentModel.fromFirestore).toList();
        final porLoja = <String, AdminFiscalLojaResumo>{};

        for (final doc in docs) {
          final loja = porLoja.putIfAbsent(
            doc.storeId,
            () => AdminFiscalLojaResumo(storeId: doc.storeId),
          );
          loja.storeName ??= _storeNameCache[doc.storeId] ?? doc.storeId;
          loja.total++;
          loja.provedor ??= doc.provider;
          if (doc.isAutorizada) loja.autorizadas++;
          if (doc.isRejeitada) loja.rejeitadas++;
          if (doc.isCancelada) loja.canceladas++;
          if (doc.isProcessando) loja.pendentes++;
          if (doc.issuedAt != null &&
              (loja.ultimaEmissao == null ||
                  doc.issuedAt!.toDate().isAfter(
                      loja.ultimaEmissao!.toDate()))) {
            loja.ultimaEmissao = doc.issuedAt;
          }
        }

        final lista = porLoja.values.toList()
          ..sort((a, b) => b.total.compareTo(a.total));
        controller.add(lista);
      }, onError: controller.addError);

      controller.onCancel = sub.cancel;
    });
  }

  /// Stream de todos os documentos fiscais recentes (timeline).
  static Stream<List<FiscalDocumentModel>> streamDocumentosRecentes({
    int limite = 100,
  }) {
    return _db
        .collection('fiscal_documents')
        .orderBy('created_at', descending: true)
        .limit(limite)
        .snapshots()
        .map((snap) =>
            snap.docs.map(FiscalDocumentModel.fromFirestore).toList());
  }

  // ═══════════════════════════════════════════════════════════
  // MÉTODOS USADOS PELA TELA AdminFiscalScreen
  // ═══════════════════════════════════════════════════════════

  /// Stream de todas as configurações fiscais (store_fiscal_settings).
  /// Usado pela tela [AdminFiscalScreen] para listar integrações.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamTodasConfiguracoes() {
    return _db
        .collection('store_fiscal_settings')
        .snapshots();
  }

  /// Reativa uma integração fiscal (status → 'active').
  static Future<void> reativarIntegracao(String docId) async {
    await _db
        .collection('store_fiscal_settings')
        .doc(docId)
        .update({'status': 'active', 'updated_at': FieldValue.serverTimestamp()});
  }

  /// Suspende uma integração fiscal (status → 'suspended').
  static Future<void> suspenderIntegracao(String docId) async {
    await _db
        .collection('store_fiscal_settings')
        .doc(docId)
        .update({'status': 'suspended', 'updated_at': FieldValue.serverTimestamp()});
  }

  /// Remove permanentemente uma integração fiscal.
  static Future<void> removerIntegracao(String docId) async {
    await _db
        .collection('store_fiscal_settings')
        .doc(docId)
        .delete();
  }

  /// Stream de logs de auditoria fiscal para uma loja específica.
  /// Coleção: `fiscal_audit_logs` (filtrado por `store_id`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamAuditLogs(
      String storeId) {
    return _db
        .collection('fiscal_audit_logs')
        .where('store_id', isEqualTo: storeId)
        .orderBy('criado_em', descending: true)
        .limit(200)
        .snapshots();
  }

  // ── Helpers ──

  static AdminFiscalResumo _calcularResumo(List<FiscalDocumentModel> docs) {
    int autorizadas = 0, rejeitadas = 0, canceladas = 0;
    int pendentes = 0, contingencia = 0;
    final lojasSet = <String>{};

    for (final doc in docs) {
      lojasSet.add(doc.storeId);
      if (doc.isAutorizada) autorizadas++;
      if (doc.isRejeitada) rejeitadas++;
      if (doc.isCancelada) canceladas++;
      if (doc.isProcessando) pendentes++;
      if (doc.isContingencia) contingencia++;
    }

    return AdminFiscalResumo(
      totalDocumentos: docs.length,
      totalAutorizadas: autorizadas,
      totalRejeitadas: rejeitadas,
      totalCanceladas: canceladas,
      totalPendentes: pendentes,
      totalContingencia: contingencia,
      totalLojasComEmissao: lojasSet.length,
    );
  }
}
