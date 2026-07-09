part of '../assinaturas_inadimplencia_screen.dart';

// ─── Utilitários ────────────────────────────────────────────────────────────

final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');
final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

String fmtMoeda(double v) => _fmtMoeda.format(v);

String fmtData(DateTime? dt) {
  if (dt == null) return '—';
  return _fmtData.format(dt);
}

String fmtDataHora(DateTime? dt) {
  if (dt == null) return '—';
  return _fmtDataHora.format(dt);
}

Color riscoCor(di.RiscoInadimplencia r) => switch (r) {
      di.RiscoInadimplencia.baixo => const Color(0xFF16A34A),
      di.RiscoInadimplencia.medio => const Color(0xFFFFA726),
      di.RiscoInadimplencia.alto => const Color(0xFFF97316),
      di.RiscoInadimplencia.critico => const Color(0xFFF04438),
    };

Color riscoFundo(di.RiscoInadimplencia r) => switch (r) {
      di.RiscoInadimplencia.baixo => const Color(0xFFE8F5E9),
      di.RiscoInadimplencia.medio => const Color(0xFFFFF8E1),
      di.RiscoInadimplencia.alto => const Color(0xFFFFF3E6),
      di.RiscoInadimplencia.critico => const Color(0xFFFEF2F2),
    };

String riscoRotulo(di.RiscoInadimplencia r) => switch (r) {
      di.RiscoInadimplencia.baixo => 'Baixo',
      di.RiscoInadimplencia.medio => 'Médio',
      di.RiscoInadimplencia.alto => 'Alto',
      di.RiscoInadimplencia.critico => 'Crítico',
    };

IconData riscoIcon(di.RiscoInadimplencia r) => switch (r) {
      di.RiscoInadimplencia.baixo => Icons.check_circle_rounded,
      di.RiscoInadimplencia.medio => Icons.warning_amber_rounded,
      di.RiscoInadimplencia.alto => Icons.error_outline_rounded,
      di.RiscoInadimplencia.critico => Icons.gpp_bad_rounded,
    };

Color statusExibicaoCor(String s) => switch (s) {
      'Paga' => const Color(0xFF16A34A),
      'Cancelada' => const Color(0xFF94A3B8),
      'Reembolsada' => const Color(0xFFFF8F00),
      'Em aberto' => const Color(0xFF0EA5E9),
      'Em atraso' => const Color(0xFFF04438),
      'Pagamento prometido' => const Color(0xFFFFA726),
      'Negociado' => const Color(0xFF8B5CF6),
      'Suspenso' => const Color(0xFFF04438),
      _ => const Color(0xFF64748B),
    };

Color statusExibicaoFundo(String s) => switch (s) {
      'Paga' => const Color(0xFFE8F5E9),
      'Cancelada' => const Color(0xFFF1F5F9),
      'Reembolsada' => const Color(0xFFFFF3E6),
      'Em aberto' => const Color(0xFFE6F6FE),
      'Em atraso' => const Color(0xFFFEF2F2),
      'Pagamento prometido' => const Color(0xFFFFF8E1),
      'Negociado' => const Color(0xFFF1E9FF),
      'Suspenso' => const Color(0xFFFEF2F2),
      _ => const Color(0xFFF1F5F9),
    };

Widget _buildBadge({
  required String label,
  required Color cor,
  required Color fundo,
  double fontSize = 11,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: fundo,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cor.withOpacity(0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: cor,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
  );
}

Widget _cardWrapper({
  required Widget child,
  EdgeInsetsGeometry margin = EdgeInsets.zero,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: child,
    ),
  );
}
