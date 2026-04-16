import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela Configuração da Carteira do Lojista — em construção.
class LojistaCarteiraConfiguracaoScreen extends StatelessWidget {
  const LojistaCarteiraConfiguracaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 52,
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Configuração',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.roxo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Em construção — em breve você poderá configurar\nchave PIX, dados bancários e preferências de repasse.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
