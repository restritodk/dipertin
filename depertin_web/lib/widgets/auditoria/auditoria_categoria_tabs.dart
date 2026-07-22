import 'package:flutter/material.dart';
import '../../models/audit_filtros_model.dart';
import '../../theme/painel_admin_theme.dart';

/// Tabs/segmented control no topo da tela com 4 categorias de ator.
class AuditoriaCategoriaTabs extends StatelessWidget {
  const AuditoriaCategoriaTabs({
    super.key,
    required this.categoriaSelecionada,
    required this.onSelecionar,
  });

  final String? categoriaSelecionada;
  final void Function(String? cat) onSelecionar;

  @override
  Widget build(BuildContext context) {
    final cats = [
      _cat(AuditCategoria.cliente, 'Clientes', Icons.person_outline_rounded,
          'Ações de clientes'),
      _cat(AuditCategoria.lojista, 'Lojistas', Icons.storefront_outlined,
          'Ações de lojas'),
      _cat(
          AuditCategoria.entregador,
          'Entregadores',
          Icons.delivery_dining_rounded,
          'Ações de entregadores'),
      _cat(AuditCategoria.admin, 'Administradores', Icons.shield_outlined,
          'Ações administrativas'),
    ];

    return LayoutBuilder(
      builder: (ctx, c) {
        final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 700 ? 2 : 1);
        return GridView.count(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 4 ? 3.4 : (cols == 2 ? 3.8 : 4.6),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cats
              .map((c) => _CardCategoria(
                    key: ValueKey(c.id),
                    id: c.id,
                    label: c.label,
                    sub: c.sub,
                    icon: c.icon,
                    selected: c.id == categoriaSelecionada,
                    onTap: () {
                      if (c.id == categoriaSelecionada) {
                        onSelecionar(null);
                      } else {
                        onSelecionar(c.id);
                      }
                    },
                  ))
              .toList(),
        );
      },
    );
  }

  _CatData _cat(String id, String label, IconData icon, String sub) =>
      _CatData(id, label, sub, icon);
}

class _CatData {
  final String id;
  final String label;
  final String sub;
  final IconData icon;
  const _CatData(this.id, this.label, this.sub, this.icon);
}

class _CardCategoria extends StatelessWidget {
  const _CardCategoria({
    super.key,
    required this.id,
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roxo = PainelAdminTheme.roxo;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected
                ? roxo.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? roxo.withValues(alpha: 0.5)
                  : PainelAdminTheme.dashboardBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: roxo.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: roxo.withValues(alpha: selected ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: roxo, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? roxo
                            : PainelAdminTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedScale(
                duration: const Duration(milliseconds: 220),
                scale: selected ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: roxo,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
