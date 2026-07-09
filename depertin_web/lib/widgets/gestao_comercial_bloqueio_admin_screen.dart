import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/cliente_assinatura_model.dart';
import '../navigation/painel_navigation_scope.dart';
import '../services/assinaturas_clientes_service.dart';

/// Tela premium exibida quando o admin suspende o Gestão Comercial do lojista.
class GestaoComercialBloqueioAdminScreen extends StatefulWidget {
  const GestaoComercialBloqueioAdminScreen({
    super.key,
    required this.assinatura,
    this.lojaId,
    this.lojaNome,
    this.ownerName,
    this.ownerEmail,
  });

  final ClienteAssinaturaModel assinatura;
  final String? lojaId;
  final String? lojaNome;
  final String? ownerName;
  final String? ownerEmail;

  @override
  State<GestaoComercialBloqueioAdminScreen> createState() =>
      _GestaoComercialBloqueioAdminScreenState();
}

class _GestaoComercialBloqueioAdminScreenState
    extends State<GestaoComercialBloqueioAdminScreen> {
  ClienteAssinaturaModel? _assinaturaAtual;

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _roxoClaro = Color(0xFF8E24AA);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _fundo = Color(0xFFF5F4F8);
  static const Color _textoPrimario = Color(0xFF1A1A2E);
  static const Color _textoMuted = Color(0xFF64748B);
  static const Color _borda = Color(0xFFEEEAF6);

  @override
  void initState() {
    super.initState();
    _assinaturaAtual = widget.assinatura;
    _escutarAssinatura();
  }

  void _escutarAssinatura() {
    FirebaseFirestore.instance
        .collection(AssinaturasClientesService.colecao)
        .doc(widget.assinatura.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      setState(
        () => _assinaturaAtual = ClienteAssinaturaModel.fromFirestore(snap),
      );
    });
  }

  String get _motivoAdmin {
    final motivo = _assinaturaAtual?.blockReason?.trim() ?? '';
    if (motivo.isNotEmpty) return motivo;
    return widget.assinatura.blockReason?.trim() ?? '';
  }

  String get _dataBloqueio {
    final ts = _assinaturaAtual?.blockedAt ?? widget.assinatura.blockedAt;
    if (ts == null) return '—';
    return DateFormat('dd/MM/yyyy \'às\' HH:mm').format(ts.toDate());
  }

  Future<void> _contatarSuporte() async {
    final loja = widget.lojaNome ?? assinatura.storeName;
    final mailUri = Uri(
      scheme: 'mailto',
      path: 'contato@dipertin.com.br',
      queryParameters: {
        'subject': 'Gestão Comercial suspenso — $loja',
        'body':
            'Olá, equipe DiPertin.\n\nMinha loja teve o acesso ao Gestão Comercial suspenso '
            'e gostaria de entender como regularizar.\n\nObrigado.',
      },
    );
    await launchUrl(mailUri);
  }

  ClienteAssinaturaModel get assinatura => _assinaturaAtual ?? widget.assinatura;

  @override
  Widget build(BuildContext context) {
    final assinatura = this.assinatura;
    final motivo = _motivoAdmin;

    return Scaffold(
      backgroundColor: _fundo,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _roxo.withValues(alpha: 0.12),
                    _roxo.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _laranja.withValues(alpha: 0.10),
                    _laranja.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _borda),
                        boxShadow: [
                          BoxShadow(
                            color: _roxo.withValues(alpha: 0.08),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_roxo, _roxoClaro],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.22),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.admin_panel_settings_rounded,
                                    size: 38,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Gestão Comercial temporariamente indisponível',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'A equipe DiPertin suspendeu o acesso a este módulo '
                                  'na sua loja. Seus pedidos, cardápio e demais '
                                  'funções do painel continuam normais.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.88),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _infoChip(
                                  icon: Icons.workspace_premium_rounded,
                                  label: 'Plano contratado',
                                  valor: assinatura.planName,
                                ),
                                const SizedBox(height: 10),
                                _infoChip(
                                  icon: Icons.schedule_rounded,
                                  label: 'Suspensão registrada em',
                                  valor: _dataBloqueio,
                                ),
                                if (motivo.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  Text(
                                    'Mensagem da equipe DiPertin',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _textoPrimario,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF8F0),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: _laranja.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 20,
                                          color: _laranja.withValues(alpha: 0.9),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            motivo,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 14,
                                              color: _textoPrimario,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    'Se precisar de mais detalhes, entre em contato '
                                    'com o suporte DiPertin.',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: _textoMuted,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _contatarSuporte,
                                    icon: const Icon(Icons.support_agent_rounded,
                                        size: 18),
                                    label: const Text('Falar com o suporte'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _roxo,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.navegarPainel('/dashboard'),
                                    icon: const Icon(Icons.arrow_back_rounded,
                                        size: 18),
                                    label: const Text('Voltar ao painel principal'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _textoPrimario,
                                      side: BorderSide(
                                        color: _roxo.withValues(alpha: 0.25),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String valor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _roxo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
