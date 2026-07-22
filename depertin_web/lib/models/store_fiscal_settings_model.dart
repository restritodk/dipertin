import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuração fiscal de uma loja.
///
/// Coleção: `store_fiscal_settings/{id}`
///
/// SEGURANÇA:
/// - credentials_encrypted NÃO está neste documento (está em fiscal_integrations, staff-only)
/// - certificate_data_encrypted NÃO está neste documento (está em fiscal_certificates, staff-only)
/// - Apenas certificate_info PÚBLICO fica aqui (configured, status, subject_name, valid_until)
class StoreFiscalSettingsModel {
  final String id;
  final String storeId;
  final String integrationId;
  final bool enableNfe;
  final bool enableNfce;
  final bool enableNfse;
  final Map<String, dynamic>? companyTaxData;
  final Map<String, dynamic>? nfeSettings;
  final Map<String, dynamic>? nfceSettings;
  final Map<String, dynamic>? nfseSettings;
  final String? webhookUrl;
  final String status; // active | inactive | error
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  /// Informações públicas do certificado (campos seguros, sem conteúdo ou senha).
  final Map<String, dynamic>? certificateInfo;

  StoreFiscalSettingsModel({
    required this.id,
    required this.storeId,
    required this.integrationId,
    this.enableNfe = false,
    this.enableNfce = false,
    this.enableNfse = false,
    this.companyTaxData,
    this.nfeSettings,
    this.nfceSettings,
    this.nfseSettings,
    this.webhookUrl,
    this.status = 'inactive',
    this.createdAt,
    this.updatedAt,
    this.certificateInfo,
  });

  bool get isAtivo => status == 'active';

  static StoreFiscalSettingsModel fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StoreFiscalSettingsModel(
      id: doc.id,
      storeId: d['store_id'] as String? ?? '',
      integrationId: d['integration_id'] as String? ?? '',
      enableNfe: d['enable_nfe'] as bool? ?? false,
      enableNfce: d['enable_nfce'] as bool? ?? false,
      enableNfse: d['enable_nfse'] as bool? ?? false,
      companyTaxData: d['company_tax_data'] as Map<String, dynamic>?,
      certificateInfo: d['certificate_info'] as Map<String, dynamic>?,
      nfeSettings: d['nfe_settings'] as Map<String, dynamic>?,
      nfceSettings: d['nfce_settings'] as Map<String, dynamic>?,
      nfseSettings: d['nfse_settings'] as Map<String, dynamic>?,
      webhookUrl: d['webhook_url'] as String?,
      status: d['status'] as String? ?? 'inactive',
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'store_id': storeId,
        'integration_id': integrationId,
        'enable_nfe': enableNfe,
        'enable_nfce': enableNfce,
        'enable_nfse': enableNfse,
        'company_tax_data': companyTaxData,
        'nfe_settings': nfeSettings,
        'nfce_settings': nfceSettings,
        'nfse_settings': nfseSettings,
        'webhook_url': webhookUrl,
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
}
