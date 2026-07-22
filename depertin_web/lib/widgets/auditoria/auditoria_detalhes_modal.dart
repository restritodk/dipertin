import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/audit_log_model.dart';
import '../../models/audit_filtros_model.dart' show AuditCategoriaLog;
import '../../theme/painel_admin_theme.dart';
import '../../utils/audit_visual.dart';

/// Modal premium de detalhes com 5 seções.
class AuditoriaDetalhesModal extends StatelessWidget {
  const AuditoriaDetalhesModal({super.key, required this.log});
  final AuditLog log;

  static Future<void> show(BuildContext context, AuditLog log) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AuditoriaDetalhesModal(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      title: 'Identificação do evento',
                      icon: Icons.tag_rounded,
                      child: _kv({
                        'ID da auditoria': log.id,
                        'Data e hora': log.criadoEm != null
                            ? DateFormat('dd/MM/yyyy HH:mm:ss')
                                .format(log.criadoEm!)
                            : '—',
                        'Categoria': AuditCategoriaLog.label(log.categoria),
                        'Ação': AuditVisual.formatarNomeAcao(log.acao),
                        'Módulo': log.modulo ?? '—',
                        'Tela': log.tela ?? '—',
                        'Severidade': AuditVisual.labelSeveridade(log.severidade),
                        'Resultado': AuditVisual.labelResultado(log.resultado),
                        'Origem': log.origem,
                      }),
                    ),
                    _section(
                      title: 'Usuário responsável',
                      icon: Icons.person_rounded,
                      child: _kv({
                        'Nome': log.nomeExibicao,
                        'E-mail': log.atorEmail ?? '—',
                        'Perfil': log.perfilAmigavel,
                        'UID técnico': log.atorUid ?? '—',
                      }),
                    ),
                    _section(
                      title: 'Registro afetado',
                      icon: Icons.assignment_rounded,
                      child: _kv({
                        'Entidade': log.entityType ?? '—',
                        'ID da entidade': log.entityId ?? '—',
                      }),
                    ),
                    if ((log.diff != null && log.diff!.isNotEmpty) ||
                        (log.mudancas != null && log.mudancas!.isNotEmpty))
                      _section(
                        title: 'Alterações realizadas',
                        icon: Icons.compare_arrows_rounded,
                        color: PainelAdminTheme.laranja,
                        child: _diffTable(
                          log.mudancas ?? log.diff ?? const {},
                        ),
                      ),
                    _section(
                      title: 'Informações técnicas',
                      icon: Icons.dns_rounded,
                      child: _kv({
                        'Código interno da ação': log.acao,
                        'IP': log.ip ?? '—',
                        'Plataforma': log.plataforma ?? '—',
                        'User-Agent':
                            log.userAgent != null && log.userAgent!.length > 80
                                ? '${log.userAgent!.substring(0, 80)}…'
                                : (log.userAgent ?? '—'),
                        'Código do erro': log.codigoErro ?? '—',
                        'Mensagem de erro': log.mensagemErro ?? '—',
                      }),
                    ),
                    if (log.detalheExtras != null && log.detalheExtras!.isNotEmpty)
                      _section(
                        title: 'Detalhes extras',
                        icon: Icons.list_alt_rounded,
                        child: _kv(_stringifyMap(log.detalheExtras!)),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Map<String, String> _stringifyMap(Map<String, dynamic> m) {
    return m.map((k, v) => MapEntry(
          k,
          v == null
              ? '—'
              : (v is Map || v is List)
                  ? jsonLike(v).toString()
                  : v.toString(),
        ));
  }

  String jsonLike(dynamic v) {
    if (v == null) return '—';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    if (v is List) {
      return v.map(jsonLike).join(', ');
    }
    if (v is Map) {
      return v.entries.map((e) => '${e.key}: ${jsonLike(e.value)}').join(' · ');
    }
    return v.toString();
  }

  Widget _header() {
    final acaoAmigavel = AuditVisual.formatarNomeAcao(log.acao);
    final subtitulo = (log.atorNome != null && log.atorNome!.isNotEmpty)
        ? 'Ação realizada por ${log.atorNome}'
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(AuditVisual.iconSeveridade(log.severidade),
              color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acaoAmigavel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitulo != null)
                  Text(
                    subtitulo,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Color? color,
  }) {
    final c = color ?? PainelAdminTheme.roxo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: c, size: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: c,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(Map<String, String> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.entries
          .map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: PainelAdminTheme.textoSecundario,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        e.value.isEmpty ? '—' : e.value,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: PainelAdminTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _diffTable(Map<String, dynamic> mudancas) {
    final keys = mudancas.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: PainelAdminTheme.laranja.withValues(alpha: 0.10),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: const Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  'Campo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.laranja,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Valor anterior',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.laranja,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Novo valor',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.laranja,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...keys.map((k) {
          final v = mudancas[k];
          String de;
          String para;
          if (v is Map && (v['de'] != null || v['para'] != null)) {
            de = v['de']?.toString() ?? '—';
            para = v['para']?.toString() ?? '—';
          } else if (v is List && v.length == 2) {
            de = v[0]?.toString() ?? '—';
            para = v[1]?.toString() ?? '—';
          } else {
            de = '—';
            para = v?.toString() ?? '—';
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: PainelAdminTheme.dashboardBorder),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    k,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: PainelAdminTheme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SelectableText(
                    de,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PainelAdminTheme.errorRedAlt,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SelectableText(
                    para,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
