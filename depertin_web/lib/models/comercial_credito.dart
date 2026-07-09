import 'package:cloud_firestore/cloud_firestore.dart';

/// Status de parcela do crediário.
abstract final class ComercialParcelaStatus {
  static const emAberto = 'em_aberto';
  static const pago = 'pago';
  static const parcialmentePago = 'parcialmente_pago';
  static const vencido = 'vencido';

  static String rotulo(String status) {
    switch (status) {
      case pago:
        return 'Pago';
      case parcialmentePago:
        return 'Parcialmente pago';
      case vencido:
        return 'Vencido';
      default:
        return 'Em aberto';
    }
  }

  static String calcular({
    required double valorParcela,
    required double valorPago,
    required DateTime dataVencimento,
  }) {
    final aberto = (valorParcela - valorPago).clamp(0, double.infinity);
    if (aberto <= 0.009) return pago;
    if (valorPago > 0.009) return parcialmentePago;
    final hoje = DateTime.now();
    final venc = DateTime(
      dataVencimento.year,
      dataVencimento.month,
      dataVencimento.day,
    );
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    if (venc.isBefore(h)) return vencido;
    return emAberto;
  }
}

/// Venda financiada no crediário (`users/{lojaId}/vendas_credito/{id}`).
class ComercialVendaCredito {
  ComercialVendaCredito({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    required this.vendaId,
    required this.codigoVenda,
    required this.valorTotal,
    required this.quantidadeParcelas,
    required this.valorEntrada,
    required this.valorFinanciado,
    required this.status,
    this.dataCompra,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String lojaId;
  final String clienteId;
  final String vendaId;
  final String codigoVenda;
  final double valorTotal;
  final int quantidadeParcelas;
  final double valorEntrada;
  final double valorFinanciado;
  final String status;
  final DateTime? dataCompra;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ComercialVendaCredito.fromDoc(String id, Map<String, dynamic> d) {
    return ComercialVendaCredito(
      id: id,
      lojaId: (d['loja_id'] ?? '').toString(),
      clienteId: (d['cliente_id'] ?? '').toString(),
      vendaId: (d['venda_id'] ?? '').toString(),
      codigoVenda: (d['codigo_venda'] ?? d['codigo_pedido'] ?? '').toString(),
      valorTotal: _num(d['valor_total']),
      quantidadeParcelas: _int(d['quantidade_parcelas'], 1),
      valorEntrada: _num(d['valor_entrada']),
      valorFinanciado: _num(d['valor_financiado']),
      status: (d['status'] ?? 'ativo').toString(),
      dataCompra: _ts(d['data_compra']),
      createdAt: _ts(d['created_at']),
      updatedAt: _ts(d['updated_at']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'loja_id': lojaId,
        'cliente_id': clienteId,
        'venda_id': vendaId,
        'codigo_venda': codigoVenda,
        'valor_total': valorTotal,
        'quantidade_parcelas': quantidadeParcelas,
        'valor_entrada': valorEntrada,
        'valor_financiado': valorFinanciado,
        'status': status,
        'data_compra': dataCompra != null
            ? Timestamp.fromDate(dataCompra!)
            : FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static int _int(dynamic v, int fb) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fb;
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }
}

/// Parcela do crediário (`users/{lojaId}/parcelas_cliente/{id}`).
class ComercialParcelaCliente {
  ComercialParcelaCliente({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    required this.vendaCreditoId,
    required this.vendaId,
    required this.codigoVenda,
    required this.numeroParcela,
    required this.valorParcela,
    required this.valorPago,
    required this.dataCompra,
    required this.dataVencimento,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.renegociadoCodigo,
  });

  final String id;
  final String lojaId;
  final String clienteId;
  final String vendaCreditoId;
  final String vendaId;
  final String codigoVenda;
  final int numeroParcela;
  final double valorParcela;
  final double valorPago;
  final DateTime? dataCompra;
  final DateTime dataVencimento;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? renegociadoCodigo;

  double get valorEmAberto =>
      (valorParcela - valorPago).clamp(0, double.infinity);

  bool get podeReceber => valorEmAberto > 0.009;

  String get statusExibicao => ComercialParcelaStatus.rotulo(status);

  ComercialParcelaCliente copyWith({
    double? valorPago,
    String? status,
  }) {
    return ComercialParcelaCliente(
      id: id,
      lojaId: lojaId,
      clienteId: clienteId,
      vendaCreditoId: vendaCreditoId,
      vendaId: vendaId,
      codigoVenda: codigoVenda,
      numeroParcela: numeroParcela,
      valorParcela: valorParcela,
      valorPago: valorPago ?? this.valorPago,
      dataCompra: dataCompra,
      dataVencimento: dataVencimento,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory ComercialParcelaCliente.fromDoc(String id, Map<String, dynamic> d) {
    final valorParcela = _num(d['valor_parcela']);
    final valorPago = _num(d['valor_pago']);
    final venc = _ts(d['data_vencimento']) ?? DateTime.now();
    final statusGravado = (d['status'] ?? '').toString();
    final status = statusGravado.isNotEmpty
        ? statusGravado
        : ComercialParcelaStatus.calcular(
            valorParcela: valorParcela,
            valorPago: valorPago,
            dataVencimento: venc,
          );

    return ComercialParcelaCliente(
      id: id,
      lojaId: (d['loja_id'] ?? '').toString(),
      clienteId: (d['cliente_id'] ?? '').toString(),
      vendaCreditoId: (d['venda_credito_id'] ?? '').toString(),
      vendaId: (d['venda_id'] ?? '').toString(),
      codigoVenda: (d['codigo_venda'] ?? '').toString(),
      numeroParcela: _int(d['numero_parcela'], 1),
      valorParcela: valorParcela,
      valorPago: valorPago,
      dataCompra: _ts(d['data_compra']),
      dataVencimento: venc,
      status: status,
      createdAt: _ts(d['created_at']),
      updatedAt: _ts(d['updated_at']),
      renegociadoCodigo: d['renegociado_codigo']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'loja_id': lojaId,
        'cliente_id': clienteId,
        'venda_credito_id': vendaCreditoId,
        'venda_id': vendaId,
        'codigo_venda': codigoVenda,
        'numero_parcela': numeroParcela,
        'valor_parcela': valorParcela,
        'valor_pago': valorPago,
        'valor_em_aberto': valorEmAberto,
        'data_compra': dataCompra != null
            ? Timestamp.fromDate(dataCompra!)
            : FieldValue.serverTimestamp(),
        'data_vencimento': Timestamp.fromDate(dataVencimento),
        'status': status,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static int _int(dynamic v, int fb) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fb;
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }
}

/// Registro de pagamento recebido (`users/{lojaId}/recebimentos_cliente/{id}`).
class ComercialRecebimentoCliente {
  ComercialRecebimentoCliente({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    required this.parcelaId,
    required this.valorPago,
    required this.formaPagamento,
    required this.dataPagamento,
    this.observacao,
    this.usuarioId,
    this.usuarioNome,
    this.numeroParcela,
    this.codigoVenda,
    this.valorRestanteApos,
    this.createdAt,
  });

  final String id;
  final String lojaId;
  final String clienteId;
  final String parcelaId;
  final double valorPago;
  final String formaPagamento;
  final String? observacao;
  final String? usuarioId;
  final String? usuarioNome;
  final DateTime dataPagamento;
  final int? numeroParcela;
  final String? codigoVenda;
  final double? valorRestanteApos;
  final DateTime? createdAt;

  factory ComercialRecebimentoCliente.fromDoc(String id, Map<String, dynamic> d) {
    return ComercialRecebimentoCliente(
      id: id,
      lojaId: (d['loja_id'] ?? '').toString(),
      clienteId: (d['cliente_id'] ?? '').toString(),
      parcelaId: (d['parcela_id'] ?? '').toString(),
      valorPago: ComercialParcelaCliente._num(d['valor_pago']),
      formaPagamento: (d['forma_pagamento'] ?? '').toString(),
      observacao: d['observacao']?.toString(),
      usuarioId: d['usuario_id']?.toString(),
      usuarioNome: d['usuario_nome']?.toString(),
      dataPagamento:
          ComercialParcelaCliente._ts(d['data_pagamento']) ?? DateTime.now(),
      numeroParcela: ComercialParcelaCliente._int(d['numero_parcela'], 0),
      codigoVenda: d['codigo_venda']?.toString(),
      valorRestanteApos: d['valor_restante_apos'] != null
          ? ComercialParcelaCliente._num(d['valor_restante_apos'])
          : null,
      createdAt: ComercialParcelaCliente._ts(d['created_at']),
    );
  }
}

/// Resumo financeiro de parcelas do cliente.
class ComercialResumoParcelas {
  const ComercialResumoParcelas({
    required this.totalEmAberto,
    required this.totalPago,
    required this.parcelasVencidas,
    this.proximaParcela,
  });

  final double totalEmAberto;
  final double totalPago;
  final int parcelasVencidas;
  final ComercialParcelaCliente? proximaParcela;

  static const vazio = ComercialResumoParcelas(
    totalEmAberto: 0,
    totalPago: 0,
    parcelasVencidas: 0,
  );
}

/// Resultado de um pagamento registrado.
class ComercialRecebimentoResult {
  const ComercialRecebimentoResult({
    required this.recebimentoId,
    required this.parcela,
    required this.valorPago,
    required this.valorRestante,
    required this.formaPagamento,
    required this.dataPagamento,
    required this.clienteNome,
    required this.clienteCpf,
    required this.clienteTelefone,
    required this.lojaNome,
    required this.usuarioNome,
  });

  final String recebimentoId;
  final ComercialParcelaCliente parcela;
  final double valorPago;
  final double valorRestante;
  final String formaPagamento;
  final DateTime dataPagamento;
  final String clienteNome;
  final String? clienteCpf;
  final String? clienteTelefone;
  final String lojaNome;
  final String usuarioNome;
}
