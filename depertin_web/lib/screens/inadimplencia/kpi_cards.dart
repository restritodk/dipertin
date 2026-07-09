part of '../assinaturas_inadimplencia_screen.dart';

// ─── KPI Cards ──────────────────────────────────────────────────────────────
// Layout: Linha 1 = 3 cards, Linha 2 = 2 cards. Mesma largura/altura.

class _KpiCardsGrid extends StatelessWidget {
  const _KpiCardsGrid({required this.kpis});

  final di.InadimplenciaKpis kpis;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Linha 1: 3 cards
        Row(
          children: [
            Expanded(
              child: _buildCard(
                titulo: 'Valor em atraso',
                valor: fmtMoeda(kpis.valorEmAtraso),
                icone: Icons.account_balance_wallet_rounded,
                corIcone: const Color(0xFF6A1B9A),
                fundoIcone: const Color(0xFFF1E9FF),
                variacao: kpis.variacaoValorPercentual,
                variacaoLabel: 'vs. mês anterior',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCard(
                titulo: 'Lojistas inadimplentes',
                valor: '${kpis.clientesInadimplentes}',
                icone: Icons.people_alt_rounded,
                corIcone: const Color(0xFFFF8F00),
                fundoIcone: const Color(0xFFFFF3E6),
                variacao: kpis.variacaoClientesPercentual,
                variacaoLabel: 'vs. semana anterior',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCard(
                titulo: 'Vencem hoje',
                valor: '${kpis.vencemHojeQtd}',
                subtitulo: fmtMoeda(kpis.vencemHojeValor),
                icone: Icons.event_available_rounded,
                corIcone: const Color(0xFF0EA5E9),
                fundoIcone: const Color(0xFFE6F6FE),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Linha 2: 2 cards
        Row(
          children: [
            Expanded(
              child: _buildCard(
                titulo: 'Acima de 30 dias',
                valor: '${kpis.acima30DiasQtd}',
                subtitulo: fmtMoeda(kpis.acima30DiasValor),
                icone: Icons.timer_off_rounded,
                corIcone: const Color(0xFFF04438),
                fundoIcone: const Color(0xFFFEF2F2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCard(
                titulo: 'Recuperado este mês',
                valor: fmtMoeda(kpis.recuperadoEsteMes),
                icone: Icons.trending_up_rounded,
                corIcone: const Color(0xFF16A34A),
                fundoIcone: const Color(0xFFE8F5E9),
                variacao: kpis.variacaoRecuperadoPercentual,
                variacaoLabel: 'vs. mês anterior',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard({
    required String titulo,
    required String valor,
    String? subtitulo,
    required IconData icone,
    required Color corIcone,
    required Color fundoIcone,
    double? variacao,
    String? variacaoLabel,
  }) {
    final isPositivo = variacao == null || variacao >= 0;
    final variacaoAbs = variacao?.abs() ?? 0.0;

    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: fundoIcone,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, color: corIcone, size: 20),
            ),
            const SizedBox(height: 10),
            // Título
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            // Valor principal
            Text(
              valor,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.3,
              ),
            ),
            // Subtítulo
            if (subtitulo != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitulo,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            // Variação
            if (variacao != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isPositivo
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: isPositivo
                        ? const Color(0xFFF04438)
                        : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPositivo
                              ? const Color(0xFFF04438)
                              : const Color(0xFF16A34A),
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${isPositivo ? '+' : ''}${variacaoAbs.toStringAsFixed(1)}%',
                          ),
                          if (variacaoLabel != null)
                            TextSpan(
                              text: ' $variacaoLabel',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
