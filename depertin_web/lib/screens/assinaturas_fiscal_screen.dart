import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/fiscal_document_model.dart';
import '../services/fiscal/fiscal_admin_service.dart';
import '../theme/painel_admin_theme.dart';

// ═══════════════════════════════════════════════════════════════
// TOKENS DE COR — Padrão DiPertin (top-level para const)
// ═══════════════════════════════════════════════════════════════
const Color _roxo = DiPertinTheme.primaryRoxo;
const Color _roxoClaro = DiPertinTheme.primaryRoxoClaro;
const Color _roxoMedio = DiPertinTheme.primaryRoxoMedio;
const Color _laranja = DiPertinTheme.secondaryLaranja;
const Color _textoPrimario = DiPertinTheme.textPrimary;
const Color _textoSecundario = DiPertinTheme.textSecondary;
const Color _fundo = DiPertinTheme.backgroundFundo;
const Color _verde = Color(0xFF16A34A);
const Color _verdeFundo = Color(0xFFE8F5E9);
const Color _vermelho = Color(0xFFDC2626);
const Color _vermelhoFundo = Color(0xFFFEF2F2);
const Color _amarelo = Color(0xFFF59E0B);
const Color _amareloFundo = Color(0xFFFFF8E1);
const Color _cinza = Color(0xFF94A3B8);
const Color _cinzaFundo = Color(0xFFF1F5F9);
const Color _roxoFundo = Color(0xFFF1E9FF);
const Color _bordaCard = Color(0xFFEEEAF6);

// ═══════════════════════════════════════════════════════════════
// TELA PRINCIPAL — MONITOR FISCAL (ADMIN) — PREMIUM
// ═══════════════════════════════════════════════════════════════
class AssinaturasFiscalScreen extends StatefulWidget {
  const AssinaturasFiscalScreen({super.key});

  @override
  State<AssinaturasFiscalScreen> createState() =>
      _AssinaturasFiscalScreenState();
}

class _AssinaturasFiscalScreenState extends State<AssinaturasFiscalScreen> {
  static final _fmtInt = NumberFormat.decimalPattern('pt_BR');
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  // ─── Dados ──────────────────────────────────────────────────
  AdminFiscalResumo _resumo = const AdminFiscalResumo(
    totalDocumentos: 0,
    totalAutorizadas: 0,
    totalRejeitadas: 0,
    totalCanceladas: 0,
    totalPendentes: 0,
    totalContingencia: 0,
    totalLojasComEmissao: 0,
  );
  List<AdminFiscalLojaResumo> _lojas = [];
  List<FiscalDocumentModel> _docsRecentes = [];

  // ─── Aba ativa ─────────────────────────────────────────────
  int _abaIndex = 0; // 0 = Lojas, 1 = Timeline

  // ─── Filtros ───────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _filtroStatus = 'todos';
  String _filtroPeriodo = 'todos';

  // ─── Seleção / Paginação ────────────────────────────────────
  int _paginaAtual = 0;
  int _itensPorPagina = 10;

  // ─── Cache de nomes de lojas ────────────────────────────────
  final Map<String, _StoreInfo> _storeCache = {};

  // ─── Subscriptions ─────────────────────────────────────────
  StreamSubscription<AdminFiscalResumo>? _subResumo;
  StreamSubscription<List<AdminFiscalLojaResumo>>? _subLojas;
  StreamSubscription<List<FiscalDocumentModel>>? _subDocs;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _subResumo = FiscalAdminService.streamResumo().listen(
      (r) {
        if (!mounted) return;
        setState(() => _resumo = r);
      },
      onError: (_) {},
    );
    _subLojas = FiscalAdminService.streamLojasComEmissao().listen(
      (lista) {
        if (!mounted) return;
        setState(() => _lojas = lista);
        _resolverNomesLojas(lista);
      },
      onError: (_) {},
    );
    _subDocs = FiscalAdminService.streamDocumentosRecentes().listen(
      (lista) {
        if (!mounted) return;
        setState(() => _docsRecentes = lista);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _subResumo?.cancel();
    _subLojas?.cancel();
    _subDocs?.cancel();
    super.dispose();
  }

  // ─── Resolve nomes de lojas do Firestore ──────────────────
  Future<void> _resolverNomesLojas(List<AdminFiscalLojaResumo> lojas) async {
    for (final loja in lojas) {
      final storeId = loja.storeId;
      if (_storeCache.containsKey(storeId)) {
        // Aplica nome do cache ao model
        final info = _storeCache[storeId]!;
        loja.storeName = info.nome;
        continue;
      }
      _storeCache[storeId] = _StoreInfo(nome: storeId, carregando: true);
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(storeId)
            .get();
        if (userDoc.exists) {
          final u = userDoc.data()!;
          final nome = (u['nome_fantasia'] as String?)?.trim() ??
              (u['nome_loja'] as String?)?.trim() ??
              (u['loja_nome'] as String?)?.trim() ??
              (u['nome'] as String?)?.trim() ??
              storeId;
          final cnpj = u['cnpj'] as String? ?? '';
          final cidade = u['cidade'] as String? ?? '';
          final uf = u['uf'] as String? ?? u['estado'] as String? ?? '';
          _storeCache[storeId] = _StoreInfo(
            nome: nome,
            cnpj: cnpj,
            cidade: cidade,
            uf: uf,
            carregando: false,
          );
          loja.storeName = nome;
        } else {
          _storeCache[storeId] = _StoreInfo(nome: storeId, carregando: false);
        }
      } catch (_) {
        _storeCache[storeId] = _StoreInfo(nome: storeId, carregando: false);
      }
    }
    if (mounted) setState(() {});
  }

  _StoreInfo _storeInfo(String storeId) {
    return _storeCache[storeId] ??
        _StoreInfo(nome: storeId, carregando: true);
  }

  // ─── Filtragem ─────────────────────────────────────────────
  List<AdminFiscalLojaResumo> get _lojasFiltradas {
    var r = _lojas.toList();
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      r = r.where((l) {
        final info = _storeInfo(l.storeId);
        return info.nome.toLowerCase().contains(q) ||
            info.cnpj.toLowerCase().contains(q) ||
            (l.provedor?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return r;
  }

  List<AdminFiscalLojaResumo> get _lojasPagina {
    final lista = _lojasFiltradas;
    final start = _paginaAtual * _itensPorPagina;
    if (start >= lista.length && lista.isNotEmpty) {
      _paginaAtual = 0;
      return _lojasFiltradas
          .sublist(0, _itensPorPagina.clamp(0, _lojasFiltradas.length));
    }
    final end = (start + _itensPorPagina).clamp(0, lista.length);
    return lista.sublist(start, end);
  }

  int get _totalPaginas =>
      (_lojasFiltradas.length / _itensPorPagina).ceil().clamp(1, 999);

  // ─── Helpers de status ─────────────────────────────────────
  static Color _statusCor(String status) {
    switch (status) {
      case 'autorizada':
        return _verde;
      case 'rejeitada':
        return _vermelho;
      case 'cancelada':
      case 'cancelamento_homologado':
        return _cinza;
      case 'processando':
        return _amarelo;
      case 'contingencia':
        return _laranja;
      default:
        return _textoSecundario;
    }
  }

  static Color _statusFundo(String status) {
    switch (status) {
      case 'autorizada':
        return _verdeFundo;
      case 'rejeitada':
        return _vermelhoFundo;
      case 'cancelada':
      case 'cancelamento_homologado':
        return _cinzaFundo;
      case 'processando':
        return _amareloFundo;
      case 'contingencia':
        return _amareloFundo;
      default:
        return _roxoFundo;
    }
  }

  static String _statusRotulo(String status) {
    switch (status) {
      case StatusFiscal.autorizada:
        return 'Autorizada';
      case StatusFiscal.rejeitada:
        return 'Rejeitada';
      case StatusFiscal.cancelada:
        return 'Cancelada';
      case StatusFiscal.cancelamentoHomologado:
        return 'Cancelamento homologado';
      case StatusFiscal.processando:
        return 'Processando';
      case StatusFiscal.contingencia:
        return 'Contingência';
      case StatusFiscal.contingenciaResolvida:
        return 'Contingência resolvida';
      case StatusFiscal.ccEnviada:
        return 'CC-e enviada';
      case StatusFiscal.numeracaoInutilizada:
        return 'Numeração inutilizada';
      default:
        return status;
    }
  }

  Widget _badge(String texto, Color cor, Color fundo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withAlpha(51)),
      ),
      child: Text(texto,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cor,
              height: 1.2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _statusBadge(String status) {
    return _badge(
        _statusRotulo(status), _statusCor(status), _statusFundo(status));
  }

  String _mascararCnpj(String cnpj) {
    if (cnpj.length != 14) return cnpj;
    return '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/${cnpj.substring(8, 12)}-${cnpj.substring(12)}';
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildTabs(),
            const SizedBox(height: 20),
            if (_abaIndex == 0) _buildConteudoLojas() else _buildConteudoTimeline(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HEADER PREMIUM
  // ═══════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: _roxo.withAlpha(15),
              blurRadius: 20,
              offset: const Offset(0, 6)),
          BoxShadow(
              color: _roxo.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [_roxo, _roxoClaro], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: _roxo.withAlpha(50),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            alignment: Alignment.center,
            child:
                const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Monitor Fiscal NF-e',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _textoPrimario,
                      height: 1.2)),
              const SizedBox(height: 4),
              Text(
                  'Acompanhe todas as notas fiscais emitidas pelos lojistas em tempo real.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _textoSecundario, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _resumo.totalDocumentos > 0 ? _verdeFundo : _cinzaFundo,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _resumo.totalDocumentos > 0
                      ? _verde.withAlpha(40)
                      : _cinza.withAlpha(40)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _resumo.totalDocumentos > 0
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: _resumo.totalDocumentos > 0 ? _verde : _cinza,
              ),
              const SizedBox(width: 6),
              Text(
                _resumo.totalDocumentos > 0
                    ? '${_fmtInt.format(_resumo.totalDocumentos)} documento${_resumo.totalDocumentos == 1 ? '' : 's'}'
                    : 'Nenhum documento',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _resumo.totalDocumentos > 0 ? _verde : _cinza),
              ),
            ]),
          ),
          const SizedBox(width: 4),
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_roxo, _laranja],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SUMMARY CARDS PREMIUM
  // ═══════════════════════════════════════════════════════════
  Widget _buildSummaryCards() {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final colW = w > 1300
          ? (w - 80) / 5
          : w > 1000
              ? (w - 48) / 3
              : w > 650
                  ? (w - 16) / 2
                  : w;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        SizedBox(
            width: colW,
            child: _SummaryCard(
              icone: Icons.description_rounded,
              cor: _roxo,
              titulo: 'Total de documentos',
              valor: _fmtInt.format(_resumo.totalDocumentos),
              subtexto:
                  '${_fmtInt.format(_resumo.totalLojasComEmissao)} loja${_resumo.totalLojasComEmissao == 1 ? '' : 's'}',
              sparklineDados: [],
            )),
        SizedBox(
            width: colW,
            child: _SummaryCard(
              icone: Icons.check_circle_rounded,
              cor: _verde,
              titulo: 'Autorizadas',
              valor: _fmtInt.format(_resumo.totalAutorizadas),
              subtexto:
                  '${_resumo.totalDocumentos > 0 ? (_resumo.totalAutorizadas * 100 ~/ _resumo.totalDocumentos) : 0}% do total',
              sparklineDados: [],
            )),
        SizedBox(
            width: colW,
            child: _SummaryCard(
              icone: Icons.cancel_rounded,
              cor: _vermelho,
              titulo: 'Rejeitadas',
              valor: _fmtInt.format(_resumo.totalRejeitadas),
              subtexto:
                  '${_resumo.totalDocumentos > 0 ? (_resumo.totalRejeitadas * 100 ~/ _resumo.totalDocumentos) : 0}% do total',
              sparklineDados: [],
            )),
        SizedBox(
            width: colW,
            child: _SummaryCard(
              icone: Icons.block_rounded,
              cor: _cinza,
              titulo: 'Canceladas',
              valor: _fmtInt.format(_resumo.totalCanceladas),
              subtexto:
                  '${_resumo.totalDocumentos > 0 ? (_resumo.totalCanceladas * 100 ~/ _resumo.totalDocumentos) : 0}% do total',
              sparklineDados: [],
            )),
        SizedBox(
            width: colW,
            child: _SummaryCard(
              icone: Icons.store_rounded,
              cor: _laranja,
              titulo: 'Lojas com emissão',
              valor: _fmtInt.format(_resumo.totalLojasComEmissao),
              subtexto: 'Emissões ativas',
              sparklineDados: [],
            )),
      ]);
    });
  }

  // ═══════════════════════════════════════════════════════════
  // TABS PREMIUM
  // ═══════════════════════════════════════════════════════════
  Widget _buildTabs() {
    final tabs = ['Lojas', 'Timeline'];
    final icons = [Icons.store_rounded, Icons.history_rounded];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: _roxo.withAlpha(15),
              blurRadius: 12,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: _roxo.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final sel = _abaIndex == i;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() {
                  _abaIndex = i;
                  _paginaAtual = 0;
                }),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: sel
                        ? const LinearGradient(colors: [_roxo, _roxoClaro],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: _roxo.withAlpha(64),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ]
                        : null,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i],
                            size: 18,
                            color: sel ? Colors.white : _textoSecundario),
                        const SizedBox(width: 8),
                        Text(tabs[i],
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    sel ? Colors.white : _textoSecundario)),
                      ]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CONTEÚDO — ABA LOJAS (REFATORADO)
  // ═══════════════════════════════════════════════════════════
  Widget _buildConteudoLojas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFiltrosLinha(),
        const SizedBox(height: 16),
        _buildActionBar(),
        const SizedBox(height: 12),
        _buildTabelaLojas(),
        const SizedBox(height: 16),
        _buildPaginacao(),
      ],
    );
  }

  Widget _buildFiltrosLinha() {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 800;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            flex: compact ? 1 : 3,
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _textoPrimario),
                decoration: InputDecoration(
                  hintText: 'Buscar por loja, CNPJ ou provedor...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _textoSecundario.withAlpha(153)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: Color(0xFF64748B)),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => _searchCtrl.clear())
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE9E8F0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE9E8F0))),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _roxo, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            _filtroDropdown(
              valor: _filtroStatus,
              itens: const [
                'todos',
                'autorizada',
                'rejeitada',
                'cancelada',
                'processando'
              ],
              rotulos: const [
                'Status',
                'Autorizadas',
                'Rejeitadas',
                'Canceladas',
                'Pendentes'
              ],
              onChanged: (v) => setState(() => _filtroStatus = v!),
            ),
            const SizedBox(width: 10),
            _filtroDropdown(
              valor: _filtroPeriodo,
              itens: const ['todos', 'hoje', '7d', '30d', '90d'],
              rotulos: const [
                'Período',
                'Hoje',
                'Últimos 7 dias',
                'Últimos 30 dias',
                'Últimos 90 dias'
              ],
              onChanged: (v) => setState(() => _filtroPeriodo = v!),
            ),
          ],
        ]),
        if (compact) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filtroDropdown(
                valor: _filtroStatus,
                itens: const ['todos', 'autorizada', 'rejeitada', 'cancelada'],
                rotulos: const [
                  'Status',
                  'Autorizadas',
                  'Rejeitadas',
                  'Canceladas'
                ],
                onChanged: (v) => setState(() => _filtroStatus = v!),
              ),
              const SizedBox(width: 8),
              _filtroDropdown(
                valor: _filtroPeriodo,
                itens: const ['todos', 'hoje', '7d', '30d'],
                rotulos: const ['Período', 'Hoje', '7 dias', '30 dias'],
                onChanged: (v) => setState(() => _filtroPeriodo = v!),
              ),
            ]),
          ),
        ],
      ]);
    });
  }

  Widget _filtroDropdown({
    required String valor,
    required List<String> itens,
    required List<String> rotulos,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 42,
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE9E8F0))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isDense: true,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoPrimario),
          icon: const Icon(Icons.expand_more_rounded,
              size: 18, color: Color(0xFF64748B)),
          items: List.generate(
              itens.length,
              (i) => DropdownMenuItem(
                    value: itens[i],
                    child: Text(rotulos[i],
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: itens[i] == valor
                                ? FontWeight.w600
                                : FontWeight.w400)),
                  )),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ─── Action Bar ───────────────────────────────────────────
  Widget _buildActionBar() {
    final total = _lojasFiltradas.length;
    return Row(
      children: [
        Icon(Icons.store_rounded, size: 16, color: _roxo),
        const SizedBox(width: 8),
        Text(
          '${_fmtInt.format(total)} loja${total == 1 ? '' : 's'} encontrada${total == 1 ? '' : 's'}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _textoSecundario)),
        const Spacer(),
        if (_filtroStatus != 'todos' || _filtroPeriodo != 'todos')
          InkWell(
            onTap: () {
              setState(() {
                _filtroStatus = 'todos';
                _filtroPeriodo = 'todos';
                _searchCtrl.clear();
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _roxo.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt_off_rounded,
                      size: 14, color: _roxo),
                  const SizedBox(width: 4),
                  Text('Limpar filtros',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _roxo)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── TABELA DE LOJAS PREMIUM ──────────────────────────────
  Widget _buildTabelaLojas() {
    final lojas = _lojasPagina;
    if (lojas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _roxo.withAlpha(15),
                blurRadius: 20,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: _roxo.withAlpha(8),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
            child: Column(children: [
          Icon(Icons.store_mall_directory_rounded,
              size: 56, color: _textoSecundario.withAlpha(77)),
          const SizedBox(height: 16),
          Text('Nenhuma loja com emissão',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textoSecundario)),
          const SizedBox(height: 6),
          Text('As lojas que emitirem NF-e aparecerão aqui.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoSecundario)),
        ])),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final tableWidth =
          constraints.maxWidth > 1000 ? constraints.maxWidth : 1000.0;

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _roxo.withAlpha(15),
                blurRadius: 20,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: _roxo.withAlpha(8),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTableHeaderLoja(),
                ...List.generate(
                    lojas.length, (i) => _buildTableRowLoja(lojas[i], i)),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTableHeaderLoja() {
    return Column(children: [
      Container(
        padding:
            const EdgeInsets.only(left: 16, right: 24, top: 12, bottom: 12),
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(colors: [_roxo, _roxoMedio], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Row(children: [
          _colHeader('Loja', flex: 24, cor: Colors.white),
          _colHeader('Total NF-es', flex: 10, cor: Colors.white),
          _colHeader('Autorizadas', flex: 10, cor: Colors.white),
          _colHeader('Rejeitadas', flex: 10, cor: Colors.white),
          _colHeader('Canceladas', flex: 10, cor: Colors.white),
          _colHeader('Pendentes', flex: 10, cor: Colors.white),
          _colHeader('Última emissão', flex: 14, cor: Colors.white),
          _colHeader('Provedor', flex: 12, cor: Colors.white),
          const SizedBox(width: 40),
        ]),
      ),
      // Linha inferior com gradiente
      Container(
        height: 2.5,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_roxo, _roxoClaro, _laranja],
              begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
      ),
    ]);
  }

  Widget _buildTableRowLoja(AdminFiscalLojaResumo loja, int index) {
    final info = _storeInfo(loja.storeId);
    final pctAutorizadas = loja.total > 0
        ? (loja.autorizadas * 100 ~/ loja.total)
        : 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      curve: Curves.easeOut,
      builder: (context, anim, _) => Opacity(
        opacity: anim,
        child: Container(
          decoration: BoxDecoration(
            color: index.isOdd ? _fundo : Colors.white,
            border:
                Border(bottom: BorderSide(color: _bordaCard.withAlpha(179))),
          ),
          child: InkWell(
            onTap: () => _abrirDetalhesLoja(loja, info),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 24, 14),
              child: Row(children: [
                // Loja (agora com nome resolvido + CNPJ)
                Expanded(
                  flex: 24,
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _roxoFundo,
                      child: Text(
                        info.nome.isNotEmpty
                            ? info.nome[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _roxo),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.nome,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _textoPrimario,
                                  height: 1.3),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (info.cnpj.isNotEmpty)
                                Text(
                                  _mascararCnpj(info.cnpj),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10, color: _textoSecundario),
                                ),
                              if (info.cnpj.isNotEmpty &&
                                  info.cidade.isNotEmpty)
                                const SizedBox(width: 6),
                              if (info.cidade.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    '${info.cidade}${info.uf.isNotEmpty ? '/${info.uf}' : ''}',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10, color: _textoSecundario),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),

                // Total
                Expanded(
                  flex: 10,
                  child: Center(
                      child: Text(_fmtInt.format(loja.total),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textoPrimario))),
                ),

                // Autorizadas (com %)
                Expanded(
                  flex: 10,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_fmtInt.format(loja.autorizadas),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _verde)),
                        const SizedBox(height: 1),
                        Text('$pctAutorizadas%',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 9, color: _textoSecundario)),
                      ],
                    ),
                  ),
                ),

                // Rejeitadas
                Expanded(
                  flex: 10,
                  child: Center(
                      child: Text(_fmtInt.format(loja.rejeitadas),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _vermelho))),
                ),

                // Canceladas
                Expanded(
                  flex: 10,
                  child: Center(
                      child: Text(_fmtInt.format(loja.canceladas),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _cinza))),
                ),

                // Pendentes
                Expanded(
                  flex: 10,
                  child: Center(
                      child: Text(_fmtInt.format(loja.pendentes),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _amarelo))),
                ),

                // Última emissão
                Expanded(
                  flex: 14,
                  child: Center(
                      child: Text(
                    loja.ultimaEmissao != null
                        ? _dateFormat.format(loja.ultimaEmissao!.toDate())
                        : '—',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: _textoSecundario),
                  )),
                ),

                // Provedor
                Expanded(
                  flex: 12,
                  child: Center(
                      child: _badge(
                    loja.provedor ?? '—',
                    _roxo,
                    _roxoFundo,
                  )),
                ),

                // Menu de ações
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded,
                      color: _textoSecundario, size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  color: Colors.white,
                  onSelected: (action) =>
                      _handleAcaoLoja(action, loja, info),
                  itemBuilder: (_) => _menuAcoesLoja(loja),
                  offset: const Offset(0, 32),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _colHeader(String label, {int flex = 1, Color cor = _roxo}) {
    return Expanded(
      flex: flex,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cor,
                letterSpacing: 0.5)),
      ]),
    );
  }

  // ─── MENU DE AÇÕES POR LOJA ───────────────────────────────
  List<PopupMenuEntry<String>> _menuAcoesLoja(AdminFiscalLojaResumo loja) {
    return [
      const _MenuGroupLabel('VISUALIZAÇÃO'),
      const PopupMenuItem(
        value: 'detalhes',
        child: _ActionRow(Icons.info_outline_rounded,
            'Visualizar detalhes', _roxo),
      ),
      const PopupMenuItem(
        value: 'historico',
        child: _ActionRow(Icons.history_rounded,
            'Ver histórico', Color(0xFF6366F1)),
      ),
      if (loja.total > 0) ...[
        const PopupMenuDivider(height: 8),
        const _MenuGroupLabel('DOCUMENTOS'),
        const PopupMenuItem(
          value: 'xml',
          child: _ActionRow(Icons.code_rounded,
              'Consultar XML', Color(0xFF059669)),
        ),
        const PopupMenuItem(
          value: 'danfe',
          child: _ActionRow(Icons.picture_as_pdf_rounded,
              'Baixar DANFE', Color(0xFFDC2626)),
        ),
      ],
    ];
  }

  void _handleAcaoLoja(
      String action, AdminFiscalLojaResumo loja, _StoreInfo info) {
    switch (action) {
      case 'detalhes':
        _abrirDetalhesLoja(loja, info);
        break;
      case 'historico':
        setState(() => _abaIndex = 1);
        break;
      case 'xml':
      case 'danfe':
        _mostrarSnack(
            'Selecione um documento na aba "Timeline" para ${action == 'xml' ? 'baixar o XML' : 'baixar o DANFE'}.');
        break;
    }
  }

  // ─── MODAL DETALHES LOJA PREMIUM ──────────────────────────
  void _abrirDetalhesLoja(AdminFiscalLojaResumo loja, _StoreInfo info) {
    final pctAutorizadas =
        loja.total > 0 ? (loja.autorizadas * 100 ~/ loja.total) : 0;
    final pctRejeitadas =
        loja.total > 0 ? (loja.rejeitadas * 100 ~/ loja.total) : 0;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Header gradiente
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_roxo, _roxoMedio],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.store_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.nome,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (info.cnpj.isNotEmpty)
                                Text(
                                  _mascararCnpj(info.cnpj),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.white.withAlpha(200),
                                  ),
                                ),
                              if (info.cnpj.isNotEmpty &&
                                  info.cidade.isNotEmpty)
                                const SizedBox(width: 12),
                              if (info.cidade.isNotEmpty)
                                Text(
                                  '${info.cidade}${info.uf.isNotEmpty ? '/${info.uf}' : ''}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: Colors.white.withAlpha(200),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Indicadores
                      _buildDetalheSecao(
                        titulo: 'Indicadores de Emissão',
                        icone: Icons.bar_chart_rounded,
                        corIcone: _roxo,
                        children: [
                          _detailRow('Total NF-es',
                              _fmtInt.format(loja.total)),
                          _detailRow('Autorizadas',
                              '${_fmtInt.format(loja.autorizadas)} ($pctAutorizadas%)'),
                          _detailRow('Rejeitadas',
                              '${_fmtInt.format(loja.rejeitadas)} ($pctRejeitadas%)'),
                          _detailRow('Canceladas',
                              _fmtInt.format(loja.canceladas)),
                          _detailRow('Pendentes',
                              _fmtInt.format(loja.pendentes)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Dados da loja
                      _buildDetalheSecao(
                        titulo: 'Dados da Loja',
                        icone: Icons.business_rounded,
                        corIcone: _verde,
                        children: [
                          _detailRow('Provedor',
                              loja.provedor ?? 'Não configurado'),
                          _detailRow('Última emissão',
                              loja.ultimaEmissao != null
                                  ? _dateFormat
                                      .format(loja.ultimaEmissao!.toDate())
                                  : 'Nenhuma'),
                          _detailRow('Valor faturado',
                              'R\$ ${_fmtInt.format(loja.valorTotal.toInt())},00'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Botão ver histórico
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _abaIndex = 1);
                          },
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: Text('Ver histórico completo',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _roxo,
                            side: BorderSide(color: _roxo.withAlpha(80)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetalheSecao({
    required String titulo,
    required IconData icone,
    required Color corIcone,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fundo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bordaCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: corIcone.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, size: 16, color: corIcone),
              ),
              const SizedBox(width: 10),
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textoPrimario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: _textoSecundario)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _textoPrimario)),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: _roxo,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PAGINAÇÃO PREMIUM
  // ═══════════════════════════════════════════════════════════
  Widget _buildPaginacao() {
    final total = _lojasFiltradas.length;
    final inicio = _paginaAtual * _itensPorPagina + 1;
    final fim = ((_paginaAtual + 1) * _itensPorPagina).clamp(0, total);
    return Row(
      children: [
        Text(
          'Mostrando $inicio a $fim de ${_fmtInt.format(total)} loja${total == 1 ? '' : 's'}',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: _textoSecundario)),
        const Spacer(),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _pagBtn(Icons.chevron_left_rounded, _paginaAtual > 0, () {
            setState(() => _paginaAtual--);
          }),
          const SizedBox(width: 4),
          ...List.generate(_totalPaginas.clamp(1, 7), (i) {
            final pagina = _paginaAtual < 3 ? i : _paginaAtual + i - 3;
            if (pagina < 0 || pagina >= _totalPaginas) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _paginaAtual = pagina),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: pagina == _paginaAtual ? _roxo : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: pagina == _paginaAtual
                              ? _roxo
                              : _bordaCard),
                    ),
                    alignment: Alignment.center,
                    child: Text('${pagina + 1}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pagina == _paginaAtual
                              ? Colors.white
                              : _textoSecundario,
                        )),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          _pagBtn(
              Icons.chevron_right_rounded,
              _paginaAtual < _totalPaginas - 1,
              () {
            setState(() => _paginaAtual++);
          }),
        ]),
        const SizedBox(width: 16),
        _filtroDropdown(
          valor: _itensPorPagina.toString(),
          itens: const ['10', '20', '50'],
          rotulos: const ['10 por página', '20 por página', '50 por página'],
          onChanged: (v) {
            setState(() {
              _itensPorPagina = int.parse(v!);
              _paginaAtual = 0;
            });
          },
        ),
      ],
    );
  }

  Widget _pagBtn(IconData icone, bool habilitado, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _bordaCard),
          ),
          alignment: Alignment.center,
          child: Icon(icone,
              size: 18,
              color: habilitado
                  ? _textoPrimario
                  : _textoSecundario.withAlpha(77)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CONTEÚDO — ABA TIMELINE (REFATORADA)
  // ═══════════════════════════════════════════════════════════
  Widget _buildConteudoTimeline() {
    if (_docsRecentes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _roxo.withAlpha(15),
                blurRadius: 20,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: _roxo.withAlpha(8),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
            child: Column(children: [
          Icon(Icons.history_rounded,
              size: 56, color: _textoSecundario.withAlpha(77)),
          const SizedBox(height: 16),
          Text('Nenhum documento fiscal registrado',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textoSecundario)),
          const SizedBox(height: 6),
          Text(
              'Os documentos fiscais emitidos aparecerão aqui em ordem cronológica.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoSecundario)),
        ])),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: _roxo.withAlpha(15),
              blurRadius: 20,
              offset: const Offset(0, 6)),
          BoxShadow(
              color: _roxo.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // Timeline header
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_roxo, _roxoMedio],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Row(children: [
            _timelineCol('#', 50, cor: Colors.white),
            _timelineCol('Loja', 200, cor: Colors.white),
            _timelineCol('Tipo', 80, cor: Colors.white),
            _timelineCol('Número', 100, cor: Colors.white),
            _timelineCol('Data', 160, cor: Colors.white),
            _timelineCol('Status', 130, cor: Colors.white),
            _timelineCol('Chave de acesso', 240, cor: Colors.white),
          ]),
        ),
        // Linha gradiente
        Container(
          height: 2.5,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_roxo, _roxoClaro, _laranja],
                begin: Alignment.centerLeft, end: Alignment.centerRight),
          ),
        ),
        ...List.generate(_docsRecentes.take(50).length, (i) {
          final doc = _docsRecentes[i];
          final info = _storeInfo(doc.storeId);
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: i.isOdd ? _fundo : Colors.white,
              border: Border(
                  bottom:
                      BorderSide(color: _bordaCard.withAlpha(179))),
            ),
            child: Row(children: [
              SizedBox(
                  width: 50,
                  child: Text('${i + 1}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textoSecundario))),
              // Loja — agora com nome resolvido
              SizedBox(
                  width: 200,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _roxoFundo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          info.nome.isNotEmpty
                              ? info.nome[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _roxo),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(info.nome,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, color: _textoPrimario),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  )),
              SizedBox(
                  width: 80,
                  child: Text(doc.documentType.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _roxo))),
              SizedBox(
                  width: 100,
                  child: Text(doc.number ?? '—',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoPrimario))),
              SizedBox(
                  width: 160,
                  child: Text(
                    doc.issuedAt != null
                        ? _dateFormat.format(doc.issuedAt!.toDate())
                        : (doc.createdAt != null
                            ? _dateFormat.format(doc.createdAt!.toDate())
                            : '—'),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: _textoSecundario),
                  )),
              SizedBox(
                  width: 130,
                  child: Center(child: _statusBadge(doc.status))),
              SizedBox(
                  width: 240,
                  child: Text(doc.accessKey ?? '—',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10, color: _textoSecundario),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _timelineCol(String label, double width, {Color cor = _roxo}) {
    return SizedBox(
        width: width,
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cor)));
  }
}

// ═══════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ═══════════════════════════════════════════════════════════════

class _StoreInfo {
  final String nome;
  final String cnpj;
  final String cidade;
  final String uf;
  final bool carregando;
  _StoreInfo({
    required this.nome,
    this.cnpj = '',
    this.cidade = '',
    this.uf = '',
    this.carregando = false,
  });
}

class _MenuGroupLabel extends PopupMenuEntry<String> {
  final String label;
  const _MenuGroupLabel(this.label);

  @override
  double get height => 28;
  @override
  bool represents(String? value) => false;

  @override
  State<_MenuGroupLabel> createState() => _MenuGroupLabelState();
}

class _MenuGroupLabelState extends State<_MenuGroupLabel> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        widget.label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _textoSecundario.withAlpha(150),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ActionRow(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                color: color,
                fontWeight: FontWeight.w500,
                fontSize: 13)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════════════
class _SummaryCard extends StatefulWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String valor;
  final String subtexto;
  final List<double> sparklineDados;

  const _SummaryCard({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.valor,
    required this.subtexto,
    this.sparklineDados = const [],
  });

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        transform: _hover
            ? (Matrix4.identity()..setTranslationRaw(0, -3, 0))
            : Matrix4.identity(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: widget.cor.withAlpha(_hover ? 31 : 20),
                blurRadius: _hover ? 20 : 14,
                offset: Offset(0, _hover ? 6 : 4)),
            BoxShadow(
                color: widget.cor.withAlpha(_hover ? 15 : 10),
                blurRadius: _hover ? 6 : 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [widget.cor, widget.cor.withAlpha(179)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                      color: widget.cor.withAlpha(64),
                      blurRadius: 7,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Icon(widget.icone, color: Colors.white, size: 19),
            ),
          ]),
          const SizedBox(height: 14),
          Text(widget.titulo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _textoSecundario)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: double.parse(widget.valor.replaceAll('.', '').replaceAll(',', ''))),
            duration: const Duration(milliseconds: 600),
            builder: (context, value, child) {
              return Text(
                _formatAnimado(value),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    height: 1.1),
              );
            },
          ),
          const SizedBox(height: 3),
          Text(widget.subtexto,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: _textoSecundario, height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  String _formatAnimado(double value) {
    if (widget.valor.contains('R\$')) {
      return 'R\$ ${_fmtInt.format(value.toInt())}';
    }
    return _fmtInt.format(value.toInt());
  }

  static final _fmtInt = NumberFormat.decimalPattern('pt_BR');
}
