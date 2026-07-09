import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/cliente_assinatura_model.dart';
import '../models/cobranca_assinatura_model.dart';
import 'assinaturas_clientes_service.dart';
import 'cobrancas_assinatura_service.dart';

// ─── Modelo de dados para inadimplência ─────────────────────────────────────

/// Item da listagem de inadimplência (cobrança + dados do cliente).
class InadimplenciaItem {
  final String cobrancaId;
  final CobrancaAssinatura cobranca;
  final ClienteAssinaturaModel? cliente;

  InadimplenciaItem({
    required this.cobrancaId,
    required this.cobranca,
    this.cliente,
  });

  /// Dias em atraso (data atual - vencimento)
  int get diasEmAtraso {
    final hoje = DateTime.now();
    final venc = cobranca.vencimento;
    final vencNorm = DateTime(venc.year, venc.month, venc.day);
    final hojeNorm = DateTime(hoje.year, hoje.month, hoje.day);
    return hojeNorm.difference(vencNorm).inDays;
  }

  /// Nível de risco calculado
  RiscoInadimplencia get risco {
    final dias = diasEmAtraso;
    final enviadas = _totalEnvios;
    if (dias > 60 || enviadas > 8) return RiscoInadimplencia.critico;
    if (dias > 30 || enviadas > 5) return RiscoInadimplencia.alto;
    if (dias > 10 || enviadas > 3) return RiscoInadimplencia.medio;
    return RiscoInadimplencia.baixo;
  }

  int get _totalEnvios {
    if (cliente == null) return 0;
    return cliente!.historico
        .where((h) => h.tipo == 'envio' || h.tipo == 'cobranca')
        .length;
  }

  /// Status de exibição
  String get statusExibicao {
    if (cobranca.status == StatusCobranca.paga) return 'Paga';
    if (cobranca.status == StatusCobranca.cancelada) return 'Cancelada';
    if (cobranca.status == StatusCobranca.reembolsada) return 'Reembolsada';
    final dias = diasEmAtraso;
    if (dias <= 0) return 'Em aberto';
    if (dias <= 5) return 'Em atraso';
    if (dias <= 15) return 'Pagamento prometido';
    if (dias <= 30) return 'Negociado';
    if (cliente?.status == 'suspenso') return 'Suspenso';
    return 'Em atraso';
  }
}

enum RiscoInadimplencia { baixo, medio, alto, critico }

/// KPI agrupado para os cards do dashboard.
class InadimplenciaKpis {
  final double valorEmAtraso;
  final double valorEmAtrasoMesAnterior;
  final int clientesInadimplentes;
  final int clientesInadimplentesSemanaAnterior;
  final int vencemHojeQtd;
  final double vencemHojeValor;
  final int acima30DiasQtd;
  final double acima30DiasValor;
  final double recuperadoEsteMes;
  final double recuperadoMesAnterior;

  InadimplenciaKpis({
    required this.valorEmAtraso,
    required this.valorEmAtrasoMesAnterior,
    required this.clientesInadimplentes,
    required this.clientesInadimplentesSemanaAnterior,
    required this.vencemHojeQtd,
    required this.vencemHojeValor,
    required this.acima30DiasQtd,
    required this.acima30DiasValor,
    required this.recuperadoEsteMes,
    required this.recuperadoMesAnterior,
  });

  double get variacaoValorPercentual {
    if (valorEmAtrasoMesAnterior <= 0) return 0;
    return ((valorEmAtraso - valorEmAtrasoMesAnterior) /
            valorEmAtrasoMesAnterior) *
        100;
  }

  double get variacaoClientesPercentual {
    if (clientesInadimplentesSemanaAnterior <= 0) return 0;
    return ((clientesInadimplentes - clientesInadimplentesSemanaAnterior) /
            clientesInadimplentesSemanaAnterior) *
        100;
  }

  double get variacaoRecuperadoPercentual {
    if (recuperadoMesAnterior <= 0) return 0;
    return ((recuperadoEsteMes - recuperadoMesAnterior) /
            recuperadoMesAnterior) *
        100;
  }
}

/// Ponto do gráfico (um mês).
class InadimplenciaMes {
  final String rotulo;
  final double cobrado;
  final double pago;
  final double emAtraso;

  InadimplenciaMes({
    required this.rotulo,
    required this.cobrado,
    required this.pago,
    required this.emAtraso,
  });
}

// ─── Service ────────────────────────────────────────────────────────────────

/// Serviço que agrega dados em tempo real de inadimplência.
abstract final class InadimplenciaService {
  static final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  /// Stream principal que combina cobranças + clientes.
  /// Apenas cobranças do módulo Gestão Comercial.
  /// Inclui cobranças pagas (necessárias para KPI "Recuperado este mês").
  static Stream<List<InadimplenciaItem>> streamInadimplencia() {
    return Stream.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? cobrancasSnap;
      QuerySnapshot<Map<String, dynamic>>? clientesSnap;

      void emitir() {
        if (cobrancasSnap == null || clientesSnap == null) return;
        final clientesMap = <String, ClienteAssinaturaModel>{};
        for (final doc in clientesSnap!.docs) {
          final c = ClienteAssinaturaModel.fromFirestore(doc);
          final key = c.storeId.isNotEmpty ? c.storeId : doc.id;
          if (!clientesMap.containsKey(key)) {
            clientesMap[key] = c;
          }
        }

        final itens = <InadimplenciaItem>[];
        for (final doc in cobrancasSnap!.docs) {
          final cob = CobrancaAssinatura.fromFirestore(doc);

          // FILTRO PRINCIPAL: apenas Gestão Comercial
          if (cob.modulo != ModuloCobranca.gestaoComercial) continue;

          // Tenta encontrar o cliente por assinatura_id, email ou nome
          ClienteAssinaturaModel? cliente;
          final assId = cob.assinaturaId;
          if (clientesMap.containsKey(assId)) {
            cliente = clientesMap[assId];
          } else {
            ClienteAssinaturaModel? encontrado;
            for (final c in clientesMap.values) {
              if (c.email == cob.clienteEmail) {
                encontrado = c;
                break;
              }
            }
            if (encontrado == null) {
              for (final c in clientesMap.values) {
                if (c.storeName == cob.clienteNome) {
                  encontrado = c;
                  break;
                }
              }
            }
            if (encontrado == null && clientesMap.values.isNotEmpty) {
              encontrado = clientesMap.values.first;
            }
            cliente = encontrado;
          }

          itens.add(InadimplenciaItem(
            cobrancaId: doc.id,
            cobranca: cob,
            cliente: cliente,
          ));
        }
        controller.add(itens);
      }

      final subCob = FirebaseFirestore.instance
          .collection(CobrancasAssinaturaService.colecao)
          .snapshots()
          .listen(
            (s) {
              cobrancasSnap = s;
              emitir();
            },
            onError: controller.addError,
          );

      final subCli = FirebaseFirestore.instance
          .collection(AssinaturasClientesService.colecao)
          .snapshots()
          .listen(
            (s) {
              clientesSnap = s;
              emitir();
            },
            onError: controller.addError,
          );

      controller.onCancel = () {
        subCob.cancel();
        subCli.cancel();
      };
    });
  }

  /// KPIs calculados a partir da lista de itens.
  static InadimplenciaKpis calcularKpis(List<InadimplenciaItem> itens) {
    final hoje = DateTime.now();
    final hojeNorm = DateTime(hoje.year, hoje.month, hoje.day);
    final mesAtual = hoje.month;
    final anoAtual = hoje.year;

    double valorEmAtraso = 0;
    int clientesInadimplentes = 0;
    int vencemHojeQtd = 0;
    double vencemHojeValor = 0;
    int acima30DiasQtd = 0;
    double acima30DiasValor = 0;
    double recuperadoEsteMes = 0;
    double recuperadoMesAnterior = 0;
    final storeIds = <String>{};

    for (final item in itens) {
      final dias = item.diasEmAtraso;
      final valor = item.cobranca.valor;
      final venc = item.cobranca.vencimento;
      final vencNorm = DateTime(venc.year, venc.month, venc.day);

      final naoPaga =
          item.cobranca.status != StatusCobranca.paga &&
          item.cobranca.status != StatusCobranca.reembolsada;

      if (dias > 0 && naoPaga) {
        valorEmAtraso += valor;
        if (item.cliente != null) storeIds.add(item.cliente!.storeId);
      }

      if (vencNorm == hojeNorm && naoPaga) {
        vencemHojeQtd++;
        vencemHojeValor += valor;
      }

      if (dias > 30 && naoPaga) {
        acima30DiasQtd++;
        acima30DiasValor += valor;
      }

      // Cobranças pagas neste mês são "recuperadas"
      if (item.cobranca.status == StatusCobranca.paga &&
          venc.month == mesAtual &&
          venc.year == anoAtual) {
        recuperadoEsteMes += valor;
      }

      if (item.cobranca.status == StatusCobranca.paga) {
        final mesPassado = mesAtual == 1 ? 12 : mesAtual - 1;
        final anoPassado = mesAtual == 1 ? anoAtual - 1 : anoAtual;
        if (venc.month == mesPassado && venc.year == anoPassado) {
          recuperadoMesAnterior += valor;
        }
      }
    }

    clientesInadimplentes = storeIds.length;

    return InadimplenciaKpis(
      valorEmAtraso: valorEmAtraso,
      valorEmAtrasoMesAnterior: 0,
      clientesInadimplentes: clientesInadimplentes,
      clientesInadimplentesSemanaAnterior: 0,
      vencemHojeQtd: vencemHojeQtd,
      vencemHojeValor: vencemHojeValor,
      acima30DiasQtd: acima30DiasQtd,
      acima30DiasValor: acima30DiasValor,
      recuperadoEsteMes: recuperadoEsteMes,
      recuperadoMesAnterior: recuperadoMesAnterior,
    );
  }

  /// Dados para o gráfico dos últimos 12 meses.
  static List<InadimplenciaMes> calcularEvolucao(List<InadimplenciaItem> itens) {
    final meses = <InadimplenciaMes>[];
    final hoje = DateTime.now();
    const rotulos = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
    ];

    for (var i = 11; i >= 0; i--) {
      final mes = hoje.month - i;
      final ano = hoje.year + (mes <= 0 ? -1 : 0) + (mes > 12 ? 1 : 0);
      final mesNorm = ((mes - 1) % 12) + 1;
      final mesIdx = mesNorm - 1;

      double cobrado = 0;
      double pago = 0;
      double emAtraso = 0;

      for (final item in itens) {
        final venc = item.cobranca.vencimento;
        if (venc.month == mesNorm && venc.year == ano) {
          cobrado += item.cobranca.valor;
          if (item.cobranca.status == StatusCobranca.paga) {
            pago += item.cobranca.valor;
          } else if (item.diasEmAtraso > 0) {
            emAtraso += item.cobranca.valor;
          }
        }
      }

      meses.add(InadimplenciaMes(
        rotulo: rotulos[mesIdx],
        cobrado: cobrado,
        pago: pago,
        emAtraso: emAtraso,
      ));
    }

    return meses;
  }

  static String fmtMoeda(double v) => _moeda.format(v);
}
