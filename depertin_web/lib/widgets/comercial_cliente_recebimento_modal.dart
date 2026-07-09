import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/comercial_recebimento_comprovante_pdf.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Modal principal de recebimento de parcelas (crediário).
/// Lista SOMENTE parcelas em aberto. Suporta seleção múltipla
/// com cálculo dinâmico de juros/multa e baixa consolidada.
///
/// [configJurosMulta] Opcional. Se omitido, usa [JurosMultaConfig.padrao]
/// (sem cobrança de juros/multa).
Future<ComercialRecebimentoResult?> mostrarComercialClienteRecebimentoModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
  String? lojaNome,
  JurosMultaConfig? configJurosMulta,
}) {
  return showDialog<ComercialRecebimentoResult?>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => _RecebimentoModal(
      lojaId: lojaId,
      clienteInicial: cliente,
      lojaNome: lojaNome,
      configJurosMulta: configJurosMulta ?? JurosMultaConfig.padrao,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// Modal principal — Stateful para gerenciar seleção + pagamento
// ─────────────────────────────────────────────────────────────────────
class _RecebimentoModal extends StatefulWidget {
  const _RecebimentoModal({
    required this.lojaId,
    required this.clienteInicial,
    this.lojaNome,
    this.configJurosMulta = JurosMultaConfig.padrao,
  });

  final String lojaId;
  final ComercialCliente clienteInicial;
  final String? lojaNome;
  final JurosMultaConfig configJurosMulta;

  @override
  State<_RecebimentoModal> createState() => _RecebimentoModalState();
}

class _RecebimentoModalState extends State<_RecebimentoModal> {
  final Set<String> _selecionados = {};
  static const _formas = [
    'Dinheiro',
    'PIX',
    'Cartão de débito',
    'Cartão de crédito',
    'Transferência',
    'Carteira DiPertin',
  ];

  String _formaPagamento = 'Dinheiro';
  bool _salvando = false;

  /// Filtra apenas parcelas em aberto (com saldo a receber).
  List<ComercialParcelaCliente> _apenasAbertas(List<ComercialParcelaCliente> todas) {
    return todas.where((p) => p.podeReceber).toList();
  }

  /// Parcelas selecionadas (garantindo que ainda estão abertas).
  List<ComercialParcelaCliente> _itensSelecionados(
      List<ComercialParcelaCliente> abertas) {
    return abertas.where((p) => _selecionados.contains(p.id)).toList();
  }

  /// Cálculo consolidado das parcelas selecionadas.
  _SelecaoResumo _calcularResumoSelecao(
    List<ComercialParcelaCliente> abertas,
  ) {
    final escolhidas = _itensSelecionados(abertas);
    if (escolhidas.isEmpty) return _SelecaoResumo.vazio;

    double valorOriginal = 0;
    double multaTotal = 0;
    double jurosTotal = 0;

    for (final p in escolhidas) {
      valorOriginal += p.valorEmAberto;
      final calc = calcularJurosMulta(
        p.valorEmAberto,
        p.dataVencimento,
        widget.configJurosMulta,
      );
      multaTotal += calc.multa;
      jurosTotal += calc.juros;
    }

    return _SelecaoResumo(
      quantidade: escolhidas.length,
      valorOriginal: (valorOriginal * 100).roundToDouble() / 100,
      multaTotal: (multaTotal * 100).roundToDouble() / 100,
      jurosTotal: (jurosTotal * 100).roundToDouble() / 100,
    );
  }

  Future<void> _confirmarPagamento(
    List<ComercialParcelaCliente> abertas,
    ComercialCliente cliente,
  ) async {
    final escolhidas = _itensSelecionados(abertas);
    if (escolhidas.isEmpty) return;

    setState(() => _salvando = true);
    final resultados = <ComercialRecebimentoResult>[];
    String? erro;

    for (final parcela in escolhidas) {
      try {
        final calc = calcularJurosMulta(
          parcela.valorEmAberto,
          parcela.dataVencimento,
          widget.configJurosMulta,
        );
        final result = await ComercialCreditoService.registrarPagamentoParcela(
          lojaId: widget.lojaId,
          cliente: cliente,
          parcela: parcela,
          valorPago: parcela.valorEmAberto,
          formaPagamento: _formaPagamento,
          lojaNome: widget.lojaNome,
          valorMulta: calc.multa,
          valorJuros: calc.juros,
        );
        resultados.add(result);
      } catch (e) {
        erro = e is ArgumentError
            ? e.message ?? '$e'
            : 'Erro na parcela ${parcela.numeroParcela}: $e';
        break; // para no primeiro erro
      }
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    if (erro != null) {
      _mostrarFeedback(context, erro, isErro: true);
      return;
    }

    if (resultados.isEmpty) return;

    // Consolidar resultado do último pagamento para o PDF
    final resumo = _calcularResumoSelecao(abertas);
    final lastResult = resultados.last;
    final resultConsolidado = ComercialRecebimentoResult(
      recebimentoId: lastResult.recebimentoId,
      parcela: lastResult.parcela,
      valorPago: resumo.valorTotal,
      valorRestante: 0,
      formaPagamento: _formaPagamento,
      dataPagamento: DateTime.now(),
      clienteNome: lastResult.clienteNome,
      clienteCpf: lastResult.clienteCpf,
      clienteTelefone: lastResult.clienteTelefone,
      lojaNome: lastResult.lojaNome,
      usuarioNome: lastResult.usuarioNome,
    );

    // Toast de sucesso
    _mostrarFeedback(context,
        'Pagamento registrado com sucesso (${resultados.length} ${resultados.length == 1 ? 'parcela' : 'parcelas'}).');

    // Fechar modal e mostrar comprovante
    Navigator.pop(context, resultConsolidado);

    if (context.mounted) {
      _mostrarComprovanteSucesso(context, resultConsolidado);
    }
  }

  void _mostrarFeedback(BuildContext context, String msg, {bool isErro = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: isErro ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
      ),
    );
  }

  static Future<void> _mostrarComprovanteSucesso(
    BuildContext context,
    ComercialRecebimentoResult r,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pagamento registrado',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Pagamento registrado com sucesso.',
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                ComercialRecebimentoComprovantePdf.baixarPdf(r),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Baixar PDF'),
          ),
          FilledButton.icon(
            onPressed: () =>
                ComercialRecebimentoComprovantePdf.imprimir(r),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Imprimir'),
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.laranja,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 720, maxWidth: 900),
        child: Material(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          elevation: 28,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.lojaId)
                .collection('clientes_comercial')
                .doc(widget.clienteInicial.id)
                .snapshots(),
            builder: (context, clienteSnap) {
              ComercialCliente cliente = widget.clienteInicial;
              if (clienteSnap.hasData && clienteSnap.data!.exists) {
                cliente = ComercialCliente.fromDoc(
                  widget.clienteInicial.id,
                  widget.lojaId,
                  safeWebDocData(clienteSnap.data!),
                  totalComprado: widget.clienteInicial.totalComprado,
                  ultimaCompra: widget.clienteInicial.ultimaCompra,
                );
              }

              return StreamBuilder<List<ComercialParcelaCliente>>(
                stream: ComercialCreditoService.streamParcelasCliente(
                  widget.lojaId,
                  cliente.id,
                ),
                builder: (context, parcelasSnap) {
                  final todas = parcelasSnap.data ?? const [];
                  final abertas = _apenasAbertas(todas);
                  final resumo = ComercialCreditoService.calcularResumo(todas);
                  final maxH = MediaQuery.sizeOf(context).height * 0.9;

                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeaderRecebimento(
                          cliente: cliente,
                          onFechar: () => Navigator.pop(context),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ResumoClienteCards(
                                  cliente: cliente,
                                  resumo: resumo,
                                ),
                                const SizedBox(height: 22),
                                _TituloSecao(
                                  'Parcelas em aberto (${abertas.length})',
                                ),
                                const SizedBox(height: 10),
                                if (parcelasSnap.connectionState ==
                                    ConnectionState.waiting)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (abertas.isEmpty)
                                  _CardBranco(
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 36,
                                          color: PainelAdminTheme.roxo
                                              .withValues(alpha: 0.35),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Nenhuma parcela em aberto.',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ...abertas.map(
                                    (p) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: _ParcelaTileSelecionavel(
                                        parcela: p,
                                        selecionado:
                                            _selecionados.contains(p.id),
                                        configJurosMulta:
                                            widget.configJurosMulta,
                                        onToggle: (sel) {
                                          setState(() {
                                            if (sel) {
                                              _selecionados.add(p.id);
                                            } else {
                                              _selecionados.remove(p.id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // ── Rodapé fixo com resumo + forma de pagamento ──
                        _buildFooter(abertas, cliente),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(
    List<ComercialParcelaCliente> abertas,
    ComercialCliente cliente,
  ) {
    final selecionadas = _itensSelecionados(abertas);
    final resumo = _calcularResumoSelecao(abertas);
    final temSelecao = selecionadas.isNotEmpty;
    final fmt = ComercialClientesService.formatarMoeda;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Resumo da seleção
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      temSelecao
                          ? 'Parcelas selecionadas: ${resumo.quantidade}'
                          : 'Nenhuma parcela selecionada',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: temSelecao
                            ? PainelAdminTheme.roxo
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    if (temSelecao) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Valor original: ${fmt(resumo.valorOriginal)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      if (resumo.multaTotal > 0.009)
                        Text(
                          'Multa: ${fmt(resumo.multaTotal)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      if (resumo.jurosTotal > 0.009)
                        Text(
                          'Juros: ${fmt(resumo.jurosTotal)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFFF97316),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        'Total a receber: ${fmt(resumo.valorTotal)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Forma de pagamento
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _formaPagamento,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Forma de pgto',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FB),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _formas
                      .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f,
                              style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged:
                      _salvando ? null : (v) => setState(() => _formaPagamento = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Botões
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _salvando ? null : () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: temSelecao && !_salvando
                    ? () => _confirmarPagamento(abertas, cliente)
                    : null,
                icon: _salvando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payments_outlined, size: 18),
                label: Text(
                  _salvando
                      ? 'Salvando...'
                      : temSelecao
                          ? 'Receber ${selecionadas.length} ${selecionadas.length == 1 ? 'parcela' : 'parcelas'}'
                          : 'Receber pagamento',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────
class _HeaderRecebimento extends StatelessWidget {
  const _HeaderRecebimento({
    required this.cliente,
    required this.onFechar,
  });

  final ComercialCliente cliente;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payments_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recebimento',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  cliente.nome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onFechar,
            icon: Icon(Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Cards de resumo do cliente
// ─────────────────────────────────────────────────────────────────────
class _ResumoClienteCards extends StatelessWidget {
  const _ResumoClienteCards({
    required this.cliente,
    required this.resumo,
  });

  final ComercialCliente cliente;
  final ComercialResumoParcelas resumo;

  static String _fmtCpf(String? cpf) {
    if (cpf == null || cpf.isEmpty) return '—';
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return cpf;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TituloSecao('Dados do cliente'),
        const SizedBox(height: 10),
        _CardBranco(
          child: Column(
            children: [
              _linha('Nome', cliente.nome),
              _linha('Telefone', cliente.telefone ?? '—'),
              _linha('CPF', _fmtCpf(cliente.cpf)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            const gap = 10.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: w,
                  child: _mini('Limite total',
                      ComercialClientesService.formatarMoeda(cliente.limiteCredito),
                      PainelAdminTheme.roxo),
                ),
                SizedBox(
                  width: w,
                  child: _mini('Limite usado',
                      ComercialClientesService.formatarMoeda(cliente.creditoUtilizado),
                      PainelAdminTheme.laranja),
                ),
                SizedBox(
                  width: w,
                  child: _mini(
                    'Disponível',
                    ComercialClientesService.formatarMoeda(cliente.creditoDisponivel),
                    const Color(0xFF10B981),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _mini('Total em aberto',
                      ComercialClientesService.formatarMoeda(resumo.totalEmAberto),
                      const Color(0xFFEF4444)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _linha(String r, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(r,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: const Color(0xFF64748B))),
            ),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _mini(String rotulo, String valor, Color cor) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotulo,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: const Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(valor,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w800, color: cor)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────
// Parcela com checkbox - selecionável
// ─────────────────────────────────────────────────────────────────────
class _ParcelaTileSelecionavel extends StatelessWidget {
  const _ParcelaTileSelecionavel({
    required this.parcela,
    required this.selecionado,
    required this.onToggle,
    this.configJurosMulta = JurosMultaConfig.padrao,
  });

  final ComercialParcelaCliente parcela;
  final bool selecionado;
  final ValueChanged<bool> onToggle;
  final JurosMultaConfig configJurosMulta;

  Color get _corStatus {
    switch (parcela.status) {
      case ComercialParcelaStatus.vencido:
        return const Color(0xFFEF4444);
      case ComercialParcelaStatus.parcialmentePago:
        return PainelAdminTheme.laranja;
      default:
        return const Color(0xFF6366F1);
    }
  }

  String get _labelStatus {
    switch (parcela.status) {
      case ComercialParcelaStatus.vencido:
        return 'Vencido';
      default:
        return 'Em aberto';
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    final isVencida = parcela.status == ComercialParcelaStatus.vencido;

    // Calcula encargos para vencidas
    final calc = isVencida
        ? calcularJurosMulta(
            parcela.valorEmAberto,
            parcela.dataVencimento,
            configJurosMulta,
          )
        : null;

    final fmt = ComercialClientesService.formatarMoeda;

    return Material(
      color: selecionado
          ? const Color(0xFFF3E8FF)
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onToggle(!selecionado),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado
                  ? PainelAdminTheme.roxo
                  : const Color(0xFFE8ECF4),
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Checkbox
              Transform.scale(
                scale: 1.05,
                child: Checkbox(
                  value: selecionado,
                  onChanged: (v) => onToggle(v ?? false),
                  activeColor: PainelAdminTheme.roxo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              // Número da parcela
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (selecionado ? PainelAdminTheme.roxo : PainelAdminTheme.roxo)
                      .withValues(alpha: selecionado ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${parcela.numeroParcela}',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parcela.codigoVenda.isNotEmpty
                          ? parcela.codigoVenda
                          : 'Venda',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Venc. ${df.format(parcela.dataVencimento)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: isVencida
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    if (calc != null && calc.temEncargos) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Multa: ${fmt(calc.multa)} · Juros: ${fmt(calc.juros)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: const Color(0xFFF97316),
                        ),
                      ),
                    ],
                    Text(
                      'Valor: ${fmt(parcela.valorParcela)} · Aberto: ${fmt(parcela.valorEmAberto)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _corStatus.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _labelStatus,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _corStatus,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmt(parcela.valorEmAberto),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────
class _TituloSecao extends StatelessWidget {
  const _TituloSecao(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: PainelAdminTheme.roxo,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E1B4B),
          ),
        ),
      ],
    );
  }
}

class _CardBranco extends StatelessWidget {
  const _CardBranco({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF4)),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Modelo auxiliar: resumo da seleção
// ─────────────────────────────────────────────────────────────────────
class _SelecaoResumo {
  const _SelecaoResumo({
    required this.quantidade,
    required this.valorOriginal,
    required this.multaTotal,
    required this.jurosTotal,
  });

  final int quantidade;
  final double valorOriginal;
  final double multaTotal;
  final double jurosTotal;

  double get valorTotal =>
      ((valorOriginal + multaTotal + jurosTotal) * 100).roundToDouble() / 100;

  static const vazio = _SelecaoResumo(
    quantidade: 0,
    valorOriginal: 0,
    multaTotal: 0,
    jurosTotal: 0,
  );
}
