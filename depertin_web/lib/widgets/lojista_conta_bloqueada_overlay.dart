import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/conta_bloqueio_lojista.dart';

/// Bloqueio operacional — sem painel em segundo plano.
String _formatarDataHora(DateTime d) {
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(d.day)}/${p2(d.month)}/${d.year} ${p2(d.hour)}:${p2(d.minute)}';
}

class LojistaContaBloqueadaOverlayWeb extends StatelessWidget {
  const LojistaContaBloqueadaOverlayWeb({
    super.key,
    required this.dadosUsuario,
    this.onSair,
  });

  final Map<String, dynamic> dadosUsuario;
  final VoidCallback? onSair;

  Future<void> _abrirWhatsApp() async {
    final texto =
        Uri.encodeComponent(ContaBloqueioLojista.mensagemWhatsAppPadrao);
    final uri = Uri.parse(
      'https://wa.me/${ContaBloqueioLojista.suporteWhatsAppDigits}?text=$texto',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final financeiro =
        ContaBloqueioLojistaHelper.isBloqueioFinanceiro(dadosUsuario);
    final temp =
        ContaBloqueioLojistaHelper.isBloqueioTemporarioTipo(dadosUsuario);
    final fim = ContaBloqueioLojistaHelper.dataFimBloqueio(dadosUsuario);
    final extraMotivo =
        ContaBloqueioLojistaHelper.textoMotivoBloqueio(dadosUsuario);

    const titulo = 'Acesso Bloqueado';

    final String corpo;
    if (financeiro) {
      corpo =
          'Seu estabelecimento encontra-se com pendências financeiras. Para regularização, entre em contato com o suporte.';
    } else if (temp) {
      corpo =
          'Sua conta foi temporariamente bloqueada. Para mais informações, entre em contato com o suporte.';
    } else {
      corpo =
          'O acesso ao painel foi suspenso. Para mais informações, entre em contato com o suporte.';
    }

    final dataFimTexto = fim != null && temp
        ? '\n\nPrevisão de liberação: ${_formatarDataHora(fim)}.'
        : '';

    final motivoExtra = extraMotivo != null ? '\n\n$extraMotivo' : '';

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    financeiro
                        ? Icons.account_balance_wallet_outlined
                        : (temp
                            ? Icons.schedule_rounded
                            : Icons.lock_outline_rounded),
                    size: 48,
                    color: PainelAdminTheme.roxo,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$corpo$dataFimTexto$motivoExtra',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    height: 1.5,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _abrirWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 22),
                    label: Text(
                      'Entrar em contato com o suporte',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: PainelAdminTheme.laranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                if (onSair != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onSair,
                    child: Text(
                      'Sair',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
