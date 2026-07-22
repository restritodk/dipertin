import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/audit_log_model.dart';
import '../../models/audit_filtros_model.dart' show AuditCategoriaLog;
import '../../theme/painel_admin_theme.dart';
import '../../utils/audit_visual.dart';

/// Tabela responsiva de eventos de auditoria. Em telas < 900px vira
/// cards expansíveis.
class AuditoriaTabela extends StatelessWidget {
  const AuditoriaTabela({
    super.key,
    required this.eventos,
    required this.onDetalhes,
    this.carregando = false,
  });

  final List<AuditLog> eventos;
  final void Function(AuditLog log) onDetalhes;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return _loading();
    }
    if (eventos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PainelAdminTheme.dashboardBorder),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded,
                  size: 48, color: PainelAdminTheme.textoSecundario),
              SizedBox(height: 12),
              Text(
                'Nenhum registro de auditoria encontrado para os filtros selecionados.',
                style: TextStyle(
                  fontSize: 14,
                  color: PainelAdminTheme.textoSecundario,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        if (c.maxWidth < 900) {
          return _ListaCards(eventos: eventos, onDetalhes: onDetalhes);
        }
        return _Tabela(eventos: eventos, onDetalhes: onDetalhes);
      },
    );
  }

  Widget _loading() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text(
              'Carregando eventos…',
              style: TextStyle(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabela extends StatelessWidget {
  const _Tabela({required this.eventos, required this.onDetalhes});
  final List<AuditLog> eventos;
  final void Function(AuditLog log) onDetalhes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Header(),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: eventos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _LinhaTabela(
              log: eventos[i],
              onDetalhes: () => onDetalhes(eventos[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: PainelAdminTheme.fundoCanvas,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: const [
          _H(text: 'Data e hora', flex: 2),
          _H(text: 'Usuário', flex: 2),
          _H(text: 'Categoria', flex: 1),
          _H(text: 'Ação', flex: 2),
          _H(text: 'Módulo', flex: 1),
          _H(text: 'Severidade', flex: 1),
          _H(text: 'Resultado', flex: 1),
          _H(text: 'Ações', flex: 1, center: true),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H({required this.text, required this.flex, this.center = false});
  final String text;
  final int flex;
  final bool center;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          fontSize: 11.5,
          color: PainelAdminTheme.textoSecundario,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LinhaTabela extends StatelessWidget {
  const _LinhaTabela({required this.log, required this.onDetalhes});
  final AuditLog log;
  final VoidCallback onDetalhes;

  @override
  Widget build(BuildContext context) {
    final dataFmt = log.criadoEm != null
        ? DateFormat('dd/MM/yy HH:mm:ss').format(log.criadoEm!)
        : '—';
    return InkWell(
      onTap: onDetalhes,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: log.severidade == 'critica'
            ? AuditVisual.fundoSeveridade('critica').withValues(alpha: 0.4)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                dataFmt,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: PainelAdminTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.nomeExibicao,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: PainelAdminTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (log.atorEmail != null && log.atorEmail!.isNotEmpty)
                    Text(
                      log.atorEmail!,
                      style: const TextStyle(
                          fontSize: 11, color: PainelAdminTheme.textoSecundario),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                AuditCategoriaLog.label(log.categoria),
                style: const TextStyle(
                  fontSize: 12,
                  color: PainelAdminTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                log.descricaoResumida,
                style: const TextStyle(
                  fontSize: 12,
                  color: PainelAdminTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                log.modulo ?? '—',
                style: const TextStyle(
                    fontSize: 12, color: PainelAdminTheme.textoSecundario),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _Badge(
              color: AuditVisual.corSeveridade(log.severidade),
              background: AuditVisual.fundoSeveridade(log.severidade),
              label: AuditVisual.labelSeveridade(log.severidade),
              icon: AuditVisual.iconSeveridade(log.severidade),
            ),
            const SizedBox(width: 8),
            _Badge(
              color: AuditVisual.corResultado(log.resultado),
              background: AuditVisual.fundoResultado(log.resultado),
              label: AuditVisual.labelResultado(log.resultado),
              icon: AuditVisual.iconResultado(log.resultado),
            ),
            Expanded(
              flex: 1,
              child: Center(
                child: IconButton(
                  tooltip: 'Ver detalhes',
                  icon: const Icon(Icons.visibility_outlined,
                      size: 18, color: PainelAdminTheme.roxo),
                  onPressed: onDetalhes,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListaCards extends StatelessWidget {
  const _ListaCards({required this.eventos, required this.onDetalhes});
  final List<AuditLog> eventos;
  final void Function(AuditLog log) onDetalhes;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: eventos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final log = eventos[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => onDetalhes(log),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: log.severidade == 'critica'
                      ? AuditVisual.corSeveridade('critica').withValues(alpha: 0.5)
                      : PainelAdminTheme.dashboardBorder,
                  width: log.severidade == 'critica' ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(AuditVisual.iconCategoria(log.tipoAtor),
                          size: 18,
                          color: AuditVisual.corCategoria(log.tipoAtor)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.nomeExibicao,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: PainelAdminTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (log.atorEmail != null && log.atorEmail!.isNotEmpty)
                              Text(
                                log.atorEmail!,
                                style: const TextStyle(
                                    fontSize: 11, color: PainelAdminTheme.textoSecundario),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      _Badge(
                        color: AuditVisual.corSeveridade(log.severidade),
                        background: AuditVisual.fundoSeveridade(log.severidade),
                        label: AuditVisual.labelSeveridade(log.severidade),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    log.descricaoResumida,
                    style: const TextStyle(
                      fontSize: 13,
                      color: PainelAdminTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    log.criadoEm != null
                        ? DateFormat('dd/MM/yy HH:mm:ss').format(log.criadoEm!)
                        : '—',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.background,
    required this.label,
    this.icon,
  });
  final Color color;
  final Color background;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
