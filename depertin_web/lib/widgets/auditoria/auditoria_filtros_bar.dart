import 'package:flutter/material.dart';
import '../../models/audit_filtros_model.dart';
import '../../theme/painel_admin_theme.dart';

/// Barra de filtros avançados (período rápido + categoria + acao + resultado).
class AuditoriaFiltrosBar extends StatelessWidget {
  const AuditoriaFiltrosBar({
    super.key,
    required this.filtros,
    required this.onAlterar,
    required this.onLimpar,
    required this.onExportar,
    this.exportando = false,
    this.podeExportar = true,
  });

  final AuditFiltros filtros;
  final void Function(AuditFiltros novo) onAlterar;
  final VoidCallback onLimpar;
  final VoidCallback onExportar;
  final bool exportando;
  final bool podeExportar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: DiPertinThemeSombra.suave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  size: 18, color: PainelAdminTheme.roxo),
              const SizedBox(width: 8),
              const Text(
                'Filtros avançados',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.textPrimary,
                ),
              ),
              const Spacer(),
              _PillButton(
                icon: Icons.cleaning_services_outlined,
                label: 'Limpar',
                onPressed: onLimpar,
                color: PainelAdminTheme.textoSecundario,
              ),
              const SizedBox(width: 8),
              _PillButton(
                icon: exportando
                    ? Icons.hourglass_top_rounded
                    : Icons.file_download_outlined,
                label: exportando ? 'Exportando…' : 'Exportar CSV',
                onPressed: (exportando || !podeExportar) ? null : onExportar,
                color: PainelAdminTheme.laranja,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DropdownField<String>(
                icon: Icons.calendar_today_rounded,
                label: 'Período',
                value: filtros.periodo,
                items: const [
                  DropdownMenuItem(
                      value: AuditPeriodo.hoje, child: Text('Hoje')),
                  DropdownMenuItem(
                      value: AuditPeriodo.seteDias,
                      child: Text('Últimos 7 dias')),
                  DropdownMenuItem(
                      value: AuditPeriodo.trintaDias,
                      child: Text('Últimos 30 dias')),
                  DropdownMenuItem(
                      value: AuditPeriodo.tudo, child: Text('Tudo')),
                  DropdownMenuItem(
                      value: AuditPeriodo.personalizado,
                      child: Text('Personalizado')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  onAlterar(filtros.copyWith(periodo: v));
                },
              ),
              _DropdownField<String>(
                icon: Icons.category_outlined,
                label: 'Categoria',
                value: filtros.categoria,
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Todas')),
                  ...AuditCategoriaLog.todas.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(AuditCategoriaLog.label(c)),
                      )),
                ],
                onChanged: (v) {
                  onAlterar(filtros.copyWith(categoria: v));
                },
              ),
              _DropdownField<String>(
                icon: Icons.dashboard_outlined,
                label: 'Módulo',
                value: filtros.modulo,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'pedidos', child: Text('Pedidos')),
                  DropdownMenuItem(value: 'entregas', child: Text('Entregas')),
                  DropdownMenuItem(value: 'fiscal', child: Text('Fiscal')),
                  DropdownMenuItem(
                      value: 'assinaturas', child: Text('Assinaturas')),
                  DropdownMenuItem(value: 'financeiro', child: Text('Financeiro')),
                  DropdownMenuItem(value: 'conta', child: Text('Conta')),
                  DropdownMenuItem(
                      value: 'marketing', child: Text('Marketing')),
                ],
                onChanged: (v) {
                  onAlterar(filtros.copyWith(modulo: v));
                },
              ),
              _DropdownField<String>(
                icon: Icons.check_circle_outline_rounded,
                label: 'Resultado',
                value: filtros.resultado,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(
                      value: 'sucesso', child: Text('Sucesso')),
                  DropdownMenuItem(value: 'erro', child: Text('Erro')),
                  DropdownMenuItem(value: 'alerta', child: Text('Alerta')),
                ],
                onChanged: (v) {
                  onAlterar(filtros.copyWith(resultado: v));
                },
              ),
              _DropdownField<String>(
                icon: Icons.flag_outlined,
                label: 'Severidade',
                value: filtros.severidade,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todas')),
                  DropdownMenuItem(value: 'critica', child: Text('Crítica')),
                  DropdownMenuItem(value: 'atencao', child: Text('Atenção')),
                  DropdownMenuItem(value: 'info', child: Text('Informação')),
                ],
                onChanged: (v) {
                  onAlterar(filtros.copyWith(severidade: v));
                },
              ),
              _DropdownField<String>(
                icon: Icons.smartphone_outlined,
                label: 'Origem',
                value: filtros.origem,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todas')),
                  DropdownMenuItem(
                      value: 'cloud_functions', child: Text('Cloud Functions')),
                  DropdownMenuItem(
                      value: 'painel_web', child: Text('Painel web')),
                  DropdownMenuItem(
                      value: 'app:android', child: Text('App Android')),
                  DropdownMenuItem(
                      value: 'app:ios', child: Text('App iOS')),
                ],
                onChanged: (v) {
                  onAlterar(filtros.copyWith(origem: v));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      constraints: const BoxConstraints(minWidth: 180),
      decoration: BoxDecoration(
        color: PainelAdminTheme.fundoCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: PainelAdminTheme.textoSecundario),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
                fontSize: 12.5,
                color: PainelAdminTheme.textoSecundario,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          DropdownButton<T>(
            value: value,
            isDense: true,
            underline: const SizedBox(),
            items: items,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 13,
              color: PainelAdminTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: filled
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: filled ? 0.5 : 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: onPressed == null
                      ? PainelAdminTheme.textoSecundario
                      : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class DiPertinThemeSombra {
  static List<BoxShadow> suave() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
}
