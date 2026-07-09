part of '../assinaturas_inadimplencia_screen.dart';

// ─── Tabela Premium de Inadimplência Gestão Comercial ──────────────────────

class _DataTableSection extends StatelessWidget {
  const _DataTableSection({
    required this.itens,
    required this.totalItens,
  });

  final List<di.InadimplenciaItem> itens;
  final int totalItens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho elegante ──────────────────────────────────
          _buildHeader(theme),
          const SizedBox(height: 12),
          const Divider(height: 1),
          // ── Tabela ──────────────────────────────────────────────
          Expanded(
            child: itens.isEmpty
                ? _buildEmptyState(theme)
                : Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: _tableWidth,
                        child: Column(
                          children: [
                            _buildColumnHeaders(theme),
                            Expanded(
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: itens.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  indent: 12,
                                  endIndent: 12,
                                ),
                                itemBuilder: (context, i) {
                                  final item = itens[i];
                                  return _buildTableRow(item);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          // ── Rodapé ──────────────────────────────────────────────
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Cabeçalho ─────────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A1B9A).withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.store_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lojistas inadimplentes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF1A1A2E),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Lojistas com Gestão Comercial em atraso',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF1E9FF), Color(0xFFEDE4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6A1B9A).withOpacity(0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: Color(0xFF6A1B9A),
                ),
                const SizedBox(width: 5),
                Text(
                  '${itens.length} ${itens.length == 1 ? 'lojista' : 'lojistas'} encontrados',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Cabeçalho das colunas ─────────────────────────────────────────────────
  Widget _buildColumnHeaders(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _col('Nome da loja', 200),
          _col('CPF/CNPJ', 130),
          _col('E-mail', 180),
          _col('Telefone', 120),
          _col('Plano', 140),
          _col('Valor em atraso', 140, align: TextAlign.right),
          _col('Vencimento', 130),
          _col('Dias', 80, align: TextAlign.center),
          _col('Status do plano', 160),
          _col('Pagamento', 120),
          _col('Cidade/UF', 130),
        ],
      ),
    );
  }

  Widget _col(String label, double width, {TextAlign align = TextAlign.left}) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: align,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Plano status helpers ──────────────────────────────────────────────────

  String _planoStatusRotulo(String? status) {
    switch (status) {
      case 'ativo':
        return 'Ativo com atraso';
      case 'em_atraso':
        return 'Em atraso';
      case 'suspenso':
        return 'Suspenso';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status ?? '—';
    }
  }

  Color _planoStatusCor(String? status) {
    switch (status) {
      case 'ativo':
      case 'em_atraso':
        return const Color(0xFFFF8F00);
      case 'suspenso':
        return const Color(0xFFF04438);
      case 'cancelado':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _planoStatusFundo(String? status) {
    switch (status) {
      case 'ativo':
      case 'em_atraso':
        return const Color(0xFFFFF3E6);
      case 'suspenso':
        return const Color(0xFFFEF2F2);
      case 'cancelado':
        return const Color(0xFFF1F5F9);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  // ── Linha da tabela ───────────────────────────────────────────────────────
  Widget _buildTableRow(di.InadimplenciaItem item) {
    final c = item.cobranca;
    final cl = item.cliente;
    final dias = item.diasEmAtraso;
    final planoStatus = cl?.status;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          // Nome da loja
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      (cl?.storeName ?? c.clienteNome)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF6A1B9A),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cl?.storeName ?? c.clienteNome,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // CPF/CNPJ
          SizedBox(
            width: 130,
            child: Text(
              cl?.cpfCnpj ?? '—',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // E-mail
          SizedBox(
            width: 180,
            child: Text(
              cl?.email.isNotEmpty == true ? cl!.email : c.clienteEmail,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Telefone
          SizedBox(
            width: 120,
            child: Text(
              cl?.phone.isNotEmpty == true ? cl!.phone : '—',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // Plano contratado
          SizedBox(
            width: 140,
            child: _buildBadge(
              label: c.planoNome.isNotEmpty ? c.planoNome : '—',
              cor: const Color(0xFF6A1B9A),
              fundo: const Color(0xFFF1E9FF),
              fontSize: 11,
            ),
          ),

          // Valor em atraso
          SizedBox(
            width: 140,
            child: Text(
              fmtMoeda(c.valor),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),

          // Data de vencimento
          SizedBox(
            width: 130,
            child: Text(
              fmtData(c.vencimento),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // Dias em atraso
          SizedBox(
            width: 80,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dias > 30
                      ? const Color(0xFFFEF2F2)
                      : dias > 5
                          ? const Color(0xFFFFF8E1)
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dias > 0 ? '$dias' : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: dias > 30
                        ? const Color(0xFFF04438)
                        : dias > 5
                            ? const Color(0xFFFF8F00)
                            : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),

          // Status do plano
          SizedBox(
            width: 160,
            child: _buildBadge(
              label: _planoStatusRotulo(planoStatus),
              cor: _planoStatusCor(planoStatus),
              fundo: _planoStatusFundo(planoStatus),
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),

          // Forma de pagamento
          SizedBox(
            width: 120,
            child: Text(
              cl?.gateway ?? '—',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
          ),

          // Cidade/UF
          SizedBox(
            width: 130,
            child: Text(
              cl != null && cl.addressCity.isNotEmpty
                  ? '${cl.addressCity}${cl.addressState.isNotEmpty ? '/${cl.addressState}' : ''}'
                  : '—',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Estado vazio premium ──────────────────────────────────────────────────
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1E9FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Toda a base está em dia',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nenhum lojista com Gestão Comercial em atraso no momento.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rodapé ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_rounded,
            size: 14,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Text(
            'Exibindo ${itens.length} de $totalItens registros',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  double get _tableWidth => 200 + 130 + 180 + 120 + 140 + 140 + 130 + 80 + 160 + 120 + 130;
}
