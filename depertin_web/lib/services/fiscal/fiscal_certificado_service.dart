import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../firebase_functions_config.dart';

/// Informações extraídas de um certificado digital A1 (dados públicos).
class CertificadoInfo {
  final String? certificateId;
  final String? cnpj;
  final String? titular;
  final String? emissor;
  final String? validadeInicio;
  final String? validadeFim;
  final String? status;
  final bool isValid;
  final DateTime? enviadoEm;

  const CertificadoInfo({
    this.certificateId,
    this.cnpj,
    this.titular,
    this.emissor,
    this.validadeInicio,
    this.validadeFim,
    this.status,
    this.isValid = false,
    this.enviadoEm,
  });

  bool get isExpired {
    if (validadeFim == null) return false;
    final date = DateTime.tryParse(validadeFim!);
    return date != null && date.isBefore(DateTime.now());
  }

  String get statusLabel {
    if (status == 'vencido' || isExpired) return 'Vencido';
    if (status == 'ativo') return 'Válido';
    return status ?? 'Não configurado';
  }

  /// Cria a partir do campo `certificate_info` do `store_fiscal_settings`.
  ///
  /// Estrutura esperada (gerada pelo backend em `fiscalUploadCertificado`):
  /// ```json
  /// {
  ///   "certificate_id": "...",
  ///   "configured": true,
  ///   "status": "valid",
  ///   "subject_name": "...",
  ///   "cnpj_masked": "...",
  ///   "valid_until": Timestamp,
  ///   "expires_soon": false,
  ///   "last_validated_at": Timestamp
  /// }
  /// ```
  factory CertificadoInfo.fromMap(Map<String, dynamic> map) {
    // Tenta ler da estrutura pública certificate_info
    final configured = map['configured'] == true;
    final rawStatus = map['status'] as String? ?? '';
    final rawValidUntil = map['valid_until'];

    return CertificadoInfo(
      certificateId: map['certificate_id'] as String?,
      cnpj: map['cnpj_masked'] as String?,
      titular: map['subject_name'] as String?,
      emissor: null,
      validadeInicio: null,
      validadeFim: rawValidUntil != null
          ? (rawValidUntil is Timestamp
              ? rawValidUntil.toDate().toIso8601String()
              : rawValidUntil.toString())
          : null,
      status: configured
          ? (rawStatus == 'valid' ? 'ativo' : rawStatus == 'expired' ? 'vencido' : rawStatus)
          : null,
      isValid: configured && rawStatus == 'valid',
      enviadoEm: map['last_validated_at'] != null
          ? (map['last_validated_at'] is Timestamp
              ? (map['last_validated_at'] as Timestamp).toDate()
              : DateTime.tryParse(map['last_validated_at'] as String))
          : null,
    );
  }
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

/// Serviço para gerenciar certificados digitais A1.
///
/// O upload utiliza exclusivamente a Cloud Function fiscalUploadCertificado,
/// que valida o PKCS#12, extrai dados, criptografa com FISCAL_MASTER_KEY
/// no backend e salva em fiscal_certificates (staff-only).
///
/// SEGURANÇA:
/// - Conteúdo e senha do certificado NUNCA ficam no frontend
/// - Criptografia é feita exclusivamente no backend com FISCAL_MASTER_KEY
/// - Apenas certificate_info público é retornado ao frontend
abstract final class FiscalCertificadoService {
  static const int _maxBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> _extensoesValidas = ['pfx', 'p12'];

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

  /// Valida o arquivo de certificado (apenas extensão e tamanho, UX).
  static String? validarArquivo(PlatformFile file) {
    final ext = file.extension?.toLowerCase() ?? '';
    if (!_extensoesValidas.contains(ext)) {
      return 'Formato inválido. Use arquivos .pfx ou .p12.';
    }
    if (file.size > _maxBytes) {
      return 'Arquivo muito grande. Máximo 5MB.';
    }
    if (file.bytes == null || file.bytes!.isEmpty) {
      return 'Arquivo vazio.';
    }
    return null;
  }

  /// Envia o certificado para a Cloud Function fiscalUploadCertificado.
  ///
  /// A Function valida PKCS#12, CNPJ, validade e criptografa com
  /// FISCAL_MASTER_KEY no backend. NUNCA persiste senha ou conteúdo
  /// no frontend.
  static Future<CertificadoUploadResult> salvarCertificado({
    required String storeId,
    required Uint8List arquivoBytes,
    required String senha,
    String? integrationId,
  }) async {
    try {
      // Validação client-side (UX)
      if (arquivoBytes.length > _maxBytes) {
        return const CertificadoUploadResult(
          sucesso: false,
          erro: 'Arquivo muito grande. Máximo 5MB.',
        );
      }

      // Converte para base64 para envio à CF
      final arquivoBase64 = base64Encode(arquivoBytes);

      // Chama Cloud Function fiscalUploadCertificado
      final result = await callFirebaseFunctionSafe(
        'fiscalUploadCertificado',
        parameters: {
          'store_id': storeId,
          'arquivo_base64': arquivoBase64,
          'senha': senha,
          'nome_arquivo': integrationId ?? 'certificado.pfx',
        },
        region: 'us-east1',
      );

      if (result['sucesso'] == true) {
        final certInfoRaw = result['certificate_info'] as Map<String, dynamic>?;
        return CertificadoUploadResult(
          sucesso: true,
          info: certInfoRaw != null
              ? CertificadoInfo.fromMap(certInfoRaw)
              : null,
        );
      }

      return CertificadoUploadResult(
        sucesso: false,
        erro: result['mensagem'] as String? ?? 'Erro ao processar certificado.',
      );
    } catch (e) {
      final mensagem = e.toString();
      // Traduz erros conhecidos
      if (mensagem.contains('senha_incorreta') ||
          mensagem.contains('Senha do certificado incorreta')) {
        return const CertificadoUploadResult(
          sucesso: false,
          erro: 'Senha do certificado incorreta.',
        );
      }
      if (mensagem.contains('CNPJ') && mensagem.contains('não corresponde')) {
        return const CertificadoUploadResult(
          sucesso: false,
          erro: 'CNPJ do certificado não corresponde ao CNPJ da loja.',
        );
      }
      if (mensagem.contains('expirado') || mensagem.contains('Expirou')) {
        return const CertificadoUploadResult(
          sucesso: false,
          erro: 'Certificado digital expirado. Renove antes de enviar.',
        );
      }
      return CertificadoUploadResult(
        sucesso: false,
        erro: 'Erro ao enviar certificado: $e',
      );
    }
  }

  /// Remove certificado via Cloud Function fiscalRemoverCertificado.
  static Future<CertificadoUploadResult> removerCertificado({
    required String certificateId,
  }) async {
    try {
      final result = await callFirebaseFunctionSafe(
        'fiscalRemoverCertificado',
        parameters: {
          'certificate_id': certificateId,
        },
        region: 'us-east1',
      );

      if (result['sucesso'] == true) {
        return const CertificadoUploadResult(sucesso: true);
      }

      return CertificadoUploadResult(
        sucesso: false,
        erro: result['mensagem'] as String? ?? 'Erro ao remover certificado.',
      );
    } catch (e) {
      return CertificadoUploadResult(
        sucesso: false,
        erro: 'Erro ao remover certificado: $e',
      );
    }
  }

  /// Verifica se o certificado de uma loja está expirado.
  static Future<bool> verificarExpiracao(String storeId) async {
    try {
      final info = await obterInfoCertificado(storeId);
      return info == null || info.isExpired || info.status == 'vencido';
    } catch (_) {
      return true; // Bloqueia emissão se não conseguir verificar
    }
  }

  /// Retorna informações públicas do certificado de uma loja.
  ///
  /// Lê exclusivamente do campo `certificate_info` em `store_fiscal_settings`.
  /// SEGURANÇA: NUNCA acessa `fiscal_certificates` (staff-only).
  static Future<CertificadoInfo?> obterInfoCertificado(
      String storeId) async {
    try {
      final settings = await FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .where('store_id', isEqualTo: storeId)
          .limit(1)
          .get();

      if (settings.docs.isEmpty) return null;

      final data = settings.docs.first.data();
      final certificateInfo =
          data['certificate_info'] as Map<String, dynamic>?;

      if (certificateInfo != null && certificateInfo['configured'] == true) {
        return CertificadoInfo.fromMap(certificateInfo);
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
