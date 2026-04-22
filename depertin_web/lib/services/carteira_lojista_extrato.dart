import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Linha unificada do extrato da carteira do lojista (mesma regra que o app).
class CarteiraLancamento {
  final bool entrada;
  final double valor;
  final String titulo;
  final String subtitulo;
  final DateTime data;
  final String status;

  /// Saque PIX — nome do banco (opcional).
  final String? banco;
  final String? refPedidoId;
  final String? refSaqueId;
  final String? refEstornoId;

  const CarteiraLancamento({
    required this.entrada,
    required this.valor,
    required this.titulo,
    required this.subtitulo,
    required this.data,
    required this.status,
    this.banco,
    this.refPedidoId,
    this.refSaqueId,
    this.refEstornoId,
  });

  bool get temDetalhe =>
      refPedidoId != null || refSaqueId != null || refEstornoId != null;
}

/// Construção do extrato a partir dos mesmos documentos que [Minha Carteira].
abstract final class CarteiraLojistaExtrato {
  static double numDyn(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// Crédito que entra na carteira do lojista quando o pedido está entregue.
  /// Modelo iFood: o lojista recebe APENAS o valor dos produtos menos a
  /// taxa da plataforma sobre os produtos. Frete pertence ao entregador,
  /// não entra no crédito do lojista.
  static double creditoLoja(Map<String, dynamic> d) {
    final vl = d['valor_liquido_lojista'];
    if (vl != null) return math.max(0, numDyn(vl));
    // Fallback para pedidos antigos sem campos calculados pelo servidor:
    // usa total_produtos / subtotal (sem frete) e desconta taxa_plataforma
    // se o doc tiver. NÃO subtrai taxa_entrega de total porque produtos já
    // não devem incluir frete.
    final taxaPlataforma = numDyn(d['taxa_plataforma']);
    final produtos = valorProdutosPedido(d);
    if (produtos > 0) return math.max(0, produtos - taxaPlataforma);
    // Último recurso: pedido antigo só com `total` (provavelmente já é só
    // produtos em cenários antigos sem frete).
    return math.max(0, numDyn(d['total']) - taxaPlataforma);
  }

  static List<String> nomesProdutosDoPedido(Map<String, dynamic> d) {
    final itens = d['itens'];
    if (itens is! List) return [];
    final out = <String>[];
    for (final raw in itens) {
      if (raw is Map) {
        final nome = raw['nome']?.toString().trim() ?? '';
        if (nome.isNotEmpty) out.add(nome);
      }
    }
    return out;
  }

  static String tituloExtratoVendaPedido(
    Map<String, dynamic> d, {
    required bool creditoEntregue,
  }) {
    final nomes = nomesProdutosDoPedido(d);
    if (nomes.isEmpty) {
      return creditoEntregue ? 'Venda creditada' : 'Pedido em andamento';
    }
    if (nomes.length == 1) {
      return creditoEntregue
          ? 'Venda ${nomes.first}'
          : 'Pedido · ${nomes.first}';
    }
    final dois = nomes.take(2).join(', ');
    final extra = nomes.length - 2;
    final tail = extra > 0 ? ' +$extra' : '';
    return creditoEntregue ? 'Venda $dois$tail' : 'Pedido · $dois$tail';
  }

  static String nomesProdutoDetalheLinha(Map<String, dynamic> d) {
    final nomes = nomesProdutosDoPedido(d);
    if (nomes.isEmpty) return '—';
    return nomes.join(', ');
  }

  static double valorProdutosPedido(Map<String, dynamic> p) {
    final tp = numDyn(p['total_produtos']);
    if (tp > 0) return tp;
    final sub = numDyn(p['subtotal']);
    if (sub > 0) return sub;
    final itens = p['itens'];
    if (itens is! List) return 0;
    double s = 0;
    for (final raw in itens) {
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        final q = m['quantidade'];
        final qn = q is num ? q.toDouble() : double.tryParse('$q') ?? 1;
        s += numDyn(m['preco']) * qn;
      }
    }
    return s;
  }

  static String statusLabelPedido(String st) {
    switch (st) {
      case 'pendente':
        return 'Aguardando confirmação';
      case 'confirmado':
        return 'Confirmado';
      case 'em_preparo':
        return 'Em preparo';
      case 'saiu_para_entrega':
        return 'Saiu para entrega';
      case 'entregue':
        return 'Entregue';
      case 'concluido':
        return 'Concluído';
      case 'finalizado':
        return 'Finalizado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return st;
    }
  }

  static List<CarteiraLancamento> buildLancamentos(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> saqDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pedDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> estornoDocs,
  ) {
    final list = <CarteiraLancamento>[];

    for (final doc in saqDocs) {
      final d = doc.data();
      final ts = d['data_solicitacao'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
      final chave = d['chave_pix']?.toString() ?? '';
      final banco = d['banco']?.toString().trim();
      list.add(
        CarteiraLancamento(
          entrada: false,
          valor: numDyn(d['valor']),
          titulo: 'Transferência PIX',
          subtitulo: chave.isNotEmpty ? 'Chave: $chave' : 'Repasse solicitado',
          data: dt,
          status: d['status']?.toString() ?? 'pendente',
          banco: banco != null && banco.isNotEmpty ? banco : null,
          refSaqueId: doc.id,
        ),
      );
    }

    for (final doc in pedDocs) {
      final d = doc.data();
      final st = d['status']?.toString() ?? 'pendente';
      final ignorar = st == 'cancelado' || st == 'recusado';
      if (ignorar) continue;
      final ts = d['data_pedido'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
      final creditoEntregue =
          st == 'entregue' || st == 'concluido' || st == 'finalizado';
      // Tanto pendente quanto entregue exibem o LÍQUIDO do lojista (somente
      // produtos − taxa plataforma), não o total do pedido. Isso evita
      // confundir o lojista achando que vai receber também o valor do frete.
      final valor = creditoLoja(d);
      if (valor <= 0) continue;
      list.add(
        CarteiraLancamento(
          entrada: true,
          valor: valor,
          titulo: tituloExtratoVendaPedido(d, creditoEntregue: creditoEntregue),
          subtitulo:
              'Pedido #${doc.id.substring(0, math.min(8, doc.id.length))} · ${statusLabelPedido(st)}',
          data: dt,
          status: creditoEntregue ? 'concluido' : 'pendente',
          refPedidoId: doc.id,
        ),
      );
    }

    for (final doc in estornoDocs) {
      final d = doc.data();
      final tipoOp = d['tipo_operacao']?.toString() ?? '';
      final ts = d['data_estorno'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();

      if (tipoOp == 'credito_saque_recusado') {
        final motivo =
            d['motivo']?.toString() ?? 'Crédito após recusa do saque';
        list.add(
          CarteiraLancamento(
            entrada: true,
            valor: numDyn(d['valor']),
            titulo: 'Estorno de saque PIX',
            subtitulo: motivo,
            data: dt,
            status: 'estorno_pix_credito',
            refEstornoId: doc.id,
          ),
        );
        continue;
      }

      final motivo = d['motivo']?.toString() ?? 'Estorno de pedido';
      final pedidoId = d['pedido_id']?.toString() ?? '';
      final sub = pedidoId.isNotEmpty
          ? 'Pedido #${pedidoId.substring(0, math.min(8, pedidoId.length))} · $motivo'
          : motivo;
      list.add(
        CarteiraLancamento(
          entrada: false,
          valor: numDyn(d['valor']),
          titulo: 'Estorno ao cliente',
          subtitulo: sub,
          data: dt,
          status: 'estornado',
          refEstornoId: doc.id,
        ),
      );
    }

    list.sort((a, b) => b.data.compareTo(a.data));
    return list;
  }
}

/// Totais e indicadores para o painel Financeiro (período filtrado).
class CarteiraFinanceiroResumo {
  const CarteiraFinanceiroResumo({
    required this.entradas,
    required this.saidas,
    required this.liquido,
    required this.qLancamentos,
    required this.qVendasCreditadas,
    required this.ticketMedioVendas,
  });

  final double entradas;
  final double saidas;
  final double liquido;
  final int qLancamentos;
  final int qVendasCreditadas;
  final double? ticketMedioVendas;

  static CarteiraFinanceiroResumo fromLancamentos(
    List<CarteiraLancamento> filtrados,
  ) {
    double entradas = 0;
    double saidas = 0;
    double somaVendas = 0;
    var nVendas = 0;
    for (final l in filtrados) {
      if (l.entrada) {
        entradas += l.valor;
        if (l.refPedidoId != null && l.status == 'concluido') {
          somaVendas += l.valor;
          nVendas++;
        }
      } else {
        saidas += l.valor;
      }
    }
    return CarteiraFinanceiroResumo(
      entradas: entradas,
      saidas: saidas,
      liquido: entradas - saidas,
      qLancamentos: filtrados.length,
      qVendasCreditadas: nVendas,
      ticketMedioVendas: nVendas > 0 ? somaVendas / nVendas : null,
    );
  }
}

/// Pontos para gráfico: vendas creditadas por dia (soma dos valores).
List<CarteiraVendaDia> vendasPorDia(List<CarteiraLancamento> filtrados) {
  final map = <String, double>{};
  for (final l in filtrados) {
    if (!l.entrada || l.refPedidoId == null || l.status != 'concluido') {
      continue;
    }
    final k =
        '${l.data.year.toString().padLeft(4, '0')}-${l.data.month.toString().padLeft(2, '0')}-${l.data.day.toString().padLeft(2, '0')}';
    map[k] = (map[k] ?? 0) + l.valor;
  }
  final keys = map.keys.toList()..sort();
  return [
    for (final k in keys) CarteiraVendaDia(data: k, valor: map[k]!),
  ];
}

class CarteiraVendaDia {
  const CarteiraVendaDia({required this.data, required this.valor});

  /// yyyy-MM-dd
  final String data;
  final double valor;
}
