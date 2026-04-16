import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Atalho: análises e exportação PDF estão em **Financeiro**.
class LojistaCarteiraRelatorioScreen extends StatelessWidget {
  const LojistaCarteiraRelatorioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.laranja.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.assessment_outlined,
                    size: 52,
                    color: PainelAdminTheme.laranja.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Relatório',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gráficos, totais por período, movimentações e exportação em PDF estão reunidos na área Financeiro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      context.navegarPainel('/carteira_financeiro'),
                  icon: const Icon(Icons.bar_chart_rounded),
                  label: const Text('Abrir Financeiro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PainelAdminTheme.roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
