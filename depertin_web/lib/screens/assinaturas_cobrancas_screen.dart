import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/cliente_assinatura_model.dart';
import '../models/cobranca_assinatura_model.dart';
import '../services/assinaturas_clientes_service.dart';
import '../services/cobrancas_assinatura_service.dart';
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';
import '../widgets/dipertin_date_picker.dart';

final NumberFormat _fmtMoeda = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
);

// ============================================================
// TOKENS LOCAIS — alinhados ao design system DiPertin
// ============================================================
const Color _fundoPagina = Color(0xFFF8F8FC);
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _bordaCard = Color(0xFFEEEAF6);
const Color _bordaSuave = Color(0xFFF0EEF7);
const Color _roxo = DiPertinTheme.primaryRoxo;
const Color _laranja = DiPertinTheme.secondaryLaranja;
const Color _fundoTabelaCabecalho = Color(0xFFFCFCFE);

/// Grid da tabela (soma dos flex = 100 → equivale a %).
const int _flexCheck = 5;
const int _flexFatura = 13;
const int _flexCliente = 24;
const int _flexModulo = 20;
const int _flexVencimento = 14;
const int _flexValor = 10;
const int _flexStatus = 9;
const int _flexAcoes = 5;

const int _itensPorPagina = 5;

/// Tela premium de Cobranças — Gestão de Assinaturas (painel admin).
class AssinaturasCobrancasScreen extends StatefulWidget {
  const AssinaturasCobrancasScreen({super.key});

  @override
  State<AssinaturasCobrancasScreen> createState() =>
      _AssinaturasCobrancasScreenState();
}

class _AssinaturasCobrancasScreenState
    extends State<AssinaturasCobrancasScreen> {
  final TextEditingController _buscaCtl = TextEditingController();

  DateTimeRange? _periodo;
  StatusCobranca? _filtroStatus;
  ModuloCobranca? _filtroModulo;
  bool _apenasAberto = true;
  int _paginaAtual = 1;
  final Set<String> _selecionadas = {};

  List<CobrancaAssinatura> _todas = const [];
  bool _gerando = false;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _buscaCtl.addListener(() => setState(() => _paginaAtual = 1));
  }

  @override
  void dispose() {
    _buscaCtl.dispose();
    super.dispose();
  }

  // ---------- Filtragem ----------
  List<CobrancaAssinatura> get _filtradas {
    final busca = _buscaCtl.text.trim().toLowerCase();
    return _todas.where((c) {
      if (_apenasAberto &&
          c.status != StatusCobranca.emAberto &&
          c.status != StatusCobranca.vencida) {
        return false;
      }
      if (_filtroStatus != null && c.status != _filtroStatus) return false;
      if (_filtroModulo != null && c.modulo != _filtroModulo) return false;
      if (_periodo != null) {
        final v = DateTime(
          c.vencimento.year,
          c.vencimento.month,
          c.vencimento.day,
        );
        if (v.isBefore(_periodo!.start) || v.isAfter(_periodo!.end)) {
          return false;
        }
      }
      if (busca.isNotEmpty) {
        final alvo =
            '${c.fatura} ${c.clienteNome} ${c.clienteEmail} ${c.planoNome} ${c.id}'
                .toLowerCase();
        if (!alvo.contains(busca)) return false;
      }
      return true;
    }).toList();
  }

  int get _filtrosAtivos {
    var n = 0;
    if (_apenasAberto) n++;
    if (_periodo != null) n++;
    if (_filtroStatus != null) n++;
    if (_filtroModulo != null) n++;
    if (_buscaCtl.text.trim().isNotEmpty) n++;
    return n;
  }

  int get _totalPaginas {
    final t = _filtradas.length;
    return t == 0 ? 1 : (t / _itensPorPagina).ceil();
  }

  List<CobrancaAssinatura> get _paginaItens {
    final lista = _filtradas;
    final start = (_paginaAtual - 1) * _itensPorPagina;
    if (start >= lista.length) return const [];
    final end = (start + _itensPorPagina).clamp(0, lista.length);
    return lista.sublist(start, end);
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtl.clear();
      _periodo = null;
      _filtroStatus = null;
      _filtroModulo = null;
      _apenasAberto = true;
      _paginaAtual = 1;
    });
  }

  Future<void> _selecionarPeriodo() async {
    final inicio = await showDiPertinDatePicker(
      context,
      titulo: 'Período — início',
      subtitulo: 'Selecione a data inicial das cobranças',
      dataInicial: _periodo?.start,
      dataMinima: DateTime(2023),
      dataMaxima: DateTime.now().add(const Duration(days: 365)),
    );
    if (inicio == null || !mounted) return;
    final fim = await showDiPertinDatePicker(
      context,
      titulo: 'Período — fim',
      subtitulo: 'Selecione a data final das cobranças',
      dataInicial: _periodo?.end ?? inicio,
      dataMinima: inicio,
      dataMaxima: DateTime.now().add(const Duration(days: 365)),
    );
    if (fim == null || !mounted) return;
    setState(() {
      _periodo = DateTimeRange(start: inicio, end: fim);
      _paginaAtual = 1;
    });
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? const Color(0xFFC62828) : _roxo,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _gerarCobrancas() async {
    if (_gerando) return;
    setState(() => _gerando = true);
    try {
      final r = await CobrancasAssinaturaService.gerar();
      if (r.total == 0) {
        _snack('Nenhuma cobrança nova. Tudo já está atualizado.');
      } else {
        _snack('${r.criadas} criada(s) e ${r.atualizadas} atualizada(s).');
      }
    } on CallableHttpException catch (e) {
      _snack(mensagemCallableHttpException(e), erro: true);
    } catch (e) {
      _snack('Falha ao gerar cobranças: $e', erro: true);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPagina,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CobrancasAssinaturaService.stream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _buildErro();
          }
          final carregando =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          if (!carregando) {
            _todas = (snap.data?.docs ?? [])
                .map(CobrancaAssinatura.fromFirestore)
                .toList();
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final largura = constraints.maxWidth;
              final compacto = largura < 1180;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(compacto),
                    const SizedBox(height: 18),
                    _buildCards(largura),
                    const SizedBox(height: 18),
                    _buildAreaFiltros(compacto),
                    const SizedBox(height: 18),
                    if (carregando)
                      _buildLoading()
                    else if (_todas.isEmpty)
                      _buildVazioGeral()
                    else
                      _buildTabela(largura),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: _textoSecundario,
          ),
          const SizedBox(height: 12),
          Text(
            'Não foi possível carregar as cobranças.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bordaCard),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _roxo, strokeWidth: 3),
      ),
    );
  }

  Widget _buildVazioGeral() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bordaCard),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDF6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 42,
              color: _roxo.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nenhuma cobrança ainda',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gere as cobranças a partir das assinaturas contratadas para começar.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              color: _textoSecundario,
            ),
          ),
          const SizedBox(height: 20),
          _BotaoPrimario(
            icone: _gerando
                ? Icons.hourglass_top_rounded
                : Icons.autorenew_rounded,
            label: _gerando ? 'Gerando...' : 'Gerar cobranças',
            onTap: _gerarCobrancas,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CABEÇALHO
  // ============================================================
  Widget _buildHeader(bool compacto) {
    final titulo = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roxo, DiPertinTheme.primaryRoxoClaro],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _roxo.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cobranças',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Cobranças em aberto são exibidas por padrão. Use os filtros para visualizar pagas ou de períodos anteriores.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final acoes = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BotaoFiltros(
          ativos: _filtrosAtivos,
          onTap: () => _snack('Use os filtros abaixo para refinar a lista.'),
        ),
      ],
    );

    if (compacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titulo,
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: acoes),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titulo),
        const SizedBox(width: 16),
        acoes,
      ],
    );
  }

  // ============================================================
  // CARDS DE RESUMO
  // ============================================================
  Widget _buildCards(double largura) {
    double soma(bool Function(CobrancaAssinatura) f) =>
        _todas.where(f).fold<double>(0, (t, c) => t + c.valor);
    int conta(bool Function(CobrancaAssinatura) f) => _todas.where(f).length;

    final totalValor = _todas.fold<double>(0, (t, c) => t + c.valor);
    final emAbertoCount = conta((c) => c.status == StatusCobranca.emAberto);
    final vencidasCount = conta((c) => c.status == StatusCobranca.vencida);
    final pagasCount = conta((c) => c.status == StatusCobranca.paga);

    final cards = <Widget>[
      _CardResumo(
        indice: 0,
        icone: Icons.description_outlined,
        cor: _roxo,
        titulo: 'Total de cobranças',
        valorGrande: '${_todas.length}',
        rodape: 'Todas as faturas',
        rodapeCor: _roxo,
      ),
      _CardResumo(
        indice: 1,
        icone: Icons.payments_outlined,
        cor: _laranja,
        titulo: 'Valor total',
        valorGrande: _fmtMoeda.format(totalValor),
        rodape: 'Somatório geral',
        rodapeCor: _laranja,
      ),
      _CardResumo(
        indice: 2,
        icone: Icons.schedule_rounded,
        cor: const Color(0xFF0EA5E9),
        titulo: 'Em aberto',
        valorGrande: '$emAbertoCount',
        rodape: _fmtMoeda.format(
          soma((c) => c.status == StatusCobranca.emAberto),
        ),
        rodapeCor: const Color(0xFF0EA5E9),
      ),
      _CardResumo(
        indice: 3,
        icone: Icons.error_outline_rounded,
        cor: const Color(0xFFF04438),
        titulo: 'Vencidas',
        valorGrande: '$vencidasCount',
        rodape: _fmtMoeda.format(
          soma((c) => c.status == StatusCobranca.vencida),
        ),
        rodapeCor: const Color(0xFFF04438),
      ),
      _CardResumo(
        indice: 4,
        icone: Icons.check_circle_outline_rounded,
        cor: const Color(0xFF16A34A),
        titulo: 'Pagas',
        valorGrande: '$pagasCount',
        rodape: _fmtMoeda.format(soma((c) => c.status == StatusCobranca.paga)),
        rodapeCor: const Color(0xFF16A34A),
      ),
    ];

    // Responsivo: 5 colunas (≥1360), 3 (≥1000), 2 (≥620), senão 1.
    int colunas;
    if (largura >= 1360) {
      colunas = 5;
    } else if (largura >= 1000) {
      colunas = 3;
    } else if (largura >= 620) {
      colunas = 2;
    } else {
      colunas = 1;
    }
    const espaco = 14.0;
    final larguraCard = (largura - espaco * (colunas - 1)) / colunas;

    return Wrap(
      spacing: espaco,
      runSpacing: espaco,
      children: cards
          .map((c) => SizedBox(width: larguraCard, child: c))
          .toList(),
    );
  }

  // ============================================================
  // ÁREA DE FILTROS
  // ============================================================
  Widget _buildAreaFiltros(bool compacto) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bordaCard),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compacto ? double.infinity : 300,
                child: _campoBusca(),
              ),
              _FiltroBotao(
                icone: Icons.calendar_today_outlined,
                label: _periodo == null
                    ? 'Período'
                    : '${DateFormat('dd/MM').format(_periodo!.start)} - ${DateFormat('dd/MM').format(_periodo!.end)}',
                ativo: _periodo != null,
                onTap: _selecionarPeriodo,
              ),
              _dropdownStatus(),
              _dropdownModulo(),
              _BotaoLimpar(
                habilitado: _filtrosAtivos > 0,
                onTap: _limparFiltros,
              ),
            ],
          ),
          if (_filtrosAtivos > 0) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: _bordaSuave),
            const SizedBox(height: 14),
            _buildChipsAtivos(),
          ],
        ],
      ),
    );
  }

  Widget _campoBusca() {
    return TextField(
      controller: _buscaCtl,
      style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: _textoPrimario),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar por cliente, fatura ou plano...',
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13.5,
          color: _textoSecundario.withValues(alpha: 0.8),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: _textoSecundario,
        ),
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _bordaCard),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _bordaCard),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _roxo, width: 1.6),
        ),
      ),
    );
  }

  Widget _dropdownStatus() {
    return _DropdownFiltro<StatusCobranca?>(
      icone: Icons.flag_outlined,
      valor: _filtroStatus,
      rotuloVazio: 'Todos os status',
      ativo: _filtroStatus != null,
      itens: [
        const DropdownMenuItem<StatusCobranca?>(
          value: null,
          child: Text('Todos os status'),
        ),
        ...StatusCobranca.values.map(
          (s) => DropdownMenuItem<StatusCobranca?>(
            value: s,
            child: Text(s.rotulo),
          ),
        ),
      ],
      onChanged: (v) => setState(() {
        _filtroStatus = v;
        if (v != null) _apenasAberto = false;
        _paginaAtual = 1;
      }),
      textoSelecionado: _filtroStatus?.rotulo,
    );
  }

  Widget _dropdownModulo() {
    return _DropdownFiltro<ModuloCobranca?>(
      icone: Icons.widgets_outlined,
      valor: _filtroModulo,
      rotuloVazio: 'Todos os módulos',
      ativo: _filtroModulo != null,
      itens: [
        const DropdownMenuItem<ModuloCobranca?>(
          value: null,
          child: Text('Todos os módulos'),
        ),
        ...ModuloCobranca.values.map(
          (m) => DropdownMenuItem<ModuloCobranca?>(
            value: m,
            child: Text(m.rotulo),
          ),
        ),
      ],
      onChanged: (v) => setState(() {
        _filtroModulo = v;
        _paginaAtual = 1;
      }),
      textoSelecionado: _filtroModulo?.rotulo,
    );
  }

  Widget _buildChipsAtivos() {
    final chips = <Widget>[];
    if (_apenasAberto) {
      chips.add(
        _ChipAtivo(
          label: 'Apenas em aberto',
          cor: const Color(0xFF0EA5E9),
          onRemover: () => setState(() {
            _apenasAberto = false;
            _paginaAtual = 1;
          }),
        ),
      );
    }
    if (_periodo != null) {
      chips.add(
        _ChipAtivo(
          label:
              'Período: ${DateFormat('dd/MM').format(_periodo!.start)} a ${DateFormat('dd/MM').format(_periodo!.end)}',
          onRemover: () => setState(() {
            _periodo = null;
            _paginaAtual = 1;
          }),
        ),
      );
    }
    if (_filtroStatus != null) {
      chips.add(
        _ChipAtivo(
          label: 'Status: ${_filtroStatus!.rotulo}',
          cor: _filtroStatus!.cor,
          onRemover: () => setState(() {
            _filtroStatus = null;
            _paginaAtual = 1;
          }),
        ),
      );
    }
    if (_filtroModulo != null) {
      chips.add(
        _ChipAtivo(
          label: 'Módulo: ${_filtroModulo!.rotulo}',
          cor: _filtroModulo!.cor,
          onRemover: () => setState(() {
            _filtroModulo = null;
            _paginaAtual = 1;
          }),
        ),
      );
    }
    if (_buscaCtl.text.trim().isNotEmpty) {
      chips.add(
        _ChipAtivo(
          label: 'Busca: "${_buscaCtl.text.trim()}"',
          onRemover: () => setState(_buscaCtl.clear),
        ),
      );
    }

    return Row(
      children: [
        Text(
          'Filtros ativos:',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
      ],
    );
  }

  // ============================================================
  // TABELA
  // ============================================================
  Widget _buildTabela(double largura) {
    final itens = _paginaItens;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _bordaCard),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildCabecalhoTabela(),
          if (itens.isEmpty)
            _buildTabelaVazia()
          else
            ...List.generate(itens.length, (i) {
              return _LinhaCobranca(
                cobranca: itens[i],
                indice: i,
                selecionada: _selecionadas.contains(itens[i].id),
                onSelecionar: (v) => setState(() {
                  if (v) {
                    _selecionadas.add(itens[i].id);
                  } else {
                    _selecionadas.remove(itens[i].id);
                  }
                }),
                onAcao: (acao) => _executarAcao(acao, itens[i]),
              );
            }),
          _buildRodape(),
        ],
      ),
    );
  }

  Widget _buildCabecalhoTabela() {
    Widget h(String t, int flex, {TextAlign align = TextAlign.left}) {
      return Expanded(
        flex: flex,
        child: Text(
          t,
          textAlign: align,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: _textoSecundario,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    final todasSelecionadas =
        _paginaItens.isNotEmpty &&
        _paginaItens.every((c) => _selecionadas.contains(c.id));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: _fundoTabelaCabecalho,
        border: Border(bottom: BorderSide(color: _bordaCard)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _flexCheck,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Checkbox(
                valor: todasSelecionadas,
                onChanged: (v) => setState(() {
                  if (v) {
                    _selecionadas.addAll(_paginaItens.map((c) => c.id));
                  } else {
                    for (final c in _paginaItens) {
                      _selecionadas.remove(c.id);
                    }
                  }
                }),
              ),
            ),
          ),
          h('FATURA', _flexFatura),
          h('CLIENTE', _flexCliente),
          h('MÓDULO', _flexModulo),
          h('VENCIMENTO', _flexVencimento),
          h('VALOR', _flexValor, align: TextAlign.right),
          h('STATUS', _flexStatus),
          h('AÇÕES', _flexAcoes, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildTabelaVazia() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDF6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: _roxo.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma cobrança encontrada',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textoPrimario,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajuste os filtros para ver outras cobranças.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRodape() {
    final total = _filtradas.length;
    final inicio = total == 0 ? 0 : (_paginaAtual - 1) * _itensPorPagina + 1;
    final fim = (_paginaAtual * _itensPorPagina).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _bordaCard)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mostrando $inicio a $fim de $total cobranças',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                color: _textoSecundario,
              ),
            ),
          ),
          _Paginacao(
            paginaAtual: _paginaAtual,
            totalPaginas: _totalPaginas,
            onMudar: (p) => setState(() => _paginaAtual = p),
          ),
        ],
      ),
    );
  }

  // ---------- Ações da linha ----------
  Future<void> _executarAcao(String acao, CobrancaAssinatura c) async {
    switch (acao) {
      case 'visualizar':
        _mostrarDetalhes(c);
        return;
      case 'recibo':
        await showDialog<bool>(
          context: context,
          builder: (_) => _EscolherTipoReciboModal(cobranca: c),
        );
        return;
      case 'historico':
        _mostrarDetalhes(c);
        return;
      case 'enviar':
        await showDialog<bool>(
          context: context,
          builder: (_) => _EnviarCobrancaModal(
            cobranca: c,
            onEnviar: (mensagemPersonalizada) async {
              if (_processando) return;
              setState(() => _processando = true);
              try {
                await CobrancasAssinaturaService.enviarCobrancaEmail(
                  cobrancaId: c.id,
                  clienteEmail: c.clienteEmail,
                  clienteNome: c.clienteNome,
                  fatura: c.fatura,
                  planoNome:
                      c.planoNome.isNotEmpty ? c.planoNome : c.modulo.rotulo,
                  modulo: c.modulo.rotulo,
                  valorExibicao: c.valorExibicao,
                  vencimento: c.vencimentoExibicao,
                  statusRotulo: c.status.rotulo,
                  mensagemPersonalizada: mensagemPersonalizada,
                );
              } on CallableHttpException catch (e) {
                throw Exception(mensagemCallableHttpException(e));
              } catch (e) {
                throw Exception(
                    e is String ? e : 'Falha ao enviar cobrança: $e');
              } finally {
                if (mounted) setState(() => _processando = false);
              }
            },
          ),
        );
        return;
      case 'marcar_paga':
        await showDialog<bool>(
          context: context,
          builder: (_) => _MarcarPagaModal(
            cobranca: c,
            onConfirmar: (descricao) async {
              await _chamarAcao(
                c,
                'marcar_paga',
                sucesso: '${c.fatura} marcada como paga.',
                descricao: descricao,
              );
            },
          ),
        );
        return;
      case 'cancelar':
        await showDialog<bool>(
          context: context,
          builder: (_) => _CancelarCobrancaModal(
            cobranca: c,
            onConfirmar: () async {
              await _chamarAcao(
                c,
                'cancelar',
                sucesso: '${c.fatura} cancelada.',
              );
            },
          ),
        );
        return;
      case 'excluir':
        final ok = await _confirmar(
          titulo: 'Excluir cobrança',
          mensagem: 'Excluir permanentemente a ${c.fatura}?',
          confirmar: 'Excluir',
          perigo: true,
        );
        if (ok) {
          await _chamarAcao(c, 'excluir', sucesso: '${c.fatura} excluída.');
        }
        return;
    }
  }

  Future<void> _chamarAcao(
    CobrancaAssinatura c,
    String acao, {
    String? canal,
    String? descricao,
    required String sucesso,
  }) async {
    if (_processando) return;
    setState(() => _processando = true);
    try {
      await CobrancasAssinaturaService.atualizar(
        cobrancaId: c.id,
        acao: acao,
        canal: canal,
        descricao: descricao,
      );
      _snack(sucesso);
    } on CallableHttpException catch (e) {
      _snack(mensagemCallableHttpException(e), erro: true);
    } catch (e) {
      _snack('Falha na operação: $e', erro: true);
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensagem,
    required String confirmar,
    bool perigo = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
        content: Text(
          mensagem,
          style: GoogleFonts.plusJakartaSans(color: _textoSecundario),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Voltar',
              style: GoogleFonts.plusJakartaSans(
                color: _textoSecundario,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: perigo ? const Color(0xFFF04438) : _roxo,
            ),
            child: Text(confirmar),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _mostrarDetalhes(CobrancaAssinatura c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _BadgeModulo(modulo: c.modulo),
                    const Spacer(),
                    _BadgeStatus(status: c.status),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  c.fatura,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.planoNome.isNotEmpty ? c.planoNome : c.modulo.rotulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    color: _textoSecundario,
                  ),
                ),
                const Divider(height: 28),
                _linhaDetalhe('Cliente', c.clienteNome),
                _linhaDetalhe('E-mail', c.clienteEmail),
                _linhaDetalhe(
                  'Plano',
                  c.planoNome.isNotEmpty ? c.planoNome : c.modulo.rotulo,
                ),
                _linhaDetalhe('Vencimento', c.vencimentoExibicao),
                _linhaDetalhe('Situação', c.situacaoVencimento),
                _linhaDetalhe('Valor', c.valorExibicao),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(backgroundColor: _roxo),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linhaDetalhe(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              rotulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Exportar CSV (removido do header, mantido para uso futuro)
}

// ============================================================
// BOTÕES DO CABEÇALHO
// ============================================================
class _BotaoSecundario extends StatefulWidget {
  const _BotaoSecundario({
    required this.icone,
    required this.label,
    required this.onTap,
  });

  final IconData icone;
  final String label;
  final VoidCallback onTap;

  @override
  State<_BotaoSecundario> createState() => _BotaoSecundarioState();
}

class _BotaoSecundarioState extends State<_BotaoSecundario> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF6F4FB) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? _roxo.withValues(alpha: 0.4) : _bordaCard,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icone, size: 18, color: _textoPrimario),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotaoFiltros extends StatefulWidget {
  const _BotaoFiltros({required this.ativos, required this.onTap});

  final int ativos;
  final VoidCallback onTap;

  @override
  State<_BotaoFiltros> createState() => _BotaoFiltrosState();
}

class _BotaoFiltrosState extends State<_BotaoFiltros> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF6F4FB) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? _roxo.withValues(alpha: 0.4) : _bordaCard,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: _textoPrimario),
              const SizedBox(width: 8),
              Text(
                'Filtros',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
              if (widget.ativos > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _laranja,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.ativos}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BotaoPrimario extends StatefulWidget {
  const _BotaoPrimario({
    required this.icone,
    required this.label,
    required this.onTap,
  });

  final IconData icone;
  final String label;
  final VoidCallback onTap;

  @override
  State<_BotaoPrimario> createState() => _BotaoPrimarioState();
}

class _BotaoPrimarioState extends State<_BotaoPrimario> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: _hover
              ? (Matrix4.identity()..translateByDouble(0.0, -1.0, 0.0, 1.0))
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_roxo, DiPertinTheme.primaryRoxoClaro],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _roxo.withValues(alpha: _hover ? 0.42 : 0.28),
                blurRadius: _hover ? 18 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icone, size: 19, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CARD DE RESUMO (fade + slide)
// ============================================================
class _CardResumo extends StatelessWidget {
  const _CardResumo({
    required this.indice,
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.valorGrande,
    required this.rodape,
    required this.rodapeCor,
  });

  final int indice;
  final IconData icone;
  final Color cor;
  final String titulo;
  final String valorGrande;
  final String rodape;
  final Color rodapeCor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + indice * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _bordaCard),
          boxShadow: DiPertinTheme.sombraCardSuave(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: cor.withValues(alpha: 0.16)),
              ),
              child: Icon(icone, size: 18, color: cor),
            ),
            const SizedBox(height: 12),
            Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valorGrande,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rodape,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: rodapeCor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FILTROS
// ============================================================
class _FiltroBotao extends StatelessWidget {
  const _FiltroBotao({
    required this.icone,
    required this.label,
    required this.ativo,
    required this.onTap,
  });

  final IconData icone;
  final String label;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ativo ? _roxo.withValues(alpha: 0.4) : _bordaCard,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 18, color: ativo ? _roxo : _textoSecundario),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ativo ? _textoPrimario : _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownFiltro<T> extends StatelessWidget {
  const _DropdownFiltro({
    required this.icone,
    required this.valor,
    required this.rotuloVazio,
    required this.ativo,
    required this.itens,
    required this.onChanged,
    this.textoSelecionado,
  });

  final IconData icone;
  final T valor;
  final String rotuloVazio;
  final bool ativo;
  final List<DropdownMenuItem<T>> itens;
  final ValueChanged<T> onChanged;
  final String? textoSelecionado;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ativo ? _roxo.withValues(alpha: 0.4) : _bordaCard,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 18, color: ativo ? _roxo : _textoSecundario),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: valor,
              isDense: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: _textoSecundario,
              ),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ativo ? _textoPrimario : _textoSecundario,
              ),
              items: itens,
              onChanged: (v) => onChanged(v as T),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoLimpar extends StatelessWidget {
  const _BotaoLimpar({required this.habilitado, required this.onTap});

  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _bordaCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.close_rounded,
              size: 17,
              color: habilitado
                  ? _textoSecundario
                  : _textoSecundario.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'Limpar filtros',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: habilitado
                    ? _textoSecundario
                    : _textoSecundario.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipAtivo extends StatelessWidget {
  const _ChipAtivo({required this.label, required this.onRemover, this.cor});

  final String label;
  final VoidCallback onRemover;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = cor ?? _roxo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemover,
              borderRadius: BorderRadius.circular(20),
              child: Icon(Icons.close_rounded, size: 15, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LINHA DA TABELA (hover + fade)
// ============================================================
class _LinhaCobranca extends StatefulWidget {
  const _LinhaCobranca({
    required this.cobranca,
    required this.indice,
    required this.selecionada,
    required this.onSelecionar,
    required this.onAcao,
  });

  final CobrancaAssinatura cobranca;
  final int indice;
  final bool selecionada;
  final ValueChanged<bool> onSelecionar;
  final ValueChanged<String> onAcao;

  @override
  State<_LinhaCobranca> createState() => _LinhaCobrancaState();
}

class _LinhaCobrancaState extends State<_LinhaCobranca> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cobranca;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + widget.indice * 60),
      curve: Curves.easeOut,
      builder: (context, t, child) =>
          Opacity(opacity: t.clamp(0, 1), child: child),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFFAF9FE) : Colors.white,
            border: const Border(bottom: BorderSide(color: _bordaSuave)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: _flexCheck,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Checkbox(
                    valor: widget.selecionada,
                    onChanged: widget.onSelecionar,
                  ),
                ),
              ),
              // Fatura
              Expanded(
                flex: _flexFatura,
                child: Text(
                  c.fatura,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
              ),
              // Cliente
              Expanded(
                flex: _flexCliente,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.clienteNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.clienteEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Módulo (nome do plano + badge do módulo)
              Expanded(
                flex: _flexModulo,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.planoNome.isNotEmpty ? c.planoNome : c.modulo.rotulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _BadgeModulo(modulo: c.modulo),
                    ],
                  ),
                ),
              ),
              // Vencimento
              Expanded(
                flex: _flexVencimento,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.vencimentoExibicao,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.situacaoVencimento,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: c.situacaoVencida
                            ? const Color(0xFFF04438)
                            : const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
              // Valor
              Expanded(
                flex: _flexValor,
                child: Text(
                  c.valorExibicao,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Status
              Expanded(
                flex: _flexStatus,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _BadgeStatus(status: c.status),
                ),
              ),
              // Ações
              Expanded(
                flex: _flexAcoes,
                child: Align(
                  alignment: Alignment.center,
                  child: _MenuAcoes(onAcao: widget.onAcao),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BADGES
// ============================================================
class _BadgeModulo extends StatelessWidget {
  const _BadgeModulo({required this.modulo});

  final ModuloCobranca modulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: modulo.fundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: modulo.cor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: modulo.cor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              modulo.rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: modulo.cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStatus extends StatelessWidget {
  const _BadgeStatus({required this.status});

  final StatusCobranca status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: status.fundo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.cor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status.cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHECKBOX PREMIUM
// ============================================================
class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.valor, required this.onChanged});

  final bool valor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!valor),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: valor ? _roxo : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: valor ? _roxo : _bordaCard, width: 1.5),
        ),
        child: valor
            ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
            : null,
      ),
    );
  }
}

// ============================================================
// MENU DE AÇÕES
// ============================================================
class _MenuAcoes extends StatelessWidget {
  const _MenuAcoes({required this.onAcao});

  final ValueChanged<String> onAcao;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Ações',
      offset: const Offset(0, 40),
      elevation: 8,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _bordaCard),
      ),
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: _textoSecundario,
      ),
      onSelected: onAcao,
      itemBuilder: (context) => [
        _item('visualizar', Icons.visibility_outlined, 'Visualizar cobrança'),
        _item('enviar', Icons.send_outlined, 'Enviar cobrança'),
        const PopupMenuDivider(),
        _item(
          'marcar_paga',
          Icons.check_circle_outline_rounded,
          'Marcar como paga',
          cor: const Color(0xFF16A34A),
        ),
        _item(
          'cancelar',
          Icons.cancel_outlined,
          'Cancelar cobrança',
          cor: const Color(0xFFF04438),
        ),
        const PopupMenuDivider(),
        _item('recibo', Icons.receipt_outlined, 'Emitir recibo'),
        _item('historico', Icons.history_rounded, 'Histórico'),
        const PopupMenuDivider(),
        _item(
          'excluir',
          Icons.delete_outline_rounded,
          'Excluir',
          cor: const Color(0xFFF04438),
        ),
      ],
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icone,
    String label, {
    Color? cor,
  }) {
    final c = cor ?? _textoPrimario;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icone, size: 18, color: c),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PAGINAÇÃO
// ============================================================
class _Paginacao extends StatelessWidget {
  const _Paginacao({
    required this.paginaAtual,
    required this.totalPaginas,
    required this.onMudar,
  });

  final int paginaAtual;
  final int totalPaginas;
  final ValueChanged<int> onMudar;

  @override
  Widget build(BuildContext context) {
    final paginas = _numerosVisiveis();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _botaoSeta(
          icone: Icons.chevron_left_rounded,
          habilitado: paginaAtual > 1,
          onTap: () => onMudar(paginaAtual - 1),
        ),
        const SizedBox(width: 6),
        ...paginas.map((p) {
          if (p == -1) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('…', style: TextStyle(color: _textoSecundario)),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _botaoNumero(p),
          );
        }),
        const SizedBox(width: 6),
        _botaoSeta(
          icone: Icons.chevron_right_rounded,
          habilitado: paginaAtual < totalPaginas,
          onTap: () => onMudar(paginaAtual + 1),
        ),
      ],
    );
  }

  List<int> _numerosVisiveis() {
    if (totalPaginas <= 5) {
      return List.generate(totalPaginas, (i) => i + 1);
    }
    final res = <int>[1];
    if (paginaAtual > 3) res.add(-1);
    for (var p = paginaAtual - 1; p <= paginaAtual + 1; p++) {
      if (p > 1 && p < totalPaginas) res.add(p);
    }
    if (paginaAtual < totalPaginas - 2) res.add(-1);
    res.add(totalPaginas);
    return res;
  }

  Widget _botaoNumero(int p) {
    final ativo = p == paginaAtual;
    return InkWell(
      onTap: ativo ? null : () => onMudar(p),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: ativo
              ? const LinearGradient(
                  colors: [_roxo, DiPertinTheme.primaryRoxoClaro],
                )
              : null,
          color: ativo ? null : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ativo ? Colors.transparent : _bordaCard),
        ),
        child: Text(
          '$p',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ativo ? Colors.white : _textoPrimario,
          ),
        ),
      ),
    );
  }

  Widget _botaoSeta({
    required IconData icone,
    required bool habilitado,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _bordaCard),
        ),
        child: Icon(
          icone,
          size: 20,
          color: habilitado
              ? _textoPrimario
              : _textoSecundario.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ============================================================
// DIÁLOGO — NOVA COBRANÇA
// ============================================================
class _NovaCobrancaDialog extends StatefulWidget {
  const _NovaCobrancaDialog({required this.onGerarSistema});

  final Future<void> Function() onGerarSistema;

  @override
  State<_NovaCobrancaDialog> createState() => _NovaCobrancaDialogState();
}

class _NovaCobrancaDialogState extends State<_NovaCobrancaDialog> {
  final TextEditingController _valorCtl = TextEditingController();
  List<ClienteAssinaturaModel> _assinaturas = const [];
  ClienteAssinaturaModel? _selecionada;
  ModuloCobranca _modulo = ModuloCobranca.gestaoComercial;
  DateTime? _vencimento;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valorCtl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AssinaturasClientesService.colecao)
          .orderBy('created_at', descending: true)
          .get();
      final lista = snap.docs
          .map(ClienteAssinaturaModel.fromFirestore)
          .where((c) => c.entraListagemPrincipalAdmin)
          .toList();
      if (!mounted) return;
      setState(() {
        _assinaturas = lista;
        _carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _criar() async {
    if (_salvando) return;
    if (_selecionada == null) {
      _erro('Selecione a assinatura.');
      return;
    }
    final valor = double.tryParse(
      _valorCtl.text.trim().replaceAll('.', '').replaceAll(',', '.'),
    );
    if (valor == null || valor <= 0) {
      _erro('Informe um valor válido.');
      return;
    }
    if (_vencimento == null) {
      _erro('Informe o vencimento.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await CobrancasAssinaturaService.criarAvulsa(
        assinaturaId: _selecionada!.id,
        valor: valor,
        vencimento: _vencimento!,
        moduloCodigo: _modulo.codigo,
      );
      if (mounted) Navigator.pop(context, true);
    } on CallableHttpException catch (e) {
      _erro(mensagemCallableHttpException(e));
    } catch (e) {
      _erro('Falha ao criar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _erro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFC62828),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_roxo, DiPertinTheme.primaryRoxoClaro],
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Nova cobrança',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textoPrimario,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _roxo,
                      strokeWidth: 3,
                    ),
                  ),
                )
              else if (_assinaturas.isEmpty)
                _semAssinaturas()
              else ...[
                _rotulo('Assinatura'),
                _boxCampo(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ClienteAssinaturaModel>(
                      value: _selecionada,
                      isExpanded: true,
                      hint: Text(
                        'Selecione o cliente',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          color: _textoSecundario,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      items: _assinaturas
                          .map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(
                                '${a.storeName} · ${a.planName}',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _textoPrimario,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (a) => setState(() {
                        _selecionada = a;
                        if (a != null && _valorCtl.text.trim().isEmpty) {
                          _valorCtl.text = a.monthlyAmount
                              .toStringAsFixed(2)
                              .replaceAll('.', ',');
                        }
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _rotulo('Valor (R\$)'),
                          _boxCampo(
                            child: TextField(
                              controller: _valorCtl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: '0,00',
                              ),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _rotulo('Módulo'),
                          _boxCampo(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<ModuloCobranca>(
                                value: _modulo,
                                isExpanded: true,
                                borderRadius: BorderRadius.circular(14),
                                items: ModuloCobranca.values
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          m.rotulo,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _textoPrimario,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (m) =>
                                    setState(() => _modulo = m ?? _modulo),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _rotulo('Vencimento'),
                DiPertinDateField(
                  label: 'Vencimento',
                  data: _vencimento,
                  onChanged: (d) => setState(() => _vencimento = d),
                  tituloPicker: 'Vencimento da cobrança',
                  dataMinima: DateTime(DateTime.now().year - 1),
                  dataMaxima: DateTime.now().add(const Duration(days: 730)),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _salvando
                        ? null
                        : () async {
                            Navigator.pop(context);
                            await widget.onGerarSistema();
                          },
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    label: const Text('Gerar do sistema'),
                    style: TextButton.styleFrom(foregroundColor: _roxo),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _salvando
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.plusJakartaSans(
                        color: _textoSecundario,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        (_carregando || _assinaturas.isEmpty || _salvando)
                        ? null
                        : _criar,
                    style: FilledButton.styleFrom(backgroundColor: _roxo),
                    child: Text(_salvando ? 'Salvando...' : 'Criar cobrança'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _semAssinaturas() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 34,
            color: _roxo.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Nenhuma assinatura ativa encontrada.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rotulo(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: _textoSecundario,
      ),
    ),
  );

  Widget _boxCampo({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    height: 46,
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: const Color(0xFFF8F7FC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _bordaCard),
    ),
    child: child,
  );
}

// ============================================================
// MODAL PREMIUM — MARCAR COMO PAGA
// ============================================================
class _MarcarPagaModal extends StatefulWidget {
  const _MarcarPagaModal({required this.cobranca, required this.onConfirmar});

  final CobrancaAssinatura cobranca;
  final Future<void> Function(String descricao) onConfirmar;

  @override
  State<_MarcarPagaModal> createState() => _MarcarPagaModalState();
}

class _MarcarPagaModalState extends State<_MarcarPagaModal>
    with SingleTickerProviderStateMixin {
  bool _processando = false;
  bool _confirmou = false;
  final _descricaoCtrl = TextEditingController();
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _descricaoCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cobranca;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A0F2E).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header gradiente verde (sucesso/pagamento)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Ícone de pagamento
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Confirmar pagamento',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Registre o recebimento desta cobrança e adicione uma observação se necessário.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                // Corpo
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card com detalhes da cobrança
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEEEAF6)),
                        ),
                        child: Column(
                          children: [
                            _detalheLinha('Fatura', c.fatura, destaque: true),
                            const SizedBox(height: 8),
                            _detalheLinha('Cliente', c.clienteNome),
                            const SizedBox(height: 8),
                            _detalheLinha(
                              'Plano',
                              c.planoNome.isNotEmpty
                                  ? c.planoNome
                                  : c.modulo.rotulo,
                            ),
                            const SizedBox(height: 8),
                            _detalheLinha('Valor', c.valorExibicao),
                            const SizedBox(height: 8),
                            _detalheLinha('Vencimento', c.vencimentoExibicao),
                            const SizedBox(height: 8),
                            _detalheLinha('Status', c.status.rotulo),
                          ],
                        ),
                      ),

                      // Campo de descrição
                      const SizedBox(height: 20),
                      Text(
                        'Descrição / Observação',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descricaoCtrl,
                        maxLines: 3,
                        minLines: 2,
                        enabled: !_processando && !_confirmou,
                        decoration: InputDecoration(
                          hintText:
                              'Ex.: Pagamento via PIX, dinheiro, cartão...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: const Color(0xFF94A3B8),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8F7FC),
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE0DEE8),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE0DEE8),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF14B8A6),
                              width: 2,
                            ),
                          ),
                        ),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),

                      // Loading
                      if (_processando)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Color(0xFF14B8A6),
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        ),

                      // Feedback sucesso
                      if (_confirmou) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 28,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${c.fatura} paga',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Ações
                if (!_processando && !_confirmou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF0EEF7))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFE0DEE8)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () async {
                              final descricao = _descricaoCtrl.text.trim();
                              setState(() => _processando = true);
                              final nav = Navigator.of(context);
                              try {
                                await widget.onConfirmar(descricao);
                                if (!mounted) return;
                                setState(() => _confirmou = true);
                                await Future.delayed(
                                  const Duration(seconds: 1),
                                );
                                if (mounted) {
                                  nav.pop(true);
                                }
                              } catch (_) {
                                if (mounted) {
                                  setState(() => _processando = false);
                                  nav.pop(false);
                                }
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0F766E),
                                    Color(0xFF14B8A6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF14B8A6,
                                    ).withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Confirmar pagamento',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Botão fechar pós-confirmação
                if (_confirmou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Fechar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detalheLinha(String rotulo, String valor, {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 15 : 12.5,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// MODAL PREMIUM — ESCOLHER TIPO DE RECIBO
// ============================================================
class _EscolherTipoReciboModal extends StatefulWidget {
  const _EscolherTipoReciboModal({required this.cobranca});

  final CobrancaAssinatura cobranca;

  @override
  State<_EscolherTipoReciboModal> createState() =>
      _EscolherTipoReciboModalState();
}

class _EscolherTipoReciboModalState extends State<_EscolherTipoReciboModal>
    with SingleTickerProviderStateMixin {
  _TipoRecibo? _selecionado;
  bool _processando = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cobranca;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A0F2E).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Emitir Recibo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Escolha como deseja emitir o recibo desta cobrança.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                // Corpo — cards de opção
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    children: [
                      // Card: Enviar por E-mail
                      _cardOpcao(
                        icone: Icons.email_outlined,
                        titulo: 'Enviar por E-mail',
                        descricao:
                            'Envie um recibo completo em PDF para o e-mail cadastrado do lojista.',
                        selecionado: _selecionado == _TipoRecibo.email,
                        onTap: () =>
                            setState(() => _selecionado = _TipoRecibo.email),
                      ),
                      const SizedBox(height: 14),

                      // Card: Imprimir
                      _cardOpcao(
                        icone: Icons.print_outlined,
                        titulo: 'Imprimir',
                        descricao:
                            'Imprima um cupom de recibo em impressoras térmicas fiscais ou não fiscais.',
                        selecionado: _selecionado == _TipoRecibo.imprimir,
                        onTap: () =>
                            setState(() => _selecionado = _TipoRecibo.imprimir),
                      ),
                    ],
                  ),
                ),

                // Ações
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF0EEF7))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: const BorderSide(color: Color(0xFFE0DEE8)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _selecionado != null
                                  ? [
                                      const Color(0xFF6A1B9A),
                                      const Color(0xFF8E24AA),
                                    ]
                                  : [
                                      const Color(0xFFD0CDE0),
                                      const Color(0xFFD0CDE0),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _selecionado != null
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6A1B9A,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _selecionado == null
                                  ? null
                                  : () => _continuar(context, c),
                              child: Center(
                                child: Text(
                                  'Continuar',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardOpcao({
    required IconData icone,
    required String titulo,
    required String descricao,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selecionado
              ? const Color(0xFFF5F0FF)
              : const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selecionado
                ? const Color(0xFF6A1B9A)
                : const Color(0xFFEEEAF6),
            width: selecionado ? 2 : 1,
          ),
          boxShadow: selecionado
              ? [
                  BoxShadow(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selecionado
                    ? const Color(0xFF6A1B9A).withValues(alpha: 0.12)
                    : const Color(0xFFF0EDF6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icone,
                size: 24,
                color: selecionado
                    ? const Color(0xFF6A1B9A)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selecionado
                          ? const Color(0xFF6A1B9A)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descricao,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (selecionado)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF6A1B9A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _continuar(BuildContext context, CobrancaAssinatura c) async {
    if (_processando || _selecionado == null) return;

    if (_selecionado == _TipoRecibo.email) {
      // Confirmar envio por e-mail
      final confirmou = await _confirmarEnvioEmail(context, c);
      if (!confirmou || !mounted) return;

      setState(() => _processando = true);
      try {
        // Gerar PDF e enviar
        await _gerarReciboEmail(c);
        if (!mounted) return;
        await _mostrarSucessoEmail(context, c);
      } catch (e) {
        if (mounted) _snackErro('Falha ao enviar recibo: $e');
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    } else if (_selecionado == _TipoRecibo.imprimir) {
      // Confirmar impressão
      final confirmou = await _confirmarImpressao(context, c);
      if (!confirmou || !mounted) return;

      setState(() => _processando = true);
      try {
        await _gerarEImprimirRecibo(c);
        if (!mounted) return;
        await _mostrarSucessoImpressao(context, c);
      } catch (e) {
        if (mounted) _snackErro('Falha ao imprimir recibo: $e');
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    }
  }

  void _snackErro(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFF04438),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmarEnvioEmail(
    BuildContext context,
    CobrancaAssinatura c,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => _ConfirmarAcaoDialog(
            icone: Icons.email_outlined,
            corGradiente: const [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
            titulo: 'Confirmar envio',
            mensagem:
                'Deseja realmente enviar este recibo para o e-mail cadastrado do lojista?',
            detalhe: '${c.clienteNome} — ${c.clienteEmail}',
            textoConfirmar: 'Sim, enviar',
            textoCancelar: 'Não',
          ),
        ) ??
        false;
  }

  Future<bool> _confirmarImpressao(
    BuildContext context,
    CobrancaAssinatura c,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => _ConfirmarAcaoDialog(
            icone: Icons.print_outlined,
            corGradiente: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
            titulo: 'Confirmar impressão',
            mensagem: 'Deseja imprimir este recibo agora?',
            detalhe: '${c.fatura} — ${c.valorExibicao}',
            textoConfirmar: 'Sim, imprimir',
            textoCancelar: 'Não',
          ),
        ) ??
        false;
  }

  Future<void> _gerarReciboEmail(CobrancaAssinatura c) async {
    // Gerar PDF do recibo
    final pdfBytes = await _buildReciboPdf(c);

    // Converter para base64
    final pdfBase64 = base64Encode(pdfBytes);

    // Enviar via Cloud Function usando o SMTP do sistema
    await CobrancasAssinaturaService.enviarReciboEmail(
      cobrancaId: c.id,
      clienteEmail: c.clienteEmail,
      clienteNome: c.clienteNome,
      fatura: c.fatura,
      planoNome: c.planoNome,
      modulo: c.modulo.rotulo,
      valorExibicao: c.valorExibicao,
      vencimento: c.vencimentoExibicao,
      statusRotulo: c.status.rotulo,
      formaPagamento: '',
      dataPagamento: null,
      dataEmissao: DateTime.now().toIso8601String(),
      pdfBase64: pdfBase64,
    );
  }

  Future<void> _gerarEImprimirRecibo(CobrancaAssinatura c) async {
    final pdfBytes = await _buildReciboPdf(c, larguraMm: 80);
    await Printing.layoutPdf(
      name: 'Recibo ${c.fatura}',
      format: PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 5 * PdfPageFormat.mm,
      ),
      onLayout: (_) => pdfBytes,
    );
  }

  Future<Uint8List> _buildReciboPdf(
    CobrancaAssinatura c, {
    double larguraMm = 80,
  }) async {
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final estreito = larguraMm <= 58;

    final agora = DateTime.now();
    final dataHoraStr = DateFormat(
      "dd/MM/yyyy 'às' HH:mm",
      'pt_BR',
    ).format(agora);

    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          larguraMm * PdfPageFormat.mm,
          double.infinity,
          marginAll: (estreito ? 3.5 : 5) * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Logo / Nome
            pw.Center(
              child: pw.Text(
                'DiPertin',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 18,
                  color: PdfColors.purple700,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'RECIBO DE COBRANÇA',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: estreito ? 10 : 12,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '══════════════════════════════',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 8),

            // Dados do recibo
            _reciboLinha(
              font,
              fontBold,
              'Recibo nº',
              c.fatura,
              estreito,
              destaque: true,
            ),
            _reciboLinha(
              font,
              fontBold,
              'Data de emissão',
              dataHoraStr,
              estreito,
            ),
            _reciboLinha(
              font,
              fontBold,
              'Código',
              c.id.length > 12 ? c.id.substring(0, 12) : c.id,
              estreito,
            ),
            pw.SizedBox(height: 8),

            pw.Text(
              '──────────────────────────────',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),

            // Dados do cliente/lojista
            _reciboSecao(font, fontBold, 'DADOS DO LOJISTA', estreito),
            pw.SizedBox(height: 4),
            _reciboLinha(font, fontBold, 'Lojista', c.clienteNome, estreito),
            _reciboLinha(font, fontBold, 'E-mail', c.clienteEmail, estreito),
            pw.SizedBox(height: 8),

            pw.Text(
              '──────────────────────────────',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),

            // Dados do plano
            _reciboSecao(font, fontBold, 'DADOS DO PLANO', estreito),
            pw.SizedBox(height: 4),
            _reciboLinha(
              font,
              fontBold,
              'Plano',
              c.planoNome.isNotEmpty ? c.planoNome : c.modulo.rotulo,
              estreito,
            ),
            _reciboLinha(font, fontBold, 'Módulo', c.modulo.rotulo, estreito),
            _reciboLinha(
              font,
              fontBold,
              'Vencimento',
              c.vencimentoExibicao,
              estreito,
            ),

            pw.SizedBox(height: 8),
            pw.Text(
              '──────────────────────────────',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),

            // Financeiro
            _reciboSecao(font, fontBold, 'FINANCEIRO', estreito),
            pw.SizedBox(height: 4),
            _reciboLinha(
              font,
              fontBold,
              'Valor',
              moeda.format(c.valor),
              estreito,
              destaque: true,
            ),
            _reciboLinha(font, fontBold, 'Status', c.status.rotulo, estreito),

            pw.SizedBox(height: 8),
            pw.Text(
              '══════════════════════════════',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),

            // Total destacado
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: estreito ? 13 : 16,
                  ),
                ),
                pw.Text(
                  moeda.format(c.valor),
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: estreito ? 13 : 16,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '══════════════════════════════',
              style: pw.TextStyle(font: font, fontSize: estreito ? 8 : 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 10),

            // Mensagem de agradecimento
            pw.Center(
              child: pw.Text(
                'Obrigado pela preferência!',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: estreito ? 9 : 11,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Recibo gerado através do',
                style: pw.TextStyle(font: font, fontSize: estreito ? 7 : 8),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'DiPertin Gestão Comercial',
                style: pw.TextStyle(font: fontBold, fontSize: estreito ? 7 : 8),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'www.dipertin.com.br',
                style: pw.TextStyle(font: font, fontSize: estreito ? 7 : 8),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Impresso em $dataHoraStr',
                style: pw.TextStyle(font: font, fontSize: estreito ? 6 : 7),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _reciboSecao(
    pw.Font font,
    pw.Font fontBold,
    String titulo,
    bool estreito,
  ) {
    return pw.Text(
      titulo,
      style: pw.TextStyle(font: fontBold, fontSize: estreito ? 8 : 10),
    );
  }

  pw.Widget _reciboLinha(
    pw.Font font,
    pw.Font fontBold,
    String rotulo,
    String valor,
    bool estreito, {
    bool destaque = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            rotulo,
            style: pw.TextStyle(font: font, fontSize: estreito ? 7 : 8),
          ),
          pw.Spacer(),
          pw.Text(
            valor,
            style: pw.TextStyle(
              font: destaque ? fontBold : font,
              fontSize: destaque ? (estreito ? 9 : 11) : (estreito ? 7 : 8),
              fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarSucessoEmail(
    BuildContext context,
    CobrancaAssinatura c,
  ) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _SucessoDialog(
        icone: Icons.check_circle_rounded,
        titulo: 'E-mail enviado com sucesso',
        mensagem:
            'O recibo foi enviado com sucesso para o e-mail cadastrado do lojista.',
        detalhe: c.clienteEmail,
        corIcone: const Color(0xFF16A34A),
        corBotao: const Color(0xFF6A1B9A),
      ),
    );
  }

  Future<void> _mostrarSucessoImpressao(
    BuildContext context,
    CobrancaAssinatura c,
  ) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _SucessoDialog(
        icone: Icons.print_rounded,
        titulo: 'Recibo enviado para impressão',
        mensagem: 'O recibo foi enviado com sucesso para a impresora.',
        detalhe: c.fatura,
        corIcone: const Color(0xFF16A34A),
        corBotao: const Color(0xFF0F766E),
      ),
    );
  }
}

enum _TipoRecibo { email, imprimir }

// ─── DIÁLOGO DE CONFIRMAÇÃO GENÉRICO ────────────────────────────────────────
class _ConfirmarAcaoDialog extends StatelessWidget {
  const _ConfirmarAcaoDialog({
    required this.icone,
    required this.corGradiente,
    required this.titulo,
    required this.mensagem,
    this.detalhe,
    required this.textoConfirmar,
    required this.textoCancelar,
  });

  final IconData icone;
  final List<Color> corGradiente;
  final String titulo;
  final String mensagem;
  final String? detalhe;
  final String textoConfirmar;
  final String textoCancelar;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A0F2E).withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: corGradiente),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone, size: 28, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    titulo,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (detalhe != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F7FC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEEAF6)),
                      ),
                      child: Text(
                        detalhe!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6A1B9A),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0EEF7))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: const BorderSide(color: Color(0xFFE0DEE8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        textoCancelar,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: corGradiente.first,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        textoConfirmar,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DIÁLOGO DE SUCESSO GENÉRICO ────────────────────────────────────────────
class _SucessoDialog extends StatelessWidget {
  const _SucessoDialog({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    this.detalhe,
    required this.corIcone,
    required this.corBotao,
  });

  final IconData icone;
  final String titulo;
  final String mensagem;
  final String? detalhe;
  final Color corIcone;
  final Color corBotao;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A0F2E).withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: corIcone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, size: 34, color: corIcone),
              ),
              const SizedBox(height: 18),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              if (detalhe != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7FC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    detalhe!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6A1B9A),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: corBotao,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MODAL PREMIUM — CANCELAR COBRANÇA
// ============================================================
class _CancelarCobrancaModal extends StatefulWidget {
  const _CancelarCobrancaModal({
    required this.cobranca,
    required this.onConfirmar,
  });

  final CobrancaAssinatura cobranca;
  final Future<void> Function() onConfirmar;

  @override
  State<_CancelarCobrancaModal> createState() => _CancelarCobrancaModalState();
}

class _CancelarCobrancaModalState extends State<_CancelarCobrancaModal>
    with SingleTickerProviderStateMixin {
  bool _processando = false;
  bool _confirmou = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cobranca;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A0F2E).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header gradiente
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Ícone de alerta
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cancel_outlined,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Cancelar cobrança',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Esta ação é irreversível e cancelará a fatura permanentemente.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                // Corpo
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card com detalhes da cobrança
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEEEAF6)),
                        ),
                        child: Column(
                          children: [
                            _detalheLinha('Fatura', c.fatura, destaque: true),
                            const SizedBox(height: 8),
                            _detalheLinha('Cliente', c.clienteNome),
                            const SizedBox(height: 8),
                            _detalheLinha(
                              'Plano',
                              c.planoNome.isNotEmpty
                                  ? c.planoNome
                                  : c.modulo.rotulo,
                            ),
                            const SizedBox(height: 8),
                            _detalheLinha('Valor', c.valorExibicao),
                            const SizedBox(height: 8),
                            _detalheLinha('Vencimento', c.vencimentoExibicao),
                            const SizedBox(height: 8),
                            _detalheLinha('Status', c.status.rotulo),
                          ],
                        ),
                      ),

                      // Alerta de confirmação
                      if (!_processando && !_confirmou) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFFFF8F00,
                              ).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: const Color(0xFFFF8F00),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'O cancelamento desativará esta cobrança e não poderá ser desfeito.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF7C3E00),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Loading
                      if (_processando)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Color(0xFF6A1B9A),
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        ),

                      // Feedback sucesso
                      if (_confirmou) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 28,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${c.fatura} cancelada',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Ações
                if (!_processando && !_confirmou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF0EEF7))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFE0DEE8)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Voltar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _processando
                              ? const SizedBox(
                                  height: 48,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF6A1B9A),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: () async {
                                    setState(() => _processando = true);
                                    final nav = Navigator.of(context);
                                    try {
                                      await widget.onConfirmar();
                                      if (!mounted) return;
                                      setState(() => _confirmou = true);
                                      await Future.delayed(
                                        const Duration(seconds: 1),
                                      );
                                      if (mounted) {
                                        nav.pop(true);
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        setState(() => _processando = false);
                                        nav.pop(false);
                                      }
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFF04438),
                                          Color(0xFFDC2626),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFF04438,
                                          ).withValues(alpha: 0.35),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      'Sim, cancelar cobrança',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                // Botão fechar pós-confirmação
                if (_confirmou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Fechar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detalheLinha(String rotulo, String valor, {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 15 : 12.5,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// MODAL PREMIUM — ENVIAR COBRANÇA POR E-MAIL
// ============================================================
class _EnviarCobrancaModal extends StatefulWidget {
  const _EnviarCobrancaModal({
    required this.cobranca,
    required this.onEnviar,
  });

  final CobrancaAssinatura cobranca;
  final Future<void> Function(String mensagemPersonalizada) onEnviar;

  @override
  State<_EnviarCobrancaModal> createState() => _EnviarCobrancaModalState();
}

class _EnviarCobrancaModalState extends State<_EnviarCobrancaModal>
    with SingleTickerProviderStateMixin {
  bool _processando = false;
  bool _enviou = false;
  String? _erro;
  final _mensagemCtrl = TextEditingController();
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _mensagemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cobranca;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A0F2E).withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header gradiente
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Enviar cobrança',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A fatura será enviada para o e-mail do lojista.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),

                // Corpo
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card com detalhes da cobrança
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEEEAF6)),
                        ),
                        child: Column(
                          children: [
                            _infoLinha('Fatura', c.fatura, destaque: true),
                            const SizedBox(height: 8),
                            _infoLinha('Lojista', c.clienteNome),
                            const SizedBox(height: 8),
                            _infoLinha('E-mail', c.clienteEmail),
                            const SizedBox(height: 8),
                            _infoLinha(
                              'Plano',
                              c.planoNome.isNotEmpty
                                  ? c.planoNome
                                  : c.modulo.rotulo,
                            ),
                            const SizedBox(height: 8),
                            _infoLinha('Valor', c.valorExibicao),
                            const SizedBox(height: 8),
                            _infoLinha('Vencimento', c.vencimentoExibicao),
                            const SizedBox(height: 8),
                            _infoLinha('Status', c.status.rotulo),
                          ],
                        ),
                      ),

                      // Campo de mensagem personalizada
                      if (!_processando && !_enviou) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Mensagem personalizada (opcional)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _mensagemCtrl,
                          maxLines: 3,
                          maxLength: 500,
                          decoration: InputDecoration(
                            hintText:
                                'Escreva uma mensagem adicional para o lojista…',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF94A3B8),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8F7FC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE0DEE8),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFFE0DEE8),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF6A1B9A),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                      ],

                      // Erro
                      if (_erro != null && !_enviou) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFF04438)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: Color(0xFFF04438),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _erro!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF991B1B),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Loading
                      if (_processando) ...[
                        const SizedBox(height: 24),
                        const Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF6A1B9A),
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Enviando cobrança…',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Feedback sucesso
                      if (_enviou) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 32,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Cobrança enviada!',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${c.clienteNome} receberá a fatura no e-mail ${c.clienteEmail}.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Ações
                if (!_processando && !_enviou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Color(0xFFF0EEF7)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFE0DEE8)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _enviarCobranca,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6A1B9A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                            child: Text(
                              'Enviar cobrança',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Botão fechar pós-envio
                if (_enviou)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Fechar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enviarCobranca() async {
    if (_processando) return;
    setState(() {
      _processando = true;
      _erro = null;
    });
    try {
      await widget.onEnviar(_mensagemCtrl.text.trim());
      if (!mounted) return;
      setState(() => _enviou = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is Exception
            ? (e.toString().replaceFirst('Exception: ', ''))
            : 'Falha ao enviar cobrança. Tente novamente.';
      });
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Widget _infoLinha(String rotulo, String valor, {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 15 : 12.5,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }
}
