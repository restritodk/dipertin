import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../services/conta_bloqueio_lojista_service.dart';

/// Tela bloqueante — bloqueio operacional (sem fluxo de cadastro).
class LojistaContaBloqueadaOverlay extends StatelessWidget {
  const LojistaContaBloqueadaOverlay({
    super.key,
    required this.dadosUsuario,
    this.onSair,
  });

  final Map<String, dynamic> dadosUsuario;
  final VoidCallback? onSair;

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);

  Future<void> _abrirWhatsApp() async {
    final texto = Uri.encodeComponent(ContaBloqueioLojista.mensagemWhatsAppPadrao);
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
        ContaBloqueioLojistaService.isBloqueioFinanceiro(dadosUsuario);
    final temp =
        ContaBloqueioLojistaService.isBloqueioTemporarioTipo(dadosUsuario);
    final fim = ContaBloqueioLojistaService.dataFimBloqueio(dadosUsuario);
    final extraMotivo = ContaBloqueioLojistaService.textoMotivoBloqueio(dadosUsuario);

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
        ? '\n\nPrevisão de liberação: ${DateFormat('dd/MM/yyyy HH:mm').format(fim)}.'
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
                    color: _roxo.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    financeiro
                        ? Icons.account_balance_wallet_outlined
                        : (temp ? Icons.schedule_rounded : Icons.lock_outline_rounded),
                    size: 48,
                    color: _roxo,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$corpo$dataFimTexto$motivoExtra',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _abrirWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 22),
                    label: const Text(
                      'Entrar em contato com o suporte',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _laranja,
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
                    child: const Text(
                      'Sair',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
