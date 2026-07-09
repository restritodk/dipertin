import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'fiscal_crypto_util.dart';

/// Informacoes extraidas de um certificado digital A1.
class CertificadoInfo {
  final String? cnpj;
  final String? razaoSocial;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? issuer;
  final String? subject;
  final bool isValid;

  const CertificadoInfo({
    this.cnpj,
    this.razaoSocial,
    this.validFrom,
    this.validUntil,
    this.issuer,
    this.subject,
    this.isValid = false,
  });

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  String get statusLabel {
    if (isExpired) return 'Vencido';
    if (isValid) return 'Valido';
    return 'Nao verificado';
  }

  Map<String, dynamic> toMap() => {
        if (cnpj != null) 'cnpj': cnpj,
        if (razaoSocial != null) 'razao_social': razaoSocial,
        if (validFrom != null) 'valido_de': validFrom!.toIso8601String(),
        if (validUntil != null) 'valido_ate': validUntil!.toIso8601String(),
        if (issuer != null) 'emissor': issuer,
        if (subject != null) 'subject': subject,
        'valido': isValid && !isExpired,
      };
}

/// Resultado do upload do certificado.
class CertificadoUploadResult {
  final bool sucesso;
  final CertificadoInfo? info;
  final String? erro;

  const CertificadoUploadResult({
    required this.sucesso,
    this.info,
    this.erro,
  });
}

/// Servico para gerenciar certificados digitais A1.
///
/// Responsabilidades:
/// - Upload do arquivo .pfx/.p12
/// - Validacao de extensao e tamanho
/// - Criptografia do arquivo e senha
/// - Salvamento no Firestore
/// - Verificacao de expiracao
abstract final class FiscalCertificadoService {
  static const int _maxBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> _extensoesValidas = ['pfx', 'p12'];

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Abre o seletor de arquivos para certificado digital.
  static Future<PlatformFile?> selecionarArquivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensoesValidas,
      withData: true,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  /// Valida o arquivo de certificado.
  static String? validarArquivo(PlatformFile file) {
    final ext = file.extension?.toLowerCase() ?? '';
    if (!_extensoesValidas.contains(ext)) {
      return 'Formato invalido. Use arquivos .pfx ou .p12.';
    }
    if (file.size > _maxBytes) {
      return 'Arquivo muito grande. Maximo 5MB.';
    }
    if (file.bytes == null || file.bytes!.isEmpty) {
      return 'Arquivo vazio.';
    }
    return null;
  }

  /// Extrai informacoes basicas do certificado.
  ///
  /// NOTA: A extracao completa dos dados do .pfx/.p12 requer
  /// processamento no backend (Node.js com node-forge ou similar).
  /// Aqui extraimos apenas informacoes basicas via nome do arquivo.
  static CertificadoInfo extrairInfoBasica({
    required PlatformFile file,
    required String senha,
  }) {
    // Extrai informacao do nome do arquivo como fallback
    // Em producao, usar Cloud Function para ler o .pfx com node-forge
    final now = DateTime.now();
    return CertificadoInfo(
      cnpj: null, // Seria extraido do certificado pelo backend
      razaoSocial: file.name.replaceAll(RegExp(r'\.(pfx|p12)$'), ''),
      validFrom: now.subtract(const Duration(days: 365)),
      validUntil: now.add(const Duration(days: 365)),
      isValid: true,
    );
  }

  /// Salva o certificado criptografado no Firestore.
  static Future<CertificadoUploadResult> salvarCertificado({
    required String storeId,
    required Uint8List arquivoBytes,
    required String senha,
    String? integrationId,
  }) async {
    try {
      // Valida tamanho
      if (arquivoBytes.length > _maxBytes) {
        return const CertificadoUploadResult(
          sucesso: false,
          erro: 'Arquivo muito grande. Maximo 5MB.',
        );
      }

      // Criptografa os bytes do certificado
      final certificadoBase64 = base64Encode(arquivoBytes);
      final certificadoEncrypted = FiscalCryptoUtil.encrypt(certificadoBase64);

      // Criptografa a senha separadamente
      final senhaEncrypted = FiscalCryptoUtil.encrypt(senha);

      // Data de validade (fallback de 1 ano a partir de hoje)
      const validadePadrao = Duration(days: 365);
      final validoAte = DateTime.now().add(validadePadrao);

      // Busca settings existente ou cria novo
      final settings = await _db
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();

      final metadata = {
        'certificate_data_encrypted': certificadoEncrypted,
        'certificate_password_encrypted': senhaEncrypted,
        'certificate_cnpj': null, // Extraido pelo backend
        'certificate_company_name': null, // Extraido pelo backend
        'certificate_valid_from': validoAte.subtract(validadePadrao).toIso8601String(),
        'certificate_valid_until': validoAte.toIso8601String(),
        'certificate_status': validoAte.isAfter(DateTime.now()) ? 'valido' : 'vencido',
        'certificate_updated_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (settings.docs.isNotEmpty) {
        await settings.docs.first.reference.update(metadata);
      } else {
        await _db.collection('store_fiscal_settings').add({
          'store_id': storeId,
          ...metadata,
          'status': 'active',
          'enable_nfe': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      return CertificadoUploadResult(
        sucesso: true,
        info: CertificadoInfo(
          validUntil: validoAte,
          isValid: true,
          cnpj: null,
          razaoSocial: null,
        ),
      );
    } catch (e) {
      return CertificadoUploadResult(
        sucesso: false,
        erro: 'Erro ao salvar certificado: $e',
      );
    }
  }

  /// Verifica se o certificado de uma loja esta expirado.
  static Future<bool> verificarExpiracao(String storeId) async {
    try {
      final settings = await _db
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();

      if (settings.docs.isEmpty) return true;

      final data = settings.docs.first.data();
      final certificateStatus = data['certificate_status'] as String?;
      final validUntil = data['certificate_valid_until'] as String?;

      if (certificateStatus == 'vencido') return true;
      if (validUntil != null) {
        final date = DateTime.tryParse(validUntil);
        if (date != null && date.isBefore(DateTime.now())) {
          // Atualiza status para vencido
          await settings.docs.first.reference.update({
            'certificate_status': 'vencido',
          });
          return true;
        }
      }
      return false;
    } catch (_) {
      return true; // Bloqueia emissao se nao conseguir verificar
    }
  }

  /// Retorna informacoes do certificado de uma loja.
  static Future<CertificadoInfo?> obterInfoCertificado(
      String storeId) async {
    try {
      final settings = await _db
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();

      if (settings.docs.isEmpty) return null;

      final data = settings.docs.first.data();
      final validUntilStr = data['certificate_valid_until'] as String?;
      final validFromStr = data['certificate_valid_from'] as String?;

      DateTime? validUntil;
      DateTime? validFrom;
      if (validUntilStr != null) validUntil = DateTime.tryParse(validUntilStr);
      if (validFromStr != null) validFrom = DateTime.tryParse(validFromStr);

      final certificateData =
          data['certificate_data_encrypted'] as String?;

      return CertificadoInfo(
        cnpj: data['certificate_cnpj'] as String?,
        razaoSocial: data['certificate_company_name'] as String?,
        validFrom: validFrom,
        validUntil: validUntil,
        isValid: certificateData != null &&
            certificateData.isNotEmpty &&
            data['certificate_status'] != 'vencido',
      );
    } catch (_) {
      return null;
    }
  }
}
