import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cliente_assinatura_model.dart';
import '../models/nota_fiscal_model.dart';
import 'assinatura_gestao_comercial_service.dart';

/// Dados agregados da tela Fiscal.
class FiscalDashboardResumo {
  const FiscalDashboardResumo({
    required this.clientesAtivos,
    required this.nfeEnviadasMes,
    required this.nfePendentes,
    required this.nfeComErro,
    required this.totalEnviadoMes,
  });

  final int clientesAtivos;
  final int nfeEnviadasMes;
  final int nfePendentes;
  final int nfeComErro;
  final double totalEnviadoMes;
}

/// Service da tela Fiscal — consumo de `assinaturas_clientes` e `notas_fiscais`.
abstract final class FiscalService {
  static const String _colecaoClientes = 'assinaturas_clientes';
  static const String _colecaoNotas = 'notas_fiscais';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream de clientes cujo plano é detectado como Gestão Comercial,
  /// usando a lógica já estabelecida em [AssinaturaGestaoComercialService].
  static Stream<List<ClienteAssinaturaModel>> streamClientesGestaoComercial() {
    return Stream.multi((controller) async {
      // 1. Carrega o contexto uma vez (planos + módulos)
      AssinaturaGestaoComercialContexto ctx;
      try {
        ctx = await AssinaturaGestaoComercialService.carregarContexto();
      } catch (e) {
        controller.addError(e);
        return;
      }

      // 2. Escuta mudanças nos clientes e filtra com o contexto carregado
      final sub = _db.collection(_colecaoClientes).snapshots().listen(
        (snap) {
          final todos =
              snap.docs.map(ClienteAssinaturaModel.fromFirestore).toList();
          final filtrados =
              AssinaturaGestaoComercialService.filtrarAssinaturasGestao(
                  todos, ctx);
          controller.add(filtrados);
        },
        onError: controller.addError,
      );

      controller.onCancel = sub.cancel;
    });
  }

  /// Stream de todas as notas fiscais.
  static Stream<List<NotaFiscalModel>> streamNotasFiscais() {
    return _db
        .collection(_colecaoNotas)
        .orderBy('data_emissao', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(NotaFiscalModel.fromFirestore).toList());
  }

  /// Stream do resumo do dashboard fiscal.
  static Stream<FiscalDashboardResumo> streamResumo() {
    return Stream.multi((controller) {
      List<ClienteAssinaturaModel>? clientes;
      List<NotaFiscalModel>? notas;

      void emitir() {
        if (clientes == null || notas == null) return;
        final agora = DateTime.now();
        final mesAtual = DateTime(agora.year, agora.month, 1);

        controller.add(FiscalDashboardResumo(
          clientesAtivos:
              clientes!.where((c) => c.contaComoClienteAtivoKpi).length,
          nfeEnviadasMes: notas!
              .where((n) =>
                  n.situacao == SituacaoNfe.enviada &&
                  n.dataEnvio != null &&
                  n.dataEnvio!.toDate().isAfter(mesAtual))
              .length,
          nfePendentes:
              notas!.where((n) => n.situacao == SituacaoNfe.pendente).length,
          nfeComErro:
              notas!.where((n) => n.situacao == SituacaoNfe.erro).length,
          totalEnviadoMes: notas!
              .where((n) =>
                  n.situacao == SituacaoNfe.enviada &&
                  n.dataEnvio != null &&
                  n.dataEnvio!.toDate().isAfter(mesAtual))
              .fold<double>(0, (t, n) => t + n.valor),
        ));
      }

      final subClientes = streamClientesGestaoComercial().listen(
        (lista) {
          clientes = lista;
          emitir();
        },
        onError: controller.addError,
      );

      final subNotas = streamNotasFiscais().listen(
        (lista) {
          notas = lista;
          emitir();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        subClientes.cancel();
        subNotas.cancel();
      };
    });
  }

  /// Salva uma nota fiscal na coleção legada `notas_fiscais`.
  ///
  /// Usado para manter compatibilidade com a tela Fiscal que consome
  /// esta coleção. O `FiscalEmissaoService` também salva em `fiscal_documents`.
  static Future<void> salvarNota(NotaFiscalModel nota) async {
    await _db.collection(_colecaoNotas).add(nota.toMap());
  }
}
