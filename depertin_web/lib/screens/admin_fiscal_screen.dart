import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/fiscal_document_model.dart';
import '../services/fiscal/fiscal_admin_service.dart';
import '../services/fiscal/fiscal_pos_emissao_service.dart';
import '../services/firebase_functions_config.dart';
import '../theme/painel_admin_theme.dart';

/// Tela administrativa do módulo fiscal NF-e — Monitor Premium.
///
/// Duas abas:
/// - Monitor: visão completa de lojas, integrações, emissões com filtros/KPIs
/// - Notas Fiscais: lista de documentos emitidos com ações
class AdminFiscalScreen extends StatefulWidget {
  const AdminFiscalScreen({super.key});

  @override
  State<AdminFiscalScreen> createState() => _AdminFiscalScreenState();
}

// Cores top-level para uso em contextos const
const Color _roxo = DiPertinTheme.primaryRoxo;
const Color _roxoMedio = DiPertinTheme.primaryRoxoMedio;
const Color _roxoClaro = DiPertinTheme.primaryRoxoClaro;
const Color _laranja = DiPertinTheme.secondaryLaranja;
const Color _textoMuted = DiPertinTheme.textSecondary;
const Color _fundo = DiPertinTheme.backgroundFundo;
const Color _verde = Color(0xFF22C55E);
const Color _vermelho = Color(0xFFEF4444);
const Color _amarelo = Color(0xFFEAB308);
const Color _cinzaBadge = Color(0xFF94A3B8);
const Color _roxoPrimario = DiPertinTheme.primaryRoxo;

class _AdminFiscalScreenState extends State<AdminFiscalScreen>
    with SingleTickerProviderStateMixin {
  // ── Tabs ──
  int _tabIndex = 0;

  // ── Busca global ──
  final _searchCtrl = TextEditingController();
  String _searchTerm = '';

  // ── Filtros ──
  String _filtroProvedor = 'Todos';
  String _filtroStatus = 'Todos';
  String _filtroAmbiente = 'Todos';
  final String _filtroPlano = 'Todos'; // reservado
  // DateTime? _dataInicio; // reservado para filtro período
  // DateTime? _dataFim;    // reservado para filtro período

  // ── Paginação ──
  int _paginaAtual = 0;
  static const int _itensPorPagina = 10;

  // ── Cache de nomes de lojas ──
  final Map<String, _LojaInfoCache> _lojaCache = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchTerm = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS DE COR / TEMA
  // ═══════════════════════════════════════════════════════════════════════

  // Cores definidas como top-level (_cx*) para uso em const contexts

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _buildMonitorTab(),
                _buildNotasFiscaisTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER COM TABS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        left: 28,
        right: 24,
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título + badges
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxo, _roxoClaro],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _roxo.withAlpha(50),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monitor Fiscal NF-e',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: DiPertinTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Acompanhe todas as emissões fiscais dos lojistas em tempo real',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textoMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Tabs
          Row(
            children: [
              _TabButtom(
                label: 'Monitor',
                icon: Icons.dashboard_rounded,
                selected: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              const SizedBox(width: 6),
              _TabButtom(
                label: 'Notas Fiscais',
                icon: Icons.description_rounded,
                selected: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 0 — MONITOR (Configurações Premium)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMonitorTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FiscalAdminService.streamTodasConfiguracoes(),
      builder: (context, settingsSnap) {
        final docs = settingsSnap.data?.docs ?? [];

        if (settingsSnap.connectionState == ConnectionState.waiting) {
          return _buildShimmerLoading();
        }
        if (settingsSnap.hasError) {
          return _buildErrorState(settingsSnap.error.toString());
        }

        // Resolve nomes das lojas
        _resolverNomesLojas(docs);

        // Filtragem combinada
        var filtrados = _aplicarFiltros(docs);

        // Paginação local
        final totalPaginas =
            filtrados.isEmpty ? 1 : (filtrados.length / _itensPorPagina).ceil();
        if (_paginaAtual >= totalPaginas) _paginaAtual = 0;
        final start = _paginaAtual * _itensPorPagina;
        final end = (start + _itensPorPagina).clamp(0, filtrados.length);
        final paginaAtual = filtrados.sublist(start, end);

        return Column(
          children: [
            // KPIs premium
            _buildKpiPremium(),
            // Barra de filtros
            _buildFilterBar(),
            // Tabela premium
            Expanded(
              child: filtrados.isEmpty
                  ? _buildEmptyState()
                  : _buildPremiumTable(paginaAtual, filtrados.length),
            ),
            // Paginação
            if (filtrados.length > _itensPorPagina)
              _buildPagination(totalPaginas, filtrados.length),
          ],
        );
      },
    );
  }

  // ── Resolve nomes de lojas do Firestore ──

  Future<void> _resolverNomesLojas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      final data = doc.data();
      final storeId = data['store_id'] as String? ?? doc.id;
      if (_lojaCache.containsKey(storeId)) continue;
      _lojaCache[storeId] = _LojaInfoCache(nome: storeId, carregando: true);
      try {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(storeId).get();
        if (userDoc.exists) {
          final u = userDoc.data()!;
          final nome = (u['nome_fantasia'] as String?)?.trim() ??
              (u['nome_loja'] as String?)?.trim() ??
              (u['loja_nome'] as String?)?.trim() ??
              (u['nome'] as String?)?.trim() ??
              (u['displayName'] as String?)?.trim() ??
              storeId;
          final cnpj = u['cnpj'] as String? ?? '';
          final cidade = u['cidade'] as String? ?? '';
          final uf = u['uf'] as String? ?? u['estado'] as String? ?? '';
          _lojaCache[storeId] = _LojaInfoCache(
            nome: nome,
            cnpj: cnpj,
            cidade: cidade,
            uf: uf,
            carregando: false,
          );
        } else {
          _lojaCache[storeId] = _LojaInfoCache(nome: storeId, carregando: false);
        }
      } catch (_) {
        _lojaCache[storeId] = _LojaInfoCache(nome: storeId, carregando: false);
      }
    }
  }

  _LojaInfoCache _lojaInfo(String storeId) {
    return _lojaCache[storeId] ?? _LojaInfoCache(nome: storeId, carregando: true);
  }

  // ── Aplicar filtros ──

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _aplicarFiltros(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final d = doc.data();
      final storeId = d['store_id'] as String? ?? doc.id;
      final info = _lojaInfo(storeId);
      final prov = _provider(d);
      final env = _ambiente(d);
      final status = _statusDerivado(d);

      // Busca textual
      if (_searchTerm.isNotEmpty) {
        final q = _searchTerm.toLowerCase();
        final nome = info.nome.toLowerCase();
        final cnpj = info.cnpj.toLowerCase();
        final nfNum = (d['nf_number'] as String? ?? '').toLowerCase();
        final chave = (d['access_key'] as String? ?? '').toLowerCase();
        if (!nome.contains(q) &&
            !cnpj.contains(q) &&
            !nfNum.contains(q) &&
            !chave.contains(q) &&
            !prov.toLowerCase().contains(q)) {
          return false;
        }
      }

      // Provedor
      if (_filtroProvedor != 'Todos') {
        if (!prov.toLowerCase().contains(_filtroProvedor.toLowerCase())) {
          return false;
        }
      }

      // Status
      if (_filtroStatus != 'Todos') {
        if (!status.contains(_filtroStatus.toLowerCase())) return false;
      }

      // Ambiente
      if (_filtroAmbiente != 'Todos') {
        final envMatch = _filtroAmbiente == 'Homologação'
            ? env == 'Homologação'
            : env == 'Produção';
        if (!envMatch) return false;
      }

      return true;
    }).toList();
  }

  // ── Shimmer Loading ──

  Widget _buildShimmerLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_roxo.withAlpha(30), _roxoClaro.withAlpha(20)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 36, color: _roxoPrimario),
          ),
          const SizedBox(height: 20),
          Text(
            'Carregando monitor fiscal...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _textoMuted,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: _roxo.withAlpha(20),
                valueColor: AlwaysStoppedAnimation<Color>(_roxo),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _vermelho.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 36, color: _vermelho),
            ),
            const SizedBox(height: 20),
            Text(
              'Erro ao carregar dados fiscais',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DiPertinTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(error,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _textoMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            _PremiumButton(
              icon: Icons.refresh_rounded,
              label: 'Tentar novamente',
              onTap: () => setState(() {}),
              roxo: _roxo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: _roxo.withAlpha(12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.receipt_long_outlined,
                size: 44, color: _roxo.withAlpha(80)),
          ),
          const SizedBox(height: 20),
          Text(
            _searchTerm.isNotEmpty
                ? 'Nenhuma loja encontrada'
                : 'Nenhuma configuração fiscal encontrada',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: DiPertinTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchTerm.isNotEmpty
                ? 'Tente ajustar os filtros ou buscar por outro termo.'
                : 'As lojas com configuração fiscal aparecerão aqui.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: _textoMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // KPIs PREMIUM
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildKpiPremium() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('store_fiscal_settings')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 100);
        }

        final ativas = docs.where((d) => _statusDerivado(d.data()) == 'active').length;
        final parciais = docs.where((d) => _statusDerivado(d.data()) == 'partial').length;
        final total = docs.length;
        final semIntegracao = docs.where((d) => !_temIntegracao(d.data())).length;

        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: _PremiumKpiRow(
            items: [
              _KpiItem(
                label: 'Ativas',
                valor: ativas.toString(),
                cor: _verde,
                icone: Icons.check_circle_rounded,
              ),
              _KpiItem(
                label: 'Parciais',
                valor: parciais.toString(),
                cor: _laranja,
                icone: Icons.warning_amber_rounded,
              ),
              _KpiItem(
                label: 'Total Lojas',
                valor: total.toString(),
                cor: _roxo,
                icone: Icons.store_rounded,
              ),
              _KpiItem(
                label: 'Sem Integração',
                valor: semIntegracao.toString(),
                cor: _cinzaBadge,
                icone: Icons.link_off_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BARRA DE FILTROS PREMIUM
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          // Linha 1: Busca + Filtros principais
          Row(
            children: [
              // Campo de busca
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por loja, CNPJ, NF-e, chave de acesso...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textoMuted.withAlpha(150),
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: _textoMuted, size: 20),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                size: 18, color: _textoMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchTerm = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _roxoPrimario, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Filtro Provedor
              Expanded(
                flex: 2,
                child: _buildFilterDropdown(
                  value: _filtroProvedor,
                  items: const [
                    'Todos',
                    'Focus NFe',
                    'Nuvem Fiscal',
                    'PlugNotas',
                    'Webmania',
                    'Enotas',
                    'Arquivei',
                    'Outros'
                  ],
                  onChanged: (v) => setState(() => _filtroProvedor = v),
                  icon: Icons.cloud_rounded,
                ),
              ),
              const SizedBox(width: 10),
              // Filtro Status
              Expanded(
                flex: 2,
                child: _buildFilterDropdown(
                  value: _filtroStatus,
                  items: const [
                    'Todos',
                    'Ativo',
                    'Parcial',
                    'Inativo',
                  ],
                  onChanged: (v) => setState(() => _filtroStatus = v),
                  icon: Icons.circle_rounded,
                ),
              ),
              const SizedBox(width: 10),
              // Filtro Ambiente
              Expanded(
                flex: 2,
                child: _buildFilterDropdown(
                  value: _filtroAmbiente,
                  items: const ['Todos', 'Homologação', 'Produção'],
                  onChanged: (v) => setState(() => _filtroAmbiente = v),
                  icon: Icons.language_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Linha 2: Ações
          Row(
            children: [
              // Botão aplicar (placeholder - filtros já são reativos)
              _PremiumSmallButton(
                icon: Icons.filter_alt_off_rounded,
                label: 'Limpar filtros',
                onTap: () {
                  setState(() {
                    _filtroProvedor = 'Todos';
                    _filtroStatus = 'Todos';
                    _filtroAmbiente = 'Todos';
                    _searchCtrl.clear();
                    _searchTerm = '';
                    _paginaAtual = 0;
                  });
                },
                cor: _roxo,
              ),
              const SizedBox(width: 10),
              Text(
                'Filtros aplicados em tempo real',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textoMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _roxo.withAlpha(150)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DiPertinTheme.textPrimary,
                ),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                items: items
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TABELA PREMIUM
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pagina,
    int totalFiltrados,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      itemCount: pagina.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildTableHeader(totalFiltrados);
        return _buildPremiumRow(pagina[index - 1]);
      },
    );
  }

  Widget _buildTableHeader(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_roxo.withAlpha(15), _roxoClaro.withAlpha(8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxo.withAlpha(30)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _HeaderText('LOJA')),
          Expanded(flex: 2, child: _HeaderText('PROVEDOR')),
          Expanded(flex: 1, child: _HeaderText('AMBIENTE')),
          Expanded(flex: 2, child: _HeaderText('STATUS')),
          Expanded(flex: 1, child: _HeaderText('LIMITE')),
          Expanded(child: _HeaderText('TODO')),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildPremiumRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final storeId = data['store_id'] as String? ?? doc.id;
    final info = _lojaInfo(storeId);
    final provider = _provider(data);
    final ambiente = _ambiente(data);
    final status = _statusDerivado(data);
    final temInteg = _temIntegracao(data);
    final taxData = data['company_tax_data'] as Map<String, dynamic>?;
    final intNum = taxData?['crt'] as String? ?? '—';

    final statusCor = _statusCor(status);
    final statusLabel = _statusLabel(status);
    final statusIcon = _statusIcon(status);

    // Badge certificado
    final certInfo = _certificadoInfo(data);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _abrirDetalhesModal(doc.id, data, info),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                // Indicador status
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: temInteg ? statusCor : _cinzaBadge,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (temInteg ? statusCor : _cinzaBadge).withAlpha(80),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Loja (nome resolvido)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.nome,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DiPertinTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (info.cnpj.isNotEmpty) ...[
                            Text(
                              _mascararCnpj(info.cnpj),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: _textoMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (info.cidade.isNotEmpty)
                            Flexible(
                              child: Text(
                                '${info.cidade}${info.uf.isNotEmpty ? '/${info.uf}' : ''}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: _textoMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Provedor
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _roxo.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          provider,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _roxo,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Ambiente
                Expanded(
                  flex: 1,
                  child: _ambienteBadge(ambiente),
                ),
                // Status / Certificado
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusCor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusCor),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusCor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Certificado (compacto)
                      if (certInfo != null)
                        Tooltip(
                          message: certInfo.tooltip,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: certInfo.cor.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              certInfo.label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: certInfo.cor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Limite
                Expanded(
                  flex: 1,
                  child: Text(
                    intNum != '—' ? '$intNum usa' : '—',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: _textoMuted,
                    ),
                  ),
                ),
                // TODO (plac.)
                Expanded(
                  child: Text(
                    '0',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _textoMuted,
                    ),
                  ),
                ),
                // Menu de ações
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded,
                      color: _textoMuted, size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  color: Colors.white,
                  onSelected: (action) =>
                      _handleAction(action, doc.id, data, info),
                  itemBuilder: (_) => _buildActionMenuItems(temInteg),
                  offset: const Offset(0, 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ambienteBadge(String ambiente) {
    final isProd = ambiente == 'Produção';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isProd
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ambiente,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isProd ? const Color(0xFF16A34A) : const Color(0xFFD97706),
        ),
      ),
    );
  }

  _CertInfo? _certificadoInfo(Map<String, dynamic> data) {
    final cert = data['certificate_info'] as Map<String, dynamic>?;
    if (cert == null) return null;
    final venc = cert['validade'] as String?;
    if (venc == null) return null;
    try {
      final dt = DateTime.parse(venc);
      final dias = dt.difference(DateTime.now()).inDays;
      if (dias < 0) {
        return _CertInfo(label: 'Vencido', cor: _vermelho, tooltip: 'Certificado vencido há ${-dias} dias');
      }
      if (dias <= 30) {
        return _CertInfo(label: 'Vence ${dias}d', cor: _amarelo, tooltip: 'Certificado vence em $dias dias');
      }
      return _CertInfo(label: 'OK', cor: _verde, tooltip: 'Certificado válido (vence em $dias dias)');
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AÇÕES
  // ═══════════════════════════════════════════════════════════════════════

  List<PopupMenuEntry<String>> _buildActionMenuItems(bool temIntegracao) {
    return [
      const _MenuGroupLabel('VISUALIZAÇÃO'),
      const PopupMenuItem(
        value: 'detalhes',
        child: _ActionRow(Icons.info_outline_rounded, 'Visualizar detalhes', _roxoPrimario),
      ),
      const PopupMenuItem(
        value: 'historico',
        child: _ActionRow(Icons.history_rounded, 'Ver histórico', Color(0xFF6366F1)),
      ),
      if (temIntegracao) ...[
        const PopupMenuDivider(height: 8),
        const _MenuGroupLabel('DOCUMENTOS'),
        const PopupMenuItem(
          value: 'consultar_xml',
          child: _ActionRow(Icons.find_in_page_rounded, 'Consultar XML', Color(0xFF0891B2)),
        ),
        const PopupMenuItem(
          value: 'baixar_xml',
          child: _ActionRow(Icons.code_rounded, 'Baixar XML', Color(0xFF059669)),
        ),
        const PopupMenuItem(
          value: 'baixar_danfe',
          child: _ActionRow(Icons.picture_as_pdf_rounded, 'Baixar DANFE', Color(0xFFDC2626)),
        ),
        const PopupMenuDivider(height: 8),
        const _MenuGroupLabel('INTEGRAÇÃO'),
        const PopupMenuItem(
          value: 'testar_conexao',
          child: _ActionRow(Icons.wifi_tethering_rounded, 'Testar integração', _roxoPrimario),
        ),
        const PopupMenuItem(
          value: 'webhook',
          child: _ActionRow(Icons.webhook_rounded, 'Consultar Webhook', Color(0xFF7C3AED)),
        ),
        const PopupMenuItem(
          value: 'logs',
          child: _ActionRow(Icons.terminal_rounded, 'Consultar Logs', Color(0xFF475569)),
        ),
      ],
      const PopupMenuDivider(height: 8),
      const _MenuGroupLabel('GESTÃO'),
      if (temIntegracao) ...[
        const PopupMenuItem(
          value: 'suspender',
          child: _ActionRow(Icons.pause_circle_outline_rounded, 'Suspender integração', _laranja),
        ),
      ] else ...[
        const PopupMenuItem(
          value: 'reativar',
          child: _ActionRow(Icons.play_circle_outline_rounded, 'Reativar integração', _verde),
        ),
      ],
    ];
  }

  Future<void> _handleAction(
    String action,
    String docId,
    Map<String, dynamic> data,
    _LojaInfoCache info,
  ) async {
    switch (action) {
      case 'detalhes':
        _abrirDetalhesModal(docId, data, info);
        break;
      case 'historico':
        _mostrarLogs(docId, info.nome);
        break;
      case 'consultar_xml':
      case 'baixar_xml':
      case 'baixar_danfe':
        _mostrarSnack('Função disponível na aba "Notas Fiscais".');
        break;
      case 'testar_conexao':
        _mostrarSnack('Teste de conexão iniciado para ${info.nome}...');
        break;
      case 'webhook':
        _mostrarSnack('Webhook: ${data['webhook_url'] as String? ?? 'Não configurado'}');
        break;
      case 'logs':
        _mostrarLogs(docId, info.nome);
        break;
      case 'suspender':
        await _confirmarESuspender(docId, info.nome);
        break;
      case 'reativar':
        await FiscalAdminService.reativarIntegracao(docId);
        if (mounted) _mostrarSnack('Integração reativada!');
        break;
    }
  }

  Future<void> _confirmarESuspender(String docId, String storeNome) async {
    final confirmou = await _confirmarDialog(
      titulo: 'Suspender integração',
      mensagem:
          'Tem certeza que deseja suspender a integração fiscal de "$storeNome"?\n\n'
          'A loja não conseguirá emitir novas NF-es até que a integração seja reativada.',
      cor: _laranja,
      icone: Icons.pause_circle_outline_rounded,
    );
    if (confirmou == true && mounted) {
      await FiscalAdminService.suspenderIntegracao(docId);
      if (mounted) _mostrarSnack('Integração suspensa.');
    }
  }

  Future<bool?> _confirmarDialog({
    required String titulo,
    required String mensagem,
    required Color cor,
    required IconData icone,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cor.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, color: cor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(titulo,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        content: Text(mensagem,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: _textoMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: GoogleFonts.plusJakartaSans(color: _textoMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text('Confirmar',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.plusJakartaSans(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: _roxo,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODAL DETALHES PREMIUM
  // ═══════════════════════════════════════════════════════════════════════

  void _abrirDetalhesModal(
    String docId,
    Map<String, dynamic> data,
    _LojaInfoCache info,
  ) {
    final integData = data['integration_data'] as Map<String, dynamic>?;
    final taxData = data['company_tax_data'] as Map<String, dynamic>?;
    final storeName = info.nome;
    final provider = _provider(data);
    final ambiente = _ambiente(data);
    final status = _statusDerivado(data);
    final temInteg = _temIntegracao(data);

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 640,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Header gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxo, _roxoMedio],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
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
                            storeName,
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
                      // Status
                      _buildDetalheSecao(
                        titulo: 'Status da Integração',
                        icone: Icons.circle_rounded,
                        corIcone: _statusCor(status),
                        children: [
                          _detailRow('Situação', _statusLabel(status)),
                          _detailRow('Provider', provider),
                          _detailRow('Ambiente', ambiente),
                          _detailRow('ID Config',
                              docId.length > 20 ? '${docId.substring(0, 20)}...' : docId),
                          if (integData?['api_key'] != null)
                            _detailRow('API Key',
                                '••••${(integData!['api_key'] as String).substring((integData['api_key'] as String).length - 4)}'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Dados Fiscais
                      if (taxData != null && taxData.isNotEmpty)
                        _buildDetalheSecao(
                          titulo: 'Dados Fiscais',
                          icone: Icons.business_rounded,
                          corIcone: _roxo,
                          children: [
                            _detailRow('Razão Social',
                                taxData['razao_social'] as String? ?? '—'),
                            _detailRow('Nome Fantasia',
                                taxData['nome_fantasia'] as String? ?? '—'),
                            _detailRow('CNPJ',
                                _mascararCnpj(taxData['cnpj'] as String? ?? '—')),
                            _detailRow('IE', taxData['ie'] as String? ?? '—'),
                            _detailRow('Regime',
                                taxData['regime_tributario'] as String? ?? '—'),
                            _detailRow(
                                'CRT', taxData['crt']?.toString() ?? '—'),
                            _detailRow('CNAE',
                                taxData['cnae_fiscal'] as String? ?? '—'),
                          ],
                        ),
                      const SizedBox(height: 20),
                      // Certificado
                      _buildDetalheSecao(
                        titulo: 'Certificado Digital',
                        icone: Icons.security_rounded,
                        corIcone: _verde,
                        children: [
                          _detailRow('Status', temInteg ? 'Configurado' : 'Não enviado'),
                          _detailRow('Vencimento', '—'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Datas
                      _buildDetalheSecao(
                        titulo: 'Timeline',
                        icone: Icons.timeline_rounded,
                        corIcone: _laranja,
                        children: [
                          _detailRow('Criado em',
                              _formatDate(data['created_at'] as Timestamp?)),
                          _detailRow('Atualizado em',
                              _formatDate(data['updated_at'] as Timestamp?)),
                          if (data['sincronizado_em'] != null)
                            _detailRow('Última sincronização',
                                _formatTimestamp(data['sincronizado_em'] as Timestamp?)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Botão
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _mostrarLogs(docId, storeName);
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
        border: Border.all(color: Colors.grey.shade200),
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
                  color: DiPertinTheme.textPrimary,
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

  // ═══════════════════════════════════════════════════════════════════════
  // LOGS / HISTÓRICO
  // ═══════════════════════════════════════════════════════════════════════

  void _mostrarLogs(String docId, String storeName) {
    final storeId = docId;
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: 640,
          height: 540,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxo, _roxoMedio],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auditoria Fiscal',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            storeName,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withAlpha(200),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FiscalAdminService.streamAuditLogs(storeId),
                  builder: (context, logSnap) {
                    if (logSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final logs = logSnap.data?.docs ?? [];
                    if (logs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off,
                                size: 48, color: _roxo.withAlpha(60)),
                            const SizedBox(height: 12),
                            Text('Nenhum log encontrado',
                                style: GoogleFonts.plusJakartaSans(
                                    color: _textoMuted)),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, i) {
                        final l = logs[i].data();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _fundo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _roxo,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l['acao'] as String? ?? '—',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: DiPertinTheme.textPrimary,
                                      ),
                                    ),
                                    if (l['detalhe'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        l['detalhe'] as String? ?? '',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12, color: _textoMuted),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                _formatTimestamp(l['criado_em'] as Timestamp?),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: _textoMuted),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PAGINAÇÃO
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPagination(int totalPaginas, int totalItens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_paginaAtual * _itensPorPagina + 1}–${((_paginaAtual + 1) * _itensPorPagina).clamp(0, totalItens)} de $totalItens',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoMuted,
            ),
          ),
          Row(
            children: [
              // Anterior
              _buildPageButton(
                icon: Icons.chevron_left_rounded,
                onTap: _paginaAtual > 0
                    ? () => setState(() => _paginaAtual--)
                    : null,
              ),
              const SizedBox(width: 6),
              // Números
              ...List.generate(totalPaginas.clamp(1, 7), (i) {
                final p = i;
                final ativa = p == _paginaAtual;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => setState(() => _paginaAtual = p),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: ativa ? _roxo : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${p + 1}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight:
                              ativa ? FontWeight.w700 : FontWeight.w500,
                          color: ativa ? Colors.white : _textoMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 6),
              // Próxima
              _buildPageButton(
                icon: Icons.chevron_right_rounded,
                onTap: _paginaAtual < totalPaginas - 1
                    ? () => setState(() => _paginaAtual++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onTap != null
              ? _roxo.withAlpha(10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: onTap != null
                ? _roxo.withAlpha(40)
                : Colors.grey.shade200,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? _roxo
              : _textoMuted.withAlpha(80),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS DE EXTRAÇÃO (preservados do original)
  // ═══════════════════════════════════════════════════════════════════════

  String _provider(Map<String, dynamic> data) {
    final integ = data['integration_data'] as Map<String, dynamic>?;
    return (integ?['provider_name'] as String?) ??
        (integ?['provider'] as String?) ??
        '—';
  }

  String _ambiente(Map<String, dynamic> data) {
    final integ = data['integration_data'] as Map<String, dynamic>?;
    final env = integ?['environment'] as String?;
    if (env == 'sandbox') return 'Homologação';
    if (env == 'producao' || env == 'production') return 'Produção';
    return '—';
  }

  bool _temDadosFiscais(Map<String, dynamic> data) {
    final tax = data['company_tax_data'] as Map<String, dynamic>?;
    return tax != null &&
        tax.isNotEmpty &&
        (tax['cnpj'] as String? ?? '').isNotEmpty;
  }

  bool _temIntegracao(Map<String, dynamic> data) {
    final integId = data['integration_id'] as String?;
    return integId != null && integId.isNotEmpty;
  }

  String _statusDerivado(Map<String, dynamic> data) {
    if (_temIntegracao(data) && _temDadosFiscais(data)) return 'active';
    if (_temIntegracao(data)) return 'partial';
    return 'inactive';
  }

  Color _statusCor(String status) {
    switch (status) {
      case 'active':
        return _verde;
      case 'partial':
        return _laranja;
      case 'inactive':
        return _cinzaBadge;
      default:
        return _cinzaBadge;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Ativo';
      case 'partial':
        return 'Parcial';
      case 'inactive':
        return 'Inativo';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'partial':
        return Icons.warning_amber_rounded;
      case 'inactive':
        return Icons.remove_circle_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _mascararCnpj(String cnpj) {
    if (cnpj.length != 14) return cnpj;
    return '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/${cnpj.substring(8, 12)}-${cnpj.substring(12)}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FORMATAÇÃO DE DATAS
  // ═══════════════════════════════════════════════════════════════════════

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    return DateFormat('dd/MM HH:mm').format(dt);
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
                    color: _textoMuted)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: DiPertinTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 1 — NOTAS FISCAIS (preservado com upgrade visual)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildNotasFiscaisTab() {
    return StreamBuilder<List<FiscalDocumentModel>>(
      stream: FiscalPosEmissaoService.streamDocumentosAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildNfShimmer();
        }
        if (snap.hasError) {
          return _buildNfError(snap.error.toString());
        }
        final docs = snap.data ?? [];
        if (docs.isEmpty) return _buildNfEmpty();

        int autorizadas = 0, processando = 0, rejeitadas = 0, canceladas = 0;
        for (final d in docs) {
          if (FiscalPosEmissaoService.isAutorizada(d.status)) autorizadas++;
          if (FiscalPosEmissaoService.isProcessando(d.status)) processando++;
          if (FiscalPosEmissaoService.isRejeitada(d.status)) rejeitadas++;
          if (FiscalPosEmissaoService.isCancelada(d.status)) canceladas++;
        }

        return Column(
          children: [
            _buildNfKpis(
                autorizadas, processando, rejeitadas, canceladas, docs.length),
            Expanded(child: _buildNfLista(docs)),
          ],
        );
      },
    );
  }

  Widget _buildNfShimmer() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _roxo.withAlpha(20),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.description_rounded,
                size: 28, color: _roxoPrimario),
          ),
          const SizedBox(height: 14),
          Text('Carregando notas fiscais...',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: _textoMuted)),
        ],
      ),
    );
  }

  Widget _buildNfError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: _vermelho),
            const SizedBox(height: 16),
            Text('Erro ao carregar',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(error,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _textoMuted),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildNfEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _roxo.withAlpha(12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.description_outlined,
                size: 40, color: _roxo.withAlpha(80)),
          ),
          const SizedBox(height: 16),
          Text('Nenhuma nota fiscal encontrada',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('As notas emitidas aparecerão aqui.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: _textoMuted)),
        ],
      ),
    );
  }

  Widget _buildNfKpis(
    int autorizadas,
    int processando,
    int rejeitadas,
    int canceladas,
    int total,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: _PremiumKpiRow(
        items: [
          _KpiItem(
              label: 'Autorizadas',
              valor: autorizadas.toString(),
              cor: _verde,
              icone: Icons.check_circle_rounded),
          _KpiItem(
              label: 'Processando',
              valor: processando.toString(),
              cor: _laranja,
              icone: Icons.hourglass_top_rounded),
          _KpiItem(
              label: 'Rejeitadas',
              valor: rejeitadas.toString(),
              cor: _vermelho,
              icone: Icons.cancel_rounded),
          _KpiItem(
              label: 'Canceladas',
              valor: canceladas.toString(),
              cor: _cinzaBadge,
              icone: Icons.block_rounded),
          _KpiItem(
              label: 'Total',
              valor: total.toString(),
              cor: _roxo,
              icone: Icons.description_rounded),
        ],
      ),
    );
  }

  Widget _buildNfLista(List<FiscalDocumentModel> docs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        return _NfCard(
          doc: docs[index],
          roxo: _roxo,
          laranja: _laranja,
          textoMuted: _textoMuted,
          vermelho: _vermelho,
          verde: _verde,
          onConsultar: () => _nfConsultarStatus(docs[index]),
          onBaixarXml: () => _nfBaixarArquivo(docs[index], 'xml'),
          onBaixarDanfe: () => _nfBaixarArquivo(docs[index], 'danfe'),
          onImprimirDanfe: () => _nfImprimirDanfe(docs[index]),
          onCancelar: () => _nfCancelar(docs[index]),
          onHistorico: () => _nfHistorico(docs[index]),
          onDetalhes: () => _nfDetalhesRejeicao(docs[index]),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AÇÕES DE NOTA FISCAL (preservadas)
  // ═══════════════════════════════════════════════════════════════════════

  void _nfConsultarStatus(FiscalDocumentModel doc) async {
    if (FiscalPosEmissaoService.isStatusFinal(doc.status)) {
      _mostrarSnack('Nota já está em estado final: ${doc.status}');
      return;
    }
    final cfgSnap = await FirebaseFirestore.instance
        .collection('store_fiscal_settings')
        .where('store_id', isEqualTo: doc.storeId)
        .limit(1)
        .get();
    if (cfgSnap.docs.isEmpty) {
      _mostrarSnack('Configuração fiscal da loja não encontrada.');
      return;
    }
    final cfg = cfgSnap.docs.first.data();
    final integrationId = cfg['integration_id'] as String?;
    if (integrationId == null || integrationId.isEmpty) {
      _mostrarSnack('Loja sem integração fiscal configurada.');
      return;
    }
    if (doc.accessKey == null || doc.accessKey!.isEmpty) {
      _mostrarSnack('Nota sem chave de acesso para consultar.');
      return;
    }
    _mostrarSnack('Consultando status...');
    final resultado = await FiscalPosEmissaoService.consultarEAtualizarStatus(
      integrationId: integrationId,
      storeId: doc.storeId,
      chaveAcesso: doc.accessKey!,
      documentoId: doc.id,
    );
    if (!mounted) return;
    final status = resultado['status'] as String? ?? 'erro';
    final mensagem = resultado['mensagem'] as String? ?? '';
    if (status == 'autorizada') {
      _mostrarSnack('✅ NF-e autorizada! XML e DANFE salvos.');
    } else if (status == 'rejeitada') {
      _nfMostrarRejeicao(doc.id, mensagem, resultado['erro'] as String?);
    } else if (FiscalPosEmissaoService.isProcessando(status)) {
      _mostrarSnack('⏳ Nota ainda processando.');
    } else {
      _mostrarSnack(mensagem.isNotEmpty ? mensagem : 'Status: $status');
    }
  }

  void _nfBaixarArquivo(FiscalDocumentModel doc, String tipo) async {
    final url = tipo == 'xml' ? doc.xmlUrl : doc.pdfUrl;
    if (url == null || url.isEmpty) {
      _mostrarSnack(tipo == 'xml'
          ? 'XML não disponível.'
          : 'DANFE não disponível.');
      return;
    }
    _mostrarSnack('Baixando ${tipo.toUpperCase()}...');
    final nome = tipo == 'xml'
        ? 'nfe-${doc.number ?? doc.id}.xml'
        : 'danfe-${doc.number ?? doc.id}.pdf';
    final result = await FiscalPosEmissaoService.baixarConteudoUrl(
      url: url,
      nomeArquivo: nome,
    );
    if (!mounted) return;
    if (result['sucesso'] == true) {
      _mostrarSnack('Download concluído.');
    } else {
      _mostrarSnack('Erro: ${result['erro'] ?? 'Falha no download'}');
    }
  }

  void _nfImprimirDanfe(FiscalDocumentModel doc) {
    if (doc.pdfUrl == null || doc.pdfUrl!.isEmpty) {
      _mostrarSnack('DANFE não disponível.');
      return;
    }
    _mostrarSnack('Abrindo DANFE para impressão...');
  }

  void _nfCancelar(FiscalDocumentModel doc) async {
    if (!doc.podeCancelar) {
      _mostrarSnack('Esta nota não pode ser cancelada (status: ${doc.status}).');
      return;
    }
    final justificativa = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _vermelho.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cancel_outlined,
                    color: _vermelho, size: 22),
              ),
              const SizedBox(width: 10),
              Text('Cancelar NF-e',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Informe a justificativa (mín. 15 caracteres):',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: _textoMuted)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 255,
                  decoration: InputDecoration(
                    hintText: 'Ex: Cliente desistiu da compra...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: _fundo,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: GoogleFonts.plusJakartaSans(color: _textoMuted)),
            ),
            ElevatedButton(
              onPressed: ctrl.text.trim().length >= 15
                  ? () => Navigator.pop(ctx, ctrl.text.trim())
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _vermelho,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Confirmar Cancelamento',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
    if (justificativa == null || !mounted) return;
    _mostrarSnack('Enviando cancelamento...');
    try {
      final result = await callFirebaseFunctionSafe(
        'fiscalCancelarNFe',
        parameters: {
          'store_id': doc.storeId,
          'chave_acesso': doc.accessKey,
          'justificativa': justificativa,
          'numero_protocolo': doc.protocol,
          'integration_id': null,
        },
        region: 'southamerica-east1',
        timeout: const Duration(seconds: 60),
      );
      if (mounted) {
        if (result['sucesso'] == true) {
          _mostrarSnack('✅ NF-e cancelada com sucesso!');
        } else {
          _mostrarSnack('❌ Erro: ${result['erro'] ?? 'Falha ao cancelar'}');
        }
      }
    } catch (e) {
      if (mounted) _mostrarSnack('Erro ao cancelar: $e');
    }
  }

  void _nfHistorico(FiscalDocumentModel doc) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: 700,
          height: 540,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxo, _roxoMedio],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Histórico da NF-e',
                              style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text('NFe ${doc.number ?? ''}',
                              style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FiscalPosEmissaoService.streamHistoricoStatus(doc.id),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final items = snap.data?.docs ?? [];
                    if (items.isEmpty) {
                      return Center(
                        child: Text('Nenhum registro.',
                            style: GoogleFonts.plusJakartaSans(
                                color: _textoMuted)),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _buildNfInfoHeader(doc);
                        }
                        final h = items[i - 1].data();
                        final oldStatus = h['oldStatus'] as String? ?? '—';
                        final newStatus = h['newStatus'] as String? ?? '—';
                        final source = h['source'] as String? ?? '—';
                        final message = h['message'] as String? ?? '';
                        final ts = h['createdAt'] as Timestamp?;
                        final corStatus =
                            _statusHistoryCor(oldStatus, newStatus);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _fundo,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: corStatus.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$oldStatus → $newStatus',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: corStatus,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(_formatTs(ts),
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11, color: _textoMuted)),
                                ],
                              ),
                              if (message.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(message,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12, color: _textoMuted)),
                              ],
                              Text('Fonte: $source',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11, color: _textoMuted)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNfInfoHeader(FiscalDocumentModel doc) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _roxo.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxo.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Número', doc.number ?? '—'),
          _infoRow('Série', doc.series ?? '—'),
          _infoRow('Chave de Acesso', doc.accessKey ?? '—'),
          _infoRow('Protocolo', doc.protocol ?? '—'),
          if (doc.rejectionReason != null)
            _infoRow('Motivo rejeição', doc.rejectionReason!),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: _textoMuted)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: DiPertinTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _nfDetalhesRejeicao(FiscalDocumentModel doc) {
    if (!doc.isRejeitada && doc.rejectionReason == null) {
      _mostrarSnack('Esta nota não possui rejeição registrada.');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _vermelho.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cancel, color: _vermelho, size: 22),
            ),
            const SizedBox(width: 10),
            Text('Detalhes da Rejeição',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (doc.rejectionCode != null) ...[
                  _detailRow('Código', doc.rejectionCode!),
                  const SizedBox(height: 8),
                ],
                if (doc.rejectionReason != null) ...[
                  Text('Motivo:',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: DiPertinTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(doc.rejectionReason!,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: const Color(0xFF991B1B))),
                  ),
                ],
                if (doc.providerResponse != null) ...[
                  const SizedBox(height: 16),
                  Text('Resposta do provedor:',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: DiPertinTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(doc.providerResponse!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: _textoMuted)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Fechar',
                style: GoogleFonts.plusJakartaSans(color: _textoMuted)),
          ),
        ],
      ),
    );
  }

  void _nfMostrarRejeicao(
      String documentoId, String mensagem, String? erro) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _vermelho.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cancel, color: _vermelho, size: 22),
            ),
            const SizedBox(width: 10),
            Text('NF-e Rejeitada',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mensagem,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, color: DiPertinTheme.textPrimary)),
              if (erro != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(erro,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: const Color(0xFF991B1B))),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Fechar',
                style: GoogleFonts.plusJakartaSans(color: _textoMuted)),
          ),
        ],
      ),
    );
  }

  Color _statusHistoryCor(String oldStatus, String newStatus) {
    if (newStatus == 'autorizada') return _verde;
    if (newStatus == 'rejeitada' || newStatus == 'erro') return _vermelho;
    if (newStatus == 'cancelada' || newStatus == 'cancelamento_homologado') {
      return _cinzaBadge;
    }
    return _laranja;
  }

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ═══════════════════════════════════════════════════════════════════════

class _LojaInfoCache {
  final String nome;
  final String cnpj;
  final String cidade;
  final String uf;
  final bool carregando;
  _LojaInfoCache({
    required this.nome,
    this.cnpj = '',
    this.cidade = '',
    this.uf = '',
    this.carregando = false,
  });
}

class _CertInfo {
  final String label;
  final Color cor;
  final String tooltip;
  _CertInfo({
    required this.label,
    required this.cor,
    required this.tooltip,
  });
}

class _KpiItem {
  final String label;
  final String valor;
  final Color cor;
  final IconData icone;
  const _KpiItem({
    required this.label,
    required this.valor,
    required this.cor,
    required this.icone,
  });
}

class _PremiumKpiRow extends StatelessWidget {
  final List<_KpiItem> items;
  const _PremiumKpiRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: item.cor.withAlpha(40)),
                  boxShadow: [
                    BoxShadow(
                      color: item.cor.withAlpha(15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: item.cor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icone,
                          color: item.cor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.valor,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: item.cor,
                            ),
                          ),
                          Text(
                            item.label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _textMuted,
                              fontWeight: FontWeight.w500,
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
      }).toList(),
    );
  }

  static const Color _textMuted = DiPertinTheme.textSecondary;
}

class _HeaderText extends StatelessWidget {
  final String text;
  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: DiPertinTheme.textSecondary,
        letterSpacing: 0.5,
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
          color: DiPertinTheme.textSecondary.withAlpha(150),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _TabButtom extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButtom({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? DiPertinTheme.primaryRoxo.withAlpha(15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(
                    color: DiPertinTheme.primaryRoxo.withAlpha(50), width: 1.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? DiPertinTheme.primaryRoxo
                    : DiPertinTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? DiPertinTheme.primaryRoxo
                      : DiPertinTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color roxo;
  const _PremiumButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.roxo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [DiPertinTheme.primaryRoxo, DiPertinTheme.primaryRoxoClaro],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: DiPertinTheme.primaryRoxo.withAlpha(50),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumSmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color cor;
  const _PremiumSmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: cor.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cor.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: cor),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NF CARD (preservado do original com upgrade visual)
// ═══════════════════════════════════════════════════════════════════════

class _NfCard extends StatelessWidget {
  final FiscalDocumentModel doc;
  final Color roxo;
  final Color laranja;
  final Color textoMuted;
  final Color vermelho;
  final Color verde;

  final VoidCallback onConsultar;
  final VoidCallback onBaixarXml;
  final VoidCallback onBaixarDanfe;
  final VoidCallback onImprimirDanfe;
  final VoidCallback onCancelar;
  final VoidCallback onHistorico;
  final VoidCallback onDetalhes;

  const _NfCard({
    required this.doc,
    required this.roxo,
    required this.laranja,
    required this.textoMuted,
    required this.vermelho,
    required this.verde,
    required this.onConsultar,
    required this.onBaixarXml,
    required this.onBaixarDanfe,
    required this.onImprimirDanfe,
    required this.onCancelar,
    required this.onHistorico,
    required this.onDetalhes,
  });

  Color get _statusCor => FiscalPosEmissaoService.statusCor(doc.status);
  String get _statusLabel => FiscalPosEmissaoService.statusLabel(doc.status);
  IconData get _statusIcon => FiscalPosEmissaoService.statusIcon(doc.status);

  @override
  Widget build(BuildContext context) {
    final isFinal = FiscalPosEmissaoService.isStatusFinal(doc.status);
    final isAutorizada = doc.isAutorizada;
    final podeCancelar = doc.podeCancelar;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _statusCor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_statusIcon,
                        color: _statusCor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.number != null
                              ? 'NF-e Nº ${doc.number}'
                              : 'NF-e ${doc.id.length > 8 ? '${doc.id.substring(0, 8)}...' : doc.id}',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: DiPertinTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _statusCor.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _statusLabel,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _statusCor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _fmtDate(doc.createdAt),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: textoMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Info row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DiPertinTheme.backgroundFundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_rounded,
                        size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      'Loja: ${doc.storeId.length > 12 ? '${doc.storeId.substring(0, 12)}...' : doc.storeId}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: textoMuted),
                    ),
                    const SizedBox(width: 16),
                    if (doc.accessKey != null) ...[
                      const Icon(Icons.vpn_key_rounded,
                          size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Chave: ${doc.accessKey!.length > 12 ? '${doc.accessKey!.substring(0, 12)}...' : doc.accessKey!}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: textoMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (doc.series != null) ...[
                      const SizedBox(width: 16),
                      Text('Série: ${doc.series}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: textoMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Ações
              Row(
                children: [
                  if (isFinal)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: roxo.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Finalizado',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: roxo)),
                    ),
                  if (!isFinal) ...[
                    Icon(Icons.hourglass_top_rounded,
                        size: 14, color: laranja),
                    const SizedBox(width: 4),
                    Text('Aguardando autorização...',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: laranja)),
                  ],
                  const Spacer(),
                  _NfActionChip(
                      Icons.refresh_rounded, 'Consultar', roxo, onConsultar),
                  if (isAutorizada && doc.xmlUrl != null) ...[
                    const SizedBox(width: 4),
                    _NfActionChip(
                        Icons.code_rounded, 'XML', verde, onBaixarXml),
                  ],
                  if (isAutorizada && doc.pdfUrl != null) ...[
                    const SizedBox(width: 4),
                    _NfActionChip(Icons.picture_as_pdf_rounded,
                        'DANFE', verde, onBaixarDanfe),
                    const SizedBox(width: 4),
                    _NfActionChip(Icons.print_rounded,
                        'Imprimir', roxo, onImprimirDanfe),
                  ],
                  if (podeCancelar) ...[
                    const SizedBox(width: 4),
                    _NfActionChip(Icons.cancel_outlined,
                        'Cancelar', vermelho, onCancelar),
                  ],
                  const SizedBox(width: 4),
                  _NfActionChip(Icons.history_rounded,
                      'Histórico', textoMuted, onHistorico),
                  if (doc.isRejeitada || doc.rejectionReason != null) ...[
                    const SizedBox(width: 4),
                    _NfActionChip(Icons.info_outline_rounded,
                        'Detalhes', vermelho, onDetalhes),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return DateFormat('dd/MM/yyyy').format(dt);
  }
}

class _NfActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NfActionChip(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
