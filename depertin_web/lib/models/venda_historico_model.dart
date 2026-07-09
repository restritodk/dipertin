import 'package:cloud_firestore/cloud_firestore.dart';

/// Item vendido dentro de uma venda.
class VendaItem {
  const VendaItem({
    required this.produtoNome,
    required this.quantidade,
    required this.valorUnitario,
    this.desconto = 0,
    this.total = 0,
  });

  final String produtoNome;
  final int quantidade;
  final double valorUnitario;
  final double desconto;
  final double total;

  factory VendaItem.fromMap(Map<String, dynamic> m) {
    final qtd = (m['quantidade'] as num?)?.toInt() ?? 1;
    final vu = _num(m['valor_unitario']);
    final desc = _num(m['desconto']);
    final tot = _num(m['total']);
    return VendaItem(
      produtoNome: (m['produto_nome'] ?? m['produto'] ?? '').toString(),
      quantidade: qtd,
      valorUnitario: vu,
      desconto: desc,
      total: tot > 0 ? tot : (vu * qtd) - desc,
    );
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }
}

/// Venda do histórico da gestão comercial.
class VendaHistorico {
  VendaHistorico({
    required this.id,
    required this.lojaId,
    this.codigoVenda,
    this.clienteId,
    this.clienteNome,
    this.clienteDocumento,
    this.clienteTelefone,
    this.clienteEmail,
    this.itens = const [],
    this.quantidadeItens = 0,
    this.formaPagamento,
    this.valorTotal = 0,
    this.valorPago = 0,
    this.valorPendente = 0,
    this.descontoTotal = 0,
    this.jurosTotal = 0,
    this.multaTotal = 0,
    this.status,
    this.operadorId,
    this.operadorNome,
    this.caixaId,
    this.dataVenda,
    this.createdAt,
    this.updatedAt,
    this.canceladoEm,
    this.dataPagoEm,
    this.motivoCancelamento,
    this.parcelas,
  });

  final String id;
  final String lojaId;
  final String? codigoVenda;
  final String? clienteId;
  final String? clienteNome;
  final String? clienteDocumento;
  final String? clienteTelefone;
  final String? clienteEmail;
  final List<VendaItem> itens;
  final int quantidadeItens;
  final String? formaPagamento;
  final double valorTotal;
  final double valorPago;
  final double valorPendente;
  final double descontoTotal;
  final double jurosTotal;
  final double multaTotal;
  final String? status;
  final String? operadorId;
  final String? operadorNome;
  final String? caixaId;
  final DateTime? dataVenda;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? canceladoEm;
  final DateTime? dataPagoEm;
  final String? motivoCancelamento;
  final int? parcelas;

  bool get isCredito => formaPagamento == 'Crédito do Cliente' ||
      formaPagamento == 'credito_cliente' ||
      formaPagamento == 'crédito';

  String get codigoExibicao {
    if (codigoVenda != null && codigoVenda!.isNotEmpty) return codigoVenda!;
    return 'VEN-${id.length > 6 ? id.substring(0, 6) : id}';
  }

  String get statusExibicao {
    switch (status) {
      case 'pago':
        return 'Pago';
      case 'pendente':
        return 'Pendente';
      case 'parcial':
        return 'Parcial';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Pendente';
    }
  }

  String get formaPagamentoExibicao {
    switch (formaPagamento) {
      case 'dinheiro':
        return 'Dinheiro';
      case 'pix':
        return 'PIX';
      case 'cartao':
      case 'cartão':
      case 'credito':
      case 'credito_debito':
        return 'Cartão';
      case 'credito_cliente':
      case 'Crédito do Cliente':
        return 'Crédito do Cliente';
      case 'transferencia':
      case 'transferência':
        return 'Transferência';
      default:
        return formaPagamento ?? '—';
    }
  }

  factory VendaHistorico.fromDoc(String id, Map<String, dynamic> d) {
    final itensRaw = d['itens'];
    final itensList = <VendaItem>[];
    if (itensRaw is List) {
      for (final raw in itensRaw) {
        if (raw is Map) {
          itensList.add(VendaItem.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }
    final vTotal = _num(d['valor_total']);
    final vPago = _num(d['valor_pago']);
    final vPend = _num(d['valor_pendente']);
    return VendaHistorico(
      id: id,
      lojaId: (d['loja_id'] ?? '').toString(),
      codigoVenda: d['codigo_venda']?.toString(),
      clienteId: d['cliente_id']?.toString(),
      clienteNome: d['cliente_nome']?.toString(),
      clienteDocumento: d['cliente_documento']?.toString(),
      clienteTelefone: d['cliente_telefone']?.toString(),
      clienteEmail: d['cliente_email']?.toString(),
      itens: itensList,
      quantidadeItens: (d['quantidade_itens'] as num?)?.toInt() ?? itensList.length,
      formaPagamento: d['forma_pagamento']?.toString(),
      valorTotal: vTotal,
      valorPago: vPago,
      valorPendente: vPend,
      descontoTotal: _num(d['desconto_total']),
      jurosTotal: _num(d['juros_total']),
      multaTotal: _num(d['multa_total']),
      status: (d['status'] ?? 'pendente').toString(),
      operadorId: d['operador_id']?.toString(),
      operadorNome: d['operador_nome']?.toString(),
      caixaId: d['caixa_id']?.toString(),
      dataVenda: _parseTs(d['data_venda']),
      createdAt: _parseTs(d['created_at']),
      updatedAt: _parseTs(d['updated_at']),
      canceladoEm: _parseTs(d['cancelado_em']),
      dataPagoEm: _parseTs(d['data_pago_em']),
      motivoCancelamento: d['motivo_cancelamento']?.toString(),
      parcelas: (d['parcelas'] as num?)?.toInt(),
    );
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final parsed = DateTime.tryParse(v?.toString() ?? '');
    return parsed;
  }
}

/// Resumo dos indicadores do histórico de vendas.
class VendasHistoricoResumo {
  const VendasHistoricoResumo({
    this.totalVendido = 0,
    this.vendasPagas = 0,
    this.vendasPendentes = 0,
    this.ticketMedio = 0,
    this.quantidadeVendas = 0,
  });

  final double totalVendido;
  final double vendasPagas;
  final double vendasPendentes;
  final double ticketMedio;
  final int quantidadeVendas;

  static const vazio = VendasHistoricoResumo();

  factory VendasHistoricoResumo.calcular(List<VendaHistorico> vendas) {
    if (vendas.isEmpty) return VendasHistoricoResumo.vazio;
    var totalVendido = 0.0;
    var vendasPagas = 0.0;
    var vendasPendentes = 0.0;
    final qtd = vendas.length;

    for (final v in vendas) {
      totalVendido += v.valorTotal;
      switch (v.status) {
        case 'pago':
          vendasPagas += v.valorTotal;
          break;
        case 'pendente':
        case 'parcial':
          vendasPendentes += v.valorPendente;
          break;
      }
    }

    final ticket = qtd > 0 ? totalVendido / qtd : 0.0;

    return VendasHistoricoResumo(
      totalVendido: _round(totalVendido),
      vendasPagas: _round(vendasPagas),
      vendasPendentes: _round(vendasPendentes),
      ticketMedio: _round(ticket),
      quantidadeVendas: qtd,
    );
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
