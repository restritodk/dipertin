/// Espelho de `depertin_cliente/lib/utils/codigo_pedido.dart`.
abstract class CodigoPedido {
  static int _dartStringHashCode(String s) {
    var hash = 0;
    for (var i = 0; i < s.length; i++) {
      hash = 0x1fffffff & (hash + s.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 5));
    }
    return hash;
  }

  static String gerar(String firebaseId) {
    final id = firebaseId.trim();
    if (id.isEmpty) return '—';
    final hash = _dartStringHashCode(id).abs();
    final numero = (hash % 999999).toString().padLeft(6, '0');
    return 'PED-$numero';
  }

  static String exibir(String pedidoId, [Map<String, dynamic>? dadosPedido]) {
    final gravado = dadosPedido?['codigo_pedido']?.toString().trim();
    if (gravado != null && gravado.isNotEmpty) return gravado;
    return gerar(pedidoId);
  }
}
