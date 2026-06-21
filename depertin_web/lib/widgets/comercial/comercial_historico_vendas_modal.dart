import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/comercial/comercial_busca_cliente_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Histórico de vendas: busca cliente → extrato detalhado.
Future<void> mostrarComercialHistoricoVendasModal(
  BuildContext context, {
  required String lojaId,
}) async {
  final cliente = await mostrarComercialBuscaClienteModal(
    context,
    lojaId: lojaId,
    titulo: 'Histórico de vendas',
    subtitulo: 'Selecione o cliente para ver o extrato',
    icone: Icons.history_rounded,
  );
  if (cliente == null || !context.mounted) return;

  await mostrarComercialModalShell<void>(
    context,
    maxWidth: 960,
    child: _HistoricoExtratoBody(lojaId: lojaId, cliente: cliente),
  );
}

class _HistoricoExtratoBody extends StatefulWidget {
  const _HistoricoExtratoBody({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_HistoricoExtratoBody> createState() => _HistoricoExtratoBodyState();
}

class _HistoricoExtratoBodyState extends State<_HistoricoExtratoBody> {
  bool _carregando = true;
  List<ComercialClienteLancamento> _lancamentos = const [];
  List<ComercialParcelaCliente> _parcelas = const [];
  double _totalComprado = 0;
  double _totalPago = 0;
  double _totalAberto = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final parcelas = await ComercialCreditoService.carregarParcelasCliente(
        widget.lojaId,
        widget.cliente.id,
      );
      final vendas = await ComercialCreditoService.carregarVendasCreditoCliente(
        widget.lojaId,
        widget.cliente.id,
      );
      final lancamentos = await ComercialClientesService.carregarLancamentosCliente(
        lojaId: widget.lojaId,
        cliente: widget.cliente,
        parcelasCliente: parcelas,
        vendasCredito: vendas,
      );

      final resumoPed = ComercialClientesService.melhorResumoHistorico([
        ComercialClientesService.historicoDeLancamentos(lancamentos),
        ComercialClientesService.historicoDeVendasCredito(vendas),
      ]);
      final resumoParc = ComercialCreditoService.calcularResumo(parcelas);
      final totalPagoParcelas =
          parcelas.fold<double>(0, (s, p) => s + p.valorPago);

      if (!mounted) return;
      setState(() {
        _lancamentos = lancamentos;
        _parcelas = parcelas;
        _totalComprado = resumoPed.total;
        _totalPago = totalPagoParcelas +
            lancamentos
                .where((l) => !l.ehVendaCredito && l.status == 'entregue')
                .fold<double>(0, (s, l) => s + l.total);
        _totalAberto = resumoParc.totalEmAberto;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double _valorPagoVenda(ComercialClienteLancamento l) {
    if (!l.ehVendaCredito) {
      return l.status == 'entregue' ? l.total : 0;
    }
    return _parcelas
        .where((p) => p.vendaId == l.pedidoId)
        .fold<double>(0, (s, p) => s + p.valorPago);
  }

  double _valorAbertoVenda(ComercialClienteLancamento l) {
    if (!l.ehVendaCredito) return 0;
    return _parcelas
        .where((p) => p.vendaId == l.pedidoId)
        .fold<double>(0, (s, p) => s + p.valorEmAberto);
  }

  void _detalheVenda(ComercialClienteLancamento l) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.codigoExibicao,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 12),
                ...l.itens.map(
                  (i) => Text(
                    '• ${i.nome} x${i.quantidade.toStringAsFixed(0)} — ${ComercialClientesService.formatarMoeda(i.subtotal)}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  ),
                ),
                const Divider(height: 24),
                Text('Pagamento: ${l.formaPagamento}'),
                Text('Total: ${ComercialClientesService.formatarMoeda(l.total)}'),
                Text('Pago: ${ComercialClientesService.formatarMoeda(_valorPagoVenda(l))}'),
                Text('Em aberto: ${ComercialClientesService.formatarMoeda(_valorAbertoVenda(l))}'),
                Text('Status: ${l.statusRotulo}'),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final disp = c.creditoDisponivel;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ComercialModalHeader(
            titulo: 'Extrato do cliente',
            subtitulo: c.nome,
            icone: Icons.receipt_long_rounded,
            onFechar: () => Navigator.pop(context),
          ),
          Flexible(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: PainelAdminTheme.roxo))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ComercialCardBranco(
                          child: Wrap(
                            spacing: 24,
                            runSpacing: 12,
                            children: [
                              _kpi('CPF', ComercialClientesService.formatarCpfExibicao(c.cpf)),
                              _kpi('Telefone', c.telefone ?? '—'),
                              _kpi('Limite', ComercialClientesService.formatarMoeda(c.limiteCredito)),
                              _kpi('Utilizado', ComercialClientesService.formatarMoeda(c.creditoUtilizado)),
                              _kpi('Disponível', ComercialClientesService.formatarMoeda(disp)),
                              _kpi('Total comprado', ComercialClientesService.formatarMoeda(_totalComprado)),
                              _kpi('Total pago', ComercialClientesService.formatarMoeda(_totalPago)),
                              _kpi('Em aberto', ComercialClientesService.formatarMoeda(_totalAberto)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Compras',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_lancamentos.isEmpty)
                          const ComercialEstadoVazio(
                            titulo: 'Nenhuma compra registrada',
                          )
                        else
                          ..._lancamentos.map((l) {
                            final pago = _valorPagoVenda(l);
                            final aberto = _valorAbertoVenda(l);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ComercialCardBranco(
                                padding: const EdgeInsets.all(14),
                                child: InkWell(
                                  onTap: () => _detalheVenda(l),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              l.codigoExibicao,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontWeight: FontWeight.w800,
                                                color: PainelAdminTheme.roxo,
                                              ),
                                            ),
                                          ),
                                          _statusChip(l.statusRotulo),
                                        ],
                                      ),
                                      Text(
                                        ComercialClientesService.formatarDataHora(l.dataHora),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      if (l.itens.isNotEmpty)
                                        Text(
                                          l.itens.first.nome +
                                              (l.itens.length > 1
                                                  ? ' +${l.itens.length - 1}'
                                                  : ''),
                                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                                        ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            l.formaPagamento,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            ComercialClientesService.formatarMoeda(l.total),
                                            style: GoogleFonts.plusJakartaSans(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'Pago: ${ComercialClientesService.formatarMoeda(pago)} · Aberto: ${ComercialClientesService.formatarMoeda(aberto)}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String valor) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B))),
          Text(valor, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color cor = const Color(0xFF6366F1);
    if (status == 'Pago') cor = const Color(0xFF10B981);
    if (status == 'Atrasada' || status == 'Cancelado') cor = const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: cor),
      ),
    );
  }
}
