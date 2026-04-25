import 'fcm_notification_eventos.dart';

/// Rota nomeada alinhada ao payload FCM (`data.type`, `tipoNotificacao`, `segmento`).
String rotaPorPayloadFcm(Map<String, dynamic> data) {
  final type = data['type']?.toString() ?? '';
  final tipo = data['tipoNotificacao']?.toString() ?? '';
  final segmento = data['segmento']?.toString() ?? '';

  if (tipo == FcmNotificationEventos.tipoNovaEntrega) {
    return '/entregador';
  }
  // Cadastro de lojista APROVADO → painel do lojista (roteador decide
  // entre dashboard operacional e formulário caso a conta esteja em
  // transição). Antes o app levava o recém-aprovado direto para
  // `LojistaFormScreen`, o que passava a sensação de "caiu no
  // cadastro de novo". Fix 04/2026.
  if (tipo == 'lojista_cadastro_aprovado' ||
      type == 'LOJISTA_CADASTRO_APROVADO') {
    return '/lojista-painel';
  }
  // Cadastro de lojista RECUSADO → formulário, para o lojista rever
  // dados e reenviar.
  if (tipo == 'lojista_cadastro_recusado' ||
      type == 'LOJISTA_CADASTRO_RECUSADO') {
    return '/lojista-cadastro';
  }
  // Cadastro de entregador APROVADO → radar de corridas (tela home do
  // entregador). Evita mandar o usuário recém-aprovado de volta ao formulário
  // de cadastro; a jornada pós-aprovação é ficar online e receber ofertas.
  if (tipo == 'entregador_cadastro_aprovado' ||
      type == 'ENTREGADOR_CADASTRO_APROVADO') {
    return '/entregador';
  }
  // Cadastro de entregador RECUSADO → formulário, para revisar dados/docs.
  if (tipo == 'entregador_cadastro_recusado' ||
      type == 'ENTREGADOR_CADASTRO_RECUSADO') {
    return '/entregador-cadastro';
  }
  if (tipo == 'suporte_inicio' ||
      tipo == 'suporte_mensagem' ||
      tipo == 'suporte_encerrado' ||
      tipo == 'atendimento_iniciado' ||
      tipo == 'atendimento_reaberto') {
    return '/suporte';
  }
  // Chat do pedido (cliente ↔ loja)
  if (tipo == 'chat_pedido_loja_para_cliente') {
    return '/meus-pedidos';
  }
  if (tipo == 'chat_pedido_cliente_para_loja') {
    return '/pedidos';
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
