import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/fiscal/fiscal_certificado_service.dart';
import '../../theme/painel_admin_theme.dart';

/// Modal premium para upload de certificado digital A1.
///
/// Permite:
/// - Upload de arquivo .pfx/.p12
/// - Validacao de extensao e tamanho
/// - Visualizacao dos dados extraidos
/// - Salvamento criptografado
class FiscalCertificadoModal extends StatefulWidget {
  final String storeId;
  final CertificadoInfo? certificadoAtual;

  const FiscalCertificadoModal({
    super.key,
    required this.storeId,
    this.certificadoAtual,
  });

  /// Exibe o modal de certificado.
  static Future<bool> mostrar(
    BuildContext context, {
    required String storeId,
    CertificadoInfo? certificadoAtual,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FiscalCertificadoModal(
        storeId: storeId,
        certificadoAtual: certificadoAtual,
      ),
    ).then((result) => result ?? false);
  }

  @override
  State<FiscalCertificadoModal> createState() =>
      _FiscalCertificadoModalState();
}

class _FiscalCertificadoModalState extends State<FiscalCertificadoModal> {
  PlatformFile? _arquivoSelecionado;
  final _senhaController = TextEditingController();
  bool _obscureSenha = true;
  bool _carregando = false;
  String? _erro;
  CertificadoInfo? _infoExtraida;

  @override
  void dispose() {
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _selecionarArquivo() async {
    final arquivo = await FiscalCertificadoService.selecionarArquivo();
    if (arquivo != null) {
      final erro = FiscalCertificadoService.validarArquivo(arquivo);
      if (erro != null) {
        setState(() {
          _erro = erro;
          _arquivoSelecionado = null;
          _infoExtraida = null;
        });
      } else {
        setState(() {
          _erro = null;
          _arquivoSelecionado = arquivo;
          // Extração local apenas para exibição (nome e tamanho)
          // A validação completa (PKCS#12) é feita no backend.
          _infoExtraida = null;
        });
      }
    }
  }

  Future<void> _salvar() async {
    if (_arquivoSelecionado == null) {
      setState(() => _erro = 'Selecione um arquivo de certificado.');
      return;
    }
    if (_senhaController.text.isEmpty) {
      setState(() => _erro = 'Informe a senha do certificado.');
      return;
    }
    if (_arquivoSelecionado!.bytes == null) {
      setState(() => _erro = 'Erro ao ler o arquivo.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
    });

    final result = await FiscalCertificadoService.salvarCertificado(
      storeId: widget.storeId,
      arquivoBytes: _arquivoSelecionado!.bytes!,
      senha: _senhaController.text,
    );

    if (!mounted) return;

    setState(() => _carregando = false);

    if (result.sucesso) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _erro = result.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.security, color: DiPertinTheme.primaryRoxo, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Certificado Digital A1',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: DiPertinTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload do certificado .pfx ou .p12',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: DiPertinTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Certificado atual
            if (widget.certificadoAtual != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.certificadoAtual!.isExpired
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.certificadoAtual!.isExpired
                        ? Colors.red.shade200
                        : Colors.green.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.certificadoAtual!.isExpired
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle,
                      color: widget.certificadoAtual!.isExpired
                          ? Colors.red
                          : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.certificadoAtual!.statusLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: widget.certificadoAtual!.isExpired
                                  ? Colors.red.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                          if (widget.certificadoAtual!.validadeFim != null)
                            Text(
                              'Valido ate: ${widget.certificadoAtual!.validadeFim!.split('T')[0]}',
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.certificadoAtual!.isExpired
                                    ? Colors.red.shade600
                                    : Colors.green.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Area de upload
            GestureDetector(
              onTap: _carregando ? null : _selecionarArquivo,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _arquivoSelecionado != null
                        ? Colors.green.shade300
                        : Colors.grey.shade300,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _arquivoSelecionado != null
                      ? Colors.green.shade50
                      : Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _arquivoSelecionado != null
                          ? Icons.check_circle
                          : Icons.upload_file,
                      size: 40,
                      color: _arquivoSelecionado != null
                          ? Colors.green
                          : DiPertinTheme.primaryRoxo,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _arquivoSelecionado?.name ?? 'Clique para selecionar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _arquivoSelecionado != null
                            ? Colors.green.shade800
                            : DiPertinTheme.textPrimary,
                      ),
                    ),
                    if (_arquivoSelecionado != null)
                      Text(
                        '${(_arquivoSelecionado!.size / 1024).toStringAsFixed(1)} KB',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Campos
            TextField(
              controller: _senhaController,
              obscureText: _obscureSenha,
              decoration: InputDecoration(
                labelText: 'Senha do Certificado',
                hintText: 'Digite a senha do arquivo .pfx/.p12',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSenha
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureSenha = !_obscureSenha),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Informacoes extraidas
            if (_infoExtraida != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DiPertinTheme.textSecondary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informacoes do certificado:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DiPertinTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_infoExtraida!.titular != null)
                      Text(
                        'Titular: ${_infoExtraida!.titular}',
                      ),
                    if (_infoExtraida!.validadeFim != null)
                      Text(
                        'Validade: ${_infoExtraida!.validadeFim}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    Text(
                      'Status: ${_infoExtraida!.statusLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        color: _infoExtraida!.isExpired
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Erro
            if (_erro != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _erro!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            const Spacer(),

            // Botoes
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _carregando ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _carregando ? null : _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DiPertinTheme.primaryRoxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _carregando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar Certificado'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
