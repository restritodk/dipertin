import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import 'sessao_timeout_service.dart';

/// Intercepta erros de Firestore que indicam que a sessão expirou.
///
/// Quando o Firebase Auth token expira (após 24h), o Firestore retorna
/// `permission-denied`. Este serviço detecta isso e faz logout graciosamente,
/// mostrando um modal elegante ao invés de deixar a tela branca de erro.
class SessaoErroInterceptor {
  SessaoErroInterceptor._();

  static bool _jaProcessandoErro = false;

  /// Checa se o erro é `permission-denied` (típico de token expirado)
  /// e faz o logout gracioso com modal.
  static bool podeInterceptarErro(Object erro) {
    if (erro is FirebaseException) {
      return erro.code.toLowerCase() == 'permission-denied';
    }
    return false;
  }

  /// Processa o erro de sessão expirada de forma elegante.
  /// Chame isso ao capturar um erro de Firestore que passou em [podeInterceptarErro].
  static Future<void> processarErroSessaoExpirada(
    BuildContext context, {
    String mensagem = 'Sua sessão expirou por segurança.',
  }) async {
    if (_jaProcessandoErro) return;
    _jaProcessandoErro = true;

    try {
      // Valida se realmente a sessão expirou
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.reload();
        } catch (_) {
          // Se reload falha, provavelmente o token é inválido
        }
      }

      // Faz logout
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      try {
        await SessaoTimeoutService.limparSessao();
      } catch (_) {}

      if (!context.mounted) return;

      // Mostra modal elegante
      await _mostrarModalSessaoExpirada(context, mensagem);

      // Redireciona para login
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } finally {
      _jaProcessandoErro = false;
    }
  }

  static Future<void> _mostrarModalSessaoExpirada(
    BuildContext context,
    String mensagem,
  ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModalSessaoExpirada(mensagem: mensagem),
    );
  }
}

/// Modal elegante e profissional para avisar sobre expiração de sessão.
class _ModalSessaoExpirada extends StatefulWidget {
  final String mensagem;

  const _ModalSessaoExpirada({required this.mensagem});

  @override
  State<_ModalSessaoExpirada> createState() => _ModalSessaoExpiradaState();
}

class _ModalSessaoExpiradaState extends State<_ModalSessaoExpirada>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeInAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeInAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const roxo = Color(0xFF6A1B9A);
    const laranja = Color(0xFFFF8F00);

    return FadeTransition(
      opacity: _fadeInAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: roxo.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícone com animação
                ScaleTransition(
                  scale: Tween<double>(begin: 0.5, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _animController,
                      curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
                    ),
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: laranja.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 40,
                      color: laranja,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Título
                const Text(
                  'Sessão Expirada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),

                // Mensagem
                Text(
                  widget.mensagem,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                // Motivo (texto secundário)
                Text(
                  'Por sua segurança, reautentique com seu email e senha.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),

                // Botão
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [roxo, Color(0xFF8E24AA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: roxo.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(14),
                        child: const Center(
                          child: Text(
                            'Fazer Login Novamente',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
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
