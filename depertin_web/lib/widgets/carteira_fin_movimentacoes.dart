import 'dart:math' as math;

import 'package:depertin_web/screens/lojista_carteira_financeiro_theme.dart';
import 'package:depertin_web/services/carteira_lojista_extrato.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Lista de movimentações (tabela / lista) com paginação.
///
/// Arquivo dedicado para o hot reload não tentar fundir alterações com a
/// biblioteca antiga em `lojista_carteira_financeiro_widgets.dart`.
class CarteiraFinMovimentacoesCard extends StatelessWidget {
  // Sem `const`: evita falhas de hot reload em classes imutáveis alteradas.
  // ignore: prefer_const_constructors_in_immutables
  CarteiraFinMovimentacoesCard({
    super.key,
    required this.filtrados,
    required this.moeda,
    required this.wide,
  });

  final List<CarteiraLancamento> filtrados;
  final NumberFormat moeda;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return _CarteiraFinMovimentacoesPaginated(
      filtrados: filtrados,
      moeda: moeda,
      wide: wide,
    );
  }
}

class _CarteiraFinMovimentacoesPaginated extends StatefulWidget {
  const _CarteiraFinMovimentacoesPaginated({
    required this.filtrados,
    required this.moeda,
    required this.wide,
  });

  final List<CarteiraLancamento> filtrados;
  final NumberFormat moeda;
  final bool wide;

  @override
  State<_CarteiraFinMovimentacoesPaginated> createState() =>
      _CarteiraFinMovimentacoesPaginatedState();
}

class _CarteiraFinMovimentacoesPaginatedState
    extends State<_CarteiraFinMovimentacoesPaginated> {
  static const double _wValor = 116;
  static const double _wStatus = 132;
  static const double _gapValorStatus = 24;
  static const int _kPageSize = 10;

  int _pageIndex = 0;

  @override
  void didUpdateWidget(_CarteiraFinMovimentacoesPaginated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filtrados.length != widget.filtrados.length) {
      _pageIndex = 0;
    } else {
      final maxIdx = _maxPageIndex(widget.filtrados.length);
      if (_pageIndex > maxIdx) _pageIndex = maxIdx;
    }
  }

  int _maxPageIndex(int total) {
    if (total <= 0) return 0;
    return (total - 1) ~/ _kPageSize;
  }

  List<CarteiraLancamento> get _pageItems {
    final f = widget.filtrados;
    final start = _pageIndex * _kPageSize;
    if (start >= f.length) return [];
    return f.sublist(start, math.min(start + _kPageSize, f.length));
  }

  int get _globalStartIndex => _pageIndex * _kPageSize;

  @override
  Widget build(BuildContext context) {
    if (widget.filtrados.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: CarteiraFinTokens.surface,
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rCard),
          border: Border.all(color: CarteiraFinTokens.border),
          boxShadow: CarteiraFinTokens.cardShadow,
        ),
        child: Center(
          child: Text(
            'Nenhum lançamento neste período.',
            style: CarteiraFinTokens.inter(
              14,
              FontWeight.w400,
              CarteiraFinTokens.textSecondary,
            ),
          ),
        ),
      );
    }

    if (widget.wide) {
      final sw = MediaQuery.sizeOf(context).width;
      final tableW = math.max(940.0, math.min(1120.0, sw - 48));
      final pageItems = _pageItems;
      return Container(
        decoration: BoxDecoration(
          color: CarteiraFinTokens.surface,
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rCard),
          border: Border.all(color: CarteiraFinTokens.border),
          boxShadow: CarteiraFinTokens.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF9FAFB),
                        border: Border(
                          bottom: BorderSide(color: CarteiraFinTokens.borderLight),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _colHead('Data', 132, align: TextAlign.center),
                          _colHead('Tipo', 100, align: TextAlign.center),
                          const Expanded(
                            child: _CarteiraFinHeadCell('Descrição'),
                          ),
                          _colHeadPadded(
                            'Valor',
                            _wValor,
                            align: TextAlign.center,
                            paddingStart: 4,
                            paddingEnd: 4,
                          ),
                          const SizedBox(width: _gapValorStatus),
                          _colHeadPadded(
                            'Status',
                            _wStatus,
                            align: TextAlign.center,
                            paddingStart: 4,
                            paddingEnd: 4,
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < pageItems.length; i++)
                      _wideRow(
                        pageItems[i],
                        (_globalStartIndex + i).isOdd,
                      ),
                  ],
                ),
              ),
            ),
            _paginationFooter(),
          ],
        ),
      );
    }

    final pageItems = _pageItems;
    return Container(
      decoration: BoxDecoration(
        color: CarteiraFinTokens.surface,
        borderRadius: BorderRadius.circular(CarteiraFinTokens.rCard),
        border: Border.all(color: CarteiraFinTokens.border),
        boxShadow: CarteiraFinTokens.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pageItems.length,
            separatorBuilder: (context, _) =>
                const Divider(height: 1, color: CarteiraFinTokens.borderLight),
            itemBuilder: (context, i) => _mobileRow(pageItems[i]),
          ),
          _paginationFooter(),
        ],
      ),
    );
  }

  Widget _paginationFooter() {
    final total = widget.filtrados.length;
    if (total <= _kPageSize) return const SizedBox.shrink();

    final totalPages = (total + _kPageSize - 1) ~/ _kPageSize;
    final from = _pageIndex * _kPageSize + 1;
    final to = math.min((_pageIndex + 1) * _kPageSize, total);
    final canPrev = _pageIndex > 0;
    final canNext = _pageIndex < totalPages - 1;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(
          top: BorderSide(color: CarteiraFinTokens.borderLight),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$from–$to de $total',
              style: CarteiraFinTokens.inter(
                12,
                FontWeight.w500,
                CarteiraFinTokens.textSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Página anterior',
            onPressed: canPrev
                ? () => setState(() => _pageIndex--)
                : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              size: 22,
              color: canPrev
                  ? CarteiraFinTokens.textPrimary
                  : CarteiraFinTokens.textSecondary.withValues(alpha: 0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_pageIndex + 1} / $totalPages',
              style: CarteiraFinTokens.inter(
                12,
                FontWeight.w600,
                CarteiraFinTokens.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Próxima página',
            onPressed: canNext
                ? () => setState(() => _pageIndex++)
                : null,
            icon: Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: canNext
                  ? CarteiraFinTokens.textPrimary
                  : CarteiraFinTokens.textSecondary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHead(
    String t,
    double w, {
    TextAlign align = TextAlign.left,
  }) {
    return SizedBox(
      width: w,
      child: Text(
        t,
        textAlign: align,
        style: CarteiraFinTokens.inter(
          11,
          FontWeight.w600,
          CarteiraFinTokens.textSecondary,
        ).copyWith(letterSpacing: 0.3),
      ),
    );
  }

  Widget _colHeadPadded(
    String t,
    double w, {
    required TextAlign align,
    double paddingStart = 0,
    double paddingEnd = 0,
  }) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: EdgeInsets.only(left: paddingStart, right: paddingEnd),
        child: Text(
          t,
          textAlign: align,
          style: CarteiraFinTokens.inter(
            11,
            FontWeight.w600,
            CarteiraFinTokens.textSecondary,
          ).copyWith(letterSpacing: 0.3),
        ),
      ),
    );
  }

  Widget _wideRow(CarteiraLancamento l, bool odd) {
    final base = odd ? const Color(0xFFFAFAFA) : CarteiraFinTokens.surface;
    return _CarteiraFinRowHover(
      baseColor: base,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                DateFormat('dd/MM/yyyy\nHH:mm').format(l.data),
                textAlign: TextAlign.center,
                style: CarteiraFinTokens.inter(
                  12,
                  FontWeight.w400,
                  CarteiraFinTokens.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: _tipoBadge(l.entrada, centralizado: true),
            ),
            Expanded(
              child: Text(
                '${l.titulo} — ${l.subtitulo}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CarteiraFinTokens.inter(
                  13,
                  FontWeight.w400,
                  CarteiraFinTokens.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: _wValor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${l.entrada ? '+' : '−'} ${widget.moeda.format(l.valor)}',
                  textAlign: TextAlign.center,
                  style: CarteiraFinTokens.inter(
                    13,
                    FontWeight.w600,
                    l.entrada ? CarteiraFinTokens.green : CarteiraFinTokens.red,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _gapValorStatus),
            SizedBox(
              width: _wStatus,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Align(
                  alignment: Alignment.center,
                  child: _statusBadge(l.status, centralizado: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipoBadge(bool entrada, {bool centralizado = false}) {
    return Align(
      alignment:
          centralizado ? Alignment.center : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: entrada
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rBadge),
        ),
        child: Text(
          entrada ? 'Entrada' : 'Saída',
          textAlign: TextAlign.center,
          style: CarteiraFinTokens.inter(
            11,
            FontWeight.w600,
            entrada ? const Color(0xFF166534) : const Color(0xFF991B1B),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status, {bool centralizado = false}) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;

    if (s == 'pago') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (s == 'recusado' || s == 'estornado') {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (s == 'concluido') {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1E40AF);
    } else if (s == 'pendente') {
      bg = const Color(0xFFF3F4F6);
      fg = CarteiraFinTokens.textSecondary;
    } else if (s == 'estorno_pix_credito') {
      bg = const Color(0xFFE0E7FF);
      fg = const Color(0xFF3730A3);
    } else {
      bg = const Color(0xFFF3F4F6);
      fg = CarteiraFinTokens.textPrimary;
    }

    return Align(
      alignment:
          centralizado ? Alignment.center : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rBadge),
        ),
        child: Text(
          _statusLabelPt(status),
          textAlign: TextAlign.center,
          style: CarteiraFinTokens.inter(11, FontWeight.w600, fg),
        ),
      ),
    );
  }

  String _statusLabelPt(String status) {
    switch (status) {
      case 'pago':
        return 'Pago';
      case 'recusado':
        return 'Recusado';
      case 'pendente':
        return 'Pendente';
      case 'concluido':
        return 'Creditado';
      case 'estornado':
        return 'Estornado';
      case 'estorno_pix_credito':
        return 'Crédito estorno';
      default:
        return status;
    }
  }

  Widget _mobileRow(CarteiraLancamento l) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        hoverColor: CarteiraFinTokens.textPrimary.withValues(alpha: 0.03),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.titulo,
                          style: CarteiraFinTokens.inter(
                            14,
                            FontWeight.w600,
                            CarteiraFinTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd/MM/yyyy · HH:mm').format(l.data),
                          style: CarteiraFinTokens.inter(
                            12,
                            FontWeight.w400,
                            CarteiraFinTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${l.entrada ? '+' : '−'} ${widget.moeda.format(l.valor)}',
                    style: CarteiraFinTokens.inter(
                      15,
                      FontWeight.w600,
                      l.entrada ? CarteiraFinTokens.green : CarteiraFinTokens.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CarteiraFinTokens.inter(
                  13,
                  FontWeight.w400,
                  CarteiraFinTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _tipoBadge(l.entrada),
                  const SizedBox(width: 8),
                  _statusBadge(l.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteiraFinHeadCell extends StatelessWidget {
  const _CarteiraFinHeadCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: CarteiraFinTokens.inter(
        11,
        FontWeight.w600,
        CarteiraFinTokens.textSecondary,
      ).copyWith(letterSpacing: 0.3),
    );
  }
}

class _CarteiraFinRowHover extends StatefulWidget {
  const _CarteiraFinRowHover({
    required this.baseColor,
    required this.child,
  });

  final Color baseColor;
  final Widget child;

  @override
  State<_CarteiraFinRowHover> createState() => _CarteiraFinRowHoverState();
}

class _CarteiraFinRowHoverState extends State<_CarteiraFinRowHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hover
              ? const Color(0xFFF3F4F6).withValues(alpha: 0.85)
              : widget.baseColor,
          border: const Border(
            bottom: BorderSide(color: CarteiraFinTokens.borderLight),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
