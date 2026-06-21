/// Código amigável único do pedido (ex.: PED-042817) — mesmo algoritmo do
/// painel admin (`monitor_pedidos_screen`) e do backend (`codigo_pedido.js`).
abstract class CodigoPedido {
  static int _dartStringHashCode(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = 0x1fffffff & (hash + s.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 5));
    }
    return hash;
  }

  /// Gera `PED-` + 6 dígitos a partir do ID Firestore do pedido.
  static String gerar(String firebaseId) {
    final id = firebaseId.trim();
    if (id.isEmpty) return '—';
    final hash = _dartStringHashCode(id).abs();
    final numero = (hash % 999999).toString().padLeft(6, '0');
    return 'PED-$numero';
  }

  /// Usa [dadosPedido]['codigo_pedido'] quando gravado; senão [gerar].
  static String exibir(String pedidoId, [Map<String, dynamic>? dadosPedido]) {
    final gravado = dadosPedido?['codigo_pedido']?.toString().trim();
    if (gravado != null && gravado.isNotEmpty) return gravado;
    return gerar(pedidoId);
  }
}
