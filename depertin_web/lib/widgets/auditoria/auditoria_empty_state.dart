import 'package:flutter/material.dart';
import '../../theme/painel_admin_theme.dart';

/// Tela de "sem permissão" para quando o usuário não é staff.
class AuditoriaSemPermissao extends StatelessWidget {
  const AuditoriaSemPermissao({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: PainelAdminTheme.laranja, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Você não possui permissão para acessar os registros de auditoria.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: PainelAdminTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Este módulo é restrito a administradores master e master_city.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuditoriaErro extends StatelessWidget {
  const AuditoriaErro({super.key, required this.mensagem, this.onTentarNovamente});
  final String mensagem;
  final VoidCallback? onTentarNovamente;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PainelAdminTheme.errorRedAlt.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: PainelAdminTheme.errorRedAlt, size: 32),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível carregar os dados.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
              const SizedBox(height: 16),
              if (onTentarNovamente != null)
                FilledButton.icon(
                  onPressed: onTentarNovamente,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Tentar novamente'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
