import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/venda_historico_model.dart';
import 'package:depertin_web/services/comercial_recebimentos_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// =============================================================================
// DATA MODELS LOCAIS (apenas para esta tela)
// =============================================================================

class _RankingItem {
  final String nome;
  final int quantidade;
  final double valor;
  const _RankingItem(this.nome, this.quantidade, this.valor);
}

class _ResumoFinanceiro {
  final double recebido;
  final double pendente;
  final double cancelado;
  final double estornado;
  final double totalVendas;
  const _ResumoFinanceiro({
    this.recebido = 0,
    this.pendente = 0,
    this.cancelado = 0,
    this.estornado = 0,
    this.totalVendas = 0,
  });
}

class _Kpis {
  final double faturamentoMes;
  final double totalRecebido;
  final double emAberto;
  final double ticketMedio;
  final int qtdVendas;
  final int clientesAtivos;
  final double faturamentoMesAnterior;
  final double totalRecebidoAnterior;
  final double emAbertoAnterior;
  final double ticketMedioAnterior;
  final double qtdVendasAnterior;
  final double clientesAtivosAnterior;
  const _Kpis({
    this.faturamentoMes = 0,
    this.totalRecebido = 0,
    this.emAberto = 0,
    this.ticketMedio = 0,
    this.qtdVendas = 0,
    this.clientesAtivos = 0,
    this.faturamentoMesAnterior = 0,
    this.totalRecebidoAnterior = 0,
    this.emAbertoAnterior = 0,
    this.ticketMedioAnterior = 0,
    this.qtdVendasAnterior = 0,
    this.clientesAtivosAnterior = 0,
  });

  double get variacaoFaturamento =>
      faturamentoMesAnterior > 0
          ? ((faturamentoMes - faturamentoMesAnterior) /
                  faturamentoMesAnterior *
                  100)
          : faturamentoMes > 0 ? 100 : 0;
  double get variacaoRecebido =>
      totalRecebidoAnterior > 0
          ? ((totalRecebido - totalRecebidoAnterior) /
                  totalRecebidoAnterior *
                  100)
          : totalRecebido > 0 ? 100 : 0;
  double get variacaoAberto =>
      emAbertoAnterior > 0
          ? ((emAberto - emAbertoAnterior) / emAbertoAnterior * 100)
          : emAberto > 0 ? 100 : 0;
  double get variacaoTicket =>
      ticketMedioAnterior > 0
          ? ((ticketMedio - ticketMedioAnterior) /
                  ticketMedioAnterior *
                  100)
          : ticketMedio > 0 ? 100 : 0;
  double get variacaoQtd =>
      qtdVendasAnterior > 0
          ? ((qtdVendas - qtdVendasAnterior) /
                  qtdVendasAnterior *
                  100)
          : qtdVendas > 0 ? 100 : 0;
  double get variacaoClientes =>
      clientesAtivosAnterior > 0
          ? ((clientesAtivos - clientesAtivosAnterior) /
                  clientesAtivosAnterior *
                  100)
          : clientesAtivos > 0 ? 100 : 0;
}

// =============================================================================
// TELA PRINCIPAL
// =============================================================================

class ComercialRelatorioScreen extends StatefulWidget {
  const ComercialRelatorioScreen({super.key});

  @override
  State<ComercialRelatorioScreen> createState() =>
      _ComercialRelatorioScreenState();
}

class _ComercialRelatorioScreenState
    extends State<ComercialRelatorioScreen> {
  // Data
  List<VendaHistorico> _vendas = [];
  List<VendaHistorico> _vendasFiltradas = [];
  _Kpis _kpis = const _Kpis();
  _ResumoFinanceiro _resumoFinanceiro = const _ResumoFinanceiro();
  List<_RankingItem> _topProdutos = [];
  List<_RankingItem> _topClientes = [];
  List<_RankingItem> _topOperadores = [];
  Map<DateTime, double> _evolucaoDiaria = {};
  Map<String, double> _formasPagamento = {};

  // Meta mensal
  double _metaMensal = 20000;

  // Filters
  String _filtroPeriodo = 'Últimos 30 dias';
  String _filtroCliente = '';
  String _filtroOperador = '';
  String _filtroForma = 'Todas';
  String _filtroStatus = 'Todos';
  Timer? _debounceTimer;
  bool _carregando = true;
  bool _erro = false;
  String _lojaId = '';

  // Paginação da tabela
  int _paginaTabela = 1;
  int _itensPorPagina = 10;

  final _clienteCtrl = TextEditingController();
  final _operadorCtrl = TextEditingController();

  final _moedaFmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _dfDia = DateFormat('dd/MM');
  final _dfCompleto = DateFormat('dd/MM/yyyy');

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _clienteCtrl.dispose();
    _operadorCtrl.dispose();
    super.dispose();
  }

  void _agendarDebounce(VoidCallback fn) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), fn);
  }

  Future<void> _carregarDados(String uidLoja) async {
    if (uidLoja.isEmpty) return;
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final agora = DateTime.now();
      final inicioMes = DateTime(agora.year, agora.month, 1);
      final fimMes = DateTime(agora.year, agora.month + 1, 1)
          .subtract(const Duration(days: 1));
      final inicioMesAnterior = DateTime(agora.year, agora.month - 1, 1);
      final fimMesAnterior =
          DateTime(agora.year, agora.month, 1).subtract(const Duration(days: 1));

      final vendasSnap = await FirebaseFirestore.instance
          .collection('gestao_comercial_vendas')
          .where('loja_id', isEqualTo: uidLoja)
          .orderBy('data_venda', descending: true)
          .get();

      final recebimentosSnap = await FirebaseFirestore.instance
          .collection('gestao_comercial_recebimentos')
          .where('loja_id', isEqualTo: uidLoja)
          .orderBy('data_recebimento', descending: true)
          .get();

      final vendas = vendasSnap.docs
          .map((d) => VendaHistorico.fromDoc(d.id, d.data()))
          .toList();

      final recebimentos = recebimentosSnap.docs
          .map((d) => ComercialRecebimento.fromDoc(d.id, d.data()))
          .toList();

      if (!mounted) return;

      final vendasMes = vendas.where((v) {
        final d = v.dataVenda;
        return d != null && !d.isBefore(inicioMes) && !d.isAfter(fimMes);
      }).toList();

      final vendasMesAnterior = vendas.where((v) {
        final d = v.dataVenda;
        return d != null &&
            !d.isBefore(inicioMesAnterior) &&
            !d.isAfter(fimMesAnterior);
      }).toList();

      final recebimentosMes = recebimentos.where((r) {
        final d = r.dataRecebimento;
        return !d.isBefore(inicioMes) && !d.isAfter(fimMes);
      }).toList();

      final recebimentosMesAnterior = recebimentos.where((r) {
        final d = r.dataRecebimento;
        return !d.isBefore(inicioMesAnterior) && !d.isAfter(fimMesAnterior);
      }).toList();

      final faturamentoMes =
          vendasMes.fold(0.0, (s, v) => s + v.valorTotal);
      final faturamentoMesAnteriorVal =
          vendasMesAnterior.fold(0.0, (s, v) => s + v.valorTotal);

      final totalRecebido =
          recebimentosMes.fold(0.0, (s, r) => s + r.valorRecebido);
      final totalRecebidoAnterior =
          recebimentosMesAnterior.fold(0.0, (s, r) => s + r.valorRecebido);

      final emAberto = vendasMes
          .where((v) => v.status == 'pendente' || v.status == 'parcial')
          .fold(0.0, (s, v) => s + v.valorPendente);
      final emAbertoAnterior = vendasMesAnterior
          .where((v) => v.status == 'pendente' || v.status == 'parcial')
          .fold(0.0, (s, v) => s + v.valorPendente);

      final qtdVendasMes = vendasMes.length;
      final qtdVendasAnteriorVal = vendasMesAnterior.length;
      final ticket = qtdVendasMes > 0 ? faturamentoMes / qtdVendasMes : 0.0;
      final ticketAnterior = qtdVendasAnteriorVal > 0
          ? faturamentoMesAnteriorVal / qtdVendasAnteriorVal
          : 0.0;

      final clientesSet = vendasMes
          .where((v) => v.clienteNome != null && v.clienteNome!.isNotEmpty)
          .map((v) => v.clienteNome!)
          .toSet();
      final clientesSetAnterior = vendasMesAnterior
          .where((v) => v.clienteNome != null && v.clienteNome!.isNotEmpty)
          .map((v) => v.clienteNome!)
          .toSet();

      final recebido = recebimentos
          .where((r) => r.status == 'confirmado')
          .fold(0.0, (s, r) => s + r.valorRecebido);
      final pendente = vendas
          .where((v) => v.status == 'pendente' || v.status == 'parcial')
          .fold(0.0, (s, v) => s + v.valorPendente);
      final cancelado = vendas
          .where((v) => v.status == 'cancelado')
          .fold(0.0, (s, v) => s + v.valorTotal);
      final estornado = recebimentos
          .where((r) => r.status == 'estornado')
          .fold(0.0, (s, r) => s + r.valorRecebido);
      final totalVendas = vendas.fold(0.0, (s, v) => s + v.valorTotal);

      // Evolução diária (últimos 30 dias)
      final evolucao = <DateTime, double>{};
      final ultimos30 = DateTime.now().subtract(const Duration(days: 30));
      for (final v in vendas) {
        final d = v.dataVenda;
        if (d != null && !d.isBefore(ultimos30)) {
          final dia = DateTime(d.year, d.month, d.day);
          evolucao[dia] = (evolucao[dia] ?? 0) + v.valorTotal;
        }
      }

      // Formas de pagamento
      final formas = <String, double>{};
      for (final r in recebimentos) {
        if (r.status == 'confirmado') {
          formas[r.formaPagamento] =
              (formas[r.formaPagamento] ?? 0) + r.valorRecebido;
        }
      }

      // Top produtos
      final prodAgg = <String, _RankingAcc>{};
      for (final v in vendas) {
        for (final item in v.itens) {
          prodAgg.putIfAbsent(item.produtoNome, () => _RankingAcc());
          prodAgg[item.produtoNome]!.qtd += item.quantidade;
          prodAgg[item.produtoNome]!.valor += item.total;
        }
      }
      final topProdutos = prodAgg.entries
          .map((e) => _RankingItem(e.key, e.value.qtd, e.value.valor))
          .toList()
        ..sort((a, b) => b.valor.compareTo(a.valor));
      final top5Prod = topProdutos.take(5).toList();

      // Top clientes
      final cliAgg = <String, _RankingAcc>{};
      for (final v in vendas) {
        final nome = v.clienteNome ?? '—';
        cliAgg.putIfAbsent(nome, () => _RankingAcc());
        cliAgg[nome]!.qtd += 1;
        cliAgg[nome]!.valor += v.valorTotal;
      }
      final topClientes = cliAgg.entries
          .map((e) => _RankingItem(e.key, e.value.qtd, e.value.valor))
          .toList()
        ..sort((a, b) => b.valor.compareTo(a.valor));
      final top5Cli = topClientes.take(5).toList();

      // Top operadores
      final opAgg = <String, _RankingAcc>{};
      for (final v in vendas) {
        if (v.operadorNome != null && v.operadorNome!.isNotEmpty) {
          opAgg.putIfAbsent(v.operadorNome!, () => _RankingAcc());
          opAgg[v.operadorNome!]!.qtd += 1;
          opAgg[v.operadorNome!]!.valor += v.valorTotal;
        }
      }
      final topOperadores = opAgg.entries
          .map((e) => _RankingItem(e.key, e.value.qtd, e.value.valor))
          .toList()
        ..sort((a, b) => b.valor.compareTo(a.valor));
      final top5Op = topOperadores.take(5).toList();

      setState(() {
        _vendas = vendas;
        _kpis = _Kpis(
          faturamentoMes: faturamentoMes,
          totalRecebido: totalRecebido,
          emAberto: emAberto,
          ticketMedio: ticket,
          qtdVendas: qtdVendasMes,
          clientesAtivos: clientesSet.length,
          faturamentoMesAnterior: faturamentoMesAnteriorVal,
          totalRecebidoAnterior: totalRecebidoAnterior,
          emAbertoAnterior: emAbertoAnterior,
          ticketMedioAnterior: ticketAnterior,
          qtdVendasAnterior: qtdVendasAnteriorVal.toDouble(),
          clientesAtivosAnterior: clientesSetAnterior.length.toDouble(),
        );
        _resumoFinanceiro = _ResumoFinanceiro(
          recebido: recebido,
          pendente: pendente,
          cancelado: cancelado,
          estornado: estornado,
          totalVendas: totalVendas,
        );
        _evolucaoDiaria = evolucao;
        _formasPagamento = formas;
        _topProdutos = top5Prod;
        _topClientes = top5Cli;
        _topOperadores = top5Op;
        _vendasFiltradas = vendas;
        _carregando = false;
        _paginaTabela = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = true;
        _carregando = false;
      });
    }
  }

  void _aplicarFiltros() {
    var filtradas = _vendas;
    if (_filtroCliente.isNotEmpty) {
      filtradas = filtradas
          .where((v) => (v.clienteNome ?? '')
              .toLowerCase()
              .contains(_filtroCliente.toLowerCase()))
          .toList();
    }
    if (_filtroOperador.isNotEmpty) {
      filtradas = filtradas
          .where((v) => (v.operadorNome ?? '')
              .toLowerCase()
              .contains(_filtroOperador.toLowerCase()))
          .toList();
    }
    if (_filtroForma != 'Todas') {
      filtradas = filtradas
          .where((v) =>
              v.formaPagamentoExibicao == _filtroForma ||
              v.formaPagamento == _filtroForma)
          .toList();
    }
    if (_filtroStatus != 'Todos') {
      filtradas = filtradas
          .where((v) => v.statusExibicao == _filtroStatus)
          .toList();
    }
    final agora = DateTime.now();
    DateTime dataLimite;
    switch (_filtroPeriodo) {
      case 'Últimos 7 dias':
        dataLimite = agora.subtract(const Duration(days: 7));
        break;
      case 'Últimos 15 dias':
        dataLimite = agora.subtract(const Duration(days: 15));
        break;
      case 'Últimos 60 dias':
        dataLimite = agora.subtract(const Duration(days: 60));
        break;
      case 'Últimos 90 dias':
        dataLimite = agora.subtract(const Duration(days: 90));
        break;
      case 'Este ano':
        dataLimite = DateTime(agora.year, 1, 1);
        break;
      default:
        dataLimite = agora.subtract(const Duration(days: 30));
    }
    filtradas = filtradas
        .where((v) {
          final d = v.dataVenda;
          return d != null && !d.isBefore(dataLimite);
        })
        .toList();

    setState(() {
      _vendasFiltradas = filtradas;
      _paginaTabela = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (uidLoja.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }
        if (_lojaId != uidLoja) {
          _lojaId = uidLoja;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _carregarDados(uidLoja);
          });
        }
        return _RelatorioBody(
          carregando: _carregando,
          erro: _erro,
          kpis: _kpis,
          resumoFinanceiro: _resumoFinanceiro,
          topProdutos: _topProdutos,
          topClientes: _topClientes,
          topOperadores: _topOperadores,
          evolucaoDiaria: _evolucaoDiaria,
          formasPagamento: _formasPagamento,
          vendasFiltradas: _vendasFiltradas,
          metaMensal: _metaMensal,
          filtroPeriodo: _filtroPeriodo,
          filtroCliente: _filtroCliente,
          filtroOperador: _filtroOperador,
          filtroForma: _filtroForma,
          filtroStatus: _filtroStatus,
          paginaTabela: _paginaTabela,
          itensPorPagina: _itensPorPagina,
          clienteCtrl: _clienteCtrl,
          operadorCtrl: _operadorCtrl,
          moedaFmt: _moedaFmt,
          dfDia: _dfDia,
          dfCompleto: _dfCompleto,
          onRefresh: () => _carregarDados(uidLoja),
          onFiltroPeriodoChanged: (v) {
            setState(() => _filtroPeriodo = v ?? 'Últimos 30 dias');
            _aplicarFiltros();
          },
          onFiltroClienteChanged: (v) {
            _filtroCliente = v;
            _agendarDebounce(_aplicarFiltros);
          },
          onFiltroOperadorChanged: (v) {
            _filtroOperador = v;
            _agendarDebounce(_aplicarFiltros);
          },
          onFiltroFormaChanged: (v) {
            setState(() => _filtroForma = v ?? 'Todas');
            _aplicarFiltros();
          },
          onFiltroStatusChanged: (v) {
            setState(() => _filtroStatus = v ?? 'Todos');
            _aplicarFiltros();
          },
          onLimparFiltros: () {
            setState(() {
              _filtroCliente = '';
              _filtroOperador = '';
              _filtroForma = 'Todas';
              _filtroStatus = 'Todos';
              _filtroPeriodo = 'Últimos 30 dias';
              _clienteCtrl.clear();
              _operadorCtrl.clear();
              _vendasFiltradas = _vendas;
              _paginaTabela = 1;
            });
          },
          onPageChanged: (v) => setState(() => _paginaTabela = v),
          onItensPorPaginaChanged: (v) => setState(() {
            _itensPorPagina = v;
            _paginaTabela = 1;
          }),
          onEditarMeta: _mostrarEditarMeta,
        );
      },
    );
  }

  void _mostrarEditarMeta() {
    final ctrl = TextEditingController(
        text: _moedaFmt.format(_metaMensal).replaceAll('R\$', '').trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Editar meta mensal'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Valor da meta',
              prefixText: 'R\$ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text
                  .replaceAll(RegExp(r'[^\d,.]'), '')
                  .replaceAll(',', '.'));
              if (v != null && v > 0) {
                setState(() => _metaMensal = v);
                Navigator.pop(ctx);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.roxo,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// AGGREGATION HELPER
// =============================================================================

class _RankingAcc {
  int qtd = 0;
  double valor = 0;
}

// =============================================================================
// CONSTANTES DE ESTILO
// =============================================================================

const _cardPadding = 24.0;
const _cardBorderRadius = 16.0;
const _cardElevationColor = Color(0xFF1A1A2E);
const _cardTitleSize = 18.0;

const _kpiTitleColor = Color(0xFF6B7280);
const _kpiValueColor = Color(0xFF1A1A2E);
const _rankingCardHeight = 340.0;

// =============================================================================
// BODY
// =============================================================================

class _RelatorioBody extends StatelessWidget {
  const _RelatorioBody({
    required this.carregando,
    required this.erro,
    required this.kpis,
    required this.resumoFinanceiro,
    required this.topProdutos,
    required this.topClientes,
    required this.topOperadores,
    required this.evolucaoDiaria,
    required this.formasPagamento,
    required this.vendasFiltradas,
    required this.metaMensal,
    required this.filtroPeriodo,
    required this.filtroCliente,
    required this.filtroOperador,
    required this.filtroForma,
    required this.filtroStatus,
    required this.paginaTabela,
    required this.itensPorPagina,
    required this.clienteCtrl,
    required this.operadorCtrl,
    required this.moedaFmt,
    required this.dfDia,
    required this.dfCompleto,
    required this.onRefresh,
    required this.onFiltroPeriodoChanged,
    required this.onFiltroClienteChanged,
    required this.onFiltroOperadorChanged,
    required this.onFiltroFormaChanged,
    required this.onFiltroStatusChanged,
    required this.onLimparFiltros,
    required this.onPageChanged,
    required this.onItensPorPaginaChanged,
    required this.onEditarMeta,
  });

  final bool carregando, erro;
  final _Kpis kpis;
  final _ResumoFinanceiro resumoFinanceiro;
  final List<_RankingItem> topProdutos, topClientes, topOperadores;
  final Map<DateTime, double> evolucaoDiaria;
  final Map<String, double> formasPagamento;
  final List<VendaHistorico> vendasFiltradas;
  final double metaMensal;
  final String filtroPeriodo, filtroCliente, filtroOperador,
      filtroForma, filtroStatus;
  final int paginaTabela, itensPorPagina;
  final TextEditingController clienteCtrl, operadorCtrl;
  final NumberFormat moedaFmt;
  final DateFormat dfDia;
  final DateFormat dfCompleto;
  final VoidCallback onRefresh;
  final ValueChanged<String?> onFiltroPeriodoChanged;
  final ValueChanged<String> onFiltroClienteChanged;
  final ValueChanged<String> onFiltroOperadorChanged;
  final ValueChanged<String?> onFiltroFormaChanged;
  final ValueChanged<String?> onFiltroStatusChanged;
  final VoidCallback onLimparFiltros;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onItensPorPaginaChanged;
  final VoidCallback onEditarMeta;

  static const _periodos = [
    'Últimos 7 dias',
    'Últimos 15 dias',
    'Últimos 30 dias',
    'Últimos 60 dias',
    'Últimos 90 dias',
    'Este ano',
  ];

  static const _formas = [
    'Todas',
    'PIX',
    'Dinheiro',
    'Cartão',
    'Crédito do Cliente',
    'Transferência',
  ];

  static const _statusList = [
    'Todos',
    'Pago',
    'Pendente',
    'Parcial',
    'Cancelado',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              if (carregando) _buildSkeleton(),
              if (erro) _buildErro(),
              if (!carregando && !erro) ...[
                _buildSummaryGrid(),
                const SizedBox(height: 24),
                _buildFilterCard(),
                const SizedBox(height: 24),
                _buildAnalyticsRow(),
                const SizedBox(height: 24),
                _buildRankingsRow(),
                const SizedBox(height: 24),
                _buildTabelaSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ──
  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Relatório Comercial',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tenha uma visão completa do desempenho do seu negócio.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Atualizar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: PainelAdminTheme.roxo,
            side: const BorderSide(color: PainelAdminTheme.roxo),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(60),
        child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text('Erro ao carregar relatório',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.roxo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 6 SUMMARY CARDS ──
  Widget _buildSummaryGrid() {
    final cards = [
      _buildKpiCard(
        icone: Icons.trending_up_rounded,
        corIcone: PainelAdminTheme.roxo,
        corFundo: const Color(0xFFF1E9FF),
        titulo: 'Faturamento do mês',
        valor: moedaFmt.format(kpis.faturamentoMes),
        variacao: kpis.variacaoFaturamento,
      ),
      _buildKpiCard(
        icone: Icons.account_balance_wallet_rounded,
        corIcone: const Color(0xFF16A34A),
        corFundo: const Color(0xFFE8F5E9),
        titulo: 'Total recebido',
        valor: moedaFmt.format(kpis.totalRecebido),
        variacao: kpis.variacaoRecebido,
      ),
      _buildKpiCard(
        icone: Icons.warning_amber_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundo: const Color(0xFFFFF8E1),
        titulo: 'Em aberto',
        valor: moedaFmt.format(kpis.emAberto),
        variacao: kpis.variacaoAberto,
      ),
      _buildKpiCard(
        icone: Icons.receipt_long_rounded,
        corIcone: const Color(0xFF3B82F6),
        corFundo: const Color(0xFFEFF6FF),
        titulo: 'Ticket médio',
        valor: moedaFmt.format(kpis.ticketMedio),
        variacao: kpis.variacaoTicket,
      ),
      _buildKpiCard(
        icone: Icons.shopping_cart_rounded,
        corIcone: PainelAdminTheme.roxo,
        corFundo: const Color(0xFFF1E9FF),
        titulo: 'Quantidade de vendas',
        valor: '${kpis.qtdVendas}',
        variacao: kpis.variacaoQtd,
      ),
      _buildKpiCard(
        icone: Icons.people_alt_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundo: const Color(0xFFFFF8E1),
        titulo: 'Clientes ativos',
        valor: '${kpis.clientesAtivos}',
        variacao: kpis.variacaoClientes,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 1200
            ? 6
            : constraints.maxWidth > 900
                ? 3
                : constraints.maxWidth > 600
                    ? 2
                    : 1;
        final gaps = 12.0 * (cols - 1);
        final cardWidth = (constraints.maxWidth - gaps) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required IconData icone,
    required Color corIcone,
    required Color corFundo,
    required String titulo,
    required String valor,
    required double variacao,
  }) {
    final isUp = variacao >= 0;
    return _CardHover(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEAF6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: corFundo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icone, color: corIcone, size: 22),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUp
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: isUp
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${variacao.toStringAsFixed(1)}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isUp
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(titulo,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kpiTitleColor)),
            const SizedBox(height: 4),
            Text(valor,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kpiValueColor)),
            const SizedBox(height: 2),
            Text('vs mês anterior',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, color: const Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  // ── FILTER CARD ──
  Widget _buildFilterCard() {
    return _CardBase(
      titulo: 'Filtros',
      iconeTitulo: Icons.filter_list_rounded,
      trailing: TextButton.icon(
        onPressed: onLimparFiltros,
        icon: const Icon(Icons.clear_all_rounded, size: 16),
        label: const Text('Limpar filtros'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF64748B),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLargo = constraints.maxWidth > 900;
          if (isLargo) {
            return Row(
              children: [
                _filtroDropdown(
                  label: 'Período',
                  value: filtroPeriodo,
                  items: _periodos,
                  onChanged: onFiltroPeriodoChanged,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: clienteCtrl,
                    onChanged: onFiltroClienteChanged,
                    decoration: _inputDec(
                        hint: 'Cliente', icon: Icons.person_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: operadorCtrl,
                    onChanged: onFiltroOperadorChanged,
                    decoration: _inputDec(
                        hint: 'Operador', icon: Icons.engineering_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                _filtroDropdown(
                  label: 'Forma de pagamento',
                  value: filtroForma,
                  items: _formas,
                  onChanged: onFiltroFormaChanged,
                ),
                const SizedBox(width: 12),
                _filtroDropdown(
                  label: 'Status',
                  value: filtroStatus,
                  items: _statusList,
                  onChanged: onFiltroStatusChanged,
                ),
              ],
            );
          }
          return Column(
            children: [
              _filtroDropdown(
                label: 'Período',
                value: filtroPeriodo,
                items: _periodos,
                onChanged: onFiltroPeriodoChanged,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: clienteCtrl,
                onChanged: onFiltroClienteChanged,
                decoration: _inputDec(
                    hint: 'Cliente', icon: Icons.person_rounded),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: operadorCtrl,
                onChanged: onFiltroOperadorChanged,
                decoration: _inputDec(
                    hint: 'Operador', icon: Icons.engineering_rounded),
              ),
              const SizedBox(height: 8),
              _filtroDropdown(
                label: 'Forma de pagamento',
                value: filtroForma,
                items: _formas,
                onChanged: onFiltroFormaChanged,
              ),
              const SizedBox(height: 8),
              _filtroDropdown(
                label: 'Status',
                value: filtroStatus,
                items: _statusList,
                onChanged: onFiltroStatusChanged,
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDec({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: const Color(0xFFF8F9FB),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _filtroDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8F9FB),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        items: items
            .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ── ANALYTICS ROW ──
  Widget _buildAnalyticsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 1100) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _buildLineChartCard(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: _buildDonutChartCard(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _buildResumoFinanceiroCard(),
                    const SizedBox(height: 24),
                    _buildMetaCard(),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildLineChartCard(),
            const SizedBox(height: 24),
            _buildDonutChartCard(),
            const SizedBox(height: 24),
            _buildResumoFinanceiroCard(),
            const SizedBox(height: 24),
            _buildMetaCard(),
          ],
        );
      },
    );
  }

  // ── LINE CHART ──
  Widget _buildLineChartCard() {
    final sortedDays = evolucaoDiaria.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = sortedDays.isEmpty
        ? 1000.0
        : sortedDays.map((e) => e.value).reduce(max);

    return _CardBase(
      titulo: 'Evolução das vendas',
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              filtroPeriodo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: const Color(0xFF94A3B8)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: sortedDays.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.show_chart_rounded,
                            size: 40, color: const Color(0xFFCBD5E1)),
                        const SizedBox(height: 8),
                        Text('Nenhum dado no período',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8))),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(
                        right: 16, top: 8, bottom: 4, left: 4),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: const Color(0xFFF1F5F9),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 56,
                              getTitlesWidget: (val, meta) {
                                if (val == 0) return const SizedBox();
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    'R\$ ${(val / 1000).toStringAsFixed(0)}k',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        color: const Color(0xFF94A3B8)),
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: sortedDays.length > 1,
                              reservedSize: 28,
                              interval: max(1, (sortedDays.length / 6).ceil())
                                  .toDouble(),
                              getTitlesWidget: (val, meta) {
                                final idx = val.toInt();
                                if (idx < 0 || idx >= sortedDays.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    dfDia.format(sortedDays[idx].key),
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 9,
                                        color: const Color(0xFF94A3B8)),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: sortedDays.length == 1
                            ? const LineTouchData(enabled: false)
                            : LineTouchData(
                                enabled: true,
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (touchedSpots) {
                                    return touchedSpots.map((spot) {
                                      return LineTooltipItem(
                                        moedaFmt.format(spot.y),
                                        const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: sortedDays.isEmpty
                                ? [FlSpot(0, 0)]
                                : sortedDays.length == 1
                                    ? [
                                        FlSpot(-0.5, sortedDays.first.value),
                                        FlSpot(0.5, sortedDays.first.value),
                                      ]
                                    : sortedDays.asMap().entries.map((e) =>
                                        FlSpot(e.key.toDouble(), e.value.value)).toList(),
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: PainelAdminTheme.roxo,
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: sortedDays.length <= 15,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 3.5,
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                  strokeColor: PainelAdminTheme.roxo,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                        minY: 0,
                        maxY: maxVal * 1.25,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── DONUT CHART ──
  Widget _buildDonutChartCard() {
    final totalFormas = formasPagamento.values.fold(0.0, (s, v) => s + v);
    final colors = [
      const Color(0xFF16A34A),
      PainelAdminTheme.roxo,
      const Color(0xFFFF8F00),
      const Color(0xFF3B82F6),
      const Color(0xFF64748B),
      const Color(0xFFEF4444),
    ];

    return _CardBase(
      titulo: 'Formas de pagamento',
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: totalFormas > 0
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 45,
                          sections: formasPagamento.entries.toList().asMap().entries
                              .map((e) => PieChartSectionData(
                                    value: e.value.value,
                                    color: colors[e.key % colors.length],
                                    radius: 30,
                                    showTitle: false,
                                  ))
                              .toList(),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Total',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: const Color(0xFF64748B))),
                          Text(moedaFmt.format(totalFormas),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: PainelAdminTheme.roxo)),
                        ],
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pie_chart_outline_rounded,
                            size: 36, color: const Color(0xFFCBD5E1)),
                        const SizedBox(height: 6),
                        Text('Nenhum recebimento',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13, color: const Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (totalFormas > 0)
            ...formasPagamento.entries.toList().asMap().entries.map((e) {
              final pct =
                  totalFormas > 0 ? (e.value.value / totalFormas * 100) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[e.key % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.value.key,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: const Color(0xFF4B5563))),
                    ),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── RESUMO FINANCEIRO ──
  Widget _buildResumoFinanceiroCard() {
    return _CardBase(
      titulo: 'Resumo Financeiro',
      child: Column(
        children: [
          _resumoLinha('Recebido',
              moedaFmt.format(resumoFinanceiro.recebido), const Color(0xFF16A34A)),
          const Divider(height: 20),
          _resumoLinha('Pendente',
              moedaFmt.format(resumoFinanceiro.pendente), const Color(0xFFFF8F00)),
          const Divider(height: 20),
          _resumoLinha('Cancelado',
              moedaFmt.format(resumoFinanceiro.cancelado), const Color(0xFFDC2626)),
          const Divider(height: 20),
          _resumoLinha('Estornado',
              moedaFmt.format(resumoFinanceiro.estornado), const Color(0xFF64748B)),
          const Divider(height: 20),
          _resumoLinha('Total vendas',
              moedaFmt.format(resumoFinanceiro.totalVendas),
              PainelAdminTheme.roxo,
              bold: true),
        ],
      ),
    );
  }

  Widget _resumoLinha(String label, String valor, Color cor,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4B5563))),
        Text(valor,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: cor)),
      ],
    );
  }

  // ── META MENSAL ──
  Widget _buildMetaCard() {
    final pct = metaMensal > 0
        ? (resumoFinanceiro.recebido / metaMensal * 100).clamp(0, 100)
        : 0.0;
    final atingido = pct >= 100;
    final corProgresso =
        atingido ? const Color(0xFF16A34A) : PainelAdminTheme.roxo;

    return _CardBase(
      titulo: 'Meta mensal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _linhaMeta('Meta', moedaFmt.format(metaMensal)),
          const SizedBox(height: 6),
          _linhaMeta('Vendido', moedaFmt.format(resumoFinanceiro.recebido)),
          const SizedBox(height: 6),
          _linhaMeta(
            '% Atingido',
            '${pct.toStringAsFixed(1)}%',
            cor: corProgresso,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: const Color(0xFFF1E9FF),
              valueColor: AlwaysStoppedAnimation<Color>(corProgresso),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 150,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: onEditarMeta,
                icon:
                    const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Editar meta',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  side: const BorderSide(
                      color: PainelAdminTheme.roxo),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaMeta(String label, String valor, {Color? cor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280))),
        Text(valor,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cor ?? const Color(0xFF1F2937))),
      ],
    );
  }

  // ── RANKINGS ROW ──
  Widget _buildRankingsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 1100) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildRankingCard(
                  'Produtos mais vendidos',
                  topProdutos,
                  col1Label: 'Produto',
                  col2Label: 'Qtd',
                  col3Label: 'Valor',
                  getCol1: (item) => item.nome,
                  getCol2: (item) => '${item.quantidade}',
                  getCol3: (item) => moedaFmt.format(item.valor),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildRankingCard(
                  'Clientes que mais compraram',
                  topClientes,
                  col1Label: 'Cliente',
                  col2Label: 'Compras',
                  col3Label: 'Valor',
                  getCol1: (item) => item.nome,
                  getCol2: (item) => '${item.quantidade}',
                  getCol3: (item) => moedaFmt.format(item.valor),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildRankingCard(
                  'Operadores que mais venderam',
                  topOperadores,
                  col1Label: 'Operador',
                  col2Label: 'Vendas',
                  col3Label: 'Valor vendido',
                  getCol1: (item) => item.nome,
                  getCol2: (item) => '${item.quantidade}',
                  getCol3: (item) => moedaFmt.format(item.valor),
                ),
              ),
            ],
          );
        }
        if (constraints.maxWidth > 600) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildRankingCard(
                      'Produtos mais vendidos',
                      topProdutos,
                      col1Label: 'Produto',
                      col2Label: 'Qtd',
                      col3Label: 'Valor',
                      getCol1: (item) => item.nome,
                      getCol2: (item) => '${item.quantidade}',
                      getCol3: (item) => moedaFmt.format(item.valor),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildRankingCard(
                      'Clientes que mais compraram',
                      topClientes,
                      col1Label: 'Cliente',
                      col2Label: 'Compras',
                      col3Label: 'Valor',
                      getCol1: (item) => item.nome,
                      getCol2: (item) => '${item.quantidade}',
                      getCol3: (item) => moedaFmt.format(item.valor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildRankingCard(
                'Operadores que mais venderam',
                topOperadores,
                col1Label: 'Operador',
                col2Label: 'Vendas',
                col3Label: 'Valor vendido',
                getCol1: (item) => item.nome,
                getCol2: (item) => '${item.quantidade}',
                getCol3: (item) => moedaFmt.format(item.valor),
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildRankingCard('Produtos mais vendidos', topProdutos,
                col1Label: 'Produto', col2Label: 'Qtd', col3Label: 'Valor',
                getCol1: (item) => item.nome,
                getCol2: (item) => '${item.quantidade}',
                getCol3: (item) => moedaFmt.format(item.valor)),
            const SizedBox(height: 24),
            _buildRankingCard('Clientes que mais compraram', topClientes,
                col1Label: 'Cliente', col2Label: 'Compras', col3Label: 'Valor',
                getCol1: (item) => item.nome,
                getCol2: (item) => '${item.quantidade}',
                getCol3: (item) => moedaFmt.format(item.valor)),
            const SizedBox(height: 24),
            _buildRankingCard('Operadores que mais venderam', topOperadores,
                col1Label: 'Operador', col2Label: 'Vendas', col3Label: 'Valor vendido',
                getCol1: (item) => item.nome,
                getCol2: (item) => '${item.quantidade}',
                getCol3: (item) => moedaFmt.format(item.valor)),
          ],
        );
      },
    );
  }

  // ── BUILD RANKING CARD ──
  Widget _buildRankingCard(
    String titulo,
    List<_RankingItem> items, {
    required String col1Label,
    required String col2Label,
    required String col3Label,
    required String Function(_RankingItem) getCol1,
    required String Function(_RankingItem) getCol2,
    required String Function(_RankingItem) getCol3,
  }) {
    return SizedBox(
      height: _rankingCardHeight,
      child: _CardBase(
      titulo: titulo,
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const SizedBox(width: 22),
              Expanded(
                flex: 3,
                child: Text(col1Label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9CA3AF))),
              ),
              SizedBox(
                width: 44,
                child: Text(col2Label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9CA3AF))),
              ),
              SizedBox(
                width: 90,
                child: Text(col3Label,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9CA3AF))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 5 linhas: preenchidas ou vazias
          ...List.generate(5, (i) {
            if (i < items.length) {
              final item = items[i];
              final rank = i + 1;
              return _rankingLinha(
                rank: rank,
                col1: getCol1(item),
                col2: getCol2(item),
                col3: getCol3(item),
              );
            }
            return _rankingLinhaVazia();
          }),
        ],
      ),
    ),
    );
  }

  Widget _rankingLinha({
    required int rank,
    required String col1,
    required String col2,
    required String col3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank°',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: rank <= 3
                        ? PainelAdminTheme.roxo
                        : const Color(0xFFCBD5E1))),
          ),
          Expanded(
            flex: 3,
            child: Text(col1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1F2937))),
          ),
          SizedBox(
            width: 44,
            child: Text(col2,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F2937))),
          ),
          SizedBox(
            width: 90,
            child: Text(col3,
                textAlign: TextAlign.end,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937))),
          ),
        ],
      ),
    );
  }

  Widget _rankingLinhaVazia() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 22,
              child: Text('—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFE5E7EB)))),
          Expanded(
            flex: 3,
            child: Text('—',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFFE5E7EB))),
          ),
          SizedBox(
            width: 44,
            child: Text('—',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Color(0xFFE5E7EB))),
          ),
          SizedBox(
            width: 90,
            child: Text('—',
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 12, color: Color(0xFFE5E7EB))),
          ),
        ],
      ),
    );
  }

  // ── TABLE ──
  Widget _buildTabelaSection() {
    final inicio = (paginaTabela - 1) * itensPorPagina;
    final paginados = vendasFiltradas
        .skip(inicio)
        .take(itensPorPagina)
        .toList();

    return _CardBase(
      titulo: 'Vendas detalhadas',
      child: Column(
        children: [
          if (vendasFiltradas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 40, color: const Color(0xFFCBD5E1)),
                    const SizedBox(height: 12),
                    Text('Nenhuma venda encontrada',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8))),
                  ],
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final colWidths = _calcularColWidths(constraints.maxWidth);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 52,
                    headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFFAFAFC)),
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    headingTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                    dataTextStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF1A1A2E),
                    ),
                    columns: [
                      _col('Código', colWidths[0]),
                      _col('Cliente', colWidths[1]),
                      _col('Data', colWidths[2]),
                      _col('Produtos', colWidths[3]),
                      _col('Qtd', colWidths[4]),
                      _col('Forma pag.', colWidths[5]),
                      _col('Valor bruto', colWidths[6]),
                      _col('Desconto', colWidths[7]),
                      _col('Juros', colWidths[8]),
                      _col('Valor líquido', colWidths[9]),
                      _col('Status', colWidths[10]),
                      _col('Operador', colWidths[11]),
                      _col('Ações', colWidths[12]),
                    ],
                    rows: paginados.map((v) {
                      return DataRow(
                        color: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered)) {
                            return const Color(0xFFF8F9FD);
                          }
                          return null;
                        }),
                        cells: [
                          DataCell(Text(v.codigoExibicao,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 11))),
                          DataCell(Container(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              v.clienteNome ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          )),
                          DataCell(Text(
                              v.dataVenda != null
                                  ? dfCompleto.format(v.dataVenda!)
                                  : '—',
                              style: const TextStyle(fontSize: 11))),
                          DataCell(Text(
                              '${v.quantidadeItens} ${v.quantidadeItens == 1 ? 'item' : 'itens'}',
                              style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${v.quantidadeItens}',
                              style: const TextStyle(fontSize: 11))),
                          DataCell(Text(v.formaPagamentoExibicao,
                              style: const TextStyle(fontSize: 11))),
                          DataCell(Text(moedaFmt.format(v.valorTotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 11))),
                          DataCell(Text(
                              v.descontoTotal > 0
                                  ? moedaFmt.format(v.descontoTotal)
                                  : '—',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: v.descontoTotal > 0
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFCBD5E1)))),
                          DataCell(Text(
                              v.jurosTotal > 0
                                  ? moedaFmt.format(v.jurosTotal)
                                  : '—',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: v.jurosTotal > 0
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFCBD5E1)))),
                          DataCell(Text(moedaFmt.format(v.valorPago),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: v.valorPago > 0
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF64748B)))),
                          DataCell(_buildStatusBadge(v)),
                          DataCell(Container(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              v.operadorNome ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          )),
                          DataCell(_buildActionsMenu(v)),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            if (vendasFiltradas.length > itensPorPagina) _buildPagination(),
          ],
        ],
      ),
    );
  }

  List<double> _calcularColWidths(double totalWidth) {
    const widths = [
      100.0, 150.0, 95.0, 90.0, 45.0, 100.0, 95.0, 75.0, 65.0, 100.0,
      85.0, 110.0, 50.0,
    ];
    final sum = widths.fold(0.0, (s, w) => s + w);
    if (totalWidth > sum) {
      final extra = (totalWidth - sum) / widths.length;
      return widths.map((w) => w + extra).toList();
    }
    return widths;
  }

  DataColumn _col(String label, double width) {
    return DataColumn(
      label: SizedBox(
        width: width,
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildStatusBadge(VendaHistorico v) {
    Color bg;
    Color fg;
    switch (v.status) {
      case 'pago':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF16A34A);
        break;
      case 'pendente':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFFFF8F00);
        break;
      case 'parcial':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        break;
      case 'cancelado':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        v.statusExibicao,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildActionsMenu(VendaHistorico v) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded,
          size: 16, color: Color(0xFF94A3B8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      onSelected: (action) {},
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'detalhes',
          child: ListTile(
            leading: Icon(Icons.visibility_outlined,
                size: 18, color: PainelAdminTheme.roxo),
            title: Text('Ver detalhes', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'imprimir',
          child: ListTile(
            leading: Icon(Icons.print_outlined, size: 18),
            title: Text('Imprimir venda', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'recebimentos',
          child: ListTile(
            leading: Icon(Icons.payments_outlined, size: 18),
            title: Text('Ver recebimentos', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (v.status != 'cancelado') const PopupMenuDivider(),
        if (v.status != 'cancelado')
          const PopupMenuItem(
            value: 'cancelar',
            child: ListTile(
              leading: Icon(Icons.cancel_outlined,
                  size: 18, color: Color(0xFFDC2626)),
              title: Text('Cancelar venda', style: TextStyle(fontSize: 13)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Widget _buildPagination() {
    final total = vendasFiltradas.length;
    final totalPag = (total / itensPorPagina).ceil();
    final inicio = (paginaTabela - 1) * itensPorPagina + 1;
    final fim = (paginaTabela * itensPorPagina).clamp(0, total);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Row(
        children: [
          Text(
            'Mostrando $inicio a $fim de $total venda${total == 1 ? '' : 's'}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _pagBtn(Icons.chevron_left_rounded,
                  paginaTabela > 1 ? () => onPageChanged(paginaTabela - 1) : null),
              Text('$paginaTabela de $totalPag',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              _pagBtn(Icons.chevron_right_rounded,
                  paginaTabela < totalPag ? () => onPageChanged(paginaTabela + 1) : null),
            ],
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              Text('Itens por página:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: const Color(0xFF94A3B8))),
              const SizedBox(width: 6),
              SizedBox(
                width: 60,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: itensPorPagina,
                      isDense: true,
                      icon: const Icon(Icons.expand_more_rounded, size: 14),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      items: [5, 10, 15, 20, 50]
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) onItensPorPaginaChanged(v);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pagBtn(IconData icon, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon,
                size: 16,
                color: onTap != null
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CARD BASE (padrão para todos os cards)
// =============================================================================

class _CardBase extends StatelessWidget {
  const _CardBase({
    required this.titulo,
    this.iconeTitulo,
    this.trailing,
    required this.child,
  });

  final String titulo;
  final IconData? iconeTitulo;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _CardHover(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_cardPadding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardBorderRadius),
          border: Border.all(color: const Color(0xFFEEEAF6)),
          boxShadow: [
            BoxShadow(
              color: _cardElevationColor.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailing != null)
              Row(
                children: [
                  if (iconeTitulo != null) ...[
                    Icon(iconeTitulo, size: 18, color: PainelAdminTheme.roxo),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(titulo,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: _cardTitleSize,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E))),
                  ),
                  trailing!,
                ],
              )
            else ...[
              if (iconeTitulo != null)
                Row(
                  children: [
                    Icon(iconeTitulo, size: 18, color: PainelAdminTheme.roxo),
                    const SizedBox(width: 8),
                    Text(titulo,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: _cardTitleSize,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E))),
                  ],
                )
              else
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: _cardTitleSize,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E))),
            ],
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CARD HOVER
// =============================================================================

class _CardHover extends StatefulWidget {
  const _CardHover({required this.child});
  final Widget child;

  @override
  State<_CardHover> createState() => _CardHoverState();
}

class _CardHoverState extends State<_CardHover>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _anim;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) {
          _hovering = true;
          _animCtrl.forward();
        }
      },
      onExit: (_) {
        if (_hovering) {
          _hovering = false;
          _animCtrl.reverse();
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, -_anim.value * 2),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: _cardElevationColor
                        .withValues(alpha: 0.04 + _anim.value * 0.06),
                    blurRadius: 12 + _anim.value * 8,
                    offset: Offset(0, 2 + _anim.value * 4),
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
