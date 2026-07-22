import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/fiscal/fiscal_emissao_service.dart';
import '../../services/fiscal/fiscal_payload.dart';
import '../../services/fiscal/fiscal_validator.dart';
import '../../services/fiscal/fiscal_xml_builder.dart';
import '../../theme/painel_admin_theme.dart';

/// Modal de emissão de NF-e com pré-visualização, animação e resultado.
///
/// Fluxo:
/// 1. Pré-visualização do XML + validação
/// 2. Animação de emissão
/// 3. Resultado final (sucesso/erro)
class FiscalEmissaoModal {
  FiscalEmissaoModal._();

  /// Abre o modal de emissão de NF-e.
  static Future<FiscalEmissaoResult?> mostrar({
    required BuildContext context,
    required String lojaId,
    required FiscalPayload payload,
    required bool homologacao,
    required bool emitirNfce,
    String integrationId = '',
    Map<String, dynamic> storeSettingsData = const {},
  }) {
    return showDialog<FiscalEmissaoResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FiscalEmissaoModal(
        lojaId: lojaId,
        payload: payload,
        homologacao: homologacao,
        emitirNfce: emitirNfce,
        integrationId: integrationId,
        storeSettingsData: storeSettingsData,
      ),
    );
  }

  /// Abre o modal apenas de pré-visualização (sem emissão).
  static Future<void> mostrarPreview({
    required BuildContext context,
    required FiscalPayload payload,
    required bool homologacao,
    required bool emitirNfce,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FiscalPreviewModal(
        payload: payload,
        homologacao: homologacao,
        emitirNfce: emitirNfce,
      ),
    );
  }
}

// ─── Estado do fluxo de emissão ───
enum _EstadoEmissao { preview, validando, emitindo, resultado }

class _FiscalEmissaoModal extends StatefulWidget {
  final String lojaId;
  final FiscalPayload payload;
  final bool homologacao;
  final bool emitirNfce;
  final String integrationId;
  final Map<String, dynamic> storeSettingsData;

  const _FiscalEmissaoModal({
    required this.lojaId,
    required this.payload,
    required this.homologacao,
    required this.emitirNfce,
    this.integrationId = '',
    this.storeSettingsData = const {},
  });

  @override
  State<_FiscalEmissaoModal> createState() => _FiscalEmissaoModalState();
}

class _FiscalEmissaoModalState extends State<_FiscalEmissaoModal>
    with TickerProviderStateMixin {
  _EstadoEmissao _estado = _EstadoEmissao.preview;
  FiscalEmissaoResult? _resultado;
  String _xmlPreview = '';
  bool _expandirXml = false;
  bool _expandirDetalhes = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  Timer? _progressTimer;
  double _progresso = 0;

  final _numeroFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Gera XML preview
    _xmlPreview = FiscalXmlBuilder.gerarXmlNFeApenas(
      payload: widget.payload,
      homologacao: widget.homologacao,
      emitirNfce: widget.emitirNfce,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _iniciarEmissao() async {
    setState(() => _estado = _EstadoEmissao.validando);

    // Pequena pausa para mostrar validação
    await Future.delayed(const Duration(milliseconds: 600));

    setState(() => _estado = _EstadoEmissao.emitindo);
    _progresso = 0;

    // Simula progresso durante emissão
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      setState(() {
        _progresso = min(0.9, _progresso + 0.03 + Random().nextDouble() * 0.05);
      });
    });

    // Executa emissão real
    final resultado = await FiscalEmissaoService.instance.emitirNotaCompleta(
      lojaId: widget.lojaId,
      payload: widget.payload,
      homologacao: widget.homologacao,
      emitirNfce: widget.emitirNfce,
      integrationId: widget.integrationId,
      storeSettingsData: widget.storeSettingsData,
    );

    _progressTimer?.cancel();
    setState(() {
      _progresso = 1.0;
      _resultado = resultado;
      _estado = _EstadoEmissao.resultado;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final width = size.width > 700 ? 640.0 : size.width * 0.95;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 680),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_estado) {
      case _EstadoEmissao.preview:
        return _buildPreview(theme);
      case _EstadoEmissao.validando:
        return _buildValidando(theme);
      case _EstadoEmissao.emitindo:
        return _buildEmitindo(theme);
      case _EstadoEmissao.resultado:
        return _buildResultado(theme);
    }
  }

  // ─── Tela de Pré-visualização ───

  Widget _buildPreview(ThemeData theme) {
    final validacao = FiscalEmissaoService.validarDados(widget.payload);
    final podeEmitir = validacao.valido;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Conteúdo scrollável ──
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.emitirNfce ? Icons.receipt_long : Icons.description,
                        color: DiPertinTheme.primaryRoxo,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pré-visualização NF-e',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: DiPertinTheme.primaryRoxo,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Revise os dados antes de emitir',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: podeEmitir
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            podeEmitir ? Icons.check_circle : Icons.error_outline,
                            color: podeEmitir ? Colors.green : Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            podeEmitir ? 'OK' : '${validacao.erros.length} erro(s)',
                            style: TextStyle(
                              color: podeEmitir ? Colors.green : Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Emitente (detalhado) ──
                _buildEmitentePreview(widget.payload.emitente),
                const SizedBox(height: 8),
                _buildSummaryCard(
                  'Destinatário',
                  widget.payload.destinatario.nome,
                  widget.payload.destinatario.cpfCnpj ?? 'Consumidor Final',
                  Icons.person,
                ),
                const SizedBox(height: 8),
                _buildSummaryCard(
                  'Totais',
                  '${widget.payload.itens.length} item(ns)',
                  _numeroFormatter.format(widget.payload.totais.valorTotal),
                  Icons.calculate,
                ),
                const SizedBox(height: 16),

                // Validation errors
                if (!podeEmitir) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Erros de validação:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...validacao.erros.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  Icon(Icons.cancel, size: 12, color: Colors.red[400]),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${e.campo}: ${e.mensagem}',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.red[700]),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // XML Preview (collapsible)
                InkWell(
                  onTap: () => setState(() => _expandirXml = !_expandirXml),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.code, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'XML da NF-e (${_xmlPreview.length} caracteres)',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const Spacer(),
                        Icon(
                          _expandirXml
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expandirXml) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _xmlPreview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // ── Botões fixos no rodapé ──
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: podeEmitir ? _iniciarEmissao : null,
                  icon: Icon(
                    widget.emitirNfce
                        ? Icons.receipt_long
                        : Icons.cloud_upload,
                    size: 18,
                  ),
                  label: Text(
                    widget.emitirNfce ? 'Emitir NFC-e' : 'Emitir NF-e',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: DiPertinTheme.primaryRoxo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Card detalhado com todos os dados fiscais do emitente.
  Widget _buildEmitentePreview(FiscalEmitente emit) {
    final regimeLabel = emit.regimeTributario ?? '—';
    final crtLabel = emit.crt ?? '—';
    final complemento = emit.complemento?.isNotEmpty == true ? ' - ${emit.complemento}' : '';
    final codCidade = emit.codigoCidade ?? '—';
    final cnae = emit.cnae ?? '—';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, size: 20, color: DiPertinTheme.primaryRoxo),
              const SizedBox(width: 8),
              Text(
                'Emitente',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _emitenteLinha('Razão Social', emit.razaoSocial),
          if (emit.nomeFantasia.isNotEmpty)
            _emitenteLinha('Nome Fantasia', emit.nomeFantasia),
          _emitenteLinha('CNPJ', emit.cnpj),
          _emitenteLinha(
            'Inscrição Estadual',
            emit.ieIsento
                ? 'Isento'
                : (emit.ie.trim().isNotEmpty ? emit.ie : '—'),
          ),
          _emitenteLinha('Regime Tributário', regimeLabel),
          _emitenteLinha('CRT', crtLabel),
          const Divider(height: 14),
          _emitenteLinha('CEP', emit.cep),
          _emitenteLinha('Logradouro', emit.logradouro),
          _emitenteLinha('Número', emit.numero + complemento),
          _emitenteLinha('Bairro', emit.bairro),
          _emitenteLinha('Cidade / UF', '${emit.cidade} / ${emit.uf}'),
          _emitenteLinha('Código IBGE', codCidade),
          _emitenteLinha('CNAE', cnae),
          if (emit.emailFiscal != null && emit.emailFiscal!.isNotEmpty)
            _emitenteLinha('E-mail Fiscal', emit.emailFiscal!),
        ],
      ),
    );
  }

  /// Linha do card de emitente.
  Widget _emitenteLinha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor.isNotEmpty ? valor : '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String titulo, String linha1, String linha2, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: DiPertinTheme.primaryRoxo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  linha1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  linha2,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Validação ───

  Widget _buildValidando(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.checklist, size: 40, color: DiPertinTheme.primaryRoxo),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Validando dados fiscais...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Verificando CFOP, NCM, CST, CNPJ, IE e valores',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey[200],
              color: DiPertinTheme.primaryRoxo,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Emitindo ───

  Widget _buildEmitindo(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DiPertinTheme.primaryRoxo,
                    DiPertinTheme.secondaryLaranja,
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.cloud_upload,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Transmitindo NF-e para SEFAZ...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aguardando autorização do provedor fiscal',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _progresso,
              backgroundColor: Colors.grey[200],
              color: DiPertinTheme.primaryRoxo,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_progresso * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ─── Resultado ───

  Widget _buildResultado(ThemeData theme) {
    final sucesso = _resultado?.sucesso ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Conteúdo scrollável ──
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícone animado
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: sucesso
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    sucesso ? Icons.check_circle : Icons.cancel,
                    size: 48,
                    color: sucesso ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  sucesso ? 'NF-e Emitida com Sucesso!' : 'Falha na emissão da NF-e',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: sucesso ? Colors.green[800] : Colors.red[800],
                  ),
                ),
                const SizedBox(height: 16),

                if (sucesso) ...[
                  // ─── SUCESSO ───
                  _buildDetailRow('Chave de Acesso', _resultado?.chaveAcesso ?? '---'),
                  _buildDetailRow('Protocolo', _resultado?.protocolo ?? '---'),
                  _buildDetailRow('Número', _resultado?.numero ?? '---'),
                  _buildDetailRow('Série', _resultado?.serie ?? '---'),
                ] else ...[
                  // ─── ERRO — MODAL CORRIGIDO ───
                  // Subtítulo
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'A nota não foi autorizada. Verifique os erros abaixo.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Lista de erros reais
                  _buildErrorList(),
                  const SizedBox(height: 16),

                  // Accordion Detalhes Técnicos
                  _buildTechnicalDetails(),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── Botões fixos no rodapé ──
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: sucesso
              ? SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_resultado),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Concluir'),
                  ),
                )
              : Row(
                  children: [
                    // Copiar erro
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copiarErro,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copiar erro', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tentar novamente
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop(null);
                          // Força reabertura do modal (a tela mãe decide se deve reabrir)
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Tentar novamente', style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          backgroundColor: DiPertinTheme.primaryRoxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Fechar
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(_resultado),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: const Text('Fechar', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Lista de erros reais extraídos do resultado da emissão.
  Widget _buildErrorList() {
    final resultado = _resultado;
    if (resultado == null) return const SizedBox.shrink();

    // Prioridade: validationErrors > errosValidacao > erro > mensagem
    final List<String> erros = [];

    // Erros estruturados do backend (validationErrors)
    if (resultado.validationErrors.isNotEmpty) {
      erros.addAll(resultado.validationErrors);
    }

    // Erros de validação de payload (errosValidacao)
    if (resultado.errosValidacao.isNotEmpty) {
      for (final e in resultado.errosValidacao) {
        erros.add('${e.campo}: ${e.mensagem}');
      }
    }

    // Código de rejeição SEFAZ — prioridade alta na lista visível
    if (resultado.sefazCode != null && resultado.sefazCode!.isNotEmpty) {
      final msg = resultado.sefazMessage?.isNotEmpty == true
          ? 'Rejeição SEFAZ ${resultado.sefazCode}: ${resultado.sefazMessage}'
          : 'Rejeição SEFAZ ${resultado.sefazCode}';
      if (!erros.any((e) => e.contains(resultado.sefazCode!))) {
        erros.insert(0, msg);
      }
    } else if (resultado.codigoRejeicao != null &&
        resultado.codigoRejeicao!.isNotEmpty) {
      final msg = 'Rejeição SEFAZ ${resultado.codigoRejeicao}';
      if (!erros.any((e) => e.contains(resultado.codigoRejeicao!))) {
        erros.insert(0, msg);
      }
    }

    // Código HTTP da Focus
    if (resultado.focusStatusCode != null && resultado.focusStatusCode! > 0) {
      final msgErro = _mensagemPorHttpStatus(resultado.focusStatusCode!);
      if (msgErro != null && !erros.contains(msgErro)) {
        erros.add(msgErro);
      }
    }

    // Mensagem de erro genérica (fallback)
    if (erros.isEmpty) {
      final msg = resultado.mensagem ?? resultado.erro ?? 'Erro desconhecido ao emitir NF-e.';
      erros.add(msg);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${erros.length} erro(s) encontrado(s):',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red[700],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ...erros.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e,
                        style: TextStyle(fontSize: 12, color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Accordion com detalhes técnicos da emissão.
  Widget _buildTechnicalDetails() {
    final r = _resultado;
    if (r == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandirDetalhes = !_expandirDetalhes),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.build, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Detalhes técnicos',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Icon(
                    _expandirDetalhes ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (_expandirDetalhes) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTechField('Provider', 'Focus NFe'),
                  _buildTechField('Ambiente', _resultado?.statusFinal ?? '—'),
                  if (r.focusStatusCode != null)
                    _buildTechField('HTTP Status', r.focusStatusCode.toString()),
                  if (r.sefazCode != null && r.sefazCode!.isNotEmpty)
                    _buildTechField('Código SEFAZ', r.sefazCode!),
                  if (r.sefazMessage != null && r.sefazMessage!.isNotEmpty)
                    _buildTechField('Mensagem SEFAZ', r.sefazMessage!),
                  if (r.codigoRejeicao != null && r.codigoRejeicao!.isNotEmpty)
                    _buildTechField('Código Rejeição', r.codigoRejeicao!),
                  if (r.focusResponse != null && r.focusResponse!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Resposta Focus (sanitizada):',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 100),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          r.focusResponse!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: Colors.black54),
                        ),
                      ),
                    ),
                  ],
                  if (r.xmlGerado != null && r.xmlGerado!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'XML gerado (debug):',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 100),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          r.xmlGerado!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 8, color: Colors.black54),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTechField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// Copia o erro completo para a área de transferência.
  void _copiarErro() {
    final r = _resultado;
    if (r == null) return;

    final sb = StringBuffer();
    sb.writeln('=== Erro de Emissão NF-e ===');
    sb.writeln('Mensagem: ${r.mensagem ?? r.erro ?? "N/A"}');
    if (r.validationErrors.isNotEmpty) {
      sb.writeln('Erros:');
      for (final e in r.validationErrors) {
        sb.writeln('  - $e');
      }
    }
    if (r.sefazCode != null) sb.writeln('Código SEFAZ: ${r.sefazCode}');
    if (r.sefazMessage != null) sb.writeln('Mensagem SEFAZ: ${r.sefazMessage}');
    if (r.focusStatusCode != null) sb.writeln('HTTP Status Focus: ${r.focusStatusCode}');
    if (r.focusResponse != null) sb.writeln('Resposta Focus: ${r.focusResponse}');
    if (r.codigoRejeicao != null) sb.writeln('Código Rejeição: ${r.codigoRejeicao}');

    Clipboard.setData(ClipboardData(text: sb.toString()));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro copiado para a área de transferência.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Retorna mensagem legível para um HTTP status.
  String? _mensagemPorHttpStatus(int status) {
    switch (status) {
      case 0:
        return null;
      case 401:
        return 'Código 401: Token Focus NFe inválido.';
      case 403:
        return 'Código 403: Acesso não autorizado na Focus NFe.';
      case 404:
        return 'Código 404: Empresa não encontrada na Focus NFe.';
      case 422:
        return 'Código 422: Dados inválidos enviados para a Focus NFe.';
      case 409:
        return 'Código 409: Conflito — NF-e já existe com esta referência.';
      case 429:
        return 'Código 429: Muitas requisições.';
      default:
        return 'HTTP $status: Erro na comunicação com a Focus NFe.';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Modal apenas de Pré-visualização ───

class _FiscalPreviewModal extends StatefulWidget {
  final FiscalPayload payload;
  final bool homologacao;
  final bool emitirNfce;

  const _FiscalPreviewModal({
    required this.payload,
    required this.homologacao,
    required this.emitirNfce,
  });

  @override
  State<_FiscalPreviewModal> createState() => _FiscalPreviewModalState();
}

class _FiscalPreviewModalState extends State<_FiscalPreviewModal> {
  String _xmlPreview = '';
  String _statusMsg = '';
  bool _temErro = false;

  @override
  void initState() {
    super.initState();
    _gerarPreview();
  }

  void _gerarPreview() {
    final validacao = FiscalValidator.validarParaEmissao(widget.payload);
    _xmlPreview = FiscalXmlBuilder.gerarXmlNFeApenas(
      payload: widget.payload,
      homologacao: widget.homologacao,
      emitirNfce: widget.emitirNfce,
    );

    if (validacao.valido) {
      _statusMsg = '✓ Dados válidos — XML gerado (${_xmlPreview.length} chars)';
      _temErro = false;
    } else {
      _statusMsg =
          '✗ ${validacao.erros.length} erro(s) de validação encontrados';
      _temErro = true;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, size: 20, color: DiPertinTheme.primaryRoxo),
                const SizedBox(width: 8),
                Text(
                  'Pré-visualização NF-e',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: DiPertinTheme.primaryRoxo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _temErro
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusMsg,
                style: TextStyle(
                  fontSize: 11,
                  color: _temErro ? Colors.red[700] : Colors.green[700],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _xmlPreview,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.grey[300]!),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
