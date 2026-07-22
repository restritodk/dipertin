import 'package:flutter/material.dart';
import '../../models/audit_log_model.dart';
import '../../theme/painel_admin_theme.dart';

/// Cards de KPI (estatísticas do período).
class AuditoriaKpiCards extends StatelessWidget {
  const AuditoriaKpiCards({
    super.key,
    required this.stats,
    this.carregando = false,
  });

  final AuditStats stats;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return _loading();
    }
    final cards = [
      _Kpi(
        label: 'Total no período',
        value: stats.total,
        icon: Icons.fact_check_outlined,
        color: PainelAdminTheme.roxo,
        sublabel: '${stats.usuariosUnicos} usuários únicos',
      ),
      _Kpi(
        label: 'Ações hoje',
        value: stats.hoje,
        icon: Icons.today_rounded,
        color: PainelAdminTheme.laranja,
        sublabel:
            '${stats.tentativasLogin} tentativas de login',
      ),
      _Kpi(
        label: 'Sucessos vs erros',
        value: stats.sucesso,
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF059669),
        sublabel:
            '${stats.erro} erros · ${stats.alerta} alertas',
      ),
      _Kpi(
        label: 'Eventos críticos',
        value: stats.critica,
        icon: Icons.report_gmailerrorred_rounded,
        color: PainelAdminTheme.roxoEscuro,
        sublabel:
            '${stats.atencao} atenção · ${stats.administrativas} admin',
      ),
    ];
    return LayoutBuilder(
      builder: (ctx, c) {
        if (c.maxWidth >= 1200) {
          return Row(
            children: cards
                .map((card) => Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    )))
                .toList(),
          );
        }
        if (c.maxWidth >= 700) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards,
          );
        }
        return Column(
          children: cards
              .map((card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _loading() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(
        4,
        (i) => Container(
          width: 220,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.sublabel,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PainelAdminTheme.textoSecundario,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            style: const TextStyle(
              fontSize: 11,
              color: PainelAdminTheme.textoSecundario,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
