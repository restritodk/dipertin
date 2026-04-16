import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../services/conta_bloqueio_entregador_service.dart';

/// Tela bloqueante — bloqueio operacional do entregador (financeiro ou temporário).
class EntregadorContaBloqueadaOverlay extends StatelessWidget {
  const EntregadorContaBloqueadaOverlay({
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
        ContaBloqueioEntregadorService.isBloqueioFinanceiro(dadosUsuario);
    final temp =
        ContaBloqueioEntregadorService.isBloqueioTemporarioTipo(dadosUsuario);
    final fim = ContaBloqueioEntregadorService.dataFimBloqueio(dadosUsuario);
    final inicio =
        ContaBloqueioEntregadorService.dataInicioBloqueio(dadosUsuario);
    final extraMotivo =
        ContaBloqueioEntregadorService.textoMotivoBloqueio(dadosUsuario);

    final String titulo;
    if (financeiro) {
      titulo = 'Conta suspensa por inadimplência';
    } else if (temp) {
      titulo = 'Bloqueio temporário';
    } else {
      titulo = 'Acesso bloqueado';
    }

    final String corpo;
    if (financeiro) {
      corpo =
          'Sua conta de entregador está suspensa por pendências financeiras. '
          'Regularize a situação para voltar a aceitar corridas.';
    } else if (temp) {
      corpo =
          'Sua conta foi bloqueada por um período determinado. '
          'Durante esse tempo você não pode ficar online nem aceitar corridas.';
    } else {
      corpo =
          'O acesso ao painel de entregas foi suspenso. '
          'Entre em contato com o suporte para mais informações.';
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _roxo.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    financeiro
                        ? Icons.account_balance_wallet_outlined
                        : (temp
                            ? Icons.schedule_rounded
                            : Icons.lock_outline_rounded),
                    size: 48,
                    color: _roxo,
                  ),
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 14),
                Text(
                  corpo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (temp) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.event_available_rounded,
                                color: Colors.amber.shade900, size: 26),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Liberação prevista',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          fim != null
                              ? fmt.format(fim)
                              : 'Data a definir pelo administrador — fale com o suporte.',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade900,
                            height: 1.3,
                          ),
                        ),
                        if (inicio != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Bloqueio iniciado em ${fmt.format(inicio)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        if (extraMotivo != null &&
                            extraMotivo.trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Divider(height: 1, color: Colors.amber.shade200),
                          const SizedBox(height: 12),
                          Text(
                            'Informação administrativa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            extraMotivo,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (extraMotivo != null &&
                    extraMotivo.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    extraMotivo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
