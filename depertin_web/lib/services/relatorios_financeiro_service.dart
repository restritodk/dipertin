import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/cliente_assinatura_model.dart';
import '../models/cobranca_assinatura_model.dart';
import '../models/plano_assinatura_model.dart';
import 'assinaturas_clientes_service.dart';
import 'cobrancas_assinatura_service.dart';
import 'modulos_planos_service.dart';

// ─── Modelos de dados ───────────────────────────────────────────────────────

class RelatorioResumoFinanceiro {
  final double receitaTotal;
  final double receitaRecebida;
  final double receitaAReceber;
  final double receitaEmAtraso;
  final double receitaRecuperada;
  final double estornos;
  final double receitaTotalAnterior;
  final double receitaRecebidaAnterior;
  final double receitaAReceberAnterior;
  final double receitaEmAtrasoAnterior;
  final double receitaRecuperadaAnterior;
  final double estornosAnteriores;

  const RelatorioResumoFinanceiro({
    this.receitaTotal = 0,
    this.receitaRecebida = 0,
    this.receitaAReceber = 0,
    this.receitaEmAtraso = 0,
    this.receitaRecuperada = 0,
    this.estornos = 0,
    this.receitaTotalAnterior = 0,
    this.receitaRecebidaAnterior = 0,
    this.receitaAReceberAnterior = 0,
    this.receitaEmAtrasoAnterior = 0,
    this.receitaRecuperadaAnterior = 0,
    this.estornosAnteriores = 0,
  });
}

class RelatorioSituacaoAssinaturas {
  final int totalContratados;
  final int planosAtivos;
  final int emDia;
  final int venceHoje;
  final int aVencer7dias;
  final int vencidos;
  final int bloqueados;
  final int cancelados;

  const RelatorioSituacaoAssinaturas({
    this.totalContratados = 0,
    this.planosAtivos = 0,
    this.emDia = 0,
    this.venceHoje = 0,
    this.aVencer7dias = 0,
    this.vencidos = 0,
    this.bloqueados = 0,
    this.cancelados = 0,
  });
}

class RelatorioEvolucaoFinanceira {
  final String rotulo;
  final double receitaRecebida;
  final double receitaPrevista;
  final double receitaEmAtraso;

  const RelatorioEvolucaoFinanceira({
    required this.rotulo,
    this.receitaRecebida = 0,
    this.receitaPrevista = 0,
    this.receitaEmAtraso = 0,
  });
}

class RelatorioReceitaPorPlano {
  final String planoNome;
  final double valor;
  final int contratacoes;

  const RelatorioReceitaPorPlano({
    required this.planoNome,
    this.valor = 0,
    this.contratacoes = 0,
  });
}

class RelatorioCrescimentoAssinaturas {
  final String mes;
  final int novosContratos;
  final int renovacoes;
  final int cancelamentos;
  final int bloqueios;

  const RelatorioCrescimentoAssinaturas({
    required this.mes,
    this.novosContratos = 0,
    this.renovacoes = 0,
    this.cancelamentos = 0,
    this.bloqueios = 0,
  });
}

class RelatorioDetalheLinha {
  final ClienteAssinaturaModel cliente;
  final String planoNome;
  final double valorMensalidade;
  final String? proximoVencimento;
  final String? ultimoPagamento;
  final String situacao;
  final String formaPagamento;
  final String cidadeUf;
  final int tempoComoClienteDias;

  const RelatorioDetalheLinha({
    required this.cliente,
    required this.planoNome,
    this.valorMensalidade = 0,
    this.proximoVencimento,
    this.ultimoPagamento,
    required this.situacao,
    this.formaPagamento = '—',
    this.cidadeUf = '—',
    this.tempoComoClienteDias = 0,
  });
}

class RelatorioInsight {
  final String icone;
  final String texto;
  final String cor;

  const RelatorioInsight({
    required this.icone,
    required this.texto,
    this.cor = '#6A1B9A',
  });
}

class RelatorioFiltros {
  DateTime? dataInicio;
  DateTime? dataFim;
  String plano;
  String status;
  String formaPagamento;
  String cidade;
  String estado;

  RelatorioFiltros({
    this.dataInicio,
    this.dataFim,
    this.plano = '',
    this.status = '',
    this.formaPagamento = '',
    this.cidade = '',
    this.estado = '',
  });

  void limpar() {
    dataInicio = null;
    dataFim = null;
    plano = '';
    status = '';
    formaPagamento = '';
    cidade = '';
    estado = '';
  }

  bool get temFiltro =>
      dataInicio != null ||
      dataFim != null ||
      plano.isNotEmpty ||
      status.isNotEmpty ||
      formaPagamento.isNotEmpty ||
      cidade.isNotEmpty ||
      estado.isNotEmpty;

  RelatorioFiltros copy() => RelatorioFiltros(
        dataInicio: dataInicio,
        dataFim: dataFim,
        plano: plano,
        status: status,
        formaPagamento: formaPagamento,
        cidade: cidade,
        estado: estado,
      );
}

/// Período selecionável para os gráficos de evolução.
enum PeriodoEvolucao { dia, semana, mes, ano }

// ─── Service ─────────────────────────────────────────────────────────────────

abstract final class RelatoriosFinanceiroService {
  static final DateFormat _fmtMes = DateFormat('MMM/yy', 'pt_BR');

  /// Stream principal que emite todos os dados do relatório financeiro.
  static Stream<RelatorioDadosCompletos> streamRelatorio({
    RelatorioFiltros? filtros,
  }) {
    return Stream.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? clientesSnap;
      QuerySnapshot<Map<String, dynamic>>? cobrancasSnap;
      QuerySnapshot<Map<String, dynamic>>? planosSnap;

      void emitir() {
        if (clientesSnap == null ||
            cobrancasSnap == null ||
            planosSnap == null) {
          return;
        }

        try {
          final clientes = clientesSnap!.docs
              .map(ClienteAssinaturaModel.fromFirestore)
              .toList();
          final cobrancas = cobrancasSnap!.docs
              .map(CobrancaAssinatura.fromFirestore)
              .toList();
          final planos = planosSnap!.docs
              .map(PlanoAssinaturaModel.fromFirestore)
              .toList();

          // Aplicar filtros
          final f = filtros;
          final cobrancasFiltradas = cobrancas.where((c) {
            if (f == null) return true;
            if (f.plano.isNotEmpty &&
                !c.planoNome.toLowerCase().contains(f.plano.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();

          final clientesFiltrados = clientes.where((c) {
            if (f == null) return true;
            if (f.status.isNotEmpty && c.status != f.status) return false;
            if (f.formaPagamento.isNotEmpty &&
                !c.gateway.toLowerCase().contains(f.formaPagamento.toLowerCase())) {
              return false;
            }
            if (f.cidade.isNotEmpty &&
                !c.addressCity.toLowerCase().contains(f.cidade.toLowerCase())) {
              return false;
            }
            if (f.estado.isNotEmpty &&
                !c.addressState.toUpperCase().contains(f.estado.toUpperCase())) {
              return false;
            }
            return true;
          }).toList();

          final dados = RelatorioDadosCompletos(
            resumo: _calcularResumo(cobrancasFiltradas, cobrancas),
            situacao: _calcularSituacao(clientesFiltrados),
            receitaPorPlano: _calcularReceitaPorPlano(cobrancasFiltradas, planos),
            crescimento: _calcularCrescimento(clientesFiltrados),
            detalhes: _gerarDetalhes(clientesFiltrados, planos),
            insights: _gerarInsights(
              clientesFiltrados,
              cobrancasFiltradas,
              planos,
            ),
            cobrancas: cobrancasFiltradas,
          );
          controller.add(dados);
        } catch (e) {
          controller.addError(e);
        }
      }

      final subClientes = AssinaturasClientesService.stream().listen(
        (s) {
          clientesSnap = s;
          emitir();
        },
        onError: controller.addError,
      );
      final subCobrancas = FirebaseFirestore.instance
          .collection(CobrancasAssinaturaService.colecao)
          .snapshots()
          .listen(
            (s) {
              cobrancasSnap = s;
              emitir();
            },
            onError: controller.addError,
          );
      final subPlanos = ModulosPlanosService.stream().listen(
        (s) {
          planosSnap = s;
          emitir();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        subClientes.cancel();
        subCobrancas.cancel();
        subPlanos.cancel();
      };
    });
  }

  /// Resumo financeiro: receitas, atrasos, recuperados, estornos
  static RelatorioResumoFinanceiro _calcularResumo(
    List<CobrancaAssinatura> cobrancas,
    List<CobrancaAssinatura> todas,
  ) {
    final hoje = DateTime.now();
    final mesAtual = hoje.month;
    final anoAtual = hoje.year;
    final mesPassado = mesAtual == 1 ? 12 : mesAtual - 1;
    final anoPassado = mesAtual == 1 ? anoAtual - 1 : anoAtual;

    double receitaTotal = 0;
    double receitaRecebida = 0;
    double receitaAReceber = 0;
    double receitaEmAtraso = 0;
    double receitaRecuperada = 0;
    double estornos = 0;

    double receitaTotalAnterior = 0;
    double receitaRecebidaAnterior = 0;
    double receitaAReceberAnterior = 0;
    double receitaEmAtrasoAnterior = 0;
    double receitaRecuperadaAnterior = 0;
    double estornosAnteriores = 0;

    for (final c in cobrancas) {
      final venc = c.vencimento;
      final noMesAtual = venc.month == mesAtual && venc.year == anoAtual;
      final noMesPassado = venc.month == mesPassado && venc.year == anoPassado;
      final valor = c.valor;

      // Total geral (current period)
      if (noMesAtual) receitaTotal += valor;

      switch (c.status) {
        case StatusCobranca.paga:
          if (noMesAtual) {
            receitaRecebida += valor;
            // Verifica se é recuperação (pagamento de cobrança que venceu em período anterior)
            final diasAtraso = DateTime.now()
                .difference(DateTime(venc.year, venc.month, venc.day))
                .inDays;
            if (diasAtraso > 30) {
              receitaRecuperada += valor;
            }
          }
          if (noMesPassado) receitaRecebidaAnterior += valor;
          break;
        case StatusCobranca.emAberto:
          if (noMesAtual) receitaAReceber += valor;
          if (noMesPassado) receitaAReceberAnterior += valor;
          break;
        case StatusCobranca.vencida:
          if (noMesAtual) {
            receitaEmAtraso += valor;
            receitaAReceber += valor;
          }
          if (noMesPassado) {
            receitaEmAtrasoAnterior += valor;
            receitaAReceberAnterior += valor;
          }
          break;
        case StatusCobranca.reembolsada:
          if (noMesAtual) estornos += valor;
          if (noMesPassado) estornosAnteriores += valor;
          break;
        case StatusCobranca.cancelada:
          break;
      }
    }

    return RelatorioResumoFinanceiro(
      receitaTotal: receitaTotal,
      receitaRecebida: receitaRecebida,
      receitaAReceber: receitaAReceber,
      receitaEmAtraso: receitaEmAtraso,
      receitaRecuperada: receitaRecuperada,
      estornos: estornos,
      receitaTotalAnterior: receitaTotalAnterior,
      receitaRecebidaAnterior: receitaRecebidaAnterior,
      receitaAReceberAnterior: receitaAReceberAnterior,
      receitaEmAtrasoAnterior: receitaEmAtrasoAnterior,
      receitaRecuperadaAnterior: receitaRecuperadaAnterior,
      estornosAnteriores: estornosAnteriores,
    );
  }

  /// Situação das assinaturas
  static RelatorioSituacaoAssinaturas _calcularSituacao(
    List<ClienteAssinaturaModel> clientes,
  ) {
    int ativos = 0, emDia = 0, venceHoje = 0, aVencer7 = 0;
    int vencidos = 0, bloqueados = 0, cancelados = 0;

    final hoje = DateTime.now();
    final hojeNorm = DateTime(hoje.year, hoje.month, hoje.day);

    for (final c in clientes) {
      switch (c.status) {
        case 'ativo':
          ativos++;
          if (c.nextBillingDate != null) {
            final venc =
                c.nextBillingDate!.toDate();
            final diff = venc.difference(hojeNorm).inDays;
            if (diff == 0) {
              venceHoje++;
            } else if (diff > 0 && diff <= 7) {
              aVencer7++;
            } else if (diff > 7) {
              emDia++;
            } else {
              vencidos++;
            }
          } else {
            emDia++;
          }
          break;
        case 'em_atraso':
          vencidos++;
          break;
        case 'suspenso':
          bloqueados++;
          break;
        case 'cancelado':
          cancelados++;
          break;
        default:
          break;
      }
    }

    return RelatorioSituacaoAssinaturas(
      totalContratados: clientes.length,
      planosAtivos: ativos,
      emDia: emDia,
      venceHoje: venceHoje,
      aVencer7dias: aVencer7,
      vencidos: vencidos,
      bloqueados: bloqueados,
      cancelados: cancelados,
    );
  }

  /// Evolução financeira por período
  static List<RelatorioEvolucaoFinanceira> calcularEvolucao(
    List<CobrancaAssinatura> cobrancas,
    PeriodoEvolucao periodo,
  ) {
    final map = <String, List<double>>{}; // rotulo -> [recebido, previsto, atraso]
    final hoje = DateTime.now();

    for (final c in cobrancas) {
      final venc = c.vencimento;
      String rotulo;
      double previsto = 0, recebido = 0, atraso = 0;

      final valor = c.valor;

      switch (periodo) {
        case PeriodoEvolucao.dia:
          rotulo = DateFormat('dd/MM').format(venc);
          break;
        case PeriodoEvolucao.semana:
          // Agrupa por semana (ISO)
          final inicioSemana =
              venc.subtract(Duration(days: venc.weekday - 1));
          rotulo = 'Sem ${inicioSemana.day}/${inicioSemana.month}';
          break;
        case PeriodoEvolucao.mes:
          rotulo = _fmtMes.format(venc);
          break;
        case PeriodoEvolucao.ano:
          rotulo = '${venc.year}';
          break;
      }

      switch (c.status) {
        case StatusCobranca.paga:
          recebido = valor;
          break;
        case StatusCobranca.emAberto:
          previsto = valor;
          final diasAtraso =
              hoje.difference(DateTime(venc.year, venc.month, venc.day)).inDays;
          if (diasAtraso > 0) atraso = valor;
          break;
        case StatusCobranca.vencida:
          atraso = valor;
          break;
        default:
          break;
      }

      map.putIfAbsent(rotulo, () => [0, 0, 0]);
      map[rotulo]![0] += recebido;
      map[rotulo]![1] += previsto;
      map[rotulo]![2] += atraso;
    }

    // Últimos 12 períodos
    final chaves = map.keys.toList()..sort();
    final meses = chaves.take(12).toList();

    return meses
        .map((r) => RelatorioEvolucaoFinanceira(
              rotulo: r,
              receitaRecebida: map[r]![0],
              receitaPrevista: map[r]![1],
              receitaEmAtraso: map[r]![2],
            ))
        .toList();
  }

  /// Receita por plano
  static List<RelatorioReceitaPorPlano> _calcularReceitaPorPlano(
    List<CobrancaAssinatura> cobrancas,
    List<PlanoAssinaturaModel> planos,
  ) {
    final map = <String, double>{};
    final contratacoes = <String, int>{};

    // Conjunto de planos válidos (cadastrados em Planos e Módulos)
    final planosValidos = planos.map((p) => p.nome).toSet();

    // Apenas cobranças cujo plano ainda existe cadastrado
    for (final c in cobrancas) {
      if (c.status == StatusCobranca.paga && planosValidos.contains(c.planoNome)) {
        map[c.planoNome] = (map[c.planoNome] ?? 0) + c.valor;
        contratacoes[c.planoNome] = (contratacoes[c.planoNome] ?? 0) + 1;
      }
    }

    // Garante que todos os planos apareçam (mesmo sem cobranças)
    for (final p in planos) {
      map.putIfAbsent(p.nome, () => 0);
      contratacoes.putIfAbsent(p.nome, () => 0);
    }

    return map.entries
        .map((e) => RelatorioReceitaPorPlano(
              planoNome: e.key,
              valor: e.value,
              contratacoes: contratacoes[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
  }

  /// Crescimento de assinaturas por mês
  static List<RelatorioCrescimentoAssinaturas> _calcularCrescimento(
    List<ClienteAssinaturaModel> clientes,
  ) {
    final map = <String, List<int>>{}; // mes -> [novos, renovacoes, cancelados, bloqueios]

    for (final c in clientes) {
      String mes;
      if (c.createdAt != null) {
        mes = _fmtMes.format(c.createdAt!.toDate());
      } else {
        continue;
      }

      map.putIfAbsent(mes, () => [0, 0, 0, 0]);

      // Novo contrato
      if (c.status == 'ativo' || c.status == 'em_atraso') {
        map[mes]![0] += 1;
      }
      // Cancelado
      if (c.status == 'cancelado') {
        map[mes]![2] += 1;
      }
      // Bloqueado/suspenso
      if (c.status == 'suspenso') {
        map[mes]![3] += 1;
      }
    }

    final ordenado = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ordenado
        .map((e) => RelatorioCrescimentoAssinaturas(
              mes: e.key,
              novosContratos: e.value[0],
              renovacoes: e.value[1],
              cancelamentos: e.value[2],
              bloqueios: e.value[3],
            ))
        .toList()
        .take(12)
        .toList();
  }

  /// Detalhes das assinaturas
  static List<RelatorioDetalheLinha> _gerarDetalhes(
    List<ClienteAssinaturaModel> clientes,
    List<PlanoAssinaturaModel> planos,
  ) {
    final planoMap = {for (final p in planos) p.id: p.nome};

    return clientes.map((c) {
      final planoNome = planoMap[c.planId] ?? c.planName;
      final hoje = DateTime.now();

      String situacao;
      switch (c.status) {
        case 'ativo':
          if (c.nextBillingDate != null) {
            final venc = c.nextBillingDate!.toDate();
            final diff = venc.difference(DateTime(hoje.year, hoje.month, hoje.day)).inDays;
            if (diff == 0) {
              situacao = 'Vence hoje';
            } else if (diff > 0 && diff <= 7) {
              situacao = 'A vencer';
            } else if (diff < 0) {
              if (c.emTolerancia) {
                situacao = 'Em dia';
              } else {
                situacao = 'Em atraso';
              }
            } else {
              situacao = 'Em dia';
            }
          } else {
            situacao = 'Em dia';
          }
          break;
        case 'em_atraso':
          situacao = 'Em atraso';
          break;
        case 'suspenso':
          situacao = 'Bloqueado';
          break;
        case 'cancelado':
          situacao = 'Cancelado';
          break;
        default:
          situacao = c.status;
      }

      final tempoDias = c.createdAt != null
          ? hoje.difference(c.createdAt!.toDate()).inDays
          : 0;

      return RelatorioDetalheLinha(
        cliente: c,
        planoNome: planoNome,
        valorMensalidade: c.monthlyAmount,
        proximoVencimento: c.nextBillingDateExibir,
        ultimoPagamento: c.lastPaymentDateExibir,
        situacao: situacao,
        formaPagamento: c.gateway,
        cidadeUf: c.addressCity.isNotEmpty
            ? '${c.addressCity}${c.addressState.isNotEmpty ? '/${c.addressState}' : ''}'
            : '—',
        tempoComoClienteDias: tempoDias,
      );
    }).toList()
      ..sort((a, b) => b.tempoComoClienteDias.compareTo(a.tempoComoClienteDias));
  }

  /// Insights financeiros gerados dinamicamente
  static List<RelatorioInsight> _gerarInsights(
    List<ClienteAssinaturaModel> clientes,
    List<CobrancaAssinatura> cobrancas,
    List<PlanoAssinaturaModel> planos,
  ) {
    final insights = <RelatorioInsight>[];
    final hoje = DateTime.now();

    // 1. Planos que vencem nos próximos 5 dias
    final vencendoEmbreve = clientes.where((c) {
      if (c.nextBillingDate == null) return false;
      final venc = c.nextBillingDate!.toDate();
      final diff = venc.difference(hoje).inDays;
      return diff >= 0 && diff <= 5;
    }).length;
    if (vencendoEmbreve > 0) {
      insights.add(RelatorioInsight(
        icone: 'calendar_today',
        texto: '$vencendoEmbreve ${vencendoEmbreve == 1 ? 'plano vence' : 'planos vencem'} nos próximos 5 dias.',
        cor: '#FF8F00',
      ));
    }

    // 2. Inadimplência
    final inadimplentes = clientes.where((c) =>
        c.status == 'em_atraso' || c.status == 'suspenso').length;
    if (inadimplentes > 0 && clientes.length > 0) {
      final perc = (inadimplentes / clientes.length * 100).round();
      insights.add(RelatorioInsight(
        icone: 'trending_up',
        texto: 'Inadimplência atinge $perc% das assinaturas ($inadimplentes ${inadimplentes == 1 ? 'lojista' : 'lojistas'}).',
        cor: '#F04438',
      ));
    }

    // 3. Plano que mais representa receita
    if (cobrancas.isNotEmpty) {
      final receitaPorPlano = <String, double>{};
      for (final c in cobrancas) {
        if (c.status == StatusCobranca.paga) {
          receitaPorPlano[c.planoNome] =
              (receitaPorPlano[c.planoNome] ?? 0) + c.valor;
        }
      }
      if (receitaPorPlano.isNotEmpty) {
        final top = receitaPorPlano.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final total = receitaPorPlano.values.fold(0.0, (a, b) => a + b);
        if (total > 0) {
          final perc = (top.first.value / total * 100).round();
          insights.add(RelatorioInsight(
            icone: 'pie_chart',
            texto: 'Plano "${top.first.key}" representa $perc% da receita.',
            cor: '#6A1B9A',
          ));
        }
      }
    }

    // 4. Taxa de retenção
    if (clientes.length > 0) {
      final ativos = clientes.where((c) =>
              c.status == 'ativo' || c.status == 'em_atraso')
          .length;
      final taxa = (ativos / clientes.length * 100).round();
      insights.add(RelatorioInsight(
        icone: 'verified',
        texto: 'Taxa de retenção: $taxa% das assinaturas ativas.',
        cor: '#16A34A',
      ));
    }

    // 5. Recuperação financeira
    final mesAtual = hoje.month;
    final anoAtual = hoje.year;
    double recuperado = 0;
    for (final c in cobrancas) {
      final venc = c.vencimento;
      if (c.status == StatusCobranca.paga &&
          venc.month == mesAtual &&
          venc.year == anoAtual) {
        recuperado += c.valor;
      }
    }
    if (recuperado > 0) {
      final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      insights.add(RelatorioInsight(
        icone: 'savings',
        texto: 'Foram recuperados ${fmt.format(recuperado)} este mês.',
        cor: '#16A34A',
      ));
    }

    // 6. Total de lojistas
    if (clientes.isNotEmpty) {
      insights.add(RelatorioInsight(
        icone: 'store',
        texto: '${clientes.length} ${clientes.length == 1 ? 'lojista contratou' : 'lojistas contrataram'} planos de assinatura.',
        cor: '#6A1B9A',
      ));
    }

    return insights;
  }
}

/// Container completo dos dados do relatório.
class RelatorioDadosCompletos {
  final RelatorioResumoFinanceiro resumo;
  final RelatorioSituacaoAssinaturas situacao;
  final List<RelatorioReceitaPorPlano> receitaPorPlano;
  final List<RelatorioCrescimentoAssinaturas> crescimento;
  final List<RelatorioDetalheLinha> detalhes;
  final List<RelatorioInsight> insights;
  final List<CobrancaAssinatura> cobrancas;

  const RelatorioDadosCompletos({
    this.resumo = const RelatorioResumoFinanceiro(),
    this.situacao = const RelatorioSituacaoAssinaturas(),
    this.receitaPorPlano = const [],
    this.crescimento = const [],
    this.detalhes = const [],
    this.insights = const [],
    this.cobrancas = const [],
  });

  static const vazio = RelatorioDadosCompletos();
}
