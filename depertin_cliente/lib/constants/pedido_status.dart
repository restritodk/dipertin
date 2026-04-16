/// Status de pedido no Firestore — fluxo lojista ↔ entregador ↔ cliente.
abstract class PedidoStatus {
  static const aguardandoPagamento = 'aguardando_pagamento';
  static const pendente = 'pendente';
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
  static const String cancelClienteCodDesistencia = 'desistencia';
  static const String cancelClienteCodDemoraLoja = 'demora_loja';
  static const String cancelClienteCodOutro = 'outro';
}
