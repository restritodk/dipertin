import 'package:flutter/material.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/encomenda_painel_helpers.dart';

/// Barra de progresso horizontal compacta (sem overflow em painéis estreitos).
class EncomendaTimelineBar extends StatelessWidget {
  const EncomendaTimelineBar({
    super.key,
    required this.passos,
  });

  final List<EncomendaTimelinePasso> passos;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: passos.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
        ),
        itemBuilder: (context, i) {
          final p = passos[i];
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  p.concluido ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 13,
                  color: p.concluido ? PainelAdminTheme.roxo : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  p.rotulo,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: p.concluido
                        ? PainelAdminTheme.roxo
                        : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mini-card horizontal para painel inbox.
class EncomendaInboxMiniCard extends StatelessWidget {
  const EncomendaInboxMiniCard({
    super.key,
    required this.icone,
    required this.titulo,
    required this.corIcone,
    required this.child,
  });

  final IconData icone;
  final String titulo;
  final Color corIcone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icone, size: 14, color: corIcone),
              const SizedBox(width: 5),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              color: PainelAdminTheme.dashboardInk,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
