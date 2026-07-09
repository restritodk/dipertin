import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_pendencias_service.dart';
import 'package:depertin_web/widgets/comercial/comercial_financial_action_menu.dart';
import 'package:depertin_web/widgets/comercial/comercial_financial_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tabela de pendências financeiras — UMA linha por cliente com parcelas agrupadas.
class FinancialTable extends StatelessWidget {
  const FinancialTable({
    super.key,
    required this.itens,
    this.pagina = 1,
    this.itensPorPagina = 10,
    this.totalItens = 0,
    this.onPageChanged,
    this.onItensPorPaginaChanged,
    this.onActionReceber,
    this.onActionEnviarCobranca,
    this.onActionNegociar,
    this.onActionBloquearCredito,
    this.onActionExcluir,
  });

  final List<PendenciaFinanceiraCliente> itens;
  final int pagina;
  final int itensPorPagina;
  final int totalItens;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onItensPorPaginaChanged;
  final void Function(PendenciaFinanceiraCliente)? onActionReceber;
  final void Function(PendenciaFinanceiraCliente)? onActionEnviarCobranca;
  final void Function(PendenciaFinanceiraCliente)? onActionNegociar;
  final void Function(PendenciaFinanceiraCliente)? onActionBloquearCredito;
  final void Function(PendenciaFinanceiraCliente)? onActionExcluir;

  @override
  Widget build(BuildContext context) {
    final inicio = (pagina - 1) * itensPorPagina;
    final fim = inicio + itensPorPagina;
    final paginaItens = itens.length > itensPorPagina
        ? itens.sublist(inicio, fim.clamp(0, itens.length))
        : itens;
    final totalPaginas =
        (totalItens / itensPorPagina).ceil().clamp(1, 999);
    final mostraPagina = pagina.clamp(1, totalPaginas);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header da tabela ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: false,
                    onChanged: null,
                    fillColor: WidgetStatePropertyAll(Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
                Expanded(flex: 3, child: _headerCell('Cliente / Loja')),
                Expanded(flex: 2, child: _headerCell('Plano contratado')),
                Expanded(flex: 2, child: _headerCell('Vencimento')),
                Expanded(flex: 2, child: _headerCell('Status')),
                Expanded(flex: 2, child: _headerCell('Valor')),
                Expanded(flex: 1, child: _headerCell('Dias')),
                const SizedBox(width: 44),
              ],
            ),
          ),
          const Divider(height: 16, color: Color(0xFFEEEAF6)),
          // ── Linhas ──
          if (paginaItens.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 48,
                      color: const Color(0xFF16A34A).withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhuma pendência encontrada',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...paginaItens.map((item) => _linhaTabela(item)),
          // ── Paginação ──
          if (totalItens > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Text(
                    'Mostrando ${inicio + 1} a ${fim.clamp(0, totalItens)} de $totalItens pendências',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  // Paginação
                  Row(
                    children: [
                      _botaoPag(Icons.chevron_left_rounded, mostraPagina > 1
                          ? () => onPageChanged?.call(mostraPagina - 1)
                          : null),
                      const SizedBox(width: 4),
                      ..._paginas(mostraPagina, totalPaginas),
                      const SizedBox(width: 4),
                      _botaoPag(Icons.chevron_right_rounded, mostraPagina < totalPaginas
                          ? () => onPageChanged?.call(mostraPagina + 1)
                          : null),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Itens por página
                  Row(
                    children: [
                      Text(
                        'Itens por página:',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 60,
                        height: 32,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: itensPorPagina,
                              isDense: true,
                              icon: const Icon(
                                Icons.expand_more_rounded,
                                size: 14,
                              ),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              items: [5, 10, 15, 20, 50].map((n) {
                                return DropdownMenuItem(
                                  value: n,
                                  child: Text('$n'),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  onItensPorPaginaChanged?.call(v);
                                }
                              },
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
    );
  }

  Widget _linhaTabela(PendenciaFinanceiraCliente item) {
    final vencido = item.status == 'vencido';
    final avatarBg = vencido
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFE7F8EE);
    final avatarCor = vencido
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFFF1F5F9)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 28,
              child: Checkbox(
                value: false,
                onChanged: null,
                fillColor: WidgetStatePropertyAll(Color(0xFFF1F5F9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            // Cliente
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: avatarBg,
                    child: Text(
                      item.clienteNome.isNotEmpty
                          ? item.clienteNome[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: avatarCor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.clienteNome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        if (item.codigoVenda.isNotEmpty)
                          Text(
                            item.codigoVenda,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Plano contratado (agrupado)
            Expanded(
              flex: 2,
              child: Text(
                item.planoLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            // Vencimento (data de referência)
            Expanded(
              flex: 2,
              child: Text(
                ComercialPendenciasService.formatarData(
                    item.dataVencimentoReferencia),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
            // Status — badge pequena (chip)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FinancialStatusBadge(status: item.status),
              ),
            ),
            // Valor — mostra atualizado se vencido (com juros/multa)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ComercialPendenciasService.formatarMoeda(
                        item.valorTotalAtualizado),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: vencido
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (vencido && (item.totalJurosCalculado > 0.009 ||
                      item.totalMultaCalculada > 0.009))
                    Text(
                      '${ComercialPendenciasService.formatarMoeda(item.valorTotalEmAberto)} + encargos',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
            ),
            // Dias
            Expanded(
              flex: 1,
              child: item.diasEmAberto > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.diasEmAberto}d',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    )
                  : Text(
                      '—',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFFCBD5E1),
                      ),
                    ),
            ),
            // Ações
            SizedBox(
              width: 44,
              child: FinancialActionMenu(
                onReceber: () => onActionReceber?.call(item),
                onEnviarCobranca: () => onActionEnviarCobranca?.call(item),
                onNegociar: () => onActionNegociar?.call(item),
                onBloquearCredito: () =>
                    onActionBloquearCredito?.call(item),
                onExcluir: () => onActionExcluir?.call(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF94A3B8),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _botaoPag(IconData icon, VoidCallback? onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null
                ? const Color(0xFF1A1A2E)
                : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  List<Widget> _paginas(int atual, int total) {
    final lista = <Widget>[];
    final inicio = (atual - 2).clamp(1, (total - 4).clamp(1, total));
    final fim = (inicio + 4).clamp(1, total);

    if (inicio > 1) {
      lista.add(_botaoNumPag(1, atual == 1));
      if (inicio > 2) {
        lista.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ));
      }
    }

    for (var i = inicio; i <= fim; i++) {
      lista.add(_botaoNumPag(i, atual == i));
    }

    if (fim < total) {
      if (fim < total - 1) {
        lista.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '...',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ));
      }
      lista.add(_botaoNumPag(total, atual == total));
    }

    return lista;
  }

  Widget _botaoNumPag(int num, bool ativo) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: ativo ? const Color(0xFF6A1B9A) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPageChanged?.call(num),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Text(
              '$num',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                color: ativo ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
