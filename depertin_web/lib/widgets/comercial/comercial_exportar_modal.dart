import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_relatorios_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/comercial_credito_relatorios_pdf.dart';
import 'package:depertin_web/utils/pdf_download.dart';
import 'package:depertin_web/widgets/comercial/comercial_modal_ui.dart';
import 'package:depertin_web/widgets/dipertin_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Modal de exportação PDF dos relatórios de Crédito de Clientes.
Future<void> mostrarComercialExportarModal(
  BuildContext context, {
  required String lojaId,
  List<ComercialCliente>? clientesComCreditoFiltrados,
}) async {
  await mostrarComercialModalShell<void>(
    context,
    maxWidth: 560,
    child: _ExportarBody(
      lojaId: lojaId,
      clientesComCreditoFiltrados: clientesComCreditoFiltrados,
    ),
  );
}

class _ExportarBody extends StatefulWidget {
  const _ExportarBody({
    required this.lojaId,
    this.clientesComCreditoFiltrados,
  });

  final String lojaId;
  final List<ComercialCliente>? clientesComCreditoFiltrados;

  @override
  State<_ExportarBody> createState() => _ExportarBodyState();
}

class _ExportarBodyState extends State<_ExportarBody> {
  bool _gerando = false;

  Future<void> _gerarClientes() async {
    if (_gerando) return;
    setState(() => _gerando = true);
    final nav = Navigator.of(context);
    _mostrarLoading(context, 'Gerando relatório de clientes…');
    try {
      final nomeLoja =
          await ComercialCreditoRelatoriosService.nomeLoja(widget.lojaId);
      final dados =
          await ComercialCreditoRelatoriosService.carregarClientesComCredito(
        lojaId: widget.lojaId,
        clientesJaFiltrados: widget.clientesComCreditoFiltrados,
      );
      if (dados.clientes.isEmpty) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        await _resultadoModal(
          context,
          tipo: _ResultadoTipo.semDados,
          titulo: 'Nenhum registro encontrado',
          mensagem: 'Não existem informações para os filtros selecionados.',
        );
        return;
      }
      final geradoEm = DateTime.now();
      final bytes = await ComercialCreditoRelatoriosPdf.clientes(
        nomeLoja: nomeLoja,
        clientes: dados.clientes,
        parcelasAbertas: dados.parcelasAbertas,
        atrasoPorCliente: dados.atrasoPorCliente,
        resumo: dados.resumo,
        geradoEm: geradoEm,
        periodoAplicado: widget.clientesComCreditoFiltrados != null
            ? 'Filtros da tela aplicados'
            : null,
      );
      final stamp = DateFormat('yyyyMMdd_HHmm').format(geradoEm);
      downloadPdfFile(bytes, 'credito_clientes_$stamp.pdf');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.sucesso,
        titulo: 'Relatório gerado com sucesso',
        mensagem: 'O PDF foi preparado e está pronto para download.',
      );
      if (mounted) nav.pop();
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.erro,
        titulo: 'Não foi possível gerar o relatório',
        mensagem: 'Verifique os filtros e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  Future<void> _abrirPendencias() async {
    if (_gerando) return;
    await mostrarComercialModalShell<void>(
      context,
      maxWidth: 520,
      child: _FiltroPendenciasBody(
        lojaId: widget.lojaId,
        onGerado: () {
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _abrirVendas() async {
    if (_gerando) return;
    await mostrarComercialModalShell<void>(
      context,
      maxWidth: 560,
      child: _FiltroVendasBody(
        lojaId: widget.lojaId,
        onGerado: () {
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _abrirRecebimentos() async {
    if (_gerando) return;
    await mostrarComercialModalShell<void>(
      context,
      maxWidth: 520,
      child: _FiltroRecebimentosBody(
        lojaId: widget.lojaId,
        onGerado: () {
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComercialModalHeader(
          titulo: 'Exportar relatório',
          subtitulo: 'Gere relatórios profissionais em PDF',
          icone: Icons.picture_as_pdf_rounded,
          onFechar: _gerando ? () {} : () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OpcaoPdf(
                titulo: 'Clientes',
                desc: 'Lista de clientes com crédito concedido',
                icone: Icons.people_alt_rounded,
                onTap: _gerando ? null : _gerarClientes,
              ),
              _OpcaoPdf(
                titulo: 'Pendências',
                desc: 'Inadimplentes com juros e multa atualizados',
                icone: Icons.warning_amber_rounded,
                onTap: _gerando ? null : _abrirPendencias,
              ),
              _OpcaoPdf(
                titulo: 'Vendas',
                desc: 'Histórico de compras de um cliente',
                icone: Icons.receipt_long_rounded,
                onTap: _gerando ? null : _abrirVendas,
              ),
              _OpcaoPdf(
                titulo: 'Recebimentos',
                desc: 'Pagamentos de parcelas no período',
                icone: Icons.payments_rounded,
                onTap: _gerando ? null : _abrirRecebimentos,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpcaoPdf extends StatefulWidget {
  const _OpcaoPdf({
    required this.titulo,
    required this.desc,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String desc;
  final IconData icone;
  final VoidCallback? onTap;

  @override
  State<_OpcaoPdf> createState() => _OpcaoPdfState();
}

class _OpcaoPdfState extends State<_OpcaoPdf> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ativo = widget.onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: ativo ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hover && ativo ? -1.5 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover && ativo
                  ? PainelAdminTheme.roxo.withValues(alpha: 0.45)
                  : const Color(0xFFE2E8F0),
              width: _hover && ativo ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: PainelAdminTheme.roxo.withValues(
                  alpha: _hover && ativo ? 0.12 : 0.04,
                ),
                blurRadius: _hover && ativo ? 16 : 8,
                offset: Offset(0, _hover && ativo ? 6 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _hover && ativo
                              ? const [Color(0xFF6A1B9A), Color(0xFF8E24AA)]
                              : const [Color(0xFFF3E5F5), Color(0xFFEDE7F6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.icone,
                        color: _hover && ativo
                            ? Colors.white
                            : PainelAdminTheme.roxo,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.titulo,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.desc,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      color: _hover && ativo
                          ? PainelAdminTheme.laranja
                          : PainelAdminTheme.roxo.withValues(alpha: 0.55),
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.download_rounded,
                      color: PainelAdminTheme.roxo.withValues(
                        alpha: ativo ? 0.7 : 0.35,
                      ),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _mostrarLoading(BuildContext context, String mensagem) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => PopScope(
      canPop: false,
      child: _LoadingPremiumDialog(mensagem: mensagem),
    ),
  );
}

class _LoadingPremiumDialog extends StatefulWidget {
  const _LoadingPremiumDialog({required this.mensagem});

  final String mensagem;

  @override
  State<_LoadingPremiumDialog> createState() => _LoadingPremiumDialogState();
}

class _LoadingPremiumDialogState extends State<_LoadingPremiumDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_ctrl.value);
            return Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFF8F6FF)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.25),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 72 + 12 * t,
                        height: 72 + 12 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: PainelAdminTheme.roxo
                              .withValues(alpha: 0.10 + 0.08 * t),
                        ),
                      ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                          ),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Gerando PDF',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.mensagem,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: 0.35 + 0.55 * t,
                      backgroundColor: const Color(0xFFEDE9FE),
                      valueColor: const AlwaysStoppedAnimation(
                        PainelAdminTheme.roxo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Aguarde, preparando o download…',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _ResultadoTipo { sucesso, erro, semDados }

Future<void> _resultadoModal(
  BuildContext context, {
  required _ResultadoTipo tipo,
  required String titulo,
  required String mensagem,
}) async {
  final (Color cor, IconData icone) = switch (tipo) {
    _ResultadoTipo.sucesso => (
        const Color(0xFF10B981),
        Icons.check_circle_rounded
      ),
    _ResultadoTipo.erro => (
        const Color(0xFFEF4444),
        Icons.error_outline_rounded
      ),
    _ResultadoTipo.semDados => (
        PainelAdminTheme.laranja,
        Icons.info_outline_rounded
      ),
  };

  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF8F6FF)],
          ),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [cor, cor.withValues(alpha: 0.75)],
                ),
              ),
              child: Icon(icone, color: Colors.white, size: 32),
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
            const SizedBox(height: 8),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Entendi',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
    ),
  );
}

class _FiltroPendenciasBody extends StatefulWidget {
  const _FiltroPendenciasBody({
    required this.lojaId,
    required this.onGerado,
  });

  final String lojaId;
  final VoidCallback onGerado;

  @override
  State<_FiltroPendenciasBody> createState() => _FiltroPendenciasBodyState();
}

class _FiltroPendenciasBodyState extends State<_FiltroPendenciasBody> {
  DateTime? _de;
  DateTime? _ate;
  ComercialCliente? _cliente;
  String _faixaDias = 'Todas';
  bool _gerando = false;
  List<ComercialCliente> _clientes = const [];

  static const _faixas = <String, (int?, int?)>{
    'Todas': (null, null),
    '1 a 7 dias': (1, 7),
    '8 a 15 dias': (8, 15),
    '16 a 30 dias': (16, 30),
    'Acima de 30 dias': (31, null),
  };

  @override
  void initState() {
    super.initState();
    ComercialClientesService.listar(widget.lojaId).then((lista) {
      if (mounted) setState(() => _clientes = lista);
    });
  }

  bool get _intervaloOk {
    if (_de == null || _ate == null) return true;
    return !_de!.isAfter(_ate!);
  }

  Future<void> _exportar() async {
    if (_gerando || !_intervaloOk) return;
    setState(() => _gerando = true);
    _mostrarLoading(context, 'Gerando relatório de pendências…');
    try {
      final faixa = _faixas[_faixaDias] ?? (null, null);
      final nomeLoja =
          await ComercialCreditoRelatoriosService.nomeLoja(widget.lojaId);
      final dados = await ComercialCreditoRelatoriosService.carregarPendencias(
        lojaId: widget.lojaId,
        vencimentoDe: _de,
        vencimentoAte: _ate,
        clienteId: _cliente?.id,
        diasAtrasoMin: faixa.$1,
        diasAtrasoMax: faixa.$2,
      );
      if (dados.linhas.isEmpty) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        await _resultadoModal(
          context,
          tipo: _ResultadoTipo.semDados,
          titulo: 'Nenhum registro encontrado',
          mensagem: 'Não existem informações para os filtros selecionados.',
        );
        return;
      }
      final geradoEm = DateTime.now();
      final df = DateFormat('dd/MM/yyyy');
      String? periodo;
      if (_de != null || _ate != null) {
        periodo =
            '${_de != null ? df.format(_de!) : '…'} até ${_ate != null ? df.format(_ate!) : '…'}';
      }
      final bytes = await ComercialCreditoRelatoriosPdf.pendencias(
        nomeLoja: nomeLoja,
        linhas: dados.linhas,
        resumo: dados.resumo,
        geradoEm: geradoEm,
        periodoAplicado: periodo,
      );
      downloadPdfFile(
        bytes,
        'credito_pendencias_${DateFormat('yyyyMMdd_HHmm').format(geradoEm)}.pdf',
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.sucesso,
        titulo: 'Relatório gerado com sucesso',
        mensagem: 'O PDF foi preparado e está pronto para download.',
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onGerado();
      }
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.erro,
        titulo: 'Não foi possível gerar o relatório',
        mensagem: 'Verifique os filtros e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComercialModalHeader(
          titulo: 'Filtros — Pendências',
          subtitulo: 'Somente clientes com parcelas vencidas',
          icone: Icons.filter_alt_rounded,
          onFechar: _gerando ? () {} : () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _campoData(
                label: 'Vencimento inicial',
                valor: _de,
                onTap: () async {
                  final d = await showDiPertinDatePicker(
                    context,
                    titulo: 'Data inicial de vencimento',
                    dataInicial: _de ?? DateTime.now(),
                  );
                  if (d != null) setState(() => _de = dataSomenteLocal(d));
                },
              ),
              const SizedBox(height: 12),
              _campoData(
                label: 'Vencimento final',
                valor: _ate,
                onTap: () async {
                  final d = await showDiPertinDatePicker(
                    context,
                    titulo: 'Data final de vencimento',
                    dataInicial: _ate ?? DateTime.now(),
                  );
                  if (d != null) setState(() => _ate = dataSomenteLocal(d));
                },
              ),
              if (!_intervaloOk) ...[
                const SizedBox(height: 8),
                Text(
                  'A data inicial não pode ser posterior à final.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Cliente (opcional)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _cliente?.id,
                isExpanded: true,
                decoration: _inputDeco('Todos os clientes'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos os clientes'),
                  ),
                  ..._clientes.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.nome, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (id) {
                  setState(() {
                    _cliente = id == null
                        ? null
                        : _clientes.where((c) => c.id == id).firstOrNull;
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Faixa de dias em atraso',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _faixaDias,
                decoration: _inputDeco('Faixa'),
                items: _faixas.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _faixaDias = v);
                },
              ),
              const SizedBox(height: 22),
              _botoesAcao(
                podeExportar: _intervaloOk && !_gerando,
                onCancelar: () => Navigator.pop(context),
                onExportar: _exportar,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FiltroVendasBody extends StatefulWidget {
  const _FiltroVendasBody({
    required this.lojaId,
    required this.onGerado,
  });

  final String lojaId;
  final VoidCallback onGerado;

  @override
  State<_FiltroVendasBody> createState() => _FiltroVendasBodyState();
}

class _FiltroVendasBodyState extends State<_FiltroVendasBody> {
  final _buscaCtrl = TextEditingController();
  List<ComercialCliente> _todos = const [];
  List<ComercialCliente> _filtrados = const [];
  ComercialCliente? _selecionado;
  DateTime? _de;
  DateTime? _ate;
  bool _carregando = true;
  bool _buscou = false;
  bool _gerando = false;
  int _pagina = 0;
  static const _porPagina = 8;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await ComercialClientesService.listar(widget.lojaId);
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _filtrados = const [];
        _buscou = false;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  /// Só busca ao confirmar (Enter) — não lista todos de uma vez.
  void _buscarPorEnter([String? raw]) {
    final q = (raw ?? _buscaCtrl.text).trim();
    if (q.isEmpty) {
      setState(() {
        _filtrados = const [];
        _buscou = false;
        _pagina = 0;
      });
      return;
    }
    setState(() {
      _filtrados = ComercialClientesService.filtrarClientesBusca(_todos, q);
      _buscou = true;
      _pagina = 0;
    });
  }

  List<ComercialCliente> get _paginaAtual {
    final ini = _pagina * _porPagina;
    if (ini >= _filtrados.length) return const [];
    return _filtrados.sublist(
      ini,
      (ini + _porPagina).clamp(0, _filtrados.length),
    );
  }

  int get _totalPaginas =>
      _filtrados.isEmpty ? 1 : ((_filtrados.length - 1) ~/ _porPagina) + 1;

  bool get _datasOk {
    if (_de == null || _ate == null) return true;
    return !_de!.isAfter(_ate!);
  }

  Future<void> _exportar() async {
    if (_gerando || _selecionado == null || !_datasOk) return;
    setState(() => _gerando = true);
    _mostrarLoading(context, 'Gerando histórico de vendas…');
    try {
      final nomeLoja =
          await ComercialCreditoRelatoriosService.nomeLoja(widget.lojaId);
      final dados =
          await ComercialCreditoRelatoriosService.carregarVendasCliente(
              lojaId: widget.lojaId,
        cliente: _selecionado!,
        dataDe: _de,
        dataAte: _ate,
      );
      if (dados.vendas.isEmpty) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        await _resultadoModal(
          context,
          tipo: _ResultadoTipo.semDados,
          titulo: 'Nenhum registro encontrado',
          mensagem: 'Não existem informações para os filtros selecionados.',
        );
        return;
      }
      final geradoEm = DateTime.now();
      final df = DateFormat('dd/MM/yyyy');
      String? periodo;
      if (_de != null || _ate != null) {
        periodo =
            '${_de != null ? df.format(_de!) : '…'} até ${_ate != null ? df.format(_ate!) : '…'}';
      }
      final bytes = await ComercialCreditoRelatoriosPdf.vendas(
        nomeLoja: nomeLoja,
        cliente: _selecionado!,
        vendas: dados.vendas,
        resumo: dados.resumo,
        geradoEm: geradoEm,
        periodoAplicado: periodo,
      );
      downloadPdfFile(
        bytes,
        'credito_vendas_${_selecionado!.id}_${DateFormat('yyyyMMdd_HHmm').format(geradoEm)}.pdf',
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.sucesso,
        titulo: 'Relatório gerado com sucesso',
        mensagem: 'O PDF foi preparado e está pronto para download.',
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onGerado();
      }
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.erro,
        titulo: 'Não foi possível gerar o relatório',
        mensagem: 'Verifique os filtros e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ComercialModalHeader(
            titulo: 'Exportar vendas',
            subtitulo: 'Digite nome ou CPF e pressione Enter para buscar',
            icone: Icons.person_search_rounded,
            onFechar: _gerando ? () {} : () => Navigator.pop(context),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _buscaCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _buscarPorEnter,
                    decoration: _inputDeco(
                      'Digite nome ou CPF/CNPJ e pressione Enter…',
                    ).copyWith(
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Buscar',
                        onPressed: _carregando ? null : () => _buscarPorEnter(),
                        icon: const Icon(
                          Icons.keyboard_return_rounded,
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A lista só aparece após a busca — não exibimos todos os clientes.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selecionado != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: PainelAdminTheme.roxo,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: PainelAdminTheme.roxo,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cliente selecionado',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  _selecionado!.nome,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: const Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  ComercialCreditoRelatoriosService
                                      .mascararDocumento(_selecionado!.cpf),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _selecionado = null;
                            }),
                            child: Text(
                              'Trocar',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                color: PainelAdminTheme.roxo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_carregando)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: PainelAdminTheme.roxo,
                        ),
                      ),
                    )
                  else if (!_buscou && _selecionado == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_search_outlined,
                            size: 40,
                            color: PainelAdminTheme.roxo.withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum resultado ainda',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Digite o nome ou CPF/CNPJ e pressione Enter.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_filtrados.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nenhum cliente encontrado para essa busca.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    )
                  else ...[
                    ..._paginaAtual.map((c) {
                      final sel = _selecionado?.id == c.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: sel ? const Color(0xFFF3E5F5) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selecionado = c;
                              _filtrados = const [];
                              _buscou = false;
                              _buscaCtrl.clear();
                            }),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel
                                      ? PainelAdminTheme.roxo
                                      : const Color(0xFFE2E8F0),
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    sel
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: PainelAdminTheme.roxo,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.nome,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: const Color(0xFF1A1A2E),
                                          ),
                                        ),
                                        Text(
                                          ComercialCreditoRelatoriosService
                                              .mascararDocumento(c.cpf),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: const Color(0xFF64748B),
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
                    }),
                    if (_totalPaginas > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _pagina > 0
                                ? () => setState(() => _pagina--)
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text(
                            'Página ${_pagina + 1} de $_totalPaginas',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12),
                          ),
                          IconButton(
                            onPressed: _pagina < _totalPaginas - 1
                                ? () => setState(() => _pagina++)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Período (opcional)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _campoData(
                          label: 'Data inicial',
                          valor: _de,
                          onTap: () async {
                            final d = await showDiPertinDatePicker(
                              context,
                              titulo: 'Data inicial',
                              dataInicial: _de ?? DateTime.now(),
                            );
                            if (d != null) {
                              setState(() => _de = dataSomenteLocal(d));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _campoData(
                          label: 'Data final',
                          valor: _ate,
                          onTap: () async {
                            final d = await showDiPertinDatePicker(
                              context,
                              titulo: 'Data final',
                              dataInicial: _ate ?? DateTime.now(),
                            );
                            if (d != null) {
                              setState(() => _ate = dataSomenteLocal(d));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!_datasOk) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Intervalo de datas inválido.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _botoesAcao(
                    podeExportar:
                        _selecionado != null && _datasOk && !_gerando,
                    onCancelar: () => Navigator.pop(context),
                    onExportar: _exportar,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltroRecebimentosBody extends StatefulWidget {
  const _FiltroRecebimentosBody({
    required this.lojaId,
    required this.onGerado,
  });

  final String lojaId;
  final VoidCallback onGerado;

  @override
  State<_FiltroRecebimentosBody> createState() =>
      _FiltroRecebimentosBodyState();
}

class _FiltroRecebimentosBodyState extends State<_FiltroRecebimentosBody> {
  DateTime? _de;
  DateTime? _ate;
  ComercialCliente? _cliente;
  String _forma = 'Todos';
  String _status = 'Todos';
  bool _gerando = false;
  List<ComercialCliente> _clientes = const [];

  static const _formas = [
    'Todos',
    'Dinheiro',
    'PIX',
    'Cartão',
    'Transferência',
  ];
  static const _statusOpts = ['Todos', 'confirmado', 'estornado'];

  @override
  void initState() {
    super.initState();
    ComercialClientesService.listar(widget.lojaId).then((lista) {
      if (mounted) setState(() => _clientes = lista);
    });
  }

  bool get _intervaloValido =>
      _de != null && _ate != null && !_de!.isAfter(_ate!);

  Future<void> _exportar() async {
    if (_gerando || !_intervaloValido) return;
    setState(() => _gerando = true);
    _mostrarLoading(context, 'Gerando relatório de recebimentos…');
    try {
      final nomeLoja =
          await ComercialCreditoRelatoriosService.nomeLoja(widget.lojaId);
      final dados =
          await ComercialCreditoRelatoriosService.carregarRecebimentos(
        lojaId: widget.lojaId,
        dataDe: _de!,
        dataAte: _ate!,
        clienteId: _cliente?.id,
        formaPagamento: _forma,
        status: _status,
      );
      if (dados.recebimentos.isEmpty) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
        await _resultadoModal(
          context,
          tipo: _ResultadoTipo.semDados,
          titulo: 'Nenhum registro encontrado',
          mensagem: 'Não existem informações para os filtros selecionados.',
        );
        return;
      }
      final geradoEm = DateTime.now();
      final bytes = await ComercialCreditoRelatoriosPdf.recebimentos(
        nomeLoja: nomeLoja,
        recebimentos: dados.recebimentos,
        clientes: dados.clientes,
        resumo: dados.resumo,
        geradoEm: geradoEm,
        dataDe: _de!,
        dataAte: _ate!,
      );
      downloadPdfFile(
        bytes,
        'credito_recebimentos_${DateFormat('yyyyMMdd_HHmm').format(geradoEm)}.pdf',
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.sucesso,
        titulo: 'Relatório gerado com sucesso',
        mensagem: 'O PDF foi preparado e está pronto para download.',
      );
      if (mounted) {
      Navigator.pop(context);
        widget.onGerado();
      }
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      await _resultadoModal(
        context,
        tipo: _ResultadoTipo.erro,
        titulo: 'Não foi possível gerar o relatório',
        mensagem: 'Verifique os filtros e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ComercialModalHeader(
          titulo: 'Filtros — Recebimentos',
          subtitulo: 'Informe o período obrigatório',
          icone: Icons.date_range_rounded,
          onFechar: _gerando ? () {} : () => Navigator.pop(context),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _campoData(
                label: 'Data inicial *',
                valor: _de,
                onTap: () async {
                  final d = await showDiPertinDatePicker(
                    context,
                    titulo: 'Data inicial',
                    dataInicial: _de ?? DateTime.now(),
                  );
                  if (d != null) setState(() => _de = dataSomenteLocal(d));
                },
              ),
              const SizedBox(height: 12),
              _campoData(
                label: 'Data final *',
                valor: _ate,
                onTap: () async {
                  final d = await showDiPertinDatePicker(
                    context,
                    titulo: 'Data final',
                    dataInicial: _ate ?? DateTime.now(),
                  );
                  if (d != null) setState(() => _ate = dataSomenteLocal(d));
                },
              ),
              if (_de != null && _ate != null && !_intervaloValido) ...[
                const SizedBox(height: 8),
                Text(
                  'Intervalo de datas inválido.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Cliente (opcional)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _cliente?.id,
                isExpanded: true,
                decoration: _inputDeco('Todos'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  ..._clientes.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.nome, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (id) {
                  setState(() {
                    _cliente = id == null
                        ? null
                        : _clientes.where((c) => c.id == id).firstOrNull;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _forma,
                decoration: _inputDeco('Forma de pagamento'),
                items: _formas
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _forma = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: _inputDeco('Status'),
                items: _statusOpts
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 22),
              _botoesAcao(
                podeExportar: _intervaloValido && !_gerando,
                onCancelar: () => Navigator.pop(context),
                onExportar: _exportar,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

InputDecoration _inputDeco(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 1.5),
      ),
    );
  }

Widget _campoData({
  required String label,
  required DateTime? valor,
  required VoidCallback onTap,
}) {
  final df = DateFormat('dd/MM/yyyy');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
        ),
      ),
      const SizedBox(height: 6),
      Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: PainelAdminTheme.roxo,
                ),
                const SizedBox(width: 10),
                Text(
                  valor != null ? df.format(valor) : 'Selecionar',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: valor != null
                        ? const Color(0xFF1A1A2E)
                        : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _botoesAcao({
  required bool podeExportar,
  required VoidCallback onCancelar,
  required VoidCallback onExportar,
}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: onCancelar,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Cancelar',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: podeExportar
                  ? const [Color(0xFF6A1B9A), Color(0xFF8E24AA)]
                  : const [Color(0xFFB39DDB), Color(0xFFCE93D8)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: podeExportar ? onExportar : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Exportar PDF',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
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
  );
}
