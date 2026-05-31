import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/pedido_status.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);

/// Dados de exibição do estorno (MP + regras de cancelamento do cliente).
class PedidoEstornoUiData {
  PedidoEstornoUiData._({
    required this.deveExibirCliente,
    required this.deveExibirEntregador,
    required this.parcial,
    required this.valorProdutoEstornado,
    required this.valorFreteEstornado,
    required this.valorFreteNaoEstornado,
    required this.valorTotalEstornadoCliente,
    required this.statusEstorno,
    required this.dataSolicitacao,
    required this.creditoEntregador,
    required this.taxaPlataformaFrete,
    required this.freteBruto,
  });

  final bool deveExibirCliente;
  final bool deveExibirEntregador;
  final bool parcial;
  final double valorProdutoEstornado;
  final double valorFreteEstornado;
  final double valorFreteNaoEstornado;
  final double valorTotalEstornadoCliente;
  final String statusEstorno;
  final DateTime? dataSolicitacao;
  final double creditoEntregador;
  final double taxaPlataformaFrete;
  final double freteBruto;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? fallback;
  }

  static DateTime? _lerData(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  static String _rotuloStatusEstorno(Map<String, dynamic> pedido) {
    final st = (pedido['mp_refund_status'] ?? '').toString().trim();
    final err = (pedido['mp_refund_error'] ?? '').toString().trim();
    switch (st) {
      case 'succeeded':
        return 'Estorno concluído';
      case 'processing':
        return 'Estorno em processamento';
      case 'error':
        return err.isNotEmpty ? 'Erro no estorno' : 'Erro no estorno';
      case 'already_refunded':
        return 'Pagamento já estornado no Mercado Pago';
      case 'skipped_not_paid':
        return 'Pagamento não confirmado — estorno automático não aplicável';
      case 'skipped_zero_amount':
        return 'Sem valor a estornar';
      case 'skipped_no_refundable_balance':
        return 'Sem saldo reembolsável no gateway';
      default:
        if (st.isNotEmpty) return st;
        return 'Aguardando processamento do estorno';
    }
  }

  factory PedidoEstornoUiData.fromPedido(Map<String, dynamic> pedido) {
    final vazio = PedidoEstornoUiData._(
      deveExibirCliente: false,
      deveExibirEntregador: false,
      parcial: false,
      valorProdutoEstornado: 0,
      valorFreteEstornado: 0,
      valorFreteNaoEstornado: 0,
      valorTotalEstornadoCliente: 0,
      statusEstorno: '',
      dataSolicitacao: null,
      creditoEntregador: 0,
      taxaPlataformaFrete: 0,
      freteBruto: 0,
    );

    final status = (pedido['status'] ?? '').toString().trim().toLowerCase();
    if (status != PedidoStatus.cancelado) return vazio;

    final motivo = (pedido['cancelado_motivo'] ?? '').toString();
    final clienteSolicitou =
        motivo == PedidoStatus.canceladoMotivoClienteSolicitou;
    final refundSt = (pedido['mp_refund_status'] ?? '').toString().trim();
    final parcial = pedido['mp_refund_parcial_frete_retido'] == true;

    final total = _toDouble(pedido['total']);
    final subtotal = _toDouble(pedido['subtotal']);
    final taxa = _toDouble(pedido['taxa_entrega']);
    final valorCalc = _toDouble(pedido['mp_refund_valor_calculado']);

    final creditoEnt = _toDouble(pedido['entregador_credito_cancelamento_valor']);
    final creditoFeito = pedido['entregador_credito_cancelamento_feito'] == true;
    final taxaPlat = _toDouble(pedido['taxa_entregador']);

    final temRastreioEstorno =
        refundSt.isNotEmpty || parcial || creditoFeito;

    if (!clienteSolicitou && !temRastreioEstorno) return vazio;

    double valorProduto;
    double valorFreteEstornado;
    double valorFreteNaoEstornado;
    double valorTotalCliente;

    if (parcial) {
      valorTotalCliente =
          valorCalc > 0 ? valorCalc : (total - taxa).clamp(0.0, total);
      valorProduto = valorTotalCliente;
      valorFreteNaoEstornado = taxa;
      valorFreteEstornado = 0;
    } else {
      valorTotalCliente = valorCalc > 0 ? valorCalc : total;
      valorFreteEstornado = taxa;
      valorProduto = subtotal > 0
          ? subtotal
          : (total - taxa).clamp(0.0, total);
      if (valorProduto + valorFreteEstornado > valorTotalCliente + 0.02) {
        valorProduto = (valorTotalCliente - valorFreteEstornado).clamp(0.0, total);
      }
      valorFreteNaoEstornado = 0;
    }

    final data = _lerData(pedido['mp_refund_at']) ??
        _lerData(pedido['mp_refund_atualizado_em']) ??
        _lerData(pedido['cancelado_em']);

    final deveCliente = clienteSolicitou || temRastreioEstorno;
    final deveEntregador = parcial &&
        (creditoFeito ||
            creditoEnt > 0 ||
            taxa > 0 ||
            refundSt == 'succeeded' ||
            refundSt == 'processing');

    return PedidoEstornoUiData._(
      deveExibirCliente: deveCliente,
      deveExibirEntregador: deveEntregador,
      parcial: parcial,
      valorProdutoEstornado: valorProduto,
      valorFreteEstornado: valorFreteEstornado,
      valorFreteNaoEstornado: valorFreteNaoEstornado,
      valorTotalEstornadoCliente: valorTotalCliente,
      statusEstorno: _rotuloStatusEstorno(pedido),
      dataSolicitacao: data,
      creditoEntregador: creditoFeito ? creditoEnt : 0,
      taxaPlataformaFrete: taxaPlat,
      freteBruto: taxa,
    );
  }

  String formatarMoeda(double v) => _moeda.format(v);

  String get dataSolicitacaoFormatada {
    if (dataSolicitacao == null) return '—';
    return DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(dataSolicitacao!);
  }
}

/// Bloco de estorno no detalhe do pedido (visão cliente).
class PedidoEstornoClienteCard extends StatelessWidget {
  const PedidoEstornoClienteCard({super.key, required this.pedido});

  final Map<String, dynamic> pedido;

  @override
  Widget build(BuildContext context) {
    final d = PedidoEstornoUiData.fromPedido(pedido);
    if (!d.deveExibirCliente) return const SizedBox.shrink();

    final corTipo = d.parcial ? Colors.orange.shade800 : Colors.green.shade800;
    final fundo = d.parcial ? Colors.orange.shade50 : Colors.green.shade50;
    final borda = d.parcial ? Colors.orange.shade200 : Colors.green.shade200;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                d.parcial
                    ? Icons.payments_outlined
                    : Icons.account_balance_wallet_outlined,
                color: corTipo,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Estorno do cancelamento',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: corTipo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _linha('Tipo de estorno', d.parcial ? 'Parcial' : 'Total'),
          _linha(
            'Valor do produto estornado',
            d.formatarMoeda(d.valorProdutoEstornado),
          ),
          if (d.parcial) ...[
            _linha(
              'Valor do frete não estornado',
              d.formatarMoeda(d.valorFreteNaoEstornado),
            ),
          ] else if (d.valorFreteEstornado > 0) ...[
            _linha(
              'Valor do frete estornado',
              d.formatarMoeda(d.valorFreteEstornado),
            ),
          ],
          _linha(
            d.parcial
                ? 'Valor total estornado ao cliente'
                : 'Valor total estornado',
            d.formatarMoeda(d.valorTotalEstornadoCliente),
            destaque: true,
          ),
          const SizedBox(height: 8),
          _linha('Status do estorno', d.statusEstorno),
          _linha('Data da solicitação do estorno', d.dataSolicitacaoFormatada),
          if (d.parcial) ...[
            const SizedBox(height: 10),
            Text(
              'O frete não é devolvido ao cliente porque a entrega já estava '
              'a caminho. O valor líquido do frete é repassado ao entregador.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.grey[800],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: destaque ? 15 : 13,
                fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
                color: destaque ? _diPertinLaranja : Colors.grey[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco de estorno / frete retido (visão entregador).
class PedidoEstornoEntregadorCard extends StatelessWidget {
  const PedidoEstornoEntregadorCard({super.key, required this.pedido});

  final Map<String, dynamic> pedido;

  @override
  Widget build(BuildContext context) {
    final d = PedidoEstornoUiData.fromPedido(pedido);
    if (!d.deveExibirEntregador) return const SizedBox.shrink();

    final credito = d.creditoEntregador > 0
        ? d.creditoEntregador
        : (d.freteBruto - d.taxaPlataformaFrete).clamp(0.0, double.infinity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _diPertinRoxo.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: _diPertinRoxo, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cancelamento — estorno parcial',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _diPertinRoxo,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'O cliente cancelou após você ter iniciado o deslocamento até a '
            'entrega. O reembolso ao cliente é apenas do valor dos produtos.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 14),
          _linha('Tipo de estorno', 'Parcial (frete retido)'),
          _linha(
            'Reembolso ao cliente (produtos)',
            d.formatarMoeda(d.valorTotalEstornadoCliente),
          ),
          _linha(
            'Frete não reembolsado ao cliente',
            d.formatarMoeda(d.valorFreteNaoEstornado),
          ),
          if (d.freteBruto > 0)
            _linha('Frete bruto do pedido', d.formatarMoeda(d.freteBruto)),
          if (d.taxaPlataformaFrete > 0)
            _linha(
              'Taxa/comissão da plataforma (frete)',
              d.formatarMoeda(d.taxaPlataformaFrete),
            ),
          _linha(
            'Crédito na sua carteira (líquido)',
            d.formatarMoeda(credito),
            destaque: true,
          ),
          const SizedBox(height: 6),
          _linha('Status do estorno', d.statusEstorno),
          _linha('Data da solicitação', d.dataSolicitacaoFormatada),
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: destaque ? 15 : 13,
                fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
                color: destaque ? _diPertinLaranja : Colors.grey[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
