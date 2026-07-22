import 'package:flutter/material.dart';

import 'package:depertin_web/services/firebase_functions_config.dart';

/// Serviço para download de arquivos fiscais via Cloud Function.
///
/// FLUXO SEGURO:
/// 1. Chama fiscalDownloadArquivo com documento_id e tipo
/// 2. Cloud Function valida vínculo usuário × loja
/// 3. Gera URL assinada com validade de 5 minutos
/// 4. Retorna URL temporária para download
///
/// NÃO tenta abrir caminho interno como URL direta.
class FiscalDownloadService {
  FiscalDownloadService._();

  /// Tipos de arquivo permitidos para download.
  /// Deve coincidir com a lista em fiscalDownloadArquivo (backend).
  static const List<String> tiposPermitidos = [
    'xml',
    'danfe',
    'evento',
    'carta_correcao',
    'cancelamento',
  ];

  /// Mensagens de erro amigáveis para o lojista.
  static final Map<String, String> _mensagensErro = {
    'unauthenticated': 'Faça login para baixar o arquivo.',
    'not-found': 'Documento ou arquivo não encontrado.',
    'permission-denied': 'Você não tem permissão para acessar este arquivo.',
    'invalid-argument': 'Dados inválidos para download.',
    'assinatura_nao_encontrada': 'Assinatura não encontrada. Contrate um plano para emitir notas fiscais.',
    'documento_nao_encontrado': 'Documento fiscal não encontrado.',
    'arquivo_nao_disponivel': 'Arquivo ainda não está disponível para download.',
    'internal': 'Erro interno no servidor. Tente novamente ou contate o suporte.',
  };

  /// Baixa XML de um documento fiscal.
  ///
  /// Retorna URL assinada temporária para download.
  /// Lança [FiscalDownloadException] se falhar.
  static Future<String> baixarXml(String documentoId) async {
    return obterUrlDownload(documentoId: documentoId, tipo: 'xml');
  }

  /// Baixa DANFE (PDF) de um documento fiscal.
  ///
  /// Retorna URL assinada temporária para download.
  /// Lança [FiscalDownloadException] se falhar.
  static Future<String> baixarDanfe(String documentoId) async {
    return obterUrlDownload(documentoId: documentoId, tipo: 'danfe');
  }

  /// Baixa carta de correção de um documento fiscal.
  ///
  /// Retorna URL assinada temporária para download.
  /// Lança [FiscalDownloadException] se falhar.
  static Future<String> baixarCartaCorrecao(String documentoId) async {
    return obterUrlDownload(documentoId: documentoId, tipo: 'carta_correcao');
  }

  /// Baixa documento de cancelamento de um documento fiscal.
  ///
  /// Retorna URL assinada temporária para download.
  /// Lança [FiscalDownloadException] se falhar.
  static Future<String> baixarCancelamento(String documentoId) async {
    return obterUrlDownload(documentoId: documentoId, tipo: 'cancelamento');
  }

  /// Método genérico para download de arquivo fiscal.
  ///
  /// Envia apenas [documentoId] e [tipo] para a Cloud Function.
  /// A Cloud Function valida permissão e retorna URL assinada.
  ///
  /// Lança [FiscalDownloadException] se:
  /// - documentoId vazio
  /// - tipo não permitido
  /// - Cloud Function retornar erro
  /// - URL retornada inválida
  static Future<String> obterUrlDownload({
    required String documentoId,
    required String tipo,
  }) async {
    // 1. Validação local do documentoId
    if (documentoId.isEmpty) {
      throw FiscalDownloadException(
        _mensagensErro['documento_nao_encontrado'] ?? 'ID do documento é obrigatório.',
      );
    }

    // 2. Validação local do tipo
    final tipoLower = tipo.toLowerCase();
    if (!tiposPermitidos.contains(tipoLower)) {
      throw FiscalDownloadException(
        'Tipo "$tipo" não permitido. Use: ${tiposPermitidos.join(", ")}',
      );
    }

    try {
      // 3. Chamar Cloud Function
      final result = await callFirebaseFunctionSafe(
        'fiscalDownloadArquivo',
        parameters: {
          'documento_id': documentoId,
          'tipo': tipoLower,
        },
        region: 'us-east1',
      );

      // 4. Verificar resposta
      final data = result['data'] as Map<String, dynamic>?;

      if (data == null) {
        throw FiscalDownloadException(
          _mensagensErro['internal'] ?? 'Resposta inválida do servidor.',
        );
      }

      // 5. Verificar sucesso
      if (data['sucesso'] != true) {
        final status = data['status'] as String? ?? '';
        final mensagem = data['mensagem'] as String? ?? '';
        final erroTraduzido = _traduzirErro(status, mensagem);
        throw FiscalDownloadException(erroTraduzido);
      }

      // 6. Verificar URL
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw FiscalDownloadException(
          _mensagensErro['arquivo_nao_disponivel'] ?? 'URL de download não disponível.',
        );
      }

      // 7. Validar que é HTTPS
      if (!url.startsWith('https://')) {
        debugPrint('[FiscalDownloadService] URL não é HTTPS: $url');
        throw FiscalDownloadException(
          _mensagensErro['internal'] ?? 'URL de download inválida.',
        );
      }

      // 8. Não logar URL completa (contém token assinado)
      debugPrint('[FiscalDownloadService] URL Obtida para $tipo (documento: $documentoId)');

      return url;
    } on FiscalDownloadException {
      rethrow;
    } on CallableHttpException catch (e) {
      throw FiscalDownloadException(_traduzirErro(e.code, e.message));
    } catch (e) {
      debugPrint('[FiscalDownloadService] Erro inesperado: $e');
      throw FiscalDownloadException(
        _mensagensErro['internal'] ?? 'Erro ao obter URL de download.',
      );
    }
  }

  /// Traduz código de erro para mensagem amigável.
  static String _traduzirErro(String code, String message) {
    final codeLower = code.toLowerCase();

    // Verificar mensagens predefinidas
    for (final entry in _mensagensErro.entries) {
      if (codeLower.contains(entry.key) || message.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }

    // Fallback: usar mensagem original ou genérica
    if (message.isNotEmpty) {
      return message;
    }

    return 'Erro ao baixar arquivo. Tente novamente ou contate o suporte.';
  }
}

/// Exceção específica para erros de download fiscal.
/// Não expõe detalhes técnicos ao usuário.
class FiscalDownloadException implements Exception {
  final String mensagem;

  FiscalDownloadException(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Widget auxiliar para mostrar loading durante download.
/// Usa-se em conjunto com FutureBuilder.
class FiscalDownloadButton extends StatefulWidget {
  final String documentoId;
  final String tipo;
  final String label;
  final IconData icon;
  final Color? color;
  final Future<void> Function(String url) onDownload;

  const FiscalDownloadButton({
    super.key,
    required this.documentoId,
    required this.tipo,
    required this.label,
    required this.icon,
    required this.onDownload,
    this.color,
  });

  @override
  State<FiscalDownloadButton> createState() => _FiscalDownloadButtonState();
}

class _FiscalDownloadButtonState extends State<FiscalDownloadButton> {
  bool _loading = false;

  Future<void> _handleTap() async {
    if (_loading) return;

    setState(() => _loading = true);

    try {
      final url = await FiscalDownloadService.obterUrlDownload(
        documentoId: widget.documentoId,
        tipo: widget.tipo,
      );
      await widget.onDownload(url);
    } on FiscalDownloadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.mensagem),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : _handleTap,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon, size: 18),
      label: Text(widget.label),
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.color ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}
