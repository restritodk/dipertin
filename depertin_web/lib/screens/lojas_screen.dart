import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_lojista.dart';
import '../widgets/botao_suporte_flutuante.dart';
import '../widgets/pdf_preview_iframe.dart';

class _StatusVisual {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  const _StatusVisual(
      this.label, this.icon, this.color, this.bgColor, this.borderColor);
}

const _kStatus = <String, _StatusVisual>{
  'pendente': _StatusVisual('Pendentes', Icons.hourglass_empty_rounded,
      Color(0xFFD97706), Color(0xFFFFF7ED), Color(0xFFFED7AA)),
  'aprovada': _StatusVisual('Aprovadas', Icons.check_circle_outline_rounded,
      Color(0xFF059669), Color(0xFFECFDF5), Color(0xFFA7F3D0)),
  'bloqueada': _StatusVisual('Bloqueadas', Icons.block_rounded,
      Color(0xFFDC2626), Color(0xFFFEF2F2), Color(0xFFFECACA)),
};

enum _MaisAcoesLoja { documentos, planoTaxa, bloquear }

class LojasScreen extends StatefulWidget {
  const LojasScreen({super.key});

  @override
  State<LojasScreen> createState() => _LojasScreenState();
}

class _LojasScreenState extends State<LojasScreen>
    with SingleTickerProviderStateMixin {
  String _tipoUsuarioLogado = 'master';
  List<String> _cidadesDoGerente = [];
  /// Termo aplicado ao filtro (atualizado com debounce para não reconstruir a tela a cada tecla).
  String _busca = '';

  late final TextEditingController _campoBuscaController;
  Timer? _debounceBusca;

  static const int _debounceBuscaMs = 350;
  static const int _itensPorPagina = 10;

  /// Índice de página (0-based) por aba — independente entre Pendentes / Aprovadas / Bloqueadas.
  final Map<String, int> _paginaPorStatus = {
    'pendente': 0,
    'aprovada': 0,
    'bloqueada': 0,
  };

  static const _statusTabs = ['pendente', 'aprovada', 'bloqueada'];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _campoBuscaController = TextEditingController();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _buscarDadosDoGestor();
  }

  @override
  void dispose() {
    _debounceBusca?.cancel();
    _campoBuscaController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _agendarAtualizacaoBusca() {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(
      const Duration(milliseconds: _debounceBuscaMs),
      () {
        if (!mounted) return;
        _aplicarBuscaDoCampo();
      },
    );
  }

  void _aplicarBuscaDoCampo() {
    final t = _campoBuscaController.text.trim().toLowerCase();
    if (_busca == t) return;
    setState(() {
      _busca = t;
      for (final s in _statusTabs) {
        _paginaPorStatus[s] = 0;
      }
    });
  }

  Future<void> _buscarDadosDoGestor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final dados = doc.data()!;
        setState(() {
          _tipoUsuarioLogado = perfilAdministrativo(dados);
          final raw = dados['cidades_gerenciadas'];
          if (raw is List) {
            _cidadesDoGerente = raw
                .map((e) => e == null ? '' : '$e')
                .where((s) => s.isNotEmpty)
                .toList();
          } else {
            _cidadesDoGerente = [];
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissão: $e');
    }
  }

  Query<Map<String, dynamic>> _queryPorStatus(String status) {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('users');
    if (status == 'aprovada') {
      q = q.where('status_loja', whereIn: ['aprovada', 'ativo', 'aprovado']);
    } else if (status == 'bloqueada') {
      q = q.where(
        'status_loja',
        whereIn: ['bloqueada', 'bloqueado', 'bloqueio_temporario'],
      );
    } else {
      q = q.where('status_loja', isEqualTo: status);
    }
    if (_tipoUsuarioLogado == 'master_city' && _cidadesDoGerente.isNotEmpty) {
      q = q.where('cidade', whereIn: _cidadesDoGerente);
    }
    return q;
  }

  Future<void> _alterarStatusLoja(
    String id,
    String novoStatus, {
    String? motivo,
  }) async {
    final update = <String, dynamic>{'status_loja': novoStatus};
    if (motivo != null && motivo.isNotEmpty) {
      update['motivo_recusa'] = motivo;
      update['recusa_cadastro'] = true;
    } else if (novoStatus == 'aprovada') {
      update['motivo_recusa'] = FieldValue.delete();
      update['motivo_bloqueio'] = FieldValue.delete();
      update['recusa_cadastro'] = FieldValue.delete();
      update['status_conta'] = ContaBloqueioLojista.statusContaActive;
      update['block_active'] = false;
      update['block_type'] = FieldValue.delete();
      update['block_reason'] = FieldValue.delete();
      update['block_start_at'] = FieldValue.delete();
      update['block_end_at'] = FieldValue.delete();
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .update(update);
      if (!mounted) return;
      mostrarSnackPainel(context,
          mensagem: 'Status alterado para $novoStatus!');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final s in _statusTabs) _buildListaLojas(s),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  // ─── header ───

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.storefront_rounded,
                      color: PainelAdminTheme.roxo, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gestão de Lojas',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: PainelAdminTheme.dashboardInk,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(
                          'Aprove parceiros e defina os planos de comissão.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: PainelAdminTheme.textoSecundario,
                              height: 1.4)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 260,
                  height: 42,
                  child: TextField(
                    controller: _campoBuscaController,
                    onChanged: (_) => _agendarAtualizacaoBusca(),
                    onSubmitted: (_) {
                      _debounceBusca?.cancel();
                      _aplicarBuscaDoCampo();
                    },
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Buscar loja ou responsável…',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: PainelAdminTheme.textoSecundario),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20,
                          color: PainelAdminTheme.textoSecundario),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: PainelAdminTheme.roxo, width: 1.5)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TabBar(
              controller: _tabController,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicatorColor: PainelAdminTheme.laranja,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w500, fontSize: 13),
              labelColor: PainelAdminTheme.roxo,
              unselectedLabelColor: PainelAdminTheme.textoSecundario,
              tabs: [for (final s in _statusTabs) _buildTab(s)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String status) {
    final info = _kStatus[status]!;
    // Não usar AggregateQuery + asStream() aqui: no Flutter Web costuma quebrar
    // (TypeError em isEmpty / asserções no engine).
    return Tab(
      height: 52,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(info.icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              info.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ─── lista ───

  Widget _buildListaLojas(String status) {
    final info = _kStatus[status]!;
    return StreamBuilder<QuerySnapshot>(
      stream: _queryPorStatus(status).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erro ao carregar lojas.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFDC2626),
                  fontSize: 14,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                  color: PainelAdminTheme.roxo, strokeWidth: 2.5));
        }
        final docs = snapshot.data?.docs ?? [];
        final filtrados = _busca.isEmpty
            ? docs
            : docs.where((d) {
                try {
                  final raw = d.data();
                  if (raw is! Map) return false;
                  final data = Map<String, dynamic>.from(raw);
                  final nome = _str(data['loja_nome']).toLowerCase();
                  final dono = _str(data['nome']).toLowerCase();
                  final cidade = _str(data['cidade']).toLowerCase();
                  return nome.contains(_busca) ||
                      dono.contains(_busca) ||
                      cidade.contains(_busca);
                } catch (_) {
                  return false;
                }
              }).toList();

        if (filtrados.isEmpty) return _buildEmptyState(status, info);

        final totalItens = filtrados.length;
        final totalPaginas = math.max(
          1,
          ((totalItens - 1) ~/ _itensPorPagina) + 1,
        );
        final paginaArmazenada = _paginaPorStatus[status] ?? 0;
        final paginaAtual =
            paginaArmazenada.clamp(0, totalPaginas - 1);
        final inicio = paginaAtual * _itensPorPagina;
        final fim = math.min(inicio + _itensPorPagina, totalItens);
        final paginaItens = filtrados.sublist(inicio, fim);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                itemCount: paginaItens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) =>
                    _buildLojaCard(paginaItens[i], status, info),
              ),
            ),
            _buildBarraPaginacaoLojas(
              status: status,
              totalItens: totalItens,
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
            ),
          ],
        );
      },
    );
  }

  void _definirPaginaLoja(String status, int novaPagina, int totalPaginas) {
    final maxP = totalPaginas > 0 ? totalPaginas - 1 : 0;
    setState(() => _paginaPorStatus[status] = novaPagina.clamp(0, maxP));
  }

  /// Barra inferior: resumo + primeira / anterior / números / próxima / última.
  Widget _buildBarraPaginacaoLojas({
    required String status,
    required int totalItens,
    required int paginaAtual,
    required int totalPaginas,
  }) {
    final inicioExib = totalItens == 0 ? 0 : paginaAtual * _itensPorPagina + 1;
    final fimExib = math.min(
      (paginaAtual + 1) * _itensPorPagina,
      totalItens,
    );

    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 14, 88, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0)),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 720;
            final botoesNumeros = _buildBotoesNumerosPagina(
              paginaAtual: paginaAtual,
              totalPaginas: totalPaginas,
              onSelecionar: (p) => _definirPaginaLoja(status, p, totalPaginas),
            );

            final resumo = Text(
              totalItens == 0
                  ? 'Nenhum registro'
                  : 'Mostrando $inicioExib–$fimExib de $totalItens ${totalItens == 1 ? 'loja' : 'lojas'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: PainelAdminTheme.textoSecundario,
              ),
            );

            final controles = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pagIconBtn(
                  tooltip: 'Primeira página',
                  icon: Icons.first_page_rounded,
                  enabled: paginaAtual > 0,
                  onTap: () => _definirPaginaLoja(status, 0, totalPaginas),
                ),
                _pagIconBtn(
                  tooltip: 'Página anterior',
                  icon: Icons.chevron_left_rounded,
                  enabled: paginaAtual > 0,
                  onTap: () =>
                      _definirPaginaLoja(status, paginaAtual - 1, totalPaginas),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: botoesNumeros,
                  ),
                ),
                _pagIconBtn(
                  tooltip: 'Próxima página',
                  icon: Icons.chevron_right_rounded,
                  enabled: paginaAtual < totalPaginas - 1,
                  onTap: () =>
                      _definirPaginaLoja(status, paginaAtual + 1, totalPaginas),
                ),
                _pagIconBtn(
                  tooltip: 'Última página',
                  icon: Icons.last_page_rounded,
                  enabled: paginaAtual < totalPaginas - 1,
                  onTap: () => _definirPaginaLoja(
                    status,
                    totalPaginas - 1,
                    totalPaginas,
                  ),
                ),
              ],
            );

            final chipPagina = Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Página ${paginaAtual + 1} de $totalPaginas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.dashboardInk,
                  letterSpacing: 0.2,
                ),
              ),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  resumo,
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      chipPagina,
                      controles,
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: resumo),
                chipPagina,
                const SizedBox(width: 20),
                controles,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pagIconBtn({
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? PainelAdminTheme.roxo
                : PainelAdminTheme.textoSecundario.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  /// Até 7 botões; acima disso, primeiras / vizinhas da atual / última com reticências.
  List<Widget> _buildBotoesNumerosPagina({
    required int paginaAtual,
    required int totalPaginas,
    required ValueChanged<int> onSelecionar,
  }) {
    if (totalPaginas <= 1) {
      return [];
    }

    final List<int?> sequencia;
    if (totalPaginas <= 7) {
      sequencia = List<int?>.generate(totalPaginas, (i) => i);
    } else {
      final set = <int>{
        0,
        totalPaginas - 1,
        paginaAtual,
        paginaAtual - 1,
        paginaAtual + 1,
      };
      set.removeWhere((e) => e < 0 || e >= totalPaginas);
      final sorted = set.toList()..sort();
      sequencia = [];
      for (var i = 0; i < sorted.length; i++) {
        if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
          sequencia.add(null);
        }
        sequencia.add(sorted[i]);
      }
    }

    final out = <Widget>[];
    for (final idx in sequencia) {
      if (idx == null) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ),
        );
        continue;
      }
      final selecionada = idx == paginaAtual;
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: selecionada
                ? PainelAdminTheme.roxo.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: selecionada ? null : () => onSelecionar(idx),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 36),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  '${idx + 1}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight:
                        selecionada ? FontWeight.w800 : FontWeight.w600,
                    color: selecionada
                        ? PainelAdminTheme.roxo
                        : PainelAdminTheme.dashboardInk,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _buildEmptyState(String status, _StatusVisual info) {
    final hasSearch = _busca.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration:
                BoxDecoration(color: info.bgColor, shape: BoxShape.circle),
            child: Icon(hasSearch ? Icons.search_off_rounded : info.icon,
                size: 48, color: info.color.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 20),
          Text(
            hasSearch
                ? 'Nenhuma loja encontrada para "$_busca"'
                : 'Nenhuma loja ${info.label.toLowerCase()} encontrada.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Tente outro termo de busca.'
                : status == 'pendente'
                    ? 'Novas lojas aparecerão aqui assim que solicitarem cadastro.'
                    : 'Nenhum registro nesta categoria no momento.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario
                    .withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  // ─── card ───

  String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    try {
      return v.toString();
    } catch (_) {
      return fallback;
    }
  }

  Widget _buildLojaCard(
      QueryDocumentSnapshot doc, String status, _StatusVisual info) {
    final raw = doc.data();
    if (raw is! Map) {
      return const SizedBox.shrink();
    }
    final dados = Map<String, dynamic>.from(raw);
    final nomeLoja = _str(dados['loja_nome'], 'Loja sem nome');
    final nomeDono = _str(dados['nome'], 'N/A');
    final cidade = _str(dados['cidade'], '—');
    final telefone = _str(dados['telefone']);
    final planoId = dados['plano_taxa_id'];
    final fotoUrl = _str(dados['foto_url']);
    final motivoRecusa = _str(dados['motivo_recusa']);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8ECF1)),
          boxShadow: [
            BoxShadow(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.06),
              blurRadius: 28,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        PainelAdminTheme.roxo.withValues(alpha: 0.9),
                        PainelAdminTheme.laranja.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: fotoUrl.isNotEmpty
                                ? [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: info.bgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: fotoUrl.isNotEmpty
                                    ? Colors.white
                                    : info.borderColor,
                                width: fotoUrl.isNotEmpty ? 2.5 : 1,
                              ),
                              image: fotoUrl.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(fotoUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: fotoUrl.isEmpty
                                ? Icon(
                                    Icons.storefront_rounded,
                                    color: info.color,
                                    size: 28,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      nomeLoja,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.35,
                                        height: 1.25,
                                        color: PainelAdminTheme.dashboardInk,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: info.bgColor,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: info.borderColor,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      info.label,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                        color: info.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _metaChip(
                                    Icons.person_outline_rounded,
                                    nomeDono,
                                  ),
                                  _metaChip(
                                    Icons.location_on_outlined,
                                    cidade,
                                  ),
                                  if (telefone.isNotEmpty)
                                    _metaChip(
                                      Icons.phone_outlined,
                                      telefone,
                                    ),
                                  if (status == 'aprovada')
                                    _metaChip(
                                      Icons.receipt_long_outlined,
                                      planoId != null
                                          ? 'Plano ativo'
                                          : 'Sem plano',
                                      highlight: planoId == null,
                                    ),
                                ],
                              ),
                              if (motivoRecusa.isNotEmpty &&
                                  status == 'bloqueada') ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          motivoRecusa,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12.5,
                                            color: const Color(0xFF991B1B),
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if ((status == 'bloqueada' || status == 'aprovada') &&
                                ContaBloqueioLojistaHelper
                                    .estaBloqueadoParaOperacoes(dados)) ...[
                              _actionBtn(
                                Icons.lock_open_rounded,
                                'Desbloquear',
                                const Color(0xFF059669),
                                filled: true,
                                onTap: () =>
                                    _desbloquearLoja(doc.id, nomeLoja),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (status == 'pendente') ...[
                              _actionBtn(
                                Icons.description_outlined,
                                'Documentos',
                                const Color(0xFF3B82F6),
                                onTap: () => _mostrarDocumentosModal(dados),
                              ),
                              const SizedBox(height: 8),
                              _actionBtn(
                                Icons.check_circle_outline_rounded,
                                'Aprovar',
                                const Color(0xFF059669),
                                filled: true,
                                onTap: () =>
                                    _alterarStatusLoja(doc.id, 'aprovada'),
                              ),
                              const SizedBox(height: 8),
                              _actionBtn(
                                Icons.close_rounded,
                                'Recusar',
                                const Color(0xFFDC2626),
                                onTap: () =>
                                    _mostrarModalRecusa(doc.id, nomeLoja),
                              ),
                            ] else ...[
                              _buildMaisAcoesLojaMenu(
                                doc: doc,
                                dados: dados,
                                nomeLoja: nomeLoja,
                                planoId: planoId,
                                cidade: cidade,
                                incluirPlanoTaxaEBloquear:
                                    status == 'aprovada' &&
                                        !ContaBloqueioLojistaHelper
                                            .estaBloqueadoParaOperacoes(dados),
                              ),
                            ],
                          ],
                        ),
                      ],
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

  /// Menu ⋮ com Documentos e, se [incluirPlanoTaxaEBloquear], Plano/Taxa e Bloquear.
  Widget _buildMaisAcoesLojaMenu({
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> dados,
    required String nomeLoja,
    required dynamic planoId,
    required String cidade,
    required bool incluirPlanoTaxaEBloquear,
  }) {
    final textStyle = GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: PainelAdminTheme.dashboardInk,
    );
    return PopupMenuButton<_MaisAcoesLoja>(
      tooltip: 'Mais ações',
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      onSelected: (acao) {
        switch (acao) {
          case _MaisAcoesLoja.documentos:
            _mostrarDocumentosModal(dados);
            break;
          case _MaisAcoesLoja.planoTaxa:
            _atribuirPlanoModal(doc.id, nomeLoja, planoId, cidade);
            break;
          case _MaisAcoesLoja.bloquear:
            _mostrarModalBloqueioLojista(doc.id, nomeLoja);
            break;
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<_MaisAcoesLoja>>[
          PopupMenuItem<_MaisAcoesLoja>(
            value: _MaisAcoesLoja.documentos,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 20, color: Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                Text('Documentos', style: textStyle),
              ],
            ),
          ),
        ];
        if (incluirPlanoTaxaEBloquear) {
          entries.add(const PopupMenuDivider(height: 1));
          entries.add(
            PopupMenuItem<_MaisAcoesLoja>(
              value: _MaisAcoesLoja.planoTaxa,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded,
                      size: 20, color: PainelAdminTheme.roxo),
                  const SizedBox(width: 12),
                  Text('Plano/Taxa', style: textStyle),
                ],
              ),
            ),
          );
          entries.add(
            PopupMenuItem<_MaisAcoesLoja>(
              value: _MaisAcoesLoja.bloquear,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.block_rounded,
                      size: 20, color: Color(0xFFDC2626)),
                  const SizedBox(width: 12),
                  Text('Bloquear', style: textStyle),
                ],
              ),
            ),
          );
        }
        return entries;
      },
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 22,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, {bool highlight = false}) {
    final iconColor = highlight
        ? const Color(0xFFB45309)
        : const Color(0xFF64748B);
    final bg = highlight
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFF1F5F9);
    final border = highlight
        ? const Color(0xFFFDE68A)
        : const Color(0xFFE2E8F0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: highlight
                  ? const Color(0xFF92400E)
                  : const Color(0xFF475569),
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color,
      {required VoidCallback onTap, bool filled = false}) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final labelStyle = GoogleFonts.plusJakartaSans(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    return SizedBox(
      width: 138,
      height: 38,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 17),
              label: Text(label, style: labelStyle),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: shape,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 17),
              label: Text(label, style: labelStyle),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                backgroundColor: color.withValues(alpha: 0.06),
                side: BorderSide(color: color.withValues(alpha: 0.22)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: shape,
              ),
            ),
    );
  }

  // ─── bloqueio administrativo (loja aprovada) ───

  Future<void> _desbloquearLoja(String id, String nomeLoja) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final batch = FirebaseFirestore.instance.batch();
    batch.update(ref, {
      'status_loja': ContaBloqueioLojista.statusLojaAtivo,
      'status_conta': ContaBloqueioLojista.statusContaActive,
      'motivo_recusa': FieldValue.delete(),
      'motivo_bloqueio': FieldValue.delete(),
      'recusa_cadastro': FieldValue.delete(),
      'block_active': false,
      'block_type': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'block_start_at': FieldValue.delete(),
      'block_end_at': FieldValue.delete(),
    });
    batch.set(ref.collection('bloqueios_auditoria').doc(), {
      'admin_id': admin.uid,
      'admin_email': admin.email,
      'applied_at': FieldValue.serverTimestamp(),
      'action': 'unblock',
      'loja_nome': nomeLoja,
    });
    try {
      await batch.commit();
      if (!mounted) return;
      mostrarSnackPainel(context,
          mensagem: 'Loja desbloqueada. Auditoria registrada.');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  Future<void> _aplicarBloqueioLojista({
    required String id,
    required String nomeLoja,
    required String blockType,
    required String blockReason,
    int? durationDays,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    Timestamp? endTs;
    if (blockType == ContaBloqueioLojista.blockTemporary &&
        durationDays != null &&
        durationDays > 0) {
      endTs = Timestamp.fromDate(
        DateTime.now().add(Duration(days: durationDays)),
      );
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(id);
    final batch = FirebaseFirestore.instance.batch();
    final statusLojaPainel =
        blockType == ContaBloqueioLojista.blockTemporary
            ? ContaBloqueioLojista.statusLojaBloqueioTemporario
            : ContaBloqueioLojista.statusLojaBloqueado;
    final textoMotivoPainel = blockType == ContaBloqueioLojista.blockFull
        ? 'Pendências financeiras'
        : 'Bloqueio administrativo temporário';
    batch.update(ref, {
      'status_loja': statusLojaPainel,
      'status_conta': ContaBloqueioLojista.statusContaBlocked,
      'motivo_bloqueio': textoMotivoPainel,
      'recusa_cadastro': FieldValue.delete(),
      'block_type': blockType,
      'block_reason': blockReason,
      'block_start_at': FieldValue.serverTimestamp(),
      'block_end_at': endTs,
      'block_active': true,
    });
    batch.set(ref.collection('bloqueios_auditoria').doc(), {
      'admin_id': admin.uid,
      'admin_email': admin.email,
      'applied_at': FieldValue.serverTimestamp(),
      'action': 'block',
      'block_type': blockType,
      'block_reason': blockReason,
      'duration_days': durationDays,
      'loja_nome': nomeLoja,
    });
    try {
      await batch.commit();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabController.index != 2) {
          _tabController.animateTo(2);
        }
      });
      mostrarSnackPainel(context,
          mensagem:
              'Bloqueio aplicado. A loja está na aba Bloqueadas — use Desbloquear para reverter.');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context,
          erro: true,
          mensagem: e.code == 'permission-denied'
              ? 'Sem permissão para esta ação.'
              : 'Erro: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      mostrarSnackPainel(context, erro: true, mensagem: 'Erro: $e');
    }
  }

  void _mostrarModalBloqueioLojista(String id, String nomeLoja) {
    String modo =
        ContaBloqueioLojista.blockFull; // BLOCK_FULL | BLOCK_TEMPORARY
    final diasC = TextEditingController(text: '7');
    bool salvando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.block_rounded,
                          color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bloquear loja',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF991B1B))),
                            Text(nomeLoja,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color:
                                        PainelAdminTheme.textoSecundario),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text('Tipo de bloqueio',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 10),
                  RadioListTile<String>(
                    title: Text('Inadimplência (bloqueio total)',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    subtitle: Text(
                        'Motivo: inadimplência — acesso total suspenso',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: PainelAdminTheme.textoSecundario)),
                    value: ContaBloqueioLojista.blockFull,
                    groupValue: modo,
                    onChanged: (v) => setS(() => modo = v ?? modo),
                  ),
                  RadioListTile<String>(
                    title: Text('Temporário',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    subtitle: Text(
                        'Informe a duração em dias',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: PainelAdminTheme.textoSecundario)),
                    value: ContaBloqueioLojista.blockTemporary,
                    groupValue: modo,
                    onChanged: (v) => setS(() => modo = v ?? modo),
                  ),
                  if (modo == ContaBloqueioLojista.blockTemporary) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: diasC,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Duração (dias)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: salvando
                          ? null
                          : () async {
                              int? dur;
                              if (modo ==
                                  ContaBloqueioLojista.blockTemporary) {
                                dur = int.tryParse(diasC.text.trim());
                                if (dur == null || dur < 1) {
                                  mostrarSnackPainel(ctx,
                                      erro: true,
                                      mensagem:
                                          'Informe a duração em dias (número ≥ 1).');
                                  return;
                                }
                              }
                              setS(() => salvando = true);
                              await _aplicarBloqueioLojista(
                                id: id,
                                nomeLoja: nomeLoja,
                                blockType: modo,
                                blockReason: modo ==
                                        ContaBloqueioLojista.blockFull
                                    ? ContaBloqueioLojista.motivoInadimplencia
                                    : ContaBloqueioLojista.motivoOutros,
                                durationDays: dur,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: salvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Confirmar bloqueio'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── modal recusa ───

  void _mostrarModalRecusa(String id, String nomeLoja) {
    final motivoC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.block_rounded,
                          color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recusar / Bloquear',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF991B1B))),
                            Text(nomeLoja,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color:
                                        PainelAdminTheme.textoSecundario),
                                overflow: TextOverflow.ellipsis),
                          ]),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text(
                      'O lojista verá esta mensagem no aplicativo para poder corrigir.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.4)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: motivoC,
                    maxLines: 3,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Motivo da recusa',
                      hintText: 'Ex: CNPJ inválido, comprovante ilegível…',
                      hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: PainelAdminTheme.textoSecundario),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFDC2626), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: isSalvando
                          ? null
                          : () async {
                              if (motivoC.text.trim().isEmpty) {
                                mostrarSnackPainel(ctx,
                                    erro: true,
                                    mensagem:
                                        'Você precisa digitar um motivo.');
                                return;
                              }
                              setS(() => isSalvando = true);
                              await _alterarStatusLoja(id, 'bloqueada',
                                  motivo: motivoC.text.trim());
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      icon: isSalvando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Confirmar Recusa'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── modal docs ───

  bool _ehPdf(String url) => Uri.tryParse(url)?.path.toLowerCase().endsWith('.pdf') ?? false;

  void _mostrarImagemAmpliada(String url, String titulo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        child: Stack(children: [
          InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            minScale: 0.1,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(500),
            child: Center(
              child: Image.network(url,
                  fit: BoxFit.contain,
                  webHtmlElementStrategy: kIsWeb
                      ? WebHtmlElementStrategy.prefer
                      : WebHtmlElementStrategy.never,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white))),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              color: Colors.black54,
              child: Row(children: [
                Expanded(
                    child: Text(titulo,
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16))),
                IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    'Roda do mouse ou pinça para zoom — arraste para mover',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70, fontSize: 12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _mostrarDocumentosModal(Map<String, dynamic> dados) {
    final nomeLoja = _str(dados['loja_nome'], 'Loja sem nome');
    final tipoDoc = _str(dados['loja_tipo_documento'], 'CNPJ');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.folder_open_rounded,
                        color: Color(0xFF3B82F6), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Documentos',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: PainelAdminTheme.dashboardInk)),
                          Text(nomeLoja,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color:
                                      PainelAdminTheme.textoSecundario)),
                        ]),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Fechar'),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 18,
                                color: PainelAdminTheme.roxo.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Imagens: clique para ampliar. PDFs: pré-visualização abaixo ou nova aba / tela cheia.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDoc('Documento Pessoal (RG/CNH)',
                            _str(dados['loja_url_doc_pessoal'])),
                        if (tipoDoc == 'CPF')
                          _buildDoc('Foto da Vitrine / Local de Venda',
                              _str(dados['loja_url_vitrine']))
                        else
                          _buildDoc('CNPJ / Contrato Social',
                              _str(dados['loja_url_cnpj'])),
                        _buildDoc('Comprovante de Endereço',
                            _str(dados['loja_url_endereco'])),
                      ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _docPreviewAltura = 200.0;

  Widget _buildDoc(String titulo, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 10),
          if (url.isEmpty)
            _docCardShell(
              child: Row(
                children: [
                  Icon(
                    Icons.hide_image_outlined,
                    size: 22,
                    color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Documento não enviado pelo lojista.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: PainelAdminTheme.textoSecundario,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_ehPdf(url))
            _docCardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 32,
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Arquivo PDF',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pré-visualização embutida (navegador). Use nova aba ou tela cheia se preferir.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                height: 1.4,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tela cheia',
                        icon: Icon(
                          Icons.fullscreen_rounded,
                          color: PainelAdminTheme.roxo,
                        ),
                        onPressed: () => showPdfFullscreenDialog(
                          context,
                          url,
                          titulo,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (!await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (mounted) {
                              mostrarSnackPainel(
                                context,
                                erro: true,
                                mensagem: 'Não foi possível abrir o PDF.',
                              );
                            }
                          }
                        },
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                          color: PainelAdminTheme.roxo,
                        ),
                        label: Text(
                          'Nova aba',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  buildPdfPreview(url, height: 360),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.only(top: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final uri = Uri.parse(
                          'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}&embedded=true',
                        );
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          if (mounted) {
                            mostrarSnackPainel(
                              context,
                              erro: true,
                              mensagem: 'Não foi possível abrir o visualizador.',
                            );
                          }
                        }
                      },
                      child: Text(
                        'Se não carregar, abrir com visualizador Google',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: PainelAdminTheme.textoSecundario,
                          decoration: TextDecoration.underline,
                          decorationColor: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _mostrarImagemAmpliada(url, titulo),
                borderRadius: BorderRadius.circular(14),
                child: MouseRegion(
                  cursor: SystemMouseCursors.zoomIn,
                  child: _docCardShell(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            height: _docPreviewAltura,
                            color: const Color(0xFFF1F5F9),
                            alignment: Alignment.center,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              webHtmlElementStrategy: kIsWeb
                                  ? WebHtmlElementStrategy.prefer
                                  : WebHtmlElementStrategy.never,
                              filterQuality: FilterQuality.medium,
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return SizedBox(
                                  height: _docPreviewAltura,
                                  child: Center(
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: PainelAdminTheme.roxo,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => SizedBox(
                                height: _docPreviewAltura,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        color: PainelAdminTheme.textoSecundario,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Erro ao carregar imagem',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: PainelAdminTheme.textoSecundario,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.zoom_in_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Ampliar',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
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
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Container comum para prévias — visual consistente (imagem, PDF, vazio).
  Widget _docCardShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─── modal plano ───

  void _atribuirPlanoModal(
      String lojaId, String nomeLoja, String? planoAtualId, String cidade) {
    String? planoSelecionado = planoAtualId;
    bool isLoading = false;
    final cidadeLower = cidade.trim().toLowerCase();
    final cidadesBusca = <String>['todas'];
    if (cidadeLower.isNotEmpty && cidadeLower != 'todas') {
      cidadesBusca.add(cidadeLower);
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: PainelAdminTheme.roxo.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          color: PainelAdminTheme.roxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Definir plano',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: PainelAdminTheme.dashboardInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nomeLoja,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(
                          Icons.close_rounded,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: PainelAdminTheme.roxo.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Planos disponíveis para '
                                '${cidade.isNotEmpty ? cidade : "todas as cidades"}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: PainelAdminTheme.dashboardInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('planos_taxas')
                            .where('publico', isEqualTo: 'lojista')
                            .where('cidade', whereIn: cidadesBusca)
                            .snapshots(),
                        builder: (_, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              height: 120,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: PainelAdminTheme.roxo,
                                ),
                              ),
                            );
                          }
                          if (!snap.hasData || snap.data!.docs.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 22,
                                    color: const Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Não há planos cadastrados para esta cidade no painel (Configurações → planos). Cadastre um plano ou ajuste a cidade da loja.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        height: 1.45,
                                        color: const Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final planos = snap.data!.docs;
                          if (planoSelecionado != null &&
                              !planos.any((p) => p.id == planoSelecionado)) {
                            planoSelecionado = null;
                          }
                          // ignore: deprecated_member_use
                          return DropdownButtonFormField<String>(
                            value: planoSelecionado,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Plano de comissão',
                              hintText: 'Selecione…',
                              labelStyle: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                              floatingLabelStyle: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                color: PainelAdminTheme.roxo,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: PainelAdminTheme.roxo,
                                  width: 1.8,
                                ),
                              ),
                            ),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            items: planos.map((doc) {
                              final p = doc.data() as Map<String, dynamic>;
                              final nome = _str(p['nome'], 'Sem nome');
                              final valor = '${p['valor'] ?? 0}';
                              final tipo = p['tipo_cobranca'] == 'fixo'
                                  ? 'R\$'
                                  : '%';
                              final freq = _str(p['frequencia'], 'venda');
                              return DropdownMenuItem<String>(
                                value: doc.id,
                                child: Text(
                                  '$nome · $valor$tipo / $freq',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setS(() => planoSelecionado = v),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A taxa passa a valer para novos pedidos conforme regras do plano.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          height: 1.4,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PainelAdminTheme.roxo,
                                side: BorderSide(
                                  color: PainelAdminTheme.roxo
                                      .withValues(alpha: 0.35),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: (isLoading ||
                                      planoSelecionado == null)
                                  ? null
                                  : () async {
                                      setS(() => isLoading = true);
                                      try {
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(lojaId)
                                            .update({
                                          'plano_taxa_id': planoSelecionado
                                        });
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          mostrarSnackPainel(
                                            context,
                                            mensagem:
                                                'Plano atribuído com sucesso!',
                                          );
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          mostrarSnackPainel(
                                            ctx,
                                            erro: true,
                                            mensagem: 'Erro: $e',
                                          );
                                        }
                                      } finally {
                                        setS(() => isLoading = false);
                                      }
                                    },
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded, size: 20),
                              label: Text(
                                isLoading ? 'Salvando…' : 'Salvar plano',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: PainelAdminTheme.roxo,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    PainelAdminTheme.roxo.withValues(
                                        alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
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
}
