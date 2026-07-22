import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/fiscal_integration_model.dart';
import '../models/store_fiscal_settings_model.dart';
import '../models/fiscal_document_model.dart';
import 'firebase_functions_config.dart';

/// Log de rastreamento do módulo fiscal com horário absoluto (HH:mm:ss.SSS).
/// Usado para provar o fluxo etapa a etapa (cadastro/vínculo/emissão).
void _fiscalTrace(String etapa, String msg) {
  final n = DateTime.now();
  String d2(int v) => v.toString().padLeft(2, '0');
  String d3(int v) => v.toString().padLeft(3, '0');
  final hora = '${d2(n.hour)}:${d2(n.minute)}:${d2(n.second)}.${d3(n.millisecond)}';
  debugPrint('[TRACE_fiscal_svc] $hora | $etapa | $msg');
}

/// Serviço para gerenciar integrações fiscais.
///
/// SEGURANÇA:
///   - A escrita em fiscal_integrations é feita EXCLUSIVAMENTE pela callable
///     fiscalSalvarIntegracao, que criptografa o token com FISCAL_MASTER_KEY.
///   - O frontend NUNCA salva tokens em texto puro nem criptografa localmente.
///   - A leitura ainda usa o snapshot Firestore para exibir dados públicos
///     (provider, environment, status, etc.) — credentials_encrypted nunca é lido.
abstract final class FiscalIntegrationsService {
  static const String _colecaoIntegracoes = 'fiscal_integrations';
  static const String _colecaoSettings = 'store_fiscal_settings';
  static const String _colecaoDocumentos = 'fiscal_documents';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Região das funções fiscais (us-east1).
  static const String _regionFiscal = 'us-east1';

  // ─── Integrações ──────────────────────────────────────────────

  static Stream<List<FiscalIntegrationModel>> streamIntegracoes() {
    return _db
        .collection(_colecaoIntegracoes)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(FiscalIntegrationModel.fromFirestore).toList());
  }

  /// Cria uma nova integração fiscal via callable.
  ///
  /// A callable [fiscalSalvarIntegracao] criptografa cada token
  /// independentemente com FISCAL_MASTER_KEY (AES-256-GCM) e salva em:
  ///   - credentials_sandbox    (sandbox_token)
  ///   - credentials_production (production_token)
  ///
  /// SEGURANÇA:
  ///   - O frontend NUNCA criptografa tokens localmente
  ///   - Os tokens são enviados apenas para a callable e nunca persistem no frontend
  ///   - api_key no Firestore é sempre "" (esvaziado pela callable)
  ///
  /// [sandboxToken] Token para ambiente de homologação.
  /// [productionToken] Token para ambiente de produção.
  ///
  /// Na criação, pelo menos sandboxToken é obrigatório (o fluxo de
  /// homologação sempre vem primeiro).
  static Future<Map<String, dynamic>> salvarIntegracaoCallable({
    required String provider,
    required String providerName,
    required String sandboxToken,
    String? productionToken,
    String? nomeIntegracao,
    String status = 'active',
    String? environment,
    List<String>? supportedDocuments,
    String? baseUrlSandbox,
    String? baseUrlProduction,
  }) async {
    final params = <String, dynamic>{
      'provider': provider,
      'provider_name': providerName,
      'status': status,
      'sandbox_token': sandboxToken,
    };
    if (environment != null) params['environment'] = environment;
    if (productionToken != null && productionToken.trim().isNotEmpty) {
      params['production_token'] = productionToken.trim();
    }
    if (nomeIntegracao != null && nomeIntegracao.trim().isNotEmpty) {
      params['nome_integracao'] = nomeIntegracao.trim();
    }
    if (supportedDocuments != null) {
      params['supported_documents'] = supportedDocuments;
    }
    if (baseUrlSandbox != null) params['base_url_sandbox'] = baseUrlSandbox;
    if (baseUrlProduction != null) params['base_url_production'] = baseUrlProduction;

    // Rastreamento: parâmetros enviados (tokens redigidos — nunca logar segredo)
    final paramsLog = <String, dynamic>{
      for (final e in params.entries)
        e.key: (e.key == 'sandbox_token' || e.key == 'production_token')
            ? '***(${(e.value as String).length} chars)'
            : e.value,
    };
    _fiscalTrace('salvarIntegracaoCallable',
        'ENTRADA — region=$_regionFiscal, params=$paramsLog');

    final sw = Stopwatch()..start();
    try {
      final res = await callFirebaseFunctionSafe(
        'fiscalSalvarIntegracao',
        parameters: params,
        timeout: const Duration(seconds: 30),
        region: _regionFiscal,
      );
      sw.stop();
      _fiscalTrace('salvarIntegracaoCallable',
          'RETORNO OK — ${sw.elapsedMilliseconds}ms, resposta=$res');
      return res;
    } catch (e) {
      sw.stop();
      _fiscalTrace('salvarIntegracaoCallable',
          'EXCEÇÃO — ${sw.elapsedMilliseconds}ms, tipo=${e.runtimeType}: $e');
      rethrow;
    }
  }

  /// Atualiza uma integração existente via callable.
  ///
  /// Apenas os tokens fornecidos são criptografados e atualizados.
  /// Tokens com valor vazio/null são PRESERVADOS (não sobrescrevidos).
  ///
  /// Isso permite que o admin altere apenas o token de homologação
  /// sem perder o token de produção, e vice-versa.
  static Future<Map<String, dynamic>> atualizarIntegracaoCallable({
    required String integrationId,
    required String provider,
    required String providerName,
    String? sandboxToken,
    String? productionToken,
    String? nomeIntegracao,
    String? status,
    String? environment,
    List<String>? supportedDocuments,
    String? baseUrlSandbox,
    String? baseUrlProduction,
  }) async {
    final params = <String, dynamic>{
      'integration_id': integrationId,
      'provider': provider,
      'provider_name': providerName,
    };
    if (environment != null) params['environment'] = environment;

    // Só envia token se foi informado (senão a callable preserva o existente)
    if (sandboxToken != null && sandboxToken.trim().isNotEmpty) {
      params['sandbox_token'] = sandboxToken.trim();
    }
    if (productionToken != null && productionToken.trim().isNotEmpty) {
      params['production_token'] = productionToken.trim();
    }

    if (nomeIntegracao != null) params['nome_integracao'] = nomeIntegracao.trim();
    if (status != null) params['status'] = status;
    if (supportedDocuments != null) params['supported_documents'] = supportedDocuments;
    if (baseUrlSandbox != null) params['base_url_sandbox'] = baseUrlSandbox;
    if (baseUrlProduction != null) params['base_url_production'] = baseUrlProduction;

    return callFirebaseFunctionSafe(
      'fiscalSalvarIntegracao',
      parameters: params,
      timeout: const Duration(seconds: 30),
      region: _regionFiscal,
    );
  }

  /// Remove uma integração (escrita direta no Firestore — sem token, sem risco).
  static Future<void> removerIntegracao(String id) async {
    await _db.collection(_colecaoIntegracoes).doc(id).delete();
  }

  // ─── (Métodos legados removidos por segurança) ───────────────
  // salvarIntegracao() e atualizarIntegracao() foram removidos.
  // Usar salvarIntegracaoCallable() e atualizarIntegracaoCallable().

  // ─── Vínculo loja ↔ integração (via callable) ───────────────

  /// Vincula uma loja a uma integração fiscal via callable.
  ///
  /// A callable [fiscalVincularIntegracaoLoja] é executada no backend e:
  ///   - Valida autenticação e permissão staff/admin
  ///   - Confirma que [integrationId] existe e está ativa
  ///   - Preenche [integration_data] com whitelist de campos públicos
  ///   - Remove [integration_removida_em] com FieldValue.delete()
  ///   - Preserva company_tax_data, certificado, flags e configurações
  ///
  /// NUNCA expõe credentials_encrypted ou tokens para o frontend.
  ///
  /// Idempotente: pode ser chamado múltiplas vezes (vínculo inicial,
  /// troca de integração, revínculo, reparo de vínculo incompleto).
  static Future<Map<String, dynamic>> vincularIntegracaoLojaCallable({
    required String storeId,
    required String integrationId,
  }) async {
    return callFirebaseFunctionSafe(
      'fiscalVincularIntegracaoLoja',
      parameters: {
        'storeId': storeId,
        'integrationId': integrationId,
      },
      timeout: const Duration(seconds: 30),
      region: _regionFiscal,
    );
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

  /// Cria ou atualiza as configurações fiscais de uma loja (EXCETO vínculo).
  ///
  /// ATENÇÃO: Este método NÃO gerencia o vínculo com a integração fiscal.
  /// Para vincular/reparar/trocar integração, use [vincularIntegracaoLojaCallable].
  ///
  /// Busca por `store_id` existente; se encontrar, atualiza os campos
  /// fornecidos. Caso contrário, cria um novo documento.
  ///
  /// SEGURANÇA: Apenas dados configuráveis da loja são salvos aqui.
  /// Dados da integração (integration_data) são gerenciados exclusivamente
  /// pela callable [vincularIntegracaoLojaCallable] e pelo trigger
  /// [onFiscalIntegrationWrite] (Admin SDK).
  static Future<void> salvarOuAtualizarSettings({
    required String storeId,
    bool enableNfe = false,
    bool enableNfce = false,
    bool enableNfse = false,
    String status = 'active',
    Map<String, dynamic>? companyTaxData,
    Map<String, dynamic>? nfeSettings,
    // certificateDataEncrypted removido — certificado é mantido apenas em fiscal_certificates
  }) async {
    final existente = await buscarSettingsPorStore(storeId);
    if (existente != null) {
      final updates = <String, dynamic>{
        'enable_nfe': enableNfe,
        'enable_nfce': enableNfce,
        'enable_nfse': enableNfse,
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };
      // Só atualiza company_tax_data se foi fornecido
      if (companyTaxData != null) {
        updates['company_tax_data'] = companyTaxData;
      }
      if (nfeSettings != null) {
        updates['nfe_settings'] = nfeSettings;
      }
      // certificate_data_encrypted NÃO é mais salvo aqui — segurança
      await _db.collection(_colecaoSettings).doc(existente.id).update(updates);
    } else {
      final data = <String, dynamic>{
        'store_id': storeId,
        'enable_nfe': enableNfe,
        'enable_nfce': enableNfce,
        'enable_nfse': enableNfse,
        'company_tax_data': companyTaxData,
        // certificate_data_encrypted NÃO é mais salvo aqui — segurança
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
