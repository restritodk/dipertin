import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/encomenda_negociacao_status.dart';
import '../constants/pedido_status.dart';

/// Contagem do card **Novos** no painel do lojista e badges de gestão.
///
/// Fórmula: `pedidosNovos + encomendasNovas` (cada documento = 1, sem agrupar).
abstract class LojistaContagemNovos {
  /// Pedido pronto-entrega ou entrada de encomenda na aba "Novos" de pedidos.
  static bool pedidoStatusApareceNaAbaNovos(String status) =>
      status == PedidoStatus.pendente ||
      status == PedidoStatus.encomendaEntradaPaga;

  /// Pedido de encomenda (fase entrada) oculto quando já existe pedido de saldo.
  static bool pedidoEntradaEncomendaSubstituido(
    Map<String, dynamic> data,
    Set<String> encomendaIdsComPedidoSaldo,
  ) {
    final tipoCompra = (data['tipo_compra'] ?? '').toString();
    final fase = (data['encomenda_fase_financeira'] ?? '').toString();
    final encId = (data['encomenda_id'] ?? '').toString().trim();
    return tipoCompra == 'encomenda' &&
        fase == 'entrada' &&
        encId.isNotEmpty &&
        encomendaIdsComPedidoSaldo.contains(encId);
  }

  static Set<String> encomendaIdsComPedidoSaldoFinal(
    Iterable<QueryDocumentSnapshot> pedidosDocs,
  ) {
    return pedidosDocs
        .where((p) {
          final data = p.data() as Map<String, dynamic>;
          final tipoCompra = (data['tipo_compra'] ?? '').toString();
          final fase = (data['encomenda_fase_financeira'] ?? '').toString();
          final encId = (data['encomenda_id'] ?? '').toString().trim();
          return tipoCompra == 'encomenda' &&
              fase == 'saldo_final' &&
              encId.isNotEmpty;
        })
        .map(
          (p) =>
              ((p.data() as Map<String, dynamic>)['encomenda_id'] ?? '')
                  .toString()
                  .trim(),
        )
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Conta pedidos que exigem ação na gestão de pedidos (1 doc = 1).
  static int contarPedidosNovos(Iterable<QueryDocumentSnapshot> pedidosDocs) {
    final lista = pedidosDocs.toList();
    final saldoIds = encomendaIdsComPedidoSaldoFinal(lista);
    var total = 0;
    for (final doc in lista) {
      final data = doc.data() as Map<String, dynamic>;
      if (pedidoEntradaEncomendaSubstituido(data, saldoIds)) continue;
      final status = (data['status'] ?? 'pendente').toString();
      if (pedidoStatusApareceNaAbaNovos(status)) total++;
    }
    return total;
  }

  /// Encomenda recém-enviada ou aguardando primeira ação da loja (1 doc = 1).
  static bool encomendaContaComoNova(String statusNegociacao) {
    final st = statusNegociacao.trim();
    return st == EncomendaNegociacaoStatus.aguardandoNegociacao;
  }

  /// Conta encomendas novas (1 doc = 1).
  static int contarEncomendasNovas(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> encomendaDocs,
  ) {
    var total = 0;
    for (final doc in encomendaDocs) {
      final st = (doc.data()['status_negociacao'] ?? '').toString();
      if (encomendaContaComoNova(st)) total++;
    }
    return total;
  }

  static int totalNovosPainel({
    required Iterable<QueryDocumentSnapshot> pedidosDocs,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>>
        encomendaDocs,
  }) {
    return contarPedidosNovos(pedidosDocs) +
        contarEncomendasNovas(encomendaDocs);
  }
}
