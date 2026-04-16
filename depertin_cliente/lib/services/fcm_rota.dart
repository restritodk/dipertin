import 'fcm_notification_eventos.dart';

/// Rota nomeada alinhada ao payload FCM (`data.type`, `tipoNotificacao`, `segmento`).
String rotaPorPayloadFcm(Map<String, dynamic> data) {
  final type = data['type']?.toString() ?? '';
  final tipo = data['tipoNotificacao']?.toString() ?? '';
  final segmento = data['segmento']?.toString() ?? '';

  if (tipo == FcmNotificationEventos.tipoNovaEntrega) {
    return '/entregador';
  }
  if (tipo == 'suporte_inicio' ||
      tipo == 'suporte_mensagem' ||
      tipo == 'suporte_encerrado' ||
      tipo == 'atendimento_iniciado') {
    return '/suporte';
  }
  if (type == FcmNotificationEventos.typePagamentoConfirmado ||
      tipo == FcmNotificationEventos.tipoPedidoStatus('payment_confirmed') ||
      (segmento == FcmNotificationEventos.segmentoCliente &&
          tipo.startsWith('pedido_'))) {
    return '/meus-pedidos';
  }
  if (type == FcmNotificationEventos.typeNovoPedido ||
      tipo == FcmNotificationEventos.tipoNovoPedido) {
    return '/pedidos';
  }
  if (type == FcmNotificationEventos.typeClienteCancelouPedido ||
      tipo == FcmNotificationEventos.tipoClienteCancelouPedido) {
    return '/pedidos';
  }
  if (type == FcmNotificationEventos.typePedidoCanceladoClienteEntregador ||
      tipo == FcmNotificationEventos.tipoClienteCancelouPedidoEntregador) {
    return '/entregador';
  }
  return '/home';
}
