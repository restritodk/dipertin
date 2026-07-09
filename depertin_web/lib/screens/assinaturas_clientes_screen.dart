import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/assinatura_cancelamento_motivos.dart';
import '../models/cliente_assinatura_model.dart';
import '../services/assinaturas_clientes_service.dart';
import '../services/firebase_functions_config.dart';
import '../widgets/assinatura_cancelar_plano_modal.dart';
import '../widgets/dipertin_feedback_premium_modal.dart';

// ============================================================
// CONSTANTES DE COR
// ============================================================
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _textoCorpo = Color(0xFF45516F);
const Color _fundoPagina = Color(0xFFF8F8FC);
const Color _bordaCard = Color(0xFFEEEAF6);
const Color _bordaInput = Color(0xFFE9E8F0);
const Color _roxoBtn = Color(0xFF7D20E8);
const Color _roxoCard = Color(0xFF6E22D9);
const Color _roxoCardClaro = Color(0xFFF1E9FF);
const Color _verdeStatus = Color(0xFF16A34A);
const Color _laranjaStatus = Color(0xFFFF7A17);
const Color _laranjaFundo = Color(0xFFFFF3E6);
const Color _vermelhoStatus = Color(0xFFF04438);
const Color _vermelhoFundo = Color(0xFFFEF2F2);
const Color _fundoTabelaCabecalho = Color(0xFFFCFCFE);

/// Grid da tabela Clientes e Assinaturas (total flex = 100 → equivalente a %).
const int _gridFlexLoja = 28;
const int _gridFlexContato = 24;
const int _gridFlexPlano = 18;
const int _gridFlexStatus = 12;
const int _gridFlexCobranca = 12;
const int _gridFlexAcoes = 6;

const EdgeInsets _gridPaddingHorizontal =
    EdgeInsets.symmetric(vertical: 14, horizontal: 16);

// ============================================================
// SCREEN PRINCIPAL (dados via Firestore `assinaturas_clientes`)
// ============================================================
class AssinaturasClientesScreen extends StatefulWidget {
  const AssinaturasClientesScreen({super.key});

  @override
  State<AssinaturasClientesScreen> createState() =>
      _AssinaturasClientesScreenState();
}

class _AssinaturasClientesScreenState extends State<AssinaturasClientesScreen> {
  // --- Filtros ---
  final TextEditingController _buscaCtl = TextEditingController();
  String _filtroStatus = 'Todos';
  String _filtroPlano = 'Todos';
  String _filtroOrdenar = 'Mais recentes';

  // --- Paginação ---
  int _paginaAtual = 1;
  int _itensPorPagina = 10;

  // --- Cache da última snapshot (preenchido no StreamBuilder) ---
  List<ClienteAssinaturaModel> _clientesCache = const [];

  List<String> _planosDisponiveisDe(List<ClienteAssinaturaModel> clientes) =>
      clientes
          .where((c) =>
              _filtroStatus == 'Cancelado'
                  ? c.ehCancelada
                  : c.entraListagemPrincipalAdmin)
          .map((c) => c.planName)
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<ClienteAssinaturaModel> get _clientesOperacionais => _clientesCache
      .where((c) => c.entraListagemPrincipalAdmin)
      .toList();

  List<ClienteAssinaturaModel> _filtrarClientes(
    List<ClienteAssinaturaModel> clientes,
  ) {
    var lista = List<ClienteAssinaturaModel>.from(clientes);

    if (_filtroStatus == 'Cancelado') {
      lista = lista.where((c) => c.ehCancelada).toList();
    } else {
      lista = lista.where((c) => c.entraListagemPrincipalAdmin).toList();

      if (_filtroStatus != 'Todos') {
        lista = lista.where((c) {
          if (_filtroStatus == 'Ativo') return c.status == 'ativo';
          if (_filtroStatus == 'Em atraso') {
            return c.status == 'em_atraso' || c.statusExibicao == 'vencido';
          }
          if (_filtroStatus == 'Suspenso') return c.status == 'suspenso';
          return true;
        }).toList();
      }
    }

    final busca = _buscaCtl.text.trim().toLowerCase();
    if (busca.isNotEmpty) {
      lista = lista.where((c) {
        return c.storeName.toLowerCase().contains(busca) ||
            c.ownerName.toLowerCase().contains(busca) ||
            c.phone.contains(busca) ||
            c.email.toLowerCase().contains(busca);
      }).toList();
    }

    if (_filtroPlano != 'Todos') {
      lista = lista.where((c) => c.planName == _filtroPlano).toList();
    }

    if (_filtroOrdenar == 'Mais recentes') {
      lista.sort((a, b) {
        final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });
    } else if (_filtroOrdenar == 'Próximo vencimento') {
      lista.sort((a, b) {
        final aDate = a.nextBillingDate?.toDate() ?? DateTime(9999);
        final bDate = b.nextBillingDate?.toDate() ?? DateTime(9999);
        return aDate.compareTo(bDate);
      });
    } else if (_filtroOrdenar == 'Maior valor') {
      lista.sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
    } else if (_filtroOrdenar == 'Nome da loja') {
      lista.sort((a, b) => a.storeName.compareTo(b.storeName));
    }

    return lista;
  }

  List<ClienteAssinaturaModel> get _clientesFiltrados =>
      _filtrarClientes(_clientesCache);

  List<ClienteAssinaturaModel> get _clientesPaginados {
    final lista = _clientesFiltrados;
    final start = (_paginaAtual - 1) * _itensPorPagina;
    if (start >= lista.length) return [];
    final end = start + _itensPorPagina;
    return lista.sublist(start, end > lista.length ? lista.length : end);
  }

  int get _totalPaginas =>
      _clientesFiltrados.isEmpty
          ? 1
          : (_clientesFiltrados.length / _itensPorPagina).ceil();

  @override
  void initState() {
    super.initState();
    _buscaCtl.addListener(() {
      setState(() {
        _paginaAtual = 1;
      });
    });
  }

  @override
  void dispose() {
    _buscaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPagina,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: AssinaturasClientesService.stream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (!snapshot.hasData) {
            return _buildLoadingSkeleton();
          }

          _clientesCache = snapshot.data!.docs
              .map(ClienteAssinaturaModel.fromFirestore)
              .toList();

          if (_clientesCache.isEmpty) {
            return _buildEmptyState();
          }

          return _buildConteudo();
        },
      ),
    );
  }

  // ============================================================
  // ESTADO: LOADING SKELETON
  // ============================================================
  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skeletonHeader(),
          const SizedBox(height: 20),
          _skeletonCards(),
          const SizedBox(height: 24),
          _skeletonFiltros(),
          const SizedBox(height: 24),
          _skeletonTabela(),
        ],
      ),
    );
  }

  Widget _skeletonHeader() {
    return Row(
      children: [
        _skeletonBox(48, 48, 12),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonBox(200, 20, 4),
            const SizedBox(height: 6),
            _skeletonBox(320, 14, 4),
          ],
        ),
      ],
    );
  }

  Widget _skeletonCards() {
    final largura = MediaQuery.of(context).size.width - 48;
    final colFlex = largura > 900 ? 4 : (largura > 600 ? 2 : 1);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(
        colFlex,
        (_) => SizedBox(
          width: (largura - 16 * (colFlex - 1)) / colFlex,
          height: 114,
          child: _skeletonBoxFull(12),
        ),
      ),
    );
  }

  Widget _skeletonFiltros() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _bordaCard),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          _skeletonBox(340, 20, 4),
          const Spacer(),
          _skeletonBox(140, 20, 4),
          const SizedBox(width: 12),
          _skeletonBox(140, 20, 4),
          const SizedBox(width: 12),
          _skeletonBox(140, 20, 4),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _skeletonTabela() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCard),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _skeletonRow(),
          const SizedBox(height: 12),
          _skeletonBoxLinha(),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _skeletonBoxLinha(),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _skeletonBoxLinha(),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _skeletonBoxLinha(),
        ],
      ),
    );
  }

  Widget _skeletonRow() {
    return Row(
      children: [
        _skeletonBox(60, 16, 4),
        const SizedBox(width: 12),
        _skeletonBox(80, 16, 4),
        const Spacer(),
        _skeletonBox(60, 16, 4),
      ],
    );
  }

  Widget _skeletonBoxLinha() {
    return Row(
      children: [
        Row(
          children: [
            _skeletonBox(38, 38, 8),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonBox(140, 14, 4),
                const SizedBox(height: 6),
                _skeletonBox(100, 12, 4),
              ],
            ),
          ],
        ),
        const SizedBox(width: 20),
        _skeletonBox(120, 12, 4),
        const Spacer(),
        _skeletonBox(80, 12, 4),
        const SizedBox(width: 16),
        _skeletonBox(60, 24, 12),
        const SizedBox(width: 16),
        _skeletonBox(70, 14, 4),
        const SizedBox(width: 16),
        _skeletonBox(60, 14, 4),
      ],
    );
  }

  Widget _skeletonBox(double w, double h, double radius) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _textoSecundario.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _skeletonBoxFull(double radius) {
    return Container(
      decoration: BoxDecoration(
        color: _textoSecundario.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ============================================================
  // ESTADO: ERRO
  // ============================================================
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _vermelhoFundo,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.error_outline_rounded, size: 36, color: _vermelhoStatus),
            ),
            const SizedBox(height: 20),
            Text(
              'Erro ao carregar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Não foi possível carregar a lista de clientes. Tente novamente.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _roxoBtn,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO: VAZIO
  // ============================================================
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _roxoCardClaro,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.people_alt_rounded, size: 40, color: _roxoCard),
            ),
            const SizedBox(height: 20),
            Text(
              'Nenhum cliente com assinatura ativa',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Os lojistas aparecerão aqui automaticamente quando contratarem um plano ou módulo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: _textoSecundario,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CONTEÚDO PRINCIPAL
  // ============================================================
  Widget _buildConteudo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildFiltros(),
          const SizedBox(height: 20),
          _buildTabela(),
          const SizedBox(height: 20),
          _buildPaginacao(),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _roxoCardClaro,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.people_alt_rounded, size: 24, color: _roxoCard),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clientes e Assinaturas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _textoPrimario,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Gerencie os clientes que possuem planos ativos contratados com você.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARDS DE RESUMO
  // ============================================================
  Widget _buildSummaryCards() {
    final largura = MediaQuery.of(context).size.width - 48;
    final cols = largura > 1100
        ? 4
        : largura > 700
            ? 2
            : 1;
    final gap = 16.0;
    final cardWidth = (largura - gap * (cols - 1)) / cols;

    final operacionais = _clientesOperacionais;

    final totalAtivos =
        operacionais.where((c) => c.contaComoClienteAtivoKpi).length;
    final receitaMensal = operacionais
        .where((c) => c.contaReceitaRecorrenteKpi)
        .fold<double>(0, (total, c) => total + c.monthlyAmount);
    final totalPlanosAtivos =
        operacionais.where((c) => c.contaComoPlanoOperacionalKpi).length;
    final emAtraso = operacionais
        .where((c) => c.status == 'em_atraso' || c.statusExibicao == 'vencido')
        .length;
    final valorAtraso = operacionais
        .where((c) => c.status == 'em_atraso' || c.statusExibicao == 'vencido')
        .fold<double>(0, (total, c) => total + c.monthlyAmount);

    final cancelados =
        _clientesCache.where((c) => c.ehCancelada).length;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                icone: Icons.people_alt_rounded,
                corIcone: _roxoCard,
                corFundo: _roxoCardClaro,
                titulo: 'Clientes ativos',
                valor: '$totalAtivos',
                variacao: cancelados > 0
                    ? '$totalPlanosAtivos em operação · $cancelados cancelado${cancelados == 1 ? '' : 's'}'
                    : '$totalPlanosAtivos contrato${totalPlanosAtivos == 1 ? '' : 's'} em operação',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                icone: Icons.repeat_rounded,
                corIcone: _roxoCard,
                corFundo: _roxoCardClaro,
                titulo: 'Receita mensal recorrente',
                valor: 'R\$ ${receitaMensal.toStringAsFixed(2).replaceAll('.', ',')}',
                variacao: 'Ativos + em atraso',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                icone: Icons.calendar_month_rounded,
                corIcone: _roxoCard,
                corFundo: _roxoCardClaro,
                titulo: 'Planos ativos',
                valor: '$totalPlanosAtivos',
                variacao: 'Contratos em operação',
                variacaoCor: _verdeStatus,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                icone: Icons.warning_amber_rounded,
                corIcone: _laranjaStatus,
                corFundo: _laranjaFundo,
                titulo: 'Em atraso',
                valor: '$emAtraso',
                variacao: 'R\$ ${valorAtraso.toStringAsFixed(2).replaceAll('.', ',')} em aberto',
                variacaoCor: _vermelhoStatus,
              ),
            ),
          ],
        );
  }

  // ============================================================
  // FILTROS
  // ============================================================
  Widget _buildFiltros() {
    final larga = MediaQuery.of(context).size.width > 948;

    if (larga) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Campo de busca
                SizedBox(
                  width: 420,
                  height: 46,
                  child: TextField(
                    controller: _buscaCtl,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _textoPrimario,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome, e-mail ou telefone...',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: _textoSecundario,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: _textoSecundario, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _bordaInput),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _bordaInput),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _roxoCard, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _FiltroDropdown(
                  label: 'Status do plano',
                  valor: _filtroStatus,
                  itens: const ['Todos', 'Ativo', 'Em atraso', 'Suspenso', 'Cancelado'],
                  onChanged: (v) {
                    setState(() {
                      _filtroStatus = v;
                      _paginaAtual = 1;
                    });
                  },
                  largura: 190,
                ),
                const SizedBox(width: 12),
                _FiltroDropdown(
                  label: 'Plano contratado',
                  valor: _filtroPlano,
                  itens: ['Todos', ..._planosDisponiveisDe(_clientesCache)],
                  onChanged: (v) {
                    setState(() {
                      _filtroPlano = v;
                      _paginaAtual = 1;
                    });
                  },
                  largura: 190,
                ),
                const SizedBox(width: 12),
                _FiltroDropdown(
                  label: 'Ordenar por',
                  valor: _filtroOrdenar,
                  itens: [
                    'Mais recentes',
                    'Próximo vencimento',
                    'Maior valor',
                    'Nome da loja',
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filtroOrdenar = v;
                      _paginaAtual = 1;
                    });
                  },
                  largura: 190,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _buscaCtl.clear();
                      _filtroStatus = 'Todos';
                      _filtroPlano = 'Todos';
                      _filtroOrdenar = 'Mais recentes';
                      _paginaAtual = 1;
                    });
                  },
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: Text(
                    'Limpar filtros',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _roxoCard,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD4C8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 42),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextField(
                  controller: _buscaCtl,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _textoPrimario,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _textoSecundario,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: _textoSecundario, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _bordaInput),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _bordaInput),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _roxoCard, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FiltroDropdownCompact(
                    label: 'Status',
                    valor: _filtroStatus,
                    itens: const ['Todos', 'Ativo', 'Em atraso', 'Suspenso', 'Cancelado'],
                    onChanged: (v) {
                      setState(() {
                        _filtroStatus = v;
                        _paginaAtual = 1;
                      });
                    },
                  ),
                  _FiltroDropdownCompact(
                    label: 'Plano',
                    valor: _filtroPlano,
                    itens: ['Todos', ..._planosDisponiveisDe(_clientesCache)],
                    onChanged: (v) {
                      setState(() {
                        _filtroPlano = v;
                        _paginaAtual = 1;
                      });
                    },
                  ),
                  _FiltroDropdownCompact(
                    label: 'Ordenar',
                    valor: _filtroOrdenar,
                    itens: [
                      'Mais recentes',
                      'Próximo vencimento',
                      'Maior valor',
                      'Nome da loja',
                    ],
                    onChanged: (v) {
                      setState(() {
                        _filtroOrdenar = v;
                          _paginaAtual = 1;
                      });
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _buscaCtl.clear();
                        _filtroStatus = 'Todos';
                        _filtroPlano = 'Todos';
                        _filtroOrdenar = 'Mais recentes';
                        _paginaAtual = 1;
                      });
                    },
                    icon: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: Text(
                      'Limpar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _roxoCard,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD4C8F0)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
  }

  // ============================================================
  // TABELA PRINCIPAL
  // ============================================================
  Widget _buildTabela() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabeçalho — mesmo grid das linhas
          Container(
            color: _fundoTabelaCabecalho,
            padding: _gridPaddingHorizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _colCabecalho('Loja / Lojista', flex: _gridFlexLoja),
                _colCabecalho('Contato', flex: _gridFlexContato),
                _colCabecalho('Plano contratado', flex: _gridFlexPlano),
                _colCabecalho('Status', flex: _gridFlexStatus),
                _colCabecalho('Próx. cobrança', flex: _gridFlexCobranca),
                _colCabecalho('Ações', flex: _gridFlexAcoes, center: true),
              ],
            ),
          ),
          if (_clientesFiltrados.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              child: Center(
                child: Text(
                  _filtroStatus == 'Cancelado'
                      ? 'Nenhum plano cancelado encontrado.'
                      : _filtroStatus == 'Todos' &&
                              _clientesOperacionais.isEmpty
                          ? 'Nenhum cliente com plano ativo no momento. Planos cancelados ficam disponíveis no filtro "Cancelado".'
                          : 'Nenhum cliente encontrado com os filtros aplicados.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _textoSecundario,
                  ),
                ),
              ),
            )
          else
            ...List.generate(_clientesPaginados.length, (i) {
              final cliente = _clientesPaginados[i];
              final isUltimo = i == _clientesPaginados.length - 1;
              return _buildLinha(cliente, isUltimo: isUltimo);
            }),
        ],
      ),
    );
  }

  Widget _colCabecalho(
    String label, {
    required int flex,
    bool center = false,
  }) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _textoSecundario,
      ),
    );

    return Expanded(
      flex: flex,
      child: center ? Center(child: text) : text,
    );
  }

  Widget _buildLinha(ClienteAssinaturaModel cliente, {bool isUltimo = false}) {
    return Container(
      padding: _gridPaddingHorizontal.copyWith(top: 16, bottom: 16),
      decoration: BoxDecoration(
        border: isUltimo
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0EFF5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Loja / Lojista — 28%
          Expanded(
            flex: _gridFlexLoja,
            child: Row(
              children: [
                _AvatarLoja(nome: cliente.storeName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cliente.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Contato — 24%
          Expanded(
            flex: _gridFlexContato,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ContatoLinha(
                  icone: Icons.phone_rounded,
                  texto: cliente.phone,
                ),
                const SizedBox(height: 4),
                _ContatoLinha(
                  icone: Icons.email_rounded,
                  texto: cliente.email,
                ),
              ],
            ),
          ),
          // Plano contratado — 18%
          Expanded(
            flex: _gridFlexPlano,
            child: Text(
              cliente.planName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _roxoCard,
              ),
            ),
          ),
          // Status — 12% (badge só ocupa o necessário)
          Expanded(
            flex: _gridFlexStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _StatusBadgeDinamico(cliente: cliente),
            ),
          ),
          // Próxima cobrança — 12%
          Expanded(
            flex: _gridFlexCobranca,
            child: Text(
              cliente.nextBillingDateExibir,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cliente.statusExibicao == 'vencido'
                    ? _vermelhoStatus
                    : _textoCorpo,
              ),
            ),
          ),
          // Ações — 6% (⋮ centralizado)
          Expanded(
            flex: _gridFlexAcoes,
            child: Center(child: _buildMenuAcoes(cliente)),
          ),
        ],
      ),
    );
  }

  bool _clienteModulosSuspensos(ClienteAssinaturaModel cliente) {
    return cliente.status == 'suspenso';
  }

  bool _podeAlternarBloqueioModulos(ClienteAssinaturaModel cliente) {
    return !cliente.ehCancelada;
  }

  Widget _buildMenuAcoes(ClienteAssinaturaModel cliente) {
    final suspenso = _clienteModulosSuspensos(cliente);
    final podeAlternarBloqueio = _podeAlternarBloqueioModulos(cliente);

    return PopupMenuButton<String>(
      offset: const Offset(-140, 40),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE0D8EE)),
      ),
      shadowColor: Colors.black.withValues(alpha: 0.15),
      onSelected: (value) {
        if (value == 'bloquear') {
          _confirmarBloqueio(cliente);
        } else if (value == 'desbloquear') {
          _confirmarDesbloqueio(cliente);
        } else if (value == 'extrato') {
          _abrirModalExtrato(cliente);
        } else if (value == 'cobranca') {
          _abrirModalCobranca(cliente);
        } else if (value == 'cancelar') {
          _confirmarCancelamentoPlano(cliente);
        }
      },
      itemBuilder: (_) => [
        if (podeAlternarBloqueio && suspenso)
          _menuItemPop(
            Icons.lock_open_rounded,
            'Desbloquear',
            _verdeStatus,
            'desbloquear',
          )
        else if (podeAlternarBloqueio)
          _menuItemPop(
            Icons.block_rounded,
            'Bloquear',
            _vermelhoStatus,
            'bloquear',
          ),
        if (podeAlternarBloqueio) const PopupMenuDivider(),
        _menuItemPop(
          Icons.receipt_long_rounded,
          'Extrato de pagamento',
          _textoPrimario,
          'extrato',
        ),
        const PopupMenuDivider(),
        _menuItemPop(
          Icons.send_rounded,
          'Enviar cobrança',
          _textoPrimario,
          'cobranca',
        ),
        if (podeAlternarBloqueio) ...[
          const PopupMenuDivider(),
          _menuItemPop(
            Icons.cancel_outlined,
            'Cancelar plano',
            _vermelhoStatus,
            'cancelar',
          ),
        ],
      ],
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD4C8F0)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: const Icon(Icons.more_vert_rounded, size: 18, color: _roxoCard),
      ),
    );
  }

  static PopupMenuItem<String> _menuItemPop(
    IconData icone,
    String label,
    Color cor,
    String value,
  ) {
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icone, size: 17, color: cor),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ativo':
        return 'Ativo';
      case 'em_atraso':
        return 'Em atraso';
      case 'suspenso':
        return 'Suspenso';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  // ============================================================
  // MODAL: EXTRATO DE PAGAMENTO
  // ============================================================
  void _abrirModalExtrato(ClienteAssinaturaModel cliente) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _roxoCardClaro,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, size: 22, color: _roxoCard),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extrato de pagamento',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textoPrimario,
                          ),
                        ),
                        Text(
                          cliente.storeName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _bordaCard),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close_rounded, size: 18, color: _textoSecundario),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: _bordaCard),
              const SizedBox(height: 20),

              // Info do plano
              _extratoLinha('Plano', cliente.planName, _roxoCard),
              const SizedBox(height: 10),
              _extratoLinha('Valor mensal',
                  'R\$ ${cliente.monthlyAmount.toStringAsFixed(2).replaceAll('.', ',')}',
                  _textoPrimario),
              const SizedBox(height: 10),
              _extratoLinha('Status', cliente.statusExibicaoRotulo,
                  cliente.statusExibicaoCor),
              const SizedBox(height: 10),
              _extratoLinha('Próxima cobrança', cliente.nextBillingDateExibir, _textoCorpo),
              if (cliente.lastPaymentDate != null) ...[
                const SizedBox(height: 10),
                _extratoLinha('Último pagamento',
                    DateFormat('dd/MM/yyyy').format(cliente.lastPaymentDate!.toDate()),
                    _textoCorpo),
              ],
              const SizedBox(height: 10),
              _extratoLinha('Gateway', cliente.gateway, _textoSecundario),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: _roxoCardClaro,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Fechar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _roxoCard,
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

  static Widget _extratoLinha(String label, String valor, Color corValor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoSecundario,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: corValor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MODAL: ENVIAR COBRANÇA
  // ============================================================
  void _abrirModalCobranca(ClienteAssinaturaModel cliente) {
    final mensagemCtl = TextEditingController(
      text:
          'Olá, ${cliente.ownerName}. Identificamos uma cobrança pendente referente ao plano ${cliente.planName}. Você pode realizar o pagamento pelo link abaixo.',
    );
    var canalSelecionado = 'email';

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _bordaCard)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Enviar cobrança',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: _textoSecundario,
                    ),
                  ],
                ),
              ),
              // Conteúdo
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Info da cobrança
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _roxoCardClaro,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          _linhaCobranca('Loja', cliente.storeName),
                          const SizedBox(height: 6),
                          _linhaCobranca('Plano', cliente.planName),
                          const SizedBox(height: 6),
                          _linhaCobranca(
                            'Valor',
                            'R\$ ${cliente.monthlyAmount.toStringAsFixed(2).replaceAll('.', ',')}',
                          ),
                          const SizedBox(height: 6),
                          _linhaCobranca('Vencimento', cliente.nextBillingDateExibir),
                          const SizedBox(height: 6),
                          _linhaCobranca(
                            'Status',
                            _statusLabel(cliente.status),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Opções de envio
                    Text(
                      'Opções de envio',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _opcaoEnvio(
                          icone: Icons.email_rounded,
                          label: 'E-mail',
                          descricao: cliente.email,
                          onTap: () =>
                              setDialogState(() => canalSelecionado = 'email'),
                        ),
                        const SizedBox(width: 10),
                        _opcaoEnvio(
                          icone: Icons.chat_rounded,
                          label: 'WhatsApp',
                          descricao: cliente.phone,
                          onTap: () => setDialogState(
                              () => canalSelecionado = 'whatsapp'),
                        ),
                        const SizedBox(width: 10),
                        _opcaoEnvio(
                          icone: Icons.link_rounded,
                          label: 'Copiar link',
                          descricao: 'Link de pagamento',
                          onTap: () =>
                              setDialogState(() => canalSelecionado = 'link'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Mensagem personalizada
                    Text(
                      'Mensagem personalizada',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mensagemCtl,
                      maxLines: 5,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _textoPrimario,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _bordaInput),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: _roxoCard, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _bordaCard)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD4C8F0)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        backgroundColor: Colors.white,
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textoSecundario,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        try {
                          await AssinaturasClientesService
                              .registrarCobrancaEnviada(
                            id: cliente.id,
                            canal: canalSelecionado,
                            mensagem: mensagemCtl.text,
                          );
                          if (!mounted) return;
                          final canalLabel = switch (canalSelecionado) {
                            'email' => 'E-mail',
                            'whatsapp' => 'WhatsApp',
                            'link' => 'Link de pagamento',
                            _ => canalSelecionado,
                          };
                          await mostrarDiPertinFeedbackPremium(
                            context,
                            sucesso: true,
                            titulo: 'Cobrança registrada',
                            mensagem:
                                'O envio foi registrado no histórico da assinatura.',
                            detalhes: [
                              DiPertinFeedbackDetalhe(
                                rotulo: 'Loja',
                                valor: cliente.storeName,
                                icone: Icons.storefront_rounded,
                              ),
                              DiPertinFeedbackDetalhe(
                                rotulo: 'Canal',
                                valor: canalLabel,
                                icone: Icons.send_rounded,
                              ),
                            ],
                          );
                        } catch (e) {
                          if (!mounted) return;
                          await mostrarDiPertinFeedbackPremium(
                            context,
                            sucesso: false,
                            titulo: 'Não foi possível registrar',
                            mensagem:
                                'Ocorreu um erro ao salvar a cobrança. Tente novamente.',
                            detalhes: [
                              DiPertinFeedbackDetalhe(
                                rotulo: 'Detalhe',
                                valor: e.toString(),
                                icone: Icons.error_outline_rounded,
                              ),
                            ],
                          );
                        } finally {
                          mensagemCtl.dispose();
                        }
                      },
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Enviar cobrança'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _roxoBtn,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
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

  Widget _linhaCobranca(String label, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _roxoCard,
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _roxoCard,
          ),
        ),
      ],
    );
  }

  Widget _opcaoEnvio({
    required IconData icone,
    required String label,
    required String descricao,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _bordaInput),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icone, size: 22, color: _roxoCard),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textoPrimario,
                ),
              ),
              Text(
                descricao,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: _textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DIÁLOGO: BLOQUEAR CLIENTE
  // ============================================================
  Future<void> _confirmarBloqueio(ClienteAssinaturaModel cliente) async {
    final motivoCtl = TextEditingController();
    bool enviarNotificacao = true;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _vermelhoFundo,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 28,
                          color: _vermelhoStatus,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Bloquear acesso ao módulo?',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Você está prestes a suspender o acesso de ${cliente.storeName} aos módulos contratados.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: _textoSecundario,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _laranjaFundo,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _laranjaStatus.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded,
                            size: 18, color: _laranjaStatus),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O bloqueio não afetará pedidos, cardápio, entregas ou o painel principal da loja. Apenas os módulos extras vinculados à assinatura serão suspensos.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF92400E),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Motivo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motivo do bloqueio (opcional)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: motivoCtl,
                        maxLines: 3,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Descreva o motivo...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _bordaInput),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _bordaInput),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: _roxoCard, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Checkbox notificação
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: enviarNotificacao,
                          onChanged: (v) =>
                              setDialogState(() => enviarNotificacao = v!),
                          activeColor: _roxoCard,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Enviar notificação ao lojista',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _bordaCard)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD4C8F0)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          backgroundColor: Colors.white,
                        ),
                        child: Text(
                          'Voltar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textoSecundario,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.lock_rounded, size: 16),
                        label: const Text('Bloquear módulos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _vermelhoStatus,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
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

    if (result == true) {
      try {
        await AssinaturasClientesService.bloquearModulos(
          id: cliente.id,
          motivo: motivoCtl.text,
          enviarNotificacao: enviarNotificacao,
        );
        if (!mounted) return;
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: true,
          titulo: 'Gestão Comercial suspenso',
          mensagem:
              'O lojista verá apenas a tela de bloqueio até você reativar o acesso.',
          detalhes: [
            DiPertinFeedbackDetalhe(
              rotulo: 'Loja',
              valor: cliente.storeName,
              icone: Icons.storefront_rounded,
            ),
            DiPertinFeedbackDetalhe(
              rotulo: 'Plano',
              valor: cliente.planName,
              icone: Icons.workspace_premium_rounded,
            ),
            if (motivoCtl.text.trim().isNotEmpty)
              DiPertinFeedbackDetalhe(
                rotulo: 'Motivo informado',
                valor: motivoCtl.text.trim(),
                icone: Icons.chat_bubble_outline_rounded,
              ),
            DiPertinFeedbackDetalhe(
              rotulo: 'Notificação ao lojista',
              valor: enviarNotificacao ? 'Marcada para envio' : 'Não solicitada',
              icone: Icons.notifications_outlined,
            ),
          ],
        );
      } catch (e) {
        if (!mounted) return;
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: false,
          titulo: 'Falha ao suspender acesso',
          mensagem:
              'Não foi possível bloquear o Gestão Comercial deste cliente.',
          detalhes: [
            DiPertinFeedbackDetalhe(
              rotulo: 'Detalhe',
              valor: e.toString(),
              icone: Icons.error_outline_rounded,
            ),
          ],
        );
      }
    }
    motivoCtl.dispose();
  }

  // ============================================================
  // DIÁLOGO: DESBLOQUEAR CLIENTE
  // ============================================================
  Future<void> _confirmarDesbloqueio(ClienteAssinaturaModel cliente) async {
    final observacaoCtl = TextEditingController();
    bool enviarNotificacao = true;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          size: 28,
                          color: _verdeStatus,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Desbloquear acesso ao módulo?',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Você está prestes a reativar o acesso de ${cliente.storeName} aos módulos contratados.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: _textoSecundario,
                          height: 1.4,
                        ),
                      ),
                      if (cliente.blockReason?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Motivo do bloqueio anterior: ${cliente.blockReason}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _textoSecundario,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Observação (opcional)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: observacaoCtl,
                        maxLines: 3,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Descreva o motivo da reativação...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: _textoSecundario,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _bordaInput),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _bordaInput),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: _roxoCard,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: enviarNotificacao,
                          onChanged: (v) =>
                              setDialogState(() => enviarNotificacao = v!),
                          activeColor: _roxoCard,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Enviar notificação ao lojista',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _bordaCard)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD4C8F0)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: Text(
                          'Voltar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textoSecundario,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.lock_open_rounded, size: 16),
                        label: const Text('Desbloquear módulos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _verdeStatus,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
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

    if (result == true) {
      try {
        await AssinaturasClientesService.desbloquearModulos(
          id: cliente.id,
          observacao: observacaoCtl.text,
          enviarNotificacao: enviarNotificacao,
        );
        if (!mounted) return;
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: true,
          titulo: 'Acesso reativado',
          mensagem:
              'O lojista já pode usar o Gestão Comercial normalmente.',
          detalhes: [
            DiPertinFeedbackDetalhe(
              rotulo: 'Loja',
              valor: cliente.storeName,
              icone: Icons.storefront_rounded,
            ),
            DiPertinFeedbackDetalhe(
              rotulo: 'Plano',
              valor: cliente.planName,
              icone: Icons.workspace_premium_rounded,
            ),
            if (observacaoCtl.text.trim().isNotEmpty)
              DiPertinFeedbackDetalhe(
                rotulo: 'Observação registrada',
                valor: observacaoCtl.text.trim(),
                icone: Icons.chat_bubble_outline_rounded,
              ),
            DiPertinFeedbackDetalhe(
              rotulo: 'Notificação ao lojista',
              valor: enviarNotificacao ? 'Marcada para envio' : 'Não solicitada',
              icone: Icons.notifications_outlined,
            ),
          ],
        );
      } catch (e) {
        if (!mounted) return;
        await mostrarDiPertinFeedbackPremium(
          context,
          sucesso: false,
          titulo: 'Falha ao reativar acesso',
          mensagem:
              'Não foi possível desbloquear o Gestão Comercial deste cliente.',
          detalhes: [
            DiPertinFeedbackDetalhe(
              rotulo: 'Detalhe',
              valor: e.toString(),
              icone: Icons.error_outline_rounded,
            ),
          ],
        );
      }
    }
    observacaoCtl.dispose();
  }

  // ============================================================
  // CANCELAR PLANO
  // ============================================================
  Future<void> _confirmarCancelamentoPlano(ClienteAssinaturaModel cliente) async {
    final dados = await mostrarAssinaturaCancelarPlanoModal(
      context,
      cliente: cliente,
    );
    if (dados == null || !mounted) return;

    // Não usar await: showDialog só completa quando o modal é fechado.
    mostrarDiPertinLoadingPremium(
      context,
      titulo: 'Cancelando plano…',
      subtitulo: 'Atualizando assinatura e notificando o lojista.',
    );

    try {
      final resultado = await AssinaturasClientesService.cancelarPlano(
        id: cliente.id,
        motivoCodigo: dados.motivoCodigo,
        motivoOutroTexto: dados.motivoOutroTexto,
        observacaoInterna: dados.observacaoInterna,
      );

      if (!mounted) return;
      _fecharLoadingPremiumSeAberto();

      final motivoExibir = dados.motivoOutroTexto?.trim().isNotEmpty == true
          ? dados.motivoOutroTexto!.trim()
          : AssinaturaCancelamentoMotivo.rotuloPorCodigo(dados.motivoCodigo) ??
              dados.motivoCodigo;

      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: true,
        titulo: 'Plano cancelado',
        mensagem:
            'O lojista perderá acesso ao Gestão Comercial e verá a tela de contratação.',
        detalhes: [
          DiPertinFeedbackDetalhe(
            rotulo: 'Loja',
            valor: cliente.storeName,
            icone: Icons.storefront_rounded,
          ),
          DiPertinFeedbackDetalhe(
            rotulo: 'Plano cancelado',
            valor: cliente.planName,
            icone: Icons.workspace_premium_rounded,
          ),
          DiPertinFeedbackDetalhe(
            rotulo: 'Motivo',
            valor: motivoExibir,
            icone: Icons.fact_check_outlined,
          ),
          DiPertinFeedbackDetalhe(
            rotulo: 'E-mail ao lojista',
            valor: resultado.emailEnviado
                ? 'Enviado com sucesso'
                : 'Cancelamento OK, mas o e-mail não foi enviado',
            icone: resultado.emailEnviado
                ? Icons.mark_email_read_outlined
                : Icons.mail_outline_rounded,
          ),
        ],
      );
    } on CallableHttpException catch (e) {
      if (!mounted) return;
      _fecharLoadingPremiumSeAberto();
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Falha ao cancelar plano',
        mensagem: mensagemCallableHttpException(e),
        detalhes: const [
          DiPertinFeedbackDetalhe(
            rotulo: 'Dica',
            valor:
                'Publique a Cloud Function adminCancelarPlanoAssinatura se ainda não fez deploy.',
            icone: Icons.cloud_upload_outlined,
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      _fecharLoadingPremiumSeAberto();
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: false,
        titulo: 'Falha ao cancelar plano',
        mensagem: 'Não foi possível concluir o cancelamento.',
        detalhes: [
          DiPertinFeedbackDetalhe(
            rotulo: 'Detalhe',
            valor: e.toString(),
            icone: Icons.error_outline_rounded,
          ),
        ],
      );
    }
  }

  void _fecharLoadingPremiumSeAberto() {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  // ============================================================
  // PAGINAÇÃO
  // ============================================================
  Widget _buildPaginacao() {
    final total = _clientesFiltrados.length;
    final inicio = (_paginaAtual - 1) * _itensPorPagina + 1;
    final fim = (_paginaAtual * _itensPorPagina > total)
        ? total
        : _paginaAtual * _itensPorPagina;

    return Row(
      children: [
        Text(
          'Mostrando $inicio a $fim de $total clientes',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoSecundario,
          ),
        ),
        const Spacer(),
        if (_totalPaginas > 1) ...[
          // Anterior
          _botaoPagina(
            icone: Icons.chevron_left_rounded,
            onTap: _paginaAtual > 1
                ? () => setState(() => _paginaAtual--)
                : null,
          ),
          const SizedBox(width: 4),
          // Páginas
          ..._buildBotoesPagina(),
          const SizedBox(width: 4),
          // Próximo
          _botaoPagina(
            icone: Icons.chevron_right_rounded,
            onTap: _paginaAtual < _totalPaginas
                ? () => setState(() => _paginaAtual++)
                : null,
          ),
        ],
        const SizedBox(width: 16),
        // Itens por página
        Text(
          'Itens por página',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: _textoSecundario,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: _bordaInput),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _itensPorPagina,
              isDense: true,
              items: [10, 20, 30, 50]
                  .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(
                        '$n',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: _textoPrimario,
                        ),
                      )))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _itensPorPagina = v!;
                  _paginaAtual = 1;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBotoesPagina() {
    final paginas = <Widget>[];
    final total = _totalPaginas;
    final atual = _paginaAtual;

    void addPagina(int p) {
      paginas.add(Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _botaoPaginaNumero(numero: p, ativo: p == atual),
      ));
    }

    void addReticencias() {
      paginas.add(Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            '...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textoSecundario,
            ),
          ),
        ),
      ));
    }

    if (total <= 7) {
      for (var i = 1; i <= total; i++) {
        addPagina(i);
      }
    } else {
      addPagina(1);
      if (atual > 3) addReticencias();
      for (var i = (atual - 1).clamp(2, total - 3);
          i <= (atual + 1).clamp(2, total - 2);
          i++) {
        addPagina(i);
      }
      if (atual < total - 2) addReticencias();
      addPagina(total);
    }

    return paginas;
  }

  Widget _botaoPaginaNumero({required int numero, required bool ativo}) {
    return InkWell(
      onTap: ativo
          ? null
          : () => setState(() => _paginaAtual = numero),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ativo ? _roxoCard : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$numero',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: ativo ? FontWeight.w600 : FontWeight.w400,
            color: ativo ? Colors.white : _textoPrimario,
          ),
        ),
      ),
    );
  }

  Widget _botaoPagina({
    required IconData icone,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap != null ? _bordaInput : _bordaInput.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icone,
          size: 18,
          color: onTap != null ? _textoPrimario : _textoSecundario.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGETS REUTILIZÁVEIS
// ============================================================

// --- AVATAR DA LOJA ---
class _AvatarLoja extends StatelessWidget {
  final String nome;
  const _AvatarLoja({required this.nome});

  @override
  Widget build(BuildContext context) {
    final cores = [
      const Color(0xFF6E22D9),
      const Color(0xFF0E9F6E),
      const Color(0xFF1C64F2),
      const Color(0xFFD03801),
      const Color(0xFF8A2BE2),
      const Color(0xFFE67E22),
    ];
    final idx = nome.hashCode.abs() % cores.length;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: cores[idx].withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          nome.isNotEmpty ? nome[0].toUpperCase() : '?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cores[idx],
          ),
        ),
      ),
    );
  }
}

// --- CONTATO LINHA ---
class _ContatoLinha extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _ContatoLinha({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 12, color: _textoSecundario),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            texto,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoCorpo,
            ),
          ),
        ),
      ],
    );
  }
}

// --- BADGE DE STATUS DINÂMICO ---
class _StatusBadgeDinamico extends StatelessWidget {
  final ClienteAssinaturaModel cliente;
  const _StatusBadgeDinamico({required this.cliente});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: cliente.statusExibicaoFundo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            cliente.statusExibicaoRotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cliente.statusExibicaoCor,
            ),
          ),
        ),
      ],
    );
  }
}

// --- CARD DE RESUMO ---
class _SummaryCard extends StatelessWidget {
  final IconData icone;
  final Color corIcone;
  final Color corFundo;
  final String titulo;
  final String valor;
  final String variacao;
  final Color variacaoCor;

  const _SummaryCard({
    required this.icone,
    required this.corIcone,
    required this.corFundo,
    required this.titulo,
    required this.valor,
    required this.variacao,
    required this.variacaoCor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, size: 22, color: corIcone),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _textoSecundario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  variacao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: variacaoCor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FILTRO DROPDOWN ---
class _FiltroDropdown extends StatelessWidget {
  final String label;
  final String valor;
  final List<String> itens;
  final ValueChanged<String> onChanged;
  final double largura;

  const _FiltroDropdown({
    required this.label,
    required this.valor,
    required this.itens,
    required this.onChanged,
    this.largura = 190,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largura,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordaInput),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          isDense: true,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          items: itens.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textoPrimario,
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// --- FILTRO DROPDOWN COMPACT ---
class _FiltroDropdownCompact extends StatelessWidget {
  final String label;
  final String valor;
  final List<String> itens;
  final ValueChanged<String> onChanged;

  const _FiltroDropdownCompact({
    required this.label,
    required this.valor,
    required this.itens,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordaInput),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isExpanded: true,
          isDense: true,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: _textoPrimario,
          ),
          items: itens.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textoPrimario,
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
