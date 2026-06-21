import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/encomenda_negociacao_status.dart';
import '../theme/painel_admin_theme.dart';

const _kPedidoEntregue = 'entregue';

/// Código curto exibido no painel (derivado do ID Firestore — sem alterar backend).
String codigoEncomendaExibir(String encomendaId) {
  final id = encomendaId.trim();
  if (id.isEmpty) return '—';
  if (id.length <= 8) return 'ENC-${id.toUpperCase()}';
  return 'ENC-${id.substring(0, 8).toUpperCase()}';
}

enum FiltroEncomendaRapido {
  todas,
  novas,
  emNegociacao,
  aguardandoCliente,
  entradaPaga,
  producao,
  finalizadas,
  canceladas,
}

extension FiltroEncomendaRapidoExt on FiltroEncomendaRapido {
  String get rotulo {
    switch (this) {
      case FiltroEncomendaRapido.todas:
        return 'Todas';
      case FiltroEncomendaRapido.novas:
        return 'Novas';
      case FiltroEncomendaRapido.emNegociacao:
        return 'Em Negociação';
      case FiltroEncomendaRapido.aguardandoCliente:
        return 'Aguardando Cliente';
      case FiltroEncomendaRapido.entradaPaga:
        return 'Entrada Paga';
      case FiltroEncomendaRapido.producao:
        return 'Produção';
      case FiltroEncomendaRapido.finalizadas:
        return 'Finalizadas';
      case FiltroEncomendaRapido.canceladas:
        return 'Canceladas';
    }
  }

  IconData get icone {
    switch (this) {
      case FiltroEncomendaRapido.todas:
        return Icons.grid_view_rounded;
      case FiltroEncomendaRapido.novas:
        return Icons.fiber_new_rounded;
      case FiltroEncomendaRapido.emNegociacao:
        return Icons.handshake_outlined;
      case FiltroEncomendaRapido.aguardandoCliente:
        return Icons.hourglass_top_rounded;
      case FiltroEncomendaRapido.entradaPaga:
        return Icons.payments_outlined;
      case FiltroEncomendaRapido.producao:
        return Icons.precision_manufacturing_outlined;
      case FiltroEncomendaRapido.finalizadas:
        return Icons.check_circle_outline;
      case FiltroEncomendaRapido.canceladas:
        return Icons.cancel_outlined;
    }
  }
}

class EncomendaBadgeVisual {
  const EncomendaBadgeVisual({
    required this.label,
    required this.cor,
    required this.fundo,
    required this.icone,
  });

  final String label;
  final Color cor;
  final Color fundo;
  final IconData icone;
}

EncomendaBadgeVisual badgeEncomenda(String status) {
  switch (status) {
    case EncomendaNegociacaoStatus.aguardandoNegociacao:
      return EncomendaBadgeVisual(
        label: 'Nova solicitação',
        cor: PainelAdminTheme.roxo,
        fundo: const Color(0xFFF3E5F5),
        icone: Icons.fiber_new_rounded,
      );
    case EncomendaNegociacaoStatus.negociacaoEmAndamento:
    case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
      return EncomendaBadgeVisual(
        label: 'Em negociação',
        cor: const Color(0xFF2563EB),
        fundo: const Color(0xFFEFF6FF),
        icone: Icons.handshake_outlined,
      );
    case EncomendaNegociacaoStatus.propostaEnviada:
    case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
    case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
    case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
      return EncomendaBadgeVisual(
        label: 'Aguardando cliente',
        cor: PainelAdminTheme.laranja,
        fundo: const Color(0xFFFFF3E0),
        icone: Icons.hourglass_top_rounded,
      );
    case EncomendaNegociacaoStatus.entradaPagaEmProducao:
      return EncomendaBadgeVisual(
        label: 'Entrada paga · Produção',
        cor: const Color(0xFF0D9488),
        fundo: const Color(0xFFE0F2F1),
        icone: Icons.precision_manufacturing_outlined,
      );
    case EncomendaNegociacaoStatus.emExecucaoLogistica:
      return EncomendaBadgeVisual(
        label: 'Em entrega',
        cor: const Color(0xFF16A34A),
        fundo: const Color(0xFFECFDF5),
        icone: Icons.local_shipping_outlined,
      );
    case EncomendaNegociacaoStatus.encerradaRecusadaLoja:
    case EncomendaNegociacaoStatus.encerradaCanceladaCliente:
    case EncomendaNegociacaoStatus.encerradaCanceladaLoja:
      return EncomendaBadgeVisual(
        label: 'Cancelada',
        cor: const Color(0xFFDC2626),
        fundo: const Color(0xFFFEE2E2),
        icone: Icons.cancel_outlined,
      );
    default:
      return EncomendaBadgeVisual(
        label: EncomendaNegociacaoStatus.rotuloPt(status),
        cor: PainelAdminTheme.textoSecundario,
        fundo: const Color(0xFFF1F5F9),
        icone: Icons.info_outline,
      );
  }
}

bool encomendaPedidoVinculadoEntregue(
  Map<String, dynamic> data,
  Map<String, String> statusPedidos, {
  required String encomendaId,
}) {
  final pedidoLogistica = (data['pedido_logistica_id'] ?? '').toString().trim();
  final pedidoSaldo = (data['pedido_saldo_final_id'] ?? '').toString().trim();
  final ids = <String>[
    if (pedidoLogistica.isNotEmpty) pedidoLogistica,
    if (pedidoSaldo.isNotEmpty) pedidoSaldo,
  ];
  if (ids.any((id) => statusPedidos[id] == _kPedidoEntregue)) {
    return true;
  }
  return statusPedidos['enc:$encomendaId'] == _kPedidoEntregue;
}

bool encomendaFinalizada(
  Map<String, dynamic> data,
  Map<String, String> statusPedidos, {
  required String encomendaId,
}) {
  final st = (data['status_negociacao'] ?? '').toString();
  if (st == EncomendaNegociacaoStatus.emExecucaoLogistica) return true;
  return encomendaPedidoVinculadoEntregue(
    data,
    statusPedidos,
    encomendaId: encomendaId,
  );
}

FiltroEncomendaRapido bucketEncomendaDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  Map<String, String> statusPedidos,
) {
  final data = doc.data();
  final st = (data['status_negociacao'] ?? '').toString();
  if (EncomendaNegociacaoStatus.encerradaDefinitivamente(st)) {
    return FiltroEncomendaRapido.canceladas;
  }
  if (encomendaFinalizada(data, statusPedidos, encomendaId: doc.id)) {
    return FiltroEncomendaRapido.finalizadas;
  }
  if (st == EncomendaNegociacaoStatus.aguardandoNegociacao) {
    return FiltroEncomendaRapido.novas;
  }
  if (st == EncomendaNegociacaoStatus.negociacaoEmAndamento ||
      st == EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta) {
    return FiltroEncomendaRapido.emNegociacao;
  }
  if (st == EncomendaNegociacaoStatus.propostaEnviada ||
      st == EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada ||
      st == EncomendaNegociacaoStatus.entradaAguardandoPagamento ||
      st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto) {
    return FiltroEncomendaRapido.aguardandoCliente;
  }
  if (st == EncomendaNegociacaoStatus.entradaPagaEmProducao) {
    return FiltroEncomendaRapido.entradaPaga;
  }
  if (st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
      st == EncomendaNegociacaoStatus.emExecucaoLogistica) {
    return FiltroEncomendaRapido.producao;
  }
  return FiltroEncomendaRapido.emNegociacao;
}

/// KPIs do dashboard (sem «Entrada Paga» isolado — entra em Produção).
FiltroEncomendaRapido bucketKpiEncomendaDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  Map<String, String> statusPedidos,
) {
  final b = bucketEncomendaDoc(doc, statusPedidos);
  if (b == FiltroEncomendaRapido.entradaPaga ||
      b == FiltroEncomendaRapido.producao) {
    return FiltroEncomendaRapido.producao;
  }
  return b;
}

Map<FiltroEncomendaRapido, int> contarBucketsKpi(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  Map<String, String> statusPedidos,
) {
  final map = {
    FiltroEncomendaRapido.novas: 0,
    FiltroEncomendaRapido.emNegociacao: 0,
    FiltroEncomendaRapido.aguardandoCliente: 0,
    FiltroEncomendaRapido.producao: 0,
    FiltroEncomendaRapido.finalizadas: 0,
    FiltroEncomendaRapido.canceladas: 0,
  };
  for (final doc in docs) {
    final b = bucketKpiEncomendaDoc(doc, statusPedidos);
    map[b] = (map[b] ?? 0) + 1;
  }
  return map;
}

Map<FiltroEncomendaRapido, int> contarBuckets(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  Map<String, String> statusPedidos,
) {
  final map = {
    for (final f in FiltroEncomendaRapido.values) f: 0,
  };
  for (final doc in docs) {
    final b = bucketEncomendaDoc(doc, statusPedidos);
    map[b] = (map[b] ?? 0) + 1;
    map[FiltroEncomendaRapido.todas] =
        (map[FiltroEncomendaRapido.todas] ?? 0) + 1;
  }
  return map;
}

/// Passos da timeline compacta (paridade visual com o app).
class EncomendaTimelinePasso {
  const EncomendaTimelinePasso(this.rotulo, this.concluido);
  final String rotulo;
  final bool concluido;
}

List<EncomendaTimelinePasso> timelineCompactaEncomenda(
  Map<String, dynamic> data,
  Map<String, String> statusPedidos, {
  required String encomendaId,
}) {
  final st = (data['status_negociacao'] ?? '').toString();
  final cancelada = EncomendaNegociacaoStatus.encerradaDefinitivamente(st);
  final finalizada = encomendaFinalizada(
    data,
    statusPedidos,
    encomendaId: encomendaId,
  );

  bool passouNegociacao = st != EncomendaNegociacaoStatus.aguardandoNegociacao;
  bool passouEntrada = st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
      st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
      st == EncomendaNegociacaoStatus.emExecucaoLogistica ||
      finalizada;
  bool passouProducao = st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
      st == EncomendaNegociacaoStatus.emExecucaoLogistica ||
      finalizada;
  bool passouEntrega = st == EncomendaNegociacaoStatus.emExecucaoLogistica ||
      finalizada;

  if (cancelada) {
    return const [
      EncomendaTimelinePasso('Solicitação', true),
      EncomendaTimelinePasso('Negociação', true),
      EncomendaTimelinePasso('Encerrada', true),
    ];
  }

  return [
    const EncomendaTimelinePasso('Solicitação', true),
    EncomendaTimelinePasso('Negociação', passouNegociacao),
    EncomendaTimelinePasso('Entrada', passouEntrada),
    EncomendaTimelinePasso('Produção', passouProducao),
    EncomendaTimelinePasso('Entrega', passouEntrega),
    EncomendaTimelinePasso('Finalizada', finalizada),
  ];
}

String? produtoPrincipalNome(Map<String, dynamic> data) {
  final itens = data['itens'];
  if (itens is! List || itens.isEmpty) return null;
  final first = itens.first;
  if (first is! Map) return null;
  return (first['nome'] ?? '').toString().trim();
}

DateTime? timestampParaDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  return null;
}

/// Canceladas/encerradas ficam só na visão do cliente — lojista não vê na fila.
bool encomendaVisivelParaLojista(Map<String, dynamic> data) {
  final st = (data['status_negociacao'] ?? '').toString();
  return !EncomendaNegociacaoStatus.encerradaDefinitivamente(st);
}

List<QueryDocumentSnapshot<Map<String, dynamic>>>
    filtrarEncomendasVisiveisLojista(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.where((d) => encomendaVisivelParaLojista(d.data())).toList();
}

/// Filtros exibidos no painel web do lojista (sem «Canceladas»).
const filtrosEncomendaPainelLojista = [
  FiltroEncomendaRapido.todas,
  FiltroEncomendaRapido.novas,
  FiltroEncomendaRapido.emNegociacao,
  FiltroEncomendaRapido.aguardandoCliente,
  FiltroEncomendaRapido.entradaPaga,
  FiltroEncomendaRapido.producao,
  FiltroEncomendaRapido.finalizadas,
];

/// Indica se a loja precisa agir neste status (destaque na lista).
bool lojaPrecisaAgirEncomenda(String status) {
  return status == EncomendaNegociacaoStatus.aguardandoNegociacao ||
      status == EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta ||
      status == EncomendaNegociacaoStatus.entradaPagaEmProducao;
}

/// Texto relativo para listas compactas (ex.: «Atualizado há 5 minutos»).
String tempoRelativoAtualizacao(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 45) return 'Atualizado agora';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'Atualizado há $m ${m == 1 ? 'minuto' : 'minutos'}';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'Atualizado há $h ${h == 1 ? 'hora' : 'horas'}';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return 'Atualizado há $d ${d == 1 ? 'dia' : 'dias'}';
  }
  return 'Atualizado em ${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

Stream<Map<String, String>> streamStatusPedidosEncomenda({
  required String uidLoja,
  required Set<String> encomendaIds,
}) {
  if (encomendaIds.isEmpty) {
    return Stream<Map<String, String>>.value({});
  }
  return FirebaseFirestore.instance
      .collection('pedidos')
      .where('loja_id', isEqualTo: uidLoja)
      .where('tipo_compra', isEqualTo: 'encomenda')
      .snapshots()
      .map((snap) {
        final status = <String, String>{};
        for (final pedido in snap.docs) {
          final data = pedido.data();
          final encId = (data['encomenda_id'] ?? '').toString().trim();
          if (!encomendaIds.contains(encId)) continue;
          final st = (data['status'] ?? '').toString();
          status[pedido.id] = st;
          if (encId.isNotEmpty) {
            final atual = status['enc:$encId'];
            if (atual != _kPedidoEntregue) {
              status['enc:$encId'] = st;
            }
          }
        }
        return status;
      });
}
