import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial_cliente_form_modal.dart';
import 'package:depertin_web/widgets/comercial_cliente_perfil_modal.dart';
import 'package:depertin_web/widgets/comercial_cliente_recebimento_modal.dart';
import 'package:depertin_web/widgets/dipertin_painel_feedback.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela SaaS de gestão de clientes comerciais — Gestão Comercial lojista.
class LojistaComercialClientesScreen extends StatefulWidget {
  const LojistaComercialClientesScreen({super.key});

  @override
  State<LojistaComercialClientesScreen> createState() =>
      _LojistaComercialClientesScreenState();
}

class _LojistaComercialClientesScreenState
    extends State<LojistaComercialClientesScreen> {
  final _buscaCtrl = TextEditingController();

  String _filtroStatus = 'Todos';
  String _filtroCredito = 'Todos';
  String _filtroPendencia = 'Todos';
  String _ordenacao = 'Mais recentes';
  int _pagina = 1;
  int _itensPorPagina = 5;

  Map<String, ClientePedidoResumo> _resumosPedidos = const {};
  String? _resumosLojaCarregada;

  static const _fundo = Color(0xFFF8F9FC);
  static const _texto = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _borda = Color(0xFFE2E8F0);

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  List<ComercialCliente> _filtrar(List<ComercialCliente> todos) {
    final q = _buscaCtrl.text.trim().toLowerCase();
    var lista = todos.where((c) {
      if (q.isEmpty) return true;
      final cpf = (c.cpf ?? '').replaceAll(RegExp(r'\D'), '');
      return c.nome.toLowerCase().contains(q) ||
          (c.telefone ?? '').contains(q) ||
          cpf.contains(q.replaceAll(RegExp(r'\D'), ''));
    }).toList();

    if (_filtroStatus != 'Todos') {
      lista = lista.where((c) {
        switch (_filtroStatus) {
          case 'Ativo':
            return c.statusExibicao == 'ativo';
          case 'Com pendência':
            return c.statusExibicao == 'com_pendencia';
          case 'Bloqueado':
            return c.statusExibicao == 'bloqueado';
          default:
            return true;
        }
      }).toList();
    }

    if (_filtroCredito == 'Sim') {
      lista = lista.where((c) => c.temCredito).toList();
    } else if (_filtroCredito == 'Não') {
      lista = lista.where((c) => !c.temCredito).toList();
    }

    if (_filtroPendencia == 'Sim') {
      lista = lista.where((c) => c.temPendenciaAberta).toList();
    } else if (_filtroPendencia == 'Não') {
      lista = lista.where((c) => !c.temPendenciaAberta).toList();
    }

    switch (_ordenacao) {
      case 'Nome A-Z':
        lista.sort((a, b) => a.nome.compareTo(b.nome));
        break;
      case 'Maior total comprado':
        lista.sort((a, b) => b.totalComprado.compareTo(a.totalComprado));
        break;
      default:
        lista.sort((a, b) {
          final ta = a.createdAt ?? DateTime(1970);
          final tb = b.createdAt ?? DateTime(1970);
          return tb.compareTo(ta);
        });
    }
    return lista;
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtrl.clear();
      _filtroStatus = 'Todos';
      _filtroCredito = 'Todos';
      _filtroPendencia = 'Todos';
      _pagina = 1;
    });
  }

  Future<void> _novoCliente(String lojaId, {ComercialCliente? editar}) async {
    final r = await mostrarComercialClienteFormModal(
      context,
      lojaId: lojaId,
      cliente: editar,
    );
    if (r != null && mounted) {
      DiPertinPainelFeedback.sucesso(
        context,
        editar != null ? 'Cliente atualizado com sucesso.' : 'Cliente cadastrado com sucesso.',
      );
    }
  }

  void _abrirPerfil(ComercialCliente c, String lojaId) {
    mostrarComercialClientePerfilModal(
      context,
      lojaId: lojaId,
      cliente: c,
      onEditar: () => _novoCliente(lojaId, editar: c),
      onNovaVenda: () => _novaVendaPdv(c),
      onAdicionarCredito: () => _acaoEmBreve('Adicionar crédito — em breve.'),
      onRegistrarRecebimento: () => _abrirRecebimento(c, lojaId),
    );
  }

  void _novaVendaPdv(ComercialCliente c) {
    PdvClientePendente.definir(c.toPdvMap());
    context.navegarPainel('/pdv');
  }

  void _abrirRecebimento(ComercialCliente c, String lojaId) {
    mostrarComercialClienteRecebimentoModal(
      context,
      lojaId: lojaId,
      cliente: c,
    );
  }

  Future<void> _confirmarExclusao(String lojaId, ComercialCliente c) async {
    final ok = await DiPertinPainelFeedback.confirmar(
      context,
      titulo: 'Excluir cliente',
      mensagem: 'Remover "${c.nome}" da base comercial? Esta ação não pode ser desfeita.',
      botaoConfirmar: 'Excluir',
      botaoCancelar: 'Cancelar',
      destrutivo: true,
      icone: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    await ComercialClientesService.excluir(lojaId, c.id);
    if (mounted) {
      DiPertinPainelFeedback.sucesso(context, 'Cliente excluído com sucesso.');
    }
  }

  void _acaoEmBreve(String msg) {
    DiPertinPainelFeedback.info(context, msg);
  }

  Future<void> _carregarResumosPedidos(String lojaId) async {
    try {
      final resumos = await ComercialClientesService.carregarResumosPedidos(lojaId);
      if (!mounted || _resumosLojaCarregada != lojaId) return;
      setState(() => _resumosPedidos = resumos);
    } catch (_) {
      if (mounted) setState(() => _resumosPedidos = const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (_resumosLojaCarregada != uidLoja) {
          _resumosLojaCarregada = uidLoja;
          _resumosPedidos = const {};
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _carregarResumosPedidos(uidLoja),
          );
        }

        return Scaffold(
          backgroundColor: _fundo,
          body: SafeArea(
            child: StreamBuilder<List<ComercialCliente>>(
              stream: ComercialClientesService.streamClientes(uidLoja),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('Erro ao carregar clientes: ${snap.error}'),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
                  );
                }
                final todos = ComercialClientesService.aplicarResumosPedidos(
                  snap.data ?? [],
                  _resumosPedidos,
                );
                final filtrados = _filtrar(todos);
                final ind = ComercialClientesService.calcularIndicadores(todos);
                final totalPag =
                    (filtrados.length / _itensPorPagina).ceil().clamp(1, 99999);
                final paginaAtual = _pagina.clamp(1, totalPag);
                final ini = (paginaAtual - 1) * _itensPorPagina;
                final paginaItens = filtrados
                    .skip(ini)
                    .take(_itensPorPagina)
                    .toList();

                return LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final isMobile = w < 768;
                    final isTablet = w >= 768 && w < 1100;

                    return SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 16 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(uidLoja, isMobile),
                          SizedBox(height: isMobile ? 16 : 24),
                          _buildKpiRow(ind, isMobile, isTablet),
                          const SizedBox(height: 20),
                          _buildFiltros(isMobile, isTablet),
                          const SizedBox(height: 20),
                          _buildLista(
                            filtrados: filtrados,
                            paginaItens: paginaItens,
                            lojaId: uidLoja,
                            isMobile: isMobile,
                          ),
                          const SizedBox(height: 16),
                          _buildPaginacao(
                            total: filtrados.length,
                            ini: ini,
                            fim: (ini + paginaItens.length).clamp(0, filtrados.length),
                            totalPag: totalPag,
                            paginaAtual: paginaAtual,
                            isMobile: isMobile,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String lojaId, bool isMobile) {
    final botoes = [
      OutlinedButton.icon(
        onPressed: () => _acaoEmBreve('Importação de clientes — em breve.'),
        icon: const Icon(Icons.upload_file_rounded, size: 18),
        label: Text(
          isMobile ? 'Importar' : 'Importar clientes',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: PainelAdminTheme.roxo,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.35)),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        onPressed: () => _novoCliente(lojaId),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(
          isMobile ? 'Novo' : '+ Novo Cliente',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: PainelAdminTheme.laranja,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
    ];

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloHeader(),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: botoes[0]), Expanded(child: botoes[2])]),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _tituloHeader()),
        ...botoes,
      ],
    );
  }

  Widget _tituloHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clientes',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _texto,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Gerencie seus clientes, histórico de compras, crédito e relacionamento.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiRow(
    ComercialClientesIndicadores ind,
    bool isMobile,
    bool isTablet,
  ) {
    final cards = [
      _KpiCard(
        titulo: 'Total de clientes',
        valor: ComercialClientesService.formatarNumero(ind.total),
        sub: '100% do total',
        subCor: _muted,
        icon: Icons.people_alt_rounded,
        iconCor: PainelAdminTheme.roxo,
        iconBg: const Color(0xFFEDE9FE),
      ),
      _KpiCard(
        titulo: 'Clientes ativos',
        valor: ComercialClientesService.formatarNumero(ind.ativos),
        sub: '${ind.pct(ind.ativos).toStringAsFixed(1).replaceAll('.', ',')}% do total',
        subCor: const Color(0xFF10B981),
        icon: Icons.person_rounded,
        iconCor: const Color(0xFF10B981),
        iconBg: const Color(0xFFD1FAE5),
      ),
      _KpiCard(
        titulo: 'Com crédito',
        valor: ComercialClientesService.formatarNumero(ind.comCredito),
        sub: '${ind.pct(ind.comCredito).toStringAsFixed(1).replaceAll('.', ',')}% do total',
        subCor: PainelAdminTheme.laranja,
        icon: Icons.account_balance_wallet_outlined,
        iconCor: PainelAdminTheme.laranja,
        iconBg: const Color(0xFFFFF3E0),
      ),
      _KpiCard(
        titulo: 'Com pendências',
        valor: ComercialClientesService.formatarNumero(ind.comPendencias),
        sub: '${ind.pct(ind.comPendencias).toStringAsFixed(1).replaceAll('.', ',')}% do total',
        subCor: const Color(0xFFEF4444),
        icon: Icons.warning_amber_rounded,
        iconCor: const Color(0xFFEF4444),
        iconBg: const Color(0xFFFEE2E2),
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: c,
                ))
            .toList(),
      );
    }

    final cols = isTablet ? 2 : 4;
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 16.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((card) => SizedBox(width: w, child: card)).toList(),
        );
      },
    );
  }

  Widget _buildFiltros(bool isMobile, bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _buscaCtrl,
            onChanged: (_) => setState(() => _pagina = 1),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, telefone ou CPF...',
              hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: _fundo,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borda),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _borda),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: PainelAdminTheme.roxo, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filtroDropdown('Status', _filtroStatus, const [
                'Todos',
                'Ativo',
                'Com pendência',
                'Bloqueado',
              ], (v) => setState(() {
                _filtroStatus = v!;
                _pagina = 1;
              }), largura: 140),
              _filtroDropdown('Com crédito', _filtroCredito, const [
                'Todos',
                'Sim',
                'Não',
              ], (v) => setState(() {
                _filtroCredito = v!;
                _pagina = 1;
              }), largura: 88),
              _filtroDropdown('Com pendência', _filtroPendencia, const [
                'Todos',
                'Sim',
                'Não',
              ], (v) => setState(() {
                _filtroPendencia = v!;
                _pagina = 1;
              }), largura: 88),
              OutlinedButton.icon(
                onPressed: _limparFiltros,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: Text(
                  'Limpar filtros',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.35)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtroDropdown(
    String label,
    String valor,
    List<String> opcoes,
    ValueChanged<String?> onChanged, {
    double largura = 120,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _fundo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borda),
          ),
          child: SizedBox(
            width: largura,
            child: _dropdownString(
              valor: valor,
              opcoes: opcoes,
              onChanged: onChanged,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownString({
    required String valor,
    required List<String> opcoes,
    required ValueChanged<String?> onChanged,
    double fontSize = 12,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: valor,
        isExpanded: true,
        isDense: true,
        style: GoogleFonts.plusJakartaSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: _texto,
        ),
        items: opcoes
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdownInt({
    required int valor,
    required List<int> opcoes,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: valor,
        isExpanded: true,
        isDense: true,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _texto,
        ),
        items: opcoes
            .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildLista({
    required List<ComercialCliente> filtrados,
    required List<ComercialCliente> paginaItens,
    required String lojaId,
    required bool isMobile,
  }) {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Lista de clientes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _texto,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Ordenar por:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: _borda),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _dropdownString(
                                valor: _ordenacao,
                                opcoes: const [
                                  'Mais recentes',
                                  'Nome A-Z',
                                  'Maior total comprado',
                                ],
                                onChanged: (v) => setState(() => _ordenacao = v!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        'Lista de clientes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _texto,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Ordenar por:',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: _borda),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SizedBox(
                          width: 200,
                          child: _dropdownString(
                            valor: _ordenacao,
                            opcoes: const [
                              'Mais recentes',
                              'Nome A-Z',
                              'Maior total comprado',
                            ],
                            onChanged: (v) => setState(() => _ordenacao = v!),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Icon(Icons.people_outline_rounded, size: 48, color: _muted.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhum cliente encontrado',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            )
          else if (isMobile)
            ...paginaItens.map((c) => _ClienteCardMobile(
                  cliente: c,
                  lojaId: lojaId,
                  onPerfil: () => _abrirPerfil(c, lojaId),
                  onNovaVenda: () => _novaVendaPdv(c),
                  onMenu: (a) => _menuAcao(a, lojaId, c),
                ))
          else
            _ClienteTabela(
              itens: paginaItens,
              lojaId: lojaId,
              onPerfil: (c) => _abrirPerfil(c, lojaId),
              onNovaVenda: _novaVendaPdv,
              onMenu: _menuAcao,
            ),
        ],
      ),
    );
  }

  void _menuAcao(String acao, String lojaId, ComercialCliente c) {
    switch (acao) {
      case 'perfil':
        _abrirPerfil(c, lojaId);
      case 'editar':
        _novoCliente(lojaId, editar: c);
      case 'credito':
        _acaoEmBreve('Adicionar crédito — em breve.');
      case 'recebimento':
        _abrirRecebimento(c, lojaId);
      case 'historico':
        _acaoEmBreve('Histórico financeiro — em breve.');
      case 'bloquear':
        ComercialClientesService.bloquear(
          lojaId,
          c.id,
          bloquear: c.status != 'bloqueado',
        );
      case 'excluir':
        _confirmarExclusao(lojaId, c);
    }
  }

  Widget _buildPaginacao({
    required int total,
    required int ini,
    required int fim,
    required int totalPag,
    required int paginaAtual,
    required bool isMobile,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDeco(),
      child: isMobile
          ? Column(
              children: [
                Text(
                  'Mostrando ${total == 0 ? 0 : ini + 1} a $fim de ${ComercialClientesService.formatarNumero(total)} clientes',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                _paginacaoNumerica(totalPag, paginaAtual),
                const SizedBox(height: 12),
                _itensPorPaginaSelector(),
              ],
            )
          : Row(
              children: [
                Text(
                  'Mostrando ${total == 0 ? 0 : ini + 1} a $fim de ${ComercialClientesService.formatarNumero(total)} clientes',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _muted),
                ),
                const Spacer(),
                _paginacaoNumerica(totalPag, paginaAtual),
                const SizedBox(width: 16),
                _itensPorPaginaSelector(),
              ],
            ),
    );
  }

  Widget _itensPorPaginaSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Itens por página:',
          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _borda),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            width: 64,
            child: _dropdownInt(
              valor: _itensPorPagina,
              opcoes: const [5, 10, 25, 50],
              onChanged: (v) => setState(() {
                _itensPorPagina = v!;
                _pagina = 1;
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paginacaoNumerica(int totalPag, int paginaAtual) {
    final paginas = <int>[];
    if (totalPag <= 7) {
      paginas.addAll(List.generate(totalPag, (i) => i + 1));
    } else {
      paginas.addAll([1, 2, 3, 4, 5, -1, totalPag]);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pagBtn(Icons.chevron_left_rounded, paginaAtual > 1, () {
          setState(() => _pagina = paginaAtual - 1);
        }),
        ...paginas.map((p) {
          if (p == -1) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('…', style: GoogleFonts.plusJakartaSans(color: _muted)),
            );
          }
          final ativo = p == paginaAtual;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: ativo ? PainelAdminTheme.roxo : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => setState(() => _pagina = p),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: Text(
                    '$p',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: ativo ? Colors.white : _texto,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        _pagBtn(Icons.chevron_right_rounded, paginaAtual < totalPag, () {
          setState(() => _pagina = paginaAtual + 1);
        }),
      ],
    );
  }

  Widget _pagBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 20),
      color: _texto,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        disabledForegroundColor: _muted.withValues(alpha: 0.4),
      ),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.titulo,
    required this.valor,
    required this.sub,
    required this.subCor,
    required this.icon,
    required this.iconCor,
    required this.iconBg,
  });

  final String titulo;
  final String valor;
  final String sub;
  final Color subCor;
  final IconData icon;
  final Color iconCor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconCor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E1B4B),
                  ),
                ),
                Text(
                  sub,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subCor,
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

class _ClienteTabela extends StatelessWidget {
  const _ClienteTabela({
    required this.itens,
    required this.lojaId,
    required this.onPerfil,
    required this.onNovaVenda,
    required this.onMenu,
  });

  final List<ComercialCliente> itens;
  final String lojaId;
  final void Function(ComercialCliente) onPerfil;
  final void Function(ComercialCliente) onNovaVenda;
  final void Function(String acao, String lojaId, ComercialCliente c) onMenu;

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) return const SizedBox.shrink();

    const wFin = 108.0;
    const wUltima = 100.0;
    const wAcoes = 160.0;
    const padH = 20.0;
    const minCliente = 240.0;
    const tabelaLarguraMin = minCliente + (wFin * 4) + wUltima + wAcoes + (padH * 2);

    Widget linhaGrid({
      required Widget cliente,
      required Widget limite,
      required Widget usado,
      required Widget disponivel,
      required Widget total,
      required Widget ultima,
      required Widget acoes,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: padH),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: cliente),
            SizedBox(width: wFin, child: limite),
            SizedBox(width: wFin, child: usado),
            SizedBox(width: wFin, child: disponivel),
            SizedBox(width: wFin, child: total),
            SizedBox(width: wUltima, child: ultima),
            SizedBox(
              width: wAcoes,
              child: Center(child: acoes),
            ),
          ],
        ),
      );
    }

    Widget tabela = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: linhaGrid(
            cliente: _colHead('CLIENTE'),
            limite: _colHead('LIMITE', align: TextAlign.right),
            usado: _colHead('USADO', align: TextAlign.right),
            disponivel: _colHead('DISPONÍVEL', align: TextAlign.right),
            total: _colHead('TOTAL', align: TextAlign.right),
            ultima: _colHead('ÚLTIMA', align: TextAlign.center),
            acoes: _colHead('AÇÕES', align: TextAlign.center),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itens.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: padH, endIndent: padH),
          itemBuilder: (context, i) {
            final c = itens[i];
            final disp = c.creditoDisponivel;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: linhaGrid(
                cliente: _celulaCliente(c),
                limite: Align(
                  alignment: Alignment.centerRight,
                  child: _valorCelula(
                    ComercialClientesService.formatarMoeda(c.limiteCredito),
                  ),
                ),
                usado: Align(
                  alignment: Alignment.centerRight,
                  child: _valorCelula(
                    ComercialClientesService.formatarMoeda(c.creditoUtilizado),
                    cor: const Color(0xFFFF8F00),
                  ),
                ),
                disponivel: Align(
                  alignment: Alignment.centerRight,
                  child: _valorCelula(
                    ComercialClientesService.formatarMoeda(disp),
                    cor: disp < 0
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                  ),
                ),
                total: Align(
                  alignment: Alignment.centerRight,
                  child: _valorCelula(
                    ComercialClientesService.formatarMoeda(c.totalComprado),
                    bold: true,
                  ),
                ),
                ultima: Align(
                  alignment: Alignment.center,
                  child: Text(
                    ComercialClientesService.formatarData(c.ultimaCompra),
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                acoes: _acoesRow(context, c),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= tabelaLarguraMin) return tabela;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tabelaLarguraMin,
            child: tabela,
          ),
        );
      },
    );
  }

  Widget _colHead(String t, {TextAlign align = TextAlign.left}) => Text(
        t,
        textAlign: align,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
        ),
      );

  Widget _celulaCliente(ComercialCliente c) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: _corAvatar(c.nome),
          child: Text(
            _iniciais(c.nome),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      c.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _badgeStatus(c.statusExibicao),
                ],
              ),
              if (c.telefone != null)
                Text(
                  c.telefone!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
              if (c.cpf != null && c.cpf!.isNotEmpty)
                Text(
                  _fmtCpf(c.cpf!),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valorCelula(String v, {Color? cor, bool bold = false}) {
    return Text(
      v,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: cor ?? const Color(0xFF1E1B4B),
      ),
    );
  }

  Widget _acoesRow(BuildContext context, ComercialCliente c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: 'Ver perfil',
          child: _acaoIcone(
            Icons.visibility_outlined,
            onPerfil,
            c,
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Nova venda',
          child: _acaoIcone(
            Icons.shopping_cart_outlined,
            onNovaVenda,
            c,
          ),
        ),
        _menuMais(context, c),
      ],
    );
  }

  Widget _acaoIcone(
    IconData icon,
    void Function(ComercialCliente) acao,
    ComercialCliente c,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => acao(c),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.35),
            ),
          ),
          child: Icon(icon, size: 18, color: PainelAdminTheme.roxo),
        ),
      ),
    );
  }

  Widget _menuMais(BuildContext context, ComercialCliente c) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (a) => onMenu(a, lojaId, c),
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'perfil', child: Text('Ver perfil')),
        const PopupMenuItem(value: 'editar', child: Text('Editar cliente')),
        const PopupMenuItem(value: 'credito', child: Text('Adicionar crédito')),
        const PopupMenuItem(value: 'recebimento', child: Text('Registrar recebimento')),
        const PopupMenuItem(value: 'historico', child: Text('Histórico financeiro')),
        PopupMenuItem(
          value: 'bloquear',
          child: Text(c.status == 'bloqueado' ? 'Desbloquear cliente' : 'Bloquear cliente'),
        ),
        const PopupMenuItem(
          value: 'excluir',
          child: Text('Excluir cliente', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  static String _iniciais(String nome) {
    final p = nome.trim().split(RegExp(r'\s+'));
    if (p.length >= 2) return (p[0][0] + p[1][0]).toUpperCase();
    return p.first.isNotEmpty ? p.first[0].toUpperCase() : 'C';
  }

  static Color _corAvatar(String nome) {
    const cores = [Color(0xFF6A1B9A), Color(0xFF10B981), Color(0xFF3B82F6)];
    return cores[nome.hashCode.abs() % cores.length];
  }

  static String _fmtCpf(String cpf) {
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return cpf;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }
}

Widget _badgeStatus(String status) {
  final ativo = status == 'ativo';
  final pend = status == 'com_pendencia';
  final label = pend ? 'Com pendência' : (ativo ? 'Ativo' : 'Bloqueado');
  final cor = pend
      ? const Color(0xFFFF8F00)
      : (ativo ? const Color(0xFF10B981) : const Color(0xFF64748B));
  final bg = pend
      ? const Color(0xFFFFF3E0)
      : (ativo ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: cor,
      ),
    ),
  );
}

class _ClienteCardMobile extends StatelessWidget {
  const _ClienteCardMobile({
    required this.cliente,
    required this.lojaId,
    required this.onPerfil,
    required this.onNovaVenda,
    required this.onMenu,
  });

  final ComercialCliente cliente;
  final String lojaId;
  final VoidCallback onPerfil;
  final VoidCallback onNovaVenda;
  final void Function(String) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = cliente;
    final disp = c.creditoDisponivel;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _ClienteTabela._corAvatar(c.nome),
                child: Text(_ClienteTabela._iniciais(c.nome)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nome, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
                    _badgeStatus(c.statusExibicao),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: onMenu,
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'perfil', child: Text('Ver perfil')),
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          _linhaMob('Disponível', ComercialClientesService.formatarMoeda(disp)),
          _linhaMob('Total comprado', ComercialClientesService.formatarMoeda(c.totalComprado)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPerfil,
                  child: const Text('Ver perfil'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onNovaVenda,
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.laranja,
                  ),
                  child: const Text('Nova venda'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linhaMob(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B))),
          Text(v, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
