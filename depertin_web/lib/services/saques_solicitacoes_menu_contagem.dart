import 'package:cloud_firestore/cloud_firestore.dart';

/// Contagem de solicitações de saque para o item do menu lateral.
///
/// **Regra de negócio:** expõe apenas solicitações com `status == 'pendente'`
/// (ação administrativa: aprovar / recusar). Atualiza em tempo real quando:
/// - nova solicitação é criada como pendente;
/// - status muda para `pago` ou `recusado`;
/// - documento é removido.
///
/// O [streamPendentes] é [BroadcastStream] em cache: vários ouvintes (ex.: rebuilds
/// do menu) partilham **uma** subscrição à query, evitando consultas duplicadas.
abstract final class SaquesSolicitacoesMenuContagem {
  static Stream<int>? _pendentesBroadcast;

  /// Número de solicitações pendentes de análise (mesma origem que a fila no painel).
  static Stream<int> get streamPendentes {
    _pendentesBroadcast ??= FirebaseFirestore.instance
        .collection('saques_solicitacoes')
        .where('status', isEqualTo: 'pendente')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs.length)
        .asBroadcastStream();
    return _pendentesBroadcast!;
  }
}
