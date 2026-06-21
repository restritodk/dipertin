import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/comercial_recebimento_comprovante_pdf.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Modal principal de recebimento de parcelas (crediário).
Future<void> mostrarComercialClienteRecebimentoModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
  String? lojaNome,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => _RecebimentoModal(
      lojaId: lojaId,
      clienteInicial: cliente,
      lojaNome: lojaNome,
    ),
  );
}

class _RecebimentoModal extends StatelessWidget {
  const _RecebimentoModal({
    required this.lojaId,
    required this.clienteInicial,
    this.lojaNome,
  });

  final String lojaId;
  final ComercialCliente clienteInicial;
  final String? lojaNome;

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
                .doc(lojaId)
                .collection('clientes_comercial')
                .doc(clienteInicial.id)
                .snapshots(),
            builder: (context, clienteSnap) {
              ComercialCliente cliente = clienteInicial;
              if (clienteSnap.hasData && clienteSnap.data!.exists) {
                cliente = ComercialCliente.fromDoc(
                  clienteInicial.id,
                  lojaId,
                  safeWebDocData(clienteSnap.data!),
                  totalComprado: clienteInicial.totalComprado,
                  ultimaCompra: clienteInicial.ultimaCompra,
                );
              }

              return StreamBuilder<List<ComercialParcelaCliente>>(
                stream: ComercialCreditoService.streamParcelasCliente(
                  lojaId,
                  cliente.id,
                ),
                builder: (context, parcelasSnap) {
                  final parcelas = parcelasSnap.data ?? const [];
                  final resumo = ComercialCreditoService.calcularResumo(parcelas);
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
                                _TituloSecao('Parcelas'),
                                const SizedBox(height: 10),
                                if (parcelasSnap.connectionState ==
                                    ConnectionState.waiting)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (parcelas.isEmpty)
                                  _CardBranco(
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.calendar_month_outlined,
                                          size: 36,
                                          color: PainelAdminTheme.roxo
                                              .withValues(alpha: 0.35),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Nenhuma parcela registrada para este cliente.',
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
                                  ...parcelas.map(
                                    (p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _ParcelaTile(
                                        parcela: p,
                                        onTap: p.podeReceber
                                            ? () => _abrirReceberParcela(
                                                  context,
                                                  lojaId: lojaId,
                                                  cliente: cliente,
                                                  parcela: p,
                                                  lojaNome: lojaNome,
                                                )
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        ComercialModalFooterActions(
                          labelSecundario: 'Fechar',
                          onSecundario: () => Navigator.pop(context),
                          labelPrimario: 'Receber próxima',
                          iconePrimario: Icons.payments_outlined,
                          onPrimario: resumo.proximaParcela == null
                              ? null
                              : () => _abrirReceberParcela(
                                    context,
                                    lojaId: lojaId,
                                    cliente: cliente,
                                    parcela: resumo.proximaParcela!,
                                    lojaNome: lojaNome,
                                  ),
                          mostrarPrimario: resumo.proximaParcela != null,
                        ),
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

  static Future<void> _abrirReceberParcela(
    BuildContext context, {
    required String lojaId,
    required ComercialCliente cliente,
    required ComercialParcelaCliente parcela,
    String? lojaNome,
  }) async {
    final resultado = await showDialog<ComercialRecebimentoResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (ctx) => _ReceberParcelaDialog(
        cliente: cliente,
        parcela: parcela,
        lojaId: lojaId,
        lojaNome: lojaNome,
      ),
    );
    if (resultado != null && context.mounted) {
      await _mostrarComprovanteSucesso(context, resultado);
    }
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
}

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
                SizedBox(
                  width: w,
                  child: _mini('Total já pago',
                      ComercialClientesService.formatarMoeda(resumo.totalPago),
                      const Color(0xFF6366F1)),
                ),
                if (resumo.parcelasVencidas > 0)
                  SizedBox(
                    width: w,
                    child: _mini(
                      'Parcelas vencidas',
                      '${resumo.parcelasVencidas}',
                      const Color(0xFFEF4444),
                    ),
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

class _ParcelaTile extends StatelessWidget {
  const _ParcelaTile({required this.parcela, this.onTap});

  final ComercialParcelaCliente parcela;
  final VoidCallback? onTap;

  Color get _corStatus {
    switch (parcela.status) {
      case ComercialParcelaStatus.pago:
        return const Color(0xFF10B981);
      case ComercialParcelaStatus.vencido:
        return const Color(0xFFEF4444);
      case ComercialParcelaStatus.parcialmentePago:
        return PainelAdminTheme.laranja;
      default:
        return const Color(0xFF6366F1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8ECF4)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
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
                      'Venc. ${df.format(parcela.dataVencimento)} · Compra ${parcela.dataCompra != null ? df.format(parcela.dataCompra!) : '—'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aberto: ${ComercialClientesService.formatarMoeda(parcela.valorEmAberto)} · Pago: ${ComercialClientesService.formatarMoeda(parcela.valorPago)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
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
                      parcela.statusExibicao,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _corStatus,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ComercialClientesService.formatarMoeda(parcela.valorParcela),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceberParcelaDialog extends StatefulWidget {
  const _ReceberParcelaDialog({
    required this.cliente,
    required this.parcela,
    required this.lojaId,
    this.lojaNome,
  });

  final ComercialCliente cliente;
  final ComercialParcelaCliente parcela;
  final String lojaId;
  final String? lojaNome;

  @override
  State<_ReceberParcelaDialog> createState() => _ReceberParcelaDialogState();
}

class _ReceberParcelaDialogState extends State<_ReceberParcelaDialog> {
  static const _formas = [
    'Dinheiro',
    'PIX',
    'Cartão de débito',
    'Cartão de crédito',
    'Transferência',
    'Carteira DiPertin',
  ];

  String _forma = 'Dinheiro';
  final _valorCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _valorCtrl.text = widget.parcela.valorEmAberto.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  double _parseValor(String s) {
    final t = s.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
    if (t.contains(',')) {
      return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    }
    return double.tryParse(t) ?? 0;
  }

  Future<void> _confirmar() async {
    final valor = _parseValor(_valorCtrl.text);
    if (valor <= 0) {
      DiPertinPainelFeedback.erro(context, 'Informe um valor válido.');
      return;
    }
    if (valor > widget.parcela.valorEmAberto + 0.009) {
      DiPertinPainelFeedback.erro(
        context,
        'Valor não pode ser maior que o saldo em aberto.',
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final result = await ComercialCreditoService.registrarPagamentoParcela(
        lojaId: widget.lojaId,
        cliente: widget.cliente,
        parcela: widget.parcela,
        valorPago: valor,
        formaPagamento: _forma,
        observacao: _obsCtrl.text,
        lojaNome: widget.lojaNome,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        DiPertinPainelFeedback.erro(
          context,
          e is ArgumentError ? e.message ?? '$e' : 'Erro ao registrar: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    final p = widget.parcela;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Receber parcela',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              const SizedBox(height: 16),
              _info('Cliente', widget.cliente.nome),
              _info('Parcela', '${p.numeroParcela} · ${p.codigoVenda}'),
              _info('Valor original',
                  ComercialClientesService.formatarMoeda(p.valorParcela)),
              _info('Já pago',
                  ComercialClientesService.formatarMoeda(p.valorPago)),
              _info('Restante',
                  ComercialClientesService.formatarMoeda(p.valorEmAberto),
                  destaque: true),
              _info('Vencimento', df.format(p.dataVencimento)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _forma,
                decoration: InputDecoration(
                  labelText: 'Forma de pagamento',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _formas
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: _salvando ? null : (v) => setState(() => _forma = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valorCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Valor pago',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Observação (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ComercialModalFooterActions(
                labelSecundario: 'Cancelar',
                onSecundario: _salvando ? null : () => Navigator.pop(context),
                labelPrimario: 'Confirmar pagamento',
                onPrimario: _confirmar,
                carregando: _salvando,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(String r, String v, {bool destaque = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(r,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: const Color(0xFF64748B))),
            const Spacer(),
            Text(v,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: destaque ? 15 : 13,
                  fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
                  color: destaque ? PainelAdminTheme.laranja : null,
                )),
          ],
        ),
      );
}

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
