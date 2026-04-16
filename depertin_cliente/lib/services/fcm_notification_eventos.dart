/// Segmentação de push (alinhado a `functions/notification_dispatcher.js` e logística).
abstract class FcmNotificationEventos {
  static const segmentoLoja = 'loja';
  static const segmentoCliente = 'cliente';
  static const segmentoEntregador = 'entregador';

  static const eventoOrderCreated = 'order_created';
  static const eventoDispatchRequest = 'dispatch_request';

  /// Lojista — novo pedido (FCM `data.type`, espelho em [tipoNovoPedido]).
  static const typeNovoPedido = 'NOVO_PEDIDO';

  /// Lojista — cliente cancelou pedido em andamento.
  static const typeClienteCancelouPedido = 'CLIENTE_CANCEL_PEDIDO';

  /// Lojista — novo pedido (apenas loja_id).
  static const tipoNovoPedido = 'novo_pedido';

  /// Lojista — cliente cancelou (espelho em [typeClienteCancelouPedido]).
  static const tipoClienteCancelouPedido = 'cliente_cancelou_pedido';

  /// Entregador — cliente cancelou pedido com entregador já designado.
  static const typePedidoCanceladoClienteEntregador =
      'PEDIDO_CANCELADO_CLIENTE_ENTREGADOR';
  static const tipoClienteCancelouPedidoEntregador =
      'cliente_cancelou_pedido_entregador';

  /// Cliente — pagamento aprovado (FCM `data.type`).
  static const typePagamentoConfirmado = 'PAGAMENTO_CONFIRMADO';

  /// Entregador — oferta sequencial.
  static const tipoNovaEntrega = 'nova_entrega';

  /// FCM `data.type` na logística (espelho de [tipoNovaEntrega]).
  static const typeNovaCorrida = 'nova_corrida';

  /// Cliente — prefixo `pedido_` + evento (ex.: pedido_payment_confirmed).
  static String tipoPedidoStatus(String evento) => 'pedido_$evento';
}
