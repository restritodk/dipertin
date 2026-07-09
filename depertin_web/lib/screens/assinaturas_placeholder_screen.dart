import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';

/// Tela placeholder para sub-rotas da Gestão de Assinaturas que
/// ainda não foram implementadas.
class AssinaturasPlaceholderScreen extends StatelessWidget {
  final String titulo;
  final String descricao;
  final IconData icone;

  const AssinaturasPlaceholderScreen({
    super.key,
    required this.titulo,
    this.descricao = 'Esta funcionalidade será implementada em breve.',
    this.icone = Icons.construction_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      appBar: AppBar(
        backgroundColor: PainelAdminTheme.surfaceCard,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone,
                  color: PainelAdminTheme.roxo, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EDF6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icone,
                size: 56,
                color: PainelAdminTheme.roxo.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                descricao,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
