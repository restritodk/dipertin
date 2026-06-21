import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_credito.dart';

/// Item de um lançamento (venda/pedido) do cliente comercial.
class ComercialClienteLancamentoItem {
  const ComercialClienteLancamentoItem({
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    required this.subtotal,
  });

  final String nome;
  final double quantidade;
  final double precoUnitario;
  final double subtotal;

  static ComercialClienteLancamentoItem fromMap(Map<String, dynamic> m) {
    final qtdRaw = m['quantidade'] ?? m['qtd'] ?? 1;
    final qtd = qtdRaw is num
        ? qtdRaw.toDouble()
        : double.tryParse('$qtdRaw') ?? 1;

    final precoRaw = m['preco'] ?? m['preco_unitario'] ?? m['valor_unitario'];
    var preco = precoRaw is num
        ? precoRaw.toDouble()
        : double.tryParse('$precoRaw') ?? 0;

    final subRaw = m['valor_total'] ?? m['subtotal'] ?? m['total'];
    var sub = subRaw is num
        ? subRaw.toDouble()
        : double.tryParse('$subRaw') ?? 0;

    if (sub <= 0 && preco > 0) sub = preco * qtd;
    if (preco <= 0 && sub > 0 && qtd > 0) preco = sub / qtd;

    final nome = (m['nome'] ??
            m['nome_produto'] ??
            m['produto_nome'] ??
            m['titulo'] ??
            'Produto')
        .toString()
        .trim();

    return ComercialClienteLancamentoItem(
      nome: nome.isEmpty ? 'Produto' : nome,
      quantidade: qtd,
      precoUnitario: preco,
      subtotal: sub,
    );
  }
}

/// Venda/pedido vinculado a um cliente comercial (PDV + marketplace).
class ComercialClienteLancamento {
  ComercialClienteLancamento({
    required this.pedidoId,
    required this.codigoExibicao,
    required this.dataHora,
    required this.itens,
    required this.formaPagamento,
    required this.subtotal,
    required this.desconto,
    required this.total,
    required this.status,
    required this.statusRotulo,
    this.origem,
    this.observacao,
    this.dadosBrutos = const {},
  });

  final String pedidoId;
  final String codigoExibicao;
  final DateTime? dataHora;
  final List<ComercialClienteLancamentoItem> itens;
  final String formaPagamento;
  final double subtotal;
  final double desconto;
  final double total;
  final String status;
  final String statusRotulo;
  final String? origem;
  final String? observacao;
  final Map<String, dynamic> dadosBrutos;

  bool get ehPdv =>
      origem == 'pdv_web' || origem == 'pdv' || dadosBrutos['sessao_caixa_id'] != null;

  static ComercialClienteLancamento fromPedidoDoc(
    String pedidoId,
    Map<String, dynamic> d,
  ) {
    final itensRaw = d['itens'];
    final itens = <ComercialClienteLancamentoItem>[];
    if (itensRaw is List) {
      for (final raw in itensRaw) {
        if (raw is Map) {
          itens.add(
            ComercialClienteLancamentoItem.fromMap(
              Map<String, dynamic>.from(raw),
            ),
          );
        }
      }
    }

    final status = (d['status'] ?? '').toString();
    final codigo = (d['codigo_pedido'] ?? '').toString().trim();
    final codigoExibicao = codigo.isNotEmpty
        ? codigo
        : 'Venda #${pedidoId.length >= 4 ? pedidoId.substring(pedidoId.length - 4).toUpperCase() : pedidoId}';

    return ComercialClienteLancamento(
      pedidoId: pedidoId,
      codigoExibicao: codigoExibicao,
      dataHora: _parseData(d['data_pedido'] ?? d['data_entrega'] ?? d['created_at']),
      itens: itens,
      formaPagamento: _rotuloFormaPagamento(d['forma_pagamento']),
      subtotal: _num(d['subtotal'] ?? d['valor_produtos'] ?? d['total_produtos']),
      desconto: _num(
        d['desconto_total_calculado'] ??
            d['desconto'] ??
            d['desconto_cupom'] ??
            0,
      ),
      total: _num(d['total'] ?? d['valor_total']),
      status: status,
      statusRotulo: rotuloStatus(status),
      origem: d['origem']?.toString(),
      observacao: d['observacao']?.toString(),
      dadosBrutos: Map<String, dynamic>.from(d),
    );
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static DateTime? _parseData(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }

  bool get ehVendaCredito =>
      dadosBrutos['pagamento_credito_loja'] == true ||
      formaPagamento.toLowerCase().contains('crédito') ||
      formaPagamento.toLowerCase().contains('credito');

  static bool statusContaComoCompra(String status) {
    switch (status) {
      case 'entregue':
        return true;
      default:
        return false;
    }
  }

  /// Status exibido no card: considera parcelas do crediário quando aplicável.
  ComercialClienteLancamento comStatusPagamento(
    List<ComercialParcelaCliente> parcelasCliente,
  ) {
    final rotulo = resolverStatusPagamentoExibicao(
      status: status,
      ehVendaCredito: ehVendaCredito,
      parcelasDaVenda: parcelasCliente
          .where((p) => p.vendaId == pedidoId)
          .toList(growable: false),
    );
    return ComercialClienteLancamento(
      pedidoId: pedidoId,
      codigoExibicao: codigoExibicao,
      dataHora: dataHora,
      itens: itens,
      formaPagamento: formaPagamento,
      subtotal: subtotal,
      desconto: desconto,
      total: total,
      status: status,
      statusRotulo: rotulo,
      origem: origem,
      observacao: observacao,
      dadosBrutos: dadosBrutos,
    );
  }

  static String resolverStatusPagamentoExibicao({
    required String status,
    required bool ehVendaCredito,
    required List<ComercialParcelaCliente> parcelasDaVenda,
  }) {
    switch (status) {
      case 'cancelado':
      case 'cancelado_pelo_cliente':
      case 'cancelado_lojista':
      case 'cancelado_pelo_lojista':
      case 'recusado':
      case 'estornado':
      case 'expirado':
        return 'Cancelado';
      case 'aguardando_pagamento':
        return 'Aguardando pagamento';
      case 'confirmado':
      case 'pendente':
      case 'aceito':
      case 'em_preparo':
      case 'pronto':
      case 'aguardando_entregador':
      case 'entregador_indo_loja':
      case 'saiu_entrega':
      case 'a_caminho':
      case 'em_rota':
        return 'Em andamento';
      case 'entregue':
        break;
      default:
        if (status.isEmpty) return '—';
        return status.replaceAll('_', ' ');
    }

    if (!ehVendaCredito) return 'Pago';

    if (parcelasDaVenda.isEmpty) return 'Em dias';

    final abertas =
        parcelasDaVenda.where((p) => p.podeReceber).toList(growable: false);
    if (abertas.isEmpty) return 'Pago';

    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    for (final p in abertas) {
      if (p.status == ComercialParcelaStatus.vencido) return 'Atrasada';
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(h)) return 'Atrasada';
    }
    return 'Em dias';
  }

  static String rotuloStatus(String status) {
    switch (status) {
      case 'entregue':
        return 'Pago';
      case 'aguardando_pagamento':
        return 'Aguardando pagamento';
      case 'confirmado':
      case 'pendente':
      case 'aceito':
      case 'em_preparo':
      case 'pronto':
      case 'aguardando_entregador':
      case 'entregador_indo_loja':
      case 'saiu_entrega':
      case 'a_caminho':
      case 'em_rota':
        return 'Em andamento';
      case 'cancelado':
      case 'cancelado_pelo_cliente':
      case 'cancelado_lojista':
      case 'cancelado_pelo_lojista':
      case 'recusado':
      case 'estornado':
      case 'expirado':
        return 'Cancelado';
      default:
        if (status.isEmpty) return '—';
        return status.replaceAll('_', ' ');
    }
  }

  static String _rotuloFormaPagamento(dynamic forma) {
    final f = forma?.toString().trim() ?? '';
    if (f.isEmpty) return '—';
    switch (f.toLowerCase()) {
      case 'pix':
        return 'PIX';
      case 'credito':
      case 'cartao_credito':
      case 'cartão de crédito':
        return 'Cartão de crédito';
      case 'debito':
      case 'cartao_debito':
      case 'cartão de débito':
        return 'Cartão de débito';
      case 'dinheiro':
        return 'Dinheiro';
      case 'saldo do app':
      case 'saldo':
        return 'Saldo do app';
      default:
        return f;
    }
  }
}
