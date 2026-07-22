import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_config_service.dart';
import 'package:depertin_web/services/comercial_pendencias_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// =============================================================================
// Modal Premium — Todas as Pendências (+30 dias)
// =============================================================================

const Color _kRoxo = Color(0xFF6A1B9A);
const Color _kLaranja = Color(0xFFFF8F00);
const Color _kTexto = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF64748B);
const Color _kFundo = Color(0xFFF5F4F8);
const int _kPageSize = 10;

class _Pendencia30Row {
  const _Pendencia30Row({
    required this.clienteNome,
    required this.valorAtualizado,
    required this.dataCompra,
    required this.diasAtraso,
    required this.parcelaLabel,
  });

  final String clienteNome;
  final double valorAtualizado;
  final DateTime dataCompra;
  final int diasAtraso;
  final String parcelaLabel;
}

/// Abre o modal de todas as pendências com mais de 30 dias de atraso.
Future<void> abrirModalTodasPendencias30Dias({
  required BuildContext context,
  required String lojaId,
  required List<PendenciaFinanceiraCliente> itens,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _TodasPendencias30Modal(
      lojaId: lojaId,
      itensBase: itens,
    ),
  );
}

class _TodasPendencias30Modal extends StatefulWidget {
  const _TodasPendencias30Modal({
    required this.lojaId,
    required this.itensBase,
  });

  final String lojaId;
  final List<PendenciaFinanceiraCliente> itensBase;

  @override
  State<_TodasPendencias30Modal> createState() =>
      _TodasPendencias30ModalState();
}

class _TodasPendencias30ModalState extends State<_TodasPendencias30Modal> {
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  bool _carregando = true;
  List<_Pendencia30Row> _rows = const [];
  int _pagina = 1;

  @override
  void initState() {
    super.initState();
    _recalcular();
  }

  Future<void> _recalcular() async {
    setState(() {
      _carregando = true;
      _pagina = 1;
    });

    final config =
        await ComercialConfigService.carregarJurosMultaConfig(widget.lojaId);
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    final out = <_Pendencia30Row>[];

    for (final item in widget.itensBase) {
      for (final p in item.parcelas) {
        if (p.valorEmAberto <= 0.009) continue;
        final venc = DateTime(
          p.dataVencimento.year,
          p.dataVencimento.month,
          p.dataVencimento.day,
        );
        if (!venc.isBefore(hojeClean)) continue;

        final diasCalendario = hojeClean.difference(venc).inDays;
        if (diasCalendario <= 30) continue;

        final calc = calcularJurosMulta(
          p.valorEmAberto,
          p.dataVencimento,
          config,
        );
        final valorAtualizado = calc.valorAtualizado > 0.009
            ? calc.valorAtualizado
            : p.valorEmAberto;

        final compra = p.dataCompra ?? p.createdAt ?? venc;
        final parcelaLabel = p.codigoVenda.isNotEmpty
            ? 'Parcela ${p.numeroParcela} · ${p.codigoVenda}'
            : 'Parcela ${p.numeroParcela}';

        out.add(_Pendencia30Row(
          clienteNome: item.clienteNome,
          valorAtualizado: valorAtualizado,
          dataCompra: compra,
          diasAtraso: diasCalendario,
          parcelaLabel: parcelaLabel,
        ));
      }
    }

    out.sort((a, b) => b.diasAtraso.compareTo(a.diasAtraso));

    if (!mounted) return;
    setState(() {
      _rows = out;
      _carregando = false;
    });
  }

  int get _totalPaginas =>
      _rows.isEmpty ? 1 : ((_rows.length - 1) ~/ _kPageSize) + 1;

  List<_Pendencia30Row> get _paginaAtual {
    final start = (_pagina - 1) * _kPageSize;
    if (start >= _rows.length) return const [];
    final end = (start + _kPageSize).clamp(0, _rows.length);
    return _rows.sublist(start, end);
  }

  void _fechar() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final maxW = largura < 720 ? largura - 32.0 : 820.0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 720),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          elevation: 24,
          shadowColor: _kRoxo.withValues(alpha: 0.25),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 10, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kRoxo, Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todas as Pendências (+30 dias)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Clientes com débitos vencidos há mais de 30 dias.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _fechar,
            tooltip: 'Fechar',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: _kRoxo),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: const Icon(
                  Icons.inbox_rounded,
                  size: 40,
                  color: _kRoxo,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Nenhuma pendência superior a 30 dias foi encontrada.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kTexto,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quando houver cobranças vencidas há mais de 30 dias, elas aparecerão aqui com o valor atualizado.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: _kMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: _kLaranja),
                    const SizedBox(width: 6),
                    Text(
                      '${_rows.length} cobrança${_rows.length == 1 ? '' : 's'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kLaranja,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Valores recalculados agora',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: _kMuted,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compacto = constraints.maxWidth < 640;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  if (!compacto) _buildTableHeader(),
                  ..._paginaAtual.map(
                    (r) => compacto ? _buildCardMobile(r) : _buildTableRow(r),
                  ),
                ],
              );
            },
          ),
        ),
        if (_totalPaginas > 1) _buildPaginacao(),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDE9FE)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _th('Cliente')),
          Expanded(flex: 2, child: _th('Valor atualizado', alignEnd: true)),
          Expanded(flex: 2, child: _th('Data da compra')),
          Expanded(flex: 2, child: _th('Dias em atraso', alignEnd: true)),
        ],
      ),
    );
  }

  Widget _th(String t, {bool alignEnd = false}) {
    return Text(
      t,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _kMuted,
      ),
    );
  }

  Widget _buildTableRow(_Pendencia30Row r) {
    final inicial =
        r.clienteNome.isNotEmpty ? r.clienteNome[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFF1E9FF),
                  child: Text(
                    inicial,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kRoxo,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.clienteNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kTexto,
                        ),
                      ),
                      Text(
                        r.parcelaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: _kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              ComercialPendenciasService.formatarMoeda(r.valorAtualizado),
              textAlign: TextAlign.end,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFDC2626),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                _dataFmt.format(r.dataCompra),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kTexto,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${r.diasAtraso} dias',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMobile(_Pendencia30Row r) {
    final inicial =
        r.clienteNome.isNotEmpty ? r.clienteNome[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kFundo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF1E9FF),
                child: Text(
                  inicial,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kRoxo,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.clienteNome,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kTexto,
                  ),
                ),
              ),
              Text(
                ComercialPendenciasService.formatarMoeda(r.valorAtualizado),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.parcelaLabel,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _kMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_rounded, size: 14, color: _kLaranja),
              const SizedBox(width: 4),
              Text(
                'Compra ${_dataFmt.format(r.dataCompra)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kTexto,
                ),
              ),
              const Spacer(),
              Text(
                '${r.diasAtraso} dias atraso',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaginacao() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _pagina > 1 ? () => setState(() => _pagina--) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: Text(
              'Anterior',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: _kRoxo),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Página $_pagina de $_totalPaginas',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kRoxo,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _pagina < _totalPaginas
                ? () => setState(() => _pagina++)
                : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: Text(
              'Próxima',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: _kRoxo),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _fechar,
          child: Text(
            'Fechar',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              color: _kMuted,
            ),
          ),
        ),
      ),
    );
  }
}
