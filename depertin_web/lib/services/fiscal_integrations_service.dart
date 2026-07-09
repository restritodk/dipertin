import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fiscal_integration_model.dart';
import '../models/store_fiscal_settings_model.dart';
import '../models/fiscal_document_model.dart';
import 'fiscal/fiscal_crypto_util.dart';

/// Serviço para gerenciar integrações fiscais.
abstract final class FiscalIntegrationsService {
  static const String _colecaoIntegracoes = 'fiscal_integrations';
  static const String _colecaoSettings = 'store_fiscal_settings';
  static const String _colecaoDocumentos = 'fiscal_documents';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Integrações ──────────────────────────────────────────────

  static Stream<List<FiscalIntegrationModel>> streamIntegracoes() {
    return _db
        .collection(_colecaoIntegracoes)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(FiscalIntegrationModel.fromFirestore).toList());
  }

  static Future<void> salvarIntegracao(
    FiscalIntegrationModel model,
    Map<String, dynamic> credentials,
  ) async {
    final data = model.toCreateMap();
    // Criptografa apenas o token/api_key com AES-256-GCM antes de salvar
    final apiKey = credentials['api_key'] as String? ??
        credentials['token'] as String? ??
        '';
    data['credentials_encrypted'] =
        apiKey.isNotEmpty ? FiscalCryptoUtil.encrypt(apiKey) : '';
    await _db.collection(_colecaoIntegracoes).add(data);
  }

  static Future<void> atualizarIntegracao(
    String id,
    FiscalIntegrationModel model,
    Map<String, dynamic>? credentials,
  ) async {
    final data = model.toMap();
    if (credentials != null) {
      final apiKey = credentials['api_key'] as String? ??
          credentials['token'] as String? ??
          '';
      if (apiKey.isNotEmpty) {
        data['credentials_encrypted'] = FiscalCryptoUtil.encrypt(apiKey);
      }
    }
    await _db.collection(_colecaoIntegracoes).doc(id).update(data);
  }

  static Future<void> removerIntegracao(String id) async {
    await _db.collection(_colecaoIntegracoes).doc(id).delete();
  }

  // ─── Settings da loja ─────────────────────────────────────────

  static Stream<List<StoreFiscalSettingsModel>> streamSettings() {
    return _db
        .collection(_colecaoSettings)
        .snapshots()
        .map((snap) =>
            snap.docs.map(StoreFiscalSettingsModel.fromFirestore).toList());
  }

  /// Busca configuração fiscal de uma loja específica.
  static Future<StoreFiscalSettingsModel?> buscarSettingsPorStore(
    String storeId,
  ) async {
    final snap = await _db
        .collection(_colecaoSettings)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return StoreFiscalSettingsModel.fromFirestore(snap.docs.first);
  }

  static Future<void> salvarSettings(StoreFiscalSettingsModel model) async {
    await _db.collection(_colecaoSettings).add(model.toCreateMap());
  }

  static Future<void> atualizarSettings(
    String id,
    StoreFiscalSettingsModel model,
  ) async {
    await _db.collection(_colecaoSettings).doc(id).update(model.toMap());
  }

  /// Cria ou atualiza as configurações fiscais de uma loja.
  ///
  /// Busca por `store_id` existente; se encontrar, atualiza os campos
  /// fornecidos. Caso contrário, cria um novo documento.
  /// Usado para sincronizar configurações ao criar integração de lojista.
  ///
  /// Se [integrationId] for fornecido, vincula a settings à integração
  /// fiscal global. Caso contrário, tenta localizar automaticamente a
  /// primeira integração ativa disponível em `fiscal_integrations`.
  static Future<void> salvarOuAtualizarSettings({
    required String storeId,
    bool enableNfe = false,
    bool enableNfce = false,
    bool enableNfse = false,
    String status = 'active',
    String? integrationId,
    Map<String, dynamic>? companyTaxData,
    Map<String, dynamic>? nfeSettings,
    String? certificateDataEncrypted,
  }) async {
    // Resolve integrationId: se não informado, busca a primeira ativa
    String? resolvedId = integrationId;
    if (resolvedId == null || resolvedId.isEmpty) {
      resolvedId = await _buscarPrimeiraIntegracaoAtiva();
    }

    // Desnormaliza dados da integração (cópia dos campos relevantes)
    // para que o lojista possa ler sem precisar de acesso a fiscal_integrations
    Map<String, dynamic>? integrationData;
    if (resolvedId != null && resolvedId.isNotEmpty) {
      integrationData = await _buscarDadosIntegracao(resolvedId);
    }

    final existente = await buscarSettingsPorStore(storeId);
    if (existente != null) {
      final updates = <String, dynamic>{
        'enable_nfe': enableNfe,
        'enable_nfce': enableNfce,
        'enable_nfse': enableNfse,
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (resolvedId != null && resolvedId.isNotEmpty) {
        updates['integration_id'] = resolvedId;
      }
      if (integrationData != null) {
        updates['integration_data'] = integrationData;
      }
      // Só atualiza company_tax_data se foi fornecido
      if (companyTaxData != null) {
        updates['company_tax_data'] = companyTaxData;
      }
      if (nfeSettings != null) {
        updates['nfe_settings'] = nfeSettings;
      }
      if (certificateDataEncrypted != null) {
        updates['certificate_data_encrypted'] = certificateDataEncrypted;
      }
      await _db.collection(_colecaoSettings).doc(existente.id).update(updates);
    } else {
      final data = <String, dynamic>{
        'store_id': storeId,
        'integration_id': resolvedId,
        'integration_data': integrationData,
        'enable_nfe': enableNfe,
        'enable_nfce': enableNfce,
        'enable_nfse': enableNfse,
        'company_tax_data': companyTaxData,
        'certificate_data_encrypted': certificateDataEncrypted,
        'nfe_settings': nfeSettings,
        'nfce_settings': null,
        'nfse_settings': null,
        'webhook_url': null,
        'status': status,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      await _db.collection(_colecaoSettings).add(data);
    }
  }

  /// Busca os campos essenciais de uma integração fiscal em
  /// `fiscal_integrations/{id}` para desnormalizar em `store_fiscal_settings`.
  ///
  /// Retorna um map com `provider`, `provider_name`, `environment`,
  /// `base_url_sandbox`, `base_url_production` e `supported_documents`.
  /// Retorna `null` se a integração não for encontrada.
  static Future<Map<String, dynamic>?> _buscarDadosIntegracao(
      String integrationId) async {
    try {
      final doc = await _db
          .collection(_colecaoIntegracoes)
          .doc(integrationId)
          .get();
      if (!doc.exists) return null;
      final d = doc.data() ?? {};
      return {
        'provider': d['provider'],
        'provider_name': d['provider_name'],
        'environment': d['environment'],
        'base_url_sandbox': d['base_url_sandbox'],
        'base_url_production': d['base_url_production'],
        'supported_documents': d['supported_documents'],
        'credentials_encrypted': d['credentials_encrypted'],
      };
    } catch (_) {
      return null;
    }
  }

  /// Busca o ID da primeira integração fiscal ativa.
  ///
  /// Usado para vincular automaticamente um lojista à integração
  /// disponível quando nenhum [integrationId] é especificado.
  static Future<String?> _buscarPrimeiraIntegracaoAtiva() async {
    try {
      final snap = await _db
          .collection(_colecaoIntegracoes)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.id;
    } catch (_) {
      // Falha silenciosa
    }
    return null;
  }

  // ─── Documentos fiscais ───────────────────────────────────────

  static Stream<List<FiscalDocumentModel>> streamDocumentos() {
    return _db
        .collection(_colecaoDocumentos)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map(FiscalDocumentModel.fromFirestore).toList());
  }

  static Future<void> registrarDocumento(
    FiscalDocumentModel model,
  ) async {
    await _db.collection(_colecaoDocumentos).add(model.toCreateMap());
  }

  static Future<void> atualizarStatusDocumento(
    String id,
    String status, {
    String? accessKey,
    String? protocol,
    String? xmlUrl,
    String? pdfUrl,
    String? rejectionReason,
  }) async {
    final data = <String, dynamic>{
      'status': status,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (accessKey != null) data['access_key'] = accessKey;
    if (protocol != null) data['protocol'] = protocol;
    if (xmlUrl != null) data['xml_url'] = xmlUrl;
    if (pdfUrl != null) data['pdf_url'] = pdfUrl;
    if (rejectionReason != null) data['rejection_reason'] = rejectionReason;
    await _db.collection(_colecaoDocumentos).doc(id).update(data);
  }
}
