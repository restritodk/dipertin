import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/cobranca_assinatura_model.dart';
import '../models/cliente_assinatura_model.dart';
import '../services/inadimplencia_service.dart' as di;
import '../widgets/painel_content_skeleton.dart';

part 'inadimplencia/utils.dart';
part 'inadimplencia/header_section.dart';
part 'inadimplencia/kpi_cards.dart';
part 'inadimplencia/chart_section.dart';
part 'inadimplencia/filter_section.dart';
part 'inadimplencia/data_table.dart';
part 'inadimplencia/side_panel.dart';
part 'inadimplencia/central_cobrancas_modal.dart';

// ─── Tela Principal ─────────────────────────────────────────────────────────

class AssinaturasInadimplenciaScreen extends StatefulWidget {
  const AssinaturasInadimplenciaScreen({super.key});

  @override
  State<AssinaturasInadimplenciaScreen> createState() =>
      _AssinaturasInadimplenciaScreenState();
}

class _AssinaturasInadimplenciaScreenState
    extends State<AssinaturasInadimplenciaScreen> {
  final _filtros = _FiltrosInadimplencia();
  List<di.InadimplenciaItem> _itens = [];
  di.InadimplenciaKpis _kpis = di.InadimplenciaKpis(
    valorEmAtraso: 0,
    valorEmAtrasoMesAnterior: 0,
    clientesInadimplentes: 0,
    clientesInadimplentesSemanaAnterior: 0,
    vencemHojeQtd: 0,
    vencemHojeValor: 0,
    acima30DiasQtd: 0,
    acima30DiasValor: 0,
    recuperadoEsteMes: 0,
    recuperadoMesAnterior: 0,
  );
  List<di.InadimplenciaMes> _evolucao = [];
  bool _carregando = true;
  String? _erro;
  StreamSubscription? _sub;

  List<di.InadimplenciaItem> get _itensFiltrados {
    var lista = _itens.where((item) {
      // Filtro base: apenas cobranças Gestão Comercial não-pagas ou de clientes suspensos
      final itemStatus = item.cobranca.status;
      if (itemStatus == StatusCobranca.reembolsada) {
        return false;
      }
      // Cliente suspenso/cancelado: mostra mesmo se a cobrança está paga
      final clienteSuspenso = item.cliente != null &&
          (item.cliente!.status == 'suspenso');
      if (itemStatus == StatusCobranca.paga && !clienteSuspenso) {
        return false;
      }
      if (_filtros.search.isNotEmpty) {
        final q = _filtros.search.toLowerCase();
        final nome = item.cobranca.clienteNome.toLowerCase();
        final resp = item.cliente?.ownerName.toLowerCase() ?? '';
        final fatura = item.cobranca.fatura.toLowerCase();
        final email = item.cobranca.clienteEmail.toLowerCase();
        if (!nome.contains(q) &&
            !resp.contains(q) &&
            !fatura.contains(q) &&
            !email.contains(q)) {
          return false;
        }
      }
      if (_filtros.plano.isNotEmpty &&
          !item.cobranca.planoNome
              .toLowerCase()
              .contains(_filtros.plano.toLowerCase())) {
        return false;
      }
      if (_filtros.status.isNotEmpty &&
          item.statusExibicao != _filtros.status) {
        return false;
      }
      if (_filtros.faixaAtraso.isNotEmpty) {
        final dias = item.diasEmAtraso;
        switch (_filtros.faixaAtraso) {
          case '1-5':
            if (dias < 1 || dias > 5) return false;
            break;
          case '6-10':
            if (dias < 6 || dias > 10) return false;
            break;
          case '11-30':
            if (dias < 11 || dias > 30) return false;
            break;
          case '31-60':
            if (dias < 31 || dias > 60) return false;
            break;
          case '61+':
            if (dias < 61) return false;
            break;
        }
      }
      if (_filtros.cidade.isNotEmpty) {
        final cidade = (item.cliente?.addressCity ?? '').toLowerCase();
        if (!cidade.contains(_filtros.cidade.toLowerCase())) return false;
      }
      if (_filtros.uf.isNotEmpty) {
        final uf = (item.cliente?.addressState ?? '').toUpperCase();
        if (uf != _filtros.uf.toUpperCase()) return false;
      }
      return true;
    }).toList();

    switch (_filtros.sortBy) {
      case 'nome':
        lista.sort(
            (a, b) => a.cobranca.clienteNome.compareTo(b.cobranca.clienteNome));
        break;
      case 'valor':
        lista.sort((a, b) => b.cobranca.valor.compareTo(a.cobranca.valor));
        break;
      default:
        lista.sort((a, b) => b.diasEmAtraso.compareTo(a.diasEmAtraso));
    }
    if (!_filtros.sortAsc) lista = lista.reversed.toList();
    return lista;
  }

  @override
  void initState() {
    super.initState();
    _sub = di.InadimplenciaService.streamInadimplencia().listen(
      (itens) {
        if (!mounted) return;
        setState(() {
          _itens = itens;
          _kpis = di.InadimplenciaService.calcularKpis(itens);
          _evolucao = di.InadimplenciaService.calcularEvolucao(itens);
          _carregando = false;
          _erro = null;
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _carregando = false;
          _erro = err.toString();
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _filtros.dispose();
    super.dispose();
  }

  int get _filtrosAtivosQtd {
    int c = 0;
    if (_filtros.search.isNotEmpty) c++;
    if (_filtros.plano.isNotEmpty) c++;
    if (_filtros.status.isNotEmpty) c++;
    if (_filtros.faixaAtraso.isNotEmpty) c++;
    if (_filtros.cidade.isNotEmpty) c++;
    if (_filtros.uf.isNotEmpty) c++;
    return c;
  }

  void _limparFiltros() {
    setState(() => _filtros.limpar());
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final telaPequena = largura < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: _carregando
          ? const PainelContentSkeleton()
          : _erro != null
              ? _buildError()
              : _buildBody(telaPequena),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 64, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text('Erro ao carregar dados',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() => _carregando = true);
                _sub?.cancel();
                _sub = di.InadimplenciaService.streamInadimplencia().listen(
                  (itens) {
                    if (!mounted) return;
                    setState(() {
                      _itens = itens;
                      _kpis = di.InadimplenciaService.calcularKpis(itens);
                      _evolucao = di.InadimplenciaService.calcularEvolucao(itens);
                      _carregando = false;
                      _erro = null;
                    });
                  },
                  onError: (err) {
                    if (!mounted) return;
                    setState(() {
                      _carregando = false;
                      _erro = err.toString();
                    });
                  },
                );
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool telaPequena) {
    return Column(
      children: [
        // Header
        _HeaderSection(),

        // Área de cards + gráfico
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: telaPequena
              ? Column(
                  children: [
                    _KpiCardsGrid(kpis: _kpis),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 280,
                      child: _ChartSection(evolucao: _evolucao),
                    ),
                  ],
                )
              : SizedBox(
                  height: 340,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cards: 2 linhas (3 + 2)
                      Expanded(
                        flex: 3,
                        child: _KpiCardsGrid(kpis: _kpis),
                      ),
                      const SizedBox(width: 16),
                      // Gráfico: altura fixa
                      Expanded(
                        flex: 2,
                        child: _ChartSection(evolucao: _evolucao),
                      ),
                    ],
                  ),
                ),
        ),

        // Filtros — agora via modal (botão acima da tabela)

        // Tabela com botão de filtros
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              children: [
                // Linha com busca + botão Filtros avançados
                _buildFilterButtonRow(),
                const SizedBox(height: 8),
                // Chips de filtros ativos
                if (_filtrosAtivosQtd > 0)
                  _buildActiveChips(),
                // Tabela
                Expanded(
                  child: _DataTableSection(
                    itens: _itensFiltrados,
                    totalItens: _itens.length,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterButtonRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Pesquisar por nome, responsável, fatura...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: const Color(0xFFF8F7FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) {
                setState(() => _filtros.search = v.trim());
              },
            ),
          ),
          const SizedBox(width: 10),
          // Botão Filtros avançados
          _BotaoFiltrosAvancados(onTap: _abrirFiltrosAvancados),
        ],
      ),
    );
  }

  void _abrirFiltrosAvancados() {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _FiltrosAvancadosModal(
        filtros: _filtros,
        itens: _itens,
        onAplicar: () {
          Navigator.pop(context);
          setState(() {});
        },
        onLimpar: () {
          _limparFiltros();
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildActiveChips() {
    final chips = <Widget>[];
    void addChip(String label, String valor, VoidCallback onRemove) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Chip(
          label: Text('$label: $valor', style: const TextStyle(fontSize: 12)),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: onRemove,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: const Color(0xFFF1E9FF),
          side: BorderSide.none,
        ),
      ));
    }

    if (_filtros.search.isNotEmpty) {
      addChip('Busca', _filtros.search, () => setState(() => _filtros.search = ''));
    }
    if (_filtros.plano.isNotEmpty) {
      addChip('Plano', _filtros.plano, () => setState(() => _filtros.plano = ''));
    }
    if (_filtros.status.isNotEmpty) {
      addChip('Status', _filtros.status, () => setState(() => _filtros.status = ''));
    }
    if (_filtros.faixaAtraso.isNotEmpty) {
      addChip('Atraso', _filtros.faixaAtraso, () => setState(() => _filtros.faixaAtraso = ''));
    }
    if (_filtros.cidade.isNotEmpty) {
      addChip('Cidade', _filtros.cidade, () => setState(() => _filtros.cidade = ''));
    }
    if (_filtros.uf.isNotEmpty) {
      addChip('UF', _filtros.uf, () => setState(() => _filtros.uf = ''));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }

}

// ─── Classe de filtros ──────────────────────────────────────────────────────

class _FiltrosInadimplencia {
  String search = '';
  String plano = '';
  String status = '';
  String faixaAtraso = '';
  String cidade = '';
  String uf = '';
  String sortBy = 'dias';
  bool sortAsc = false;
  bool mostrar = true;

  void limpar() {
    search = '';
    plano = '';
    status = '';
    faixaAtraso = '';
    cidade = '';
    uf = '';
  }

  void dispose() {}
}
