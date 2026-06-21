import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre modal central "Perfil rápido do cliente".
Future<void> mostrarComercialClientePerfilModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
  required VoidCallback onEditar,
  required VoidCallback onNovaVenda,
  required VoidCallback onAdicionarCredito,
  required VoidCallback onRegistrarRecebimento,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => _ComercialClientePerfilModal(
      lojaId: lojaId,
      cliente: cliente,
      onFechar: () => Navigator.of(ctx).pop(),
      onEditar: () {
        Navigator.of(ctx).pop();
        onEditar();
      },
      onNovaVenda: () {
        Navigator.of(ctx).pop();
        onNovaVenda();
      },
      onAdicionarCredito: () {
        Navigator.of(ctx).pop();
        onAdicionarCredito();
      },
      onRegistrarRecebimento: onRegistrarRecebimento,
    ),
  );
}

class _ComercialClientePerfilModal extends StatefulWidget {
  const _ComercialClientePerfilModal({
    required this.lojaId,
    required this.cliente,
    required this.onFechar,
    required this.onEditar,
    required this.onNovaVenda,
    required this.onAdicionarCredito,
    required this.onRegistrarRecebimento,
  });

  final String lojaId;
  final ComercialCliente cliente;
  final VoidCallback onFechar;
  final VoidCallback onEditar;
  final VoidCallback onNovaVenda;
  final VoidCallback onAdicionarCredito;
  final VoidCallback onRegistrarRecebimento;

  @override
  State<_ComercialClientePerfilModal> createState() =>
      _ComercialClientePerfilModalState();
}

class _ComercialClientePerfilModalState
    extends State<_ComercialClientePerfilModal> {
  List<ComercialClienteLancamento>? _lancamentos;
  bool _carregandoLancamentos = true;
  String? _erroLancamentos;
  double _totalComprado = 0;
  DateTime? _ultimaCompra;
  ComercialResumoParcelas _resumoParcelas = ComercialResumoParcelas.vazio;

  @override
  void initState() {
    super.initState();
    _carregarDadosPerfil();
  }

  Future<void> _carregarDadosPerfil() async {
    List<ComercialParcelaCliente> parcelas = const [];
    List<ComercialVendaCredito> vendasCredito = const [];
    Map<String, ClientePedidoResumo> resumos = const {};
    List<ComercialClienteLancamento> lista = const [];
    String? erroLanc;

    try {
      parcelas = await ComercialCreditoService.carregarParcelasCliente(
        widget.lojaId,
        widget.cliente.id,
      );
    } catch (_) {}

    try {
      vendasCredito = await ComercialCreditoService.carregarVendasCreditoCliente(
        widget.lojaId,
        widget.cliente.id,
      );
    } catch (_) {}

    try {
      resumos = await ComercialClientesService.carregarResumosPedidos(
        widget.lojaId,
      );
    } catch (_) {}

    try {
      lista = await ComercialClientesService.carregarLancamentosCliente(
        lojaId: widget.lojaId,
        cliente: widget.cliente,
        parcelasCliente: parcelas,
        vendasCredito: vendasCredito,
      );
    } catch (_) {
      erroLanc = lista.isEmpty
          ? 'Não foi possível carregar os lançamentos.'
          : null;
    }

    final resumoPedidos = ComercialClientesService.resumoParaCliente(
      widget.cliente,
      resumos,
    );
    final resumoParc = ComercialCreditoService.calcularResumo(parcelas);
    final historico = ComercialClientesService.melhorResumoHistorico([
      resumoPedidos,
      ComercialClientesService.historicoDeLancamentos(lista),
      ComercialClientesService.historicoDeVendasCredito(vendasCredito),
    ]);

    if (mounted) {
      setState(() {
        _lancamentos = lista;
        _totalComprado = historico.total;
        _ultimaCompra = historico.ultima;
        _resumoParcelas = resumoParc;
        _erroLancamentos = lista.isEmpty ? erroLanc : null;
        _carregandoLancamentos = false;
      });
    }
  }

  ComercialCliente get cliente => widget.cliente;

  static String _iniciais(String nome) {
    final p = nome.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return 'C';
    if (p.length == 1) return p.first.substring(0, 1).toUpperCase();
    return (p.first[0] + p.last[0]).toUpperCase();
  }

  static String _fmtCpf(String? cpf) {
    if (cpf == null || cpf.isEmpty) return '—';
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return cpf;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  static String _fmtTelefone(String? tel) {
    if (tel == null || tel.isEmpty) return '—';
    final d = tel.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return tel;
  }

  static Future<void> _abrirWhatsapp(String tel) async {
    final n = tel.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/55$n');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _abrirDetalheLancamento(ComercialClienteLancamento l) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (ctx) => _LancamentoDetalheDialog(lancamento: l),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disp = cliente.creditoDisponivel;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const _FecharModalIntent(),
      },
      child: Actions(
        actions: {
          _FecharModalIntent: CallbackAction<_FecharModalIntent>(
            onInvoke: (_) {
              widget.onFechar();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720, maxWidth: 850),
              child: Material(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                elevation: 28,
                shadowColor: PainelAdminTheme.roxo.withValues(alpha: 0.22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _secaoTitulo('Dados cadastrais'),
                              const SizedBox(height: 10),
                              _cardConteudo([
                                _linhaDado('CPF', _fmtCpf(cliente.cpf)),
                                _linhaDado('E-mail', cliente.email ?? '—'),
                                _linhaDado(
                                  'Data de cadastro',
                                  ComercialClientesService.formatarData(
                                    cliente.createdAt,
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 22),
                              _secaoTitulo('Crédito'),
                              const SizedBox(height: 10),
                              _buildGridCredito(disp),
                              const SizedBox(height: 22),
                              _secaoTitulo('Histórico'),
                              const SizedBox(height: 10),
                              _cardConteudo([
                                if (_carregandoLancamentos)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  )
                                else ...[
                                  _linhaDado(
                                    'Total comprado',
                                    ComercialClientesService.formatarMoeda(
                                      _totalComprado,
                                    ),
                                    valorDestaque: true,
                                  ),
                                  _linhaDado(
                                    'Última compra',
                                    ComercialClientesService.formatarData(
                                      _ultimaCompra,
                                    ),
                                  ),
                                  _linhaDado(
                                    'Pendências',
                                    ComercialClientesService.rotuloPendenciasCliente(
                                      _resumoParcelas,
                                    ),
                                    valorCor: _resumoParcelas.totalEmAberto > 0.009
                                        ? (_resumoParcelas.parcelasVencidas > 0
                                            ? const Color(0xFFEF4444)
                                            : PainelAdminTheme.laranja)
                                        : const Color(0xFF10B981),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 22),
                              _secaoTitulo('Lançamentos'),
                              const SizedBox(height: 10),
                              _buildSecaoLancamentos(),
                              const SizedBox(height: 22),
                              _buildSecaoParcelasAberto(),
                              const SizedBox(height: 22),
                              _secaoTitulo('Observações'),
                              const SizedBox(height: 10),
                              _cardConteudo([
                                Text(
                                  (cliente.observacoes ?? '').trim().isEmpty
                                      ? 'Nenhuma observação registrada.'
                                      : cliente.observacoes!.trim(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    height: 1.55,
                                    color: (cliente.observacoes ?? '')
                                            .trim()
                                            .isEmpty
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      _buildRodape(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final status = cliente.statusExibicao;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 12, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4A148C),
            Color(0xFF6A1B9A),
            Color(0xFF7B1FA2),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: PainelAdminTheme.laranja.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: PainelAdminTheme.laranja,
              child: Text(
                _iniciais(cliente.nome),
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfil rápido do cliente',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.72),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cliente.nome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _fmtTelefone(cliente.telefone),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _badgeStatusHeader(status),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: widget.onFechar,
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            style: IconButton.styleFrom(
              hoverColor: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeStatusHeader(String status) {
    late Color bg;
    late Color fg;
    late String label;
    late IconData icon;
    switch (status) {
      case 'bloqueado':
        bg = Colors.white.withValues(alpha: 0.18);
        fg = const Color(0xFFFCA5A5);
        label = 'Bloqueado';
        icon = Icons.block_rounded;
      case 'com_pendencia':
        bg = Colors.white.withValues(alpha: 0.18);
        fg = PainelAdminTheme.laranjaSuave;
        label = 'Com pendência';
        icon = Icons.warning_amber_rounded;
      case 'inativo':
        bg = Colors.white.withValues(alpha: 0.14);
        fg = Colors.white.withValues(alpha: 0.75);
        label = 'Inativo';
        icon = Icons.pause_circle_outline_rounded;
      default:
        bg = Colors.white.withValues(alpha: 0.2);
        fg = const Color(0xFF6EE7B7);
        label = 'Ativo';
        icon = Icons.check_circle_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCredito(double disp) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 2;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: w,
              child: _miniCardCredito(
                'Limite',
                ComercialClientesService.formatarMoeda(cliente.limiteCredito),
                PainelAdminTheme.roxo,
              ),
            ),
            SizedBox(
              width: w,
              child: _miniCardCredito(
                'Utilizado',
                ComercialClientesService.formatarMoeda(cliente.creditoUtilizado),
                PainelAdminTheme.laranja,
              ),
            ),
            SizedBox(
              width: w,
              child: _miniCardCredito(
                'Disponível',
                ComercialClientesService.formatarMoeda(disp),
                disp < 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              ),
            ),
            SizedBox(
              width: w,
              child: _miniCardCredito(
                'Cashback',
                ComercialClientesService.formatarMoeda(cliente.cashback),
                const Color(0xFF6366F1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSecaoParcelasAberto() {
    return StreamBuilder<List<ComercialParcelaCliente>>(
      stream: ComercialCreditoService.streamParcelasCliente(
        widget.lojaId,
        cliente.id,
      ),
      builder: (context, snap) {
        final parcelas = snap.data ?? const [];
        final abertas =
            parcelas.where((p) => p.podeReceber).toList(growable: false);
        final resumo = ComercialCreditoService.calcularResumo(parcelas);

        if (snap.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _secaoTitulo('Parcelas em aberto'),
              const SizedBox(height: 10),
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _secaoTitulo('Parcelas em aberto')),
                if (abertas.isNotEmpty)
                  TextButton.icon(
                    onPressed: widget.onRegistrarRecebimento,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Receber'),
                    style: TextButton.styleFrom(
                      foregroundColor: PainelAdminTheme.laranja,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _cardConteudo([
              _linhaDado(
                'Total em aberto',
                ComercialClientesService.formatarMoeda(resumo.totalEmAberto),
                valorDestaque: resumo.totalEmAberto > 0,
                valorCor: resumo.totalEmAberto > 0
                    ? const Color(0xFFEF4444)
                    : null,
              ),
              _linhaDado(
                'Próxima parcela',
                resumo.proximaParcela != null
                    ? '${resumo.proximaParcela!.codigoVenda} · ${ComercialClientesService.formatarMoeda(resumo.proximaParcela!.valorEmAberto)}'
                    : '—',
              ),
              _linhaDado(
                'Parcelas vencidas',
                resumo.parcelasVencidas > 0
                    ? '${resumo.parcelasVencidas}'
                    : 'Nenhuma',
                valorCor: resumo.parcelasVencidas > 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
              ),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildSecaoLancamentos() {
    if (_carregandoLancamentos) {
      return _cardConteudo([
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: PainelAdminTheme.roxo.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ]);
    }

    if (_erroLancamentos != null) {
      return _cardConteudo([
        Text(
          _erroLancamentos!,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFFEF4444),
          ),
        ),
      ]);
    }

    final lista = _lancamentos ?? [];
    if (lista.isEmpty) {
      return _cardConteudo([
        Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 36,
              color: PainelAdminTheme.roxo.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'Nenhum lançamento encontrado para este cliente.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ]);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Scrollbar(
        thumbVisibility: lista.length > 3,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          shrinkWrap: true,
          itemCount: lista.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _LancamentoCard(
            lancamento: lista[i],
            onTap: () => _abrirDetalheLancamento(lista[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildRodape() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ações rápidas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _botaoAcao(
                Icons.point_of_sale_rounded,
                'Nova venda',
                widget.onNovaVenda,
                primario: true,
              ),
              _botaoAcao(Icons.edit_outlined, 'Editar', widget.onEditar),
              _botaoAcao(
                Icons.add_card_rounded,
                'Crédito',
                widget.onAdicionarCredito,
              ),
              _botaoAcao(
                Icons.payments_outlined,
                'Recebimento',
                widget.onRegistrarRecebimento,
              ),
              if (cliente.whatsapp != null && cliente.whatsapp!.isNotEmpty)
                _botaoAcao(
                  Icons.chat_rounded,
                  'WhatsApp',
                  () => _abrirWhatsapp(cliente.whatsapp!),
                  cor: const Color(0xFF25D366),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _secaoTitulo(String t) => Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            t,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
        ],
      );

  Widget _cardConteudo(List<Widget> filhos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF4)),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filhos,
      ),
    );
  }

  Widget _linhaDado(
    String rotulo,
    String valor, {
    bool valorDestaque = false,
    Color? valorCor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              rotulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: valorDestaque ? FontWeight.w800 : FontWeight.w600,
                color: valorCor ?? const Color(0xFF1E1B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCardCredito(String rotulo, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _botaoAcao(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool primario = false,
    Color? cor,
  }) {
    final accent =
        cor ?? (primario ? PainelAdminTheme.laranja : PainelAdminTheme.roxo);
    if (primario) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: accent),
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _LancamentoCard extends StatelessWidget {
  const _LancamentoCard({required this.lancamento, required this.onTap});

  final ComercialClienteLancamento lancamento;
  final VoidCallback onTap;

  Color get _corStatus {
    switch (lancamento.statusRotulo) {
      case 'Pago':
        return const Color(0xFF10B981);
      case 'Em dias':
        return const Color(0xFF6366F1);
      case 'Atrasada':
        return const Color(0xFFEF4444);
      case 'Cancelado':
        return const Color(0xFFEF4444);
      case 'Aguardando pagamento':
        return PainelAdminTheme.laranja;
      default:
        return const Color(0xFF6366F1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewItens = lancamento.itens.take(2).toList();
    final restantes = lancamento.itens.length - previewItens.length;

    return Material(
      color: const Color(0xFFFAFBFD),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: PainelAdminTheme.roxo.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8ECF4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lancamento.codigoExibicao,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ComercialClientesService.formatarDataHora(
                            lancamento.dataHora,
                          ),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _corStatus.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lancamento.statusRotulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _corStatus,
                      ),
                    ),
                  ),
                ],
              ),
              if (previewItens.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...previewItens.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• ${item.nome} x${_qtd(item.quantidade)} — ${ComercialClientesService.formatarMoeda(item.subtotal)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (restantes > 0)
                  Text(
                    '+ $restantes produto${restantes > 1 ? 's' : ''}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.7),
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.payment_rounded,
                    size: 14,
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    lancamento.formaPagamento,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    ComercialClientesService.formatarMoeda(lancamento.total),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _qtd(double q) {
    if ((q - q.round()).abs() < 0.001) return q.round().toString();
    return q.toStringAsFixed(1);
  }
}

class _LancamentoDetalheDialog extends StatelessWidget {
  const _LancamentoDetalheDialog({required this.lancamento});

  final ComercialClienteLancamento lancamento;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalhes da venda',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lancamento.codigoExibicao,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            ComercialClientesService.formatarDataHora(
                              lancamento.dataHora,
                            ),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Produtos',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: const Color(0xFF1E1B4B),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (lancamento.itens.isEmpty)
                        Text(
                          'Sem itens registrados.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        )
                      else
                        ...lancamento.itens.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.nome} x${_LancamentoCard._qtd(item.quantidade)}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  ComercialClientesService.formatarMoeda(
                                    item.subtotal,
                                  ),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: PainelAdminTheme.roxo,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 28),
                      _detLinha('Pagamento', lancamento.formaPagamento),
                      _detLinha(
                        'Subtotal',
                        ComercialClientesService.formatarMoeda(
                          lancamento.subtotal,
                        ),
                      ),
                      if (lancamento.desconto > 0)
                        _detLinha(
                          'Desconto',
                          '- ${ComercialClientesService.formatarMoeda(lancamento.desconto)}',
                          cor: PainelAdminTheme.laranja,
                        ),
                      _detLinha(
                        'Total',
                        ComercialClientesService.formatarMoeda(lancamento.total),
                        destaque: true,
                      ),
                      _detLinha('Status', lancamento.statusRotulo),
                      if (lancamento.observacao != null &&
                          lancamento.observacao!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Observação',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lancamento.observacao!.trim(),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13),
                        ),
                      ],
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

  Widget _detLinha(String rotulo, String valor, {bool destaque = false, Color? cor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            rotulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const Spacer(),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: destaque ? 16 : 13,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: cor ?? (destaque ? PainelAdminTheme.roxo : const Color(0xFF1E1B4B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FecharModalIntent extends Intent {
  const _FecharModalIntent();
}
