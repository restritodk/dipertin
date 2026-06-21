/// Status de pedido no Firestore — fluxo lojista ↔ entregador ↔ cliente.
abstract class PedidoStatus {
  static const aguardandoPagamento = 'aguardando_pagamento';
  static const pendente = 'pendente';
  /// Entrada da encomenda paga — produção antes do saldo e da logística (Fase 2).
  static const encomendaEntradaPaga = 'encomenda_entrada_paga';
  static const aceito = 'aceito';
  static const emPreparo = 'em_preparo';
  static const aguardandoEntregador = 'aguardando_entregador';
  static const entregadorIndoLoja = 'entregador_indo_loja';
  static const saiuEntrega = 'saiu_entrega';
  /// Legado / compatível com fluxo antigo
  static const aCaminho = 'a_caminho';
  static const emRota = 'em_rota';
  static const pronto = 'pronto';
  static const entregue = 'entregue';
  static const cancelado = 'cancelado';

  static const Set<String> andamentoLojista = {
    aceito,
    emPreparo,
    aguardandoEntregador,
    entregadorIndoLoja,
    saiuEntrega,
    aCaminho,
    emRota,
    pronto,
  };

  /// Após pagamento confirmado — cliente pode solicitar cancelamento em Meus pedidos.
  static const Set<String> clientePodeCancelarAposPagamento = {
    pendente,
    aceito,
    emPreparo,
    pronto,
    aguardandoEntregador,
    entregadorIndoLoja,
    saiuEntrega,
    aCaminho,
    emRota,
  };

  /// Após notificação "Saiu para entrega" (entregador a caminho do cliente).
  /// Cancelamento aqui aciona estorno **parcial** (sem taxa de entrega no MP).
  static const Set<String> clienteCancelamentoParcialFreteRetido = {
    saiuEntrega,
    aCaminho,
    emRota,
  };

  static const String canceladoMotivoClienteSolicitou = 'cliente_solicitou';
  static const String canceladoMotivoClienteCancelouPix = 'cliente_cancelou_pix';
  static const String canceladoMotivoPixExpirado = 'pix_expirado';
  /// Lojista recusou/cancelou o pedido (visível para loja e cliente).
  static const String canceladoMotivoLojistaRecusou = 'lojista_recusou';

  static const String cancelClienteCodDesistencia = 'desistencia';
  static const String cancelClienteCodDemoraLoja = 'demora_loja';
  static const String cancelClienteCodOutro = 'outro';

  static const Set<String> canceladoMotivosSomenteCliente = {
    canceladoMotivoClienteSolicitou,
    canceladoMotivoClienteCancelouPix,
    canceladoMotivoPixExpirado,
  };

  /// Cancelamento iniciado pelo cliente — não exibir na área do lojista.
  static bool canceladoPeloCliente(Map<String, dynamic> pedido) {
    final motivo = (pedido['cancelado_motivo'] ?? '').toString().trim();
    return canceladoMotivosSomenteCliente.contains(motivo);
  }

  /// Pedido `cancelado` que o lojista deve ver (recusa própria ou legado sem motivo).
  static bool canceladoVisivelParaLojista(Map<String, dynamic> pedido) {
    if ((pedido['status'] ?? '').toString() != cancelado) return false;
    return !canceladoPeloCliente(pedido);
  }
}
