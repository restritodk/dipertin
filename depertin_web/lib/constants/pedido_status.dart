/// Espelho dos helpers de cancelamento do app mobile (`depertin_cliente`).
abstract class PedidoStatusWeb {
  static const cancelado = 'cancelado';

  static const canceladoMotivoClienteSolicitou = 'cliente_solicitou';
  static const canceladoMotivoClienteCancelouPix = 'cliente_cancelou_pix';
  static const canceladoMotivoPixExpirado = 'pix_expirado';
  static const canceladoMotivoLojistaRecusou = 'lojista_recusou';

  static const Set<String> canceladoMotivosSomenteCliente = {
    canceladoMotivoClienteSolicitou,
    canceladoMotivoClienteCancelouPix,
    canceladoMotivoPixExpirado,
  };

  static bool canceladoPeloCliente(Map<String, dynamic> pedido) {
    final motivo = (pedido['cancelado_motivo'] ?? '').toString().trim();
    return canceladoMotivosSomenteCliente.contains(motivo);
  }

  static bool canceladoVisivelParaLojista(Map<String, dynamic> pedido) {
    if ((pedido['status'] ?? '').toString() != cancelado) return false;
    return !canceladoPeloCliente(pedido);
  }

  /// Pedido que deve aparecer em qualquer aba da lista do lojista (web).
  /// Cancelados (expiração PIX/cartão, cliente ou lojista) ficam ocultos.
  static bool visivelNaListaLojista(Map<String, dynamic> pedido) {
    return (pedido['status'] ?? '').toString() != cancelado;
  }
}
