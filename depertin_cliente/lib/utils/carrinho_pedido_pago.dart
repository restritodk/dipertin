import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/pedido_status.dart';

/// Lojas cujos itens podem sair da sacola após pagamento confirmado.
/// Compatível com pedido único e checkout multi-loja (legado unificado ou
/// pagamento independente por loja).
Future<Set<String>> lojaIdsParaLimparCarrinhoAposPagamento(
  String pedidoId,
) async {
  final id = pedidoId.trim();
  if (id.isEmpty) return {};

  final snap = await FirebaseFirestore.instance
      .collection('pedidos')
      .doc(id)
      .get();
  if (!snap.exists) return {};

  final data = snap.data() ?? {};
  if ((data['tipo_compra'] ?? '').toString() == 'encomenda') return {};

  final status = (data['status'] ?? '').toString();
  final pago =
      status == 'pendente' || status == PedidoStatus.encomendaEntradaPaga;
  if (!pago) return {};

  final lojaIds = <String>{};
  void addLoja(Map<String, dynamic> m) {
    final loja = (m['loja_id'] ?? '').toString().trim();
    if (loja.isNotEmpty) lojaIds.add(loja);
  }

  addLoja(data);

  final rawGrupo = data['checkout_grupo_pedido_ids'];
  if (rawGrupo is! List || rawGrupo.isEmpty) return lojaIds;

  final idsGrupo = rawGrupo
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  if (idsGrupo.length < 2) return lojaIds;

  final snaps = await Future.wait(
    idsGrupo.map(
      (gid) => FirebaseFirestore.instance.collection('pedidos').doc(gid).get(),
    ),
  );
  for (final s in snaps) {
    if (!s.exists) continue;
    final d = s.data() ?? {};
    final st = (d['status'] ?? '').toString();
    if (st == 'pendente' || st == PedidoStatus.encomendaEntradaPaga) {
      addLoja(d);
    }
  }
  return lojaIds;
}
