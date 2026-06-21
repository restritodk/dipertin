import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_navigator_key.dart';
import '../screens/auth/login_screen.dart';
import 'sessao_timeout_service.dart';

/// Mensagem padrão (texto profissional, sem jargão técnico do Firebase).
const String kMensagemSessaoExpirada =
    'Por motivo de segurança, sua sessão expirou. '
    'Faça login novamente para continuar usando sua conta.';

/// Intercepta erros de Firestore/Auth que indicam que a sessão expirou.
///
/// Quando o Firebase Auth token expira/é revogado, o Firestore passa a
/// retornar `permission-denied` (ou `unauthenticated`). Este serviço detecta
/// isso e faz logout graciosamente, mostrando um modal profissional ao invés
/// de deixar o erro técnico cru na tela.
///
/// Funciona globalmente via [navigatorKey], então pode ser acionado de
/// qualquer ponto (guard, builders de stream, catch de chamadas), sem
/// depender do [BuildContext] da tela atual.
class SessaoErroInterceptor {
  SessaoErroInterceptor._();

  static bool _jaProcessandoErro = false;

  /// `true` enquanto o fluxo de sessão expirada está em andamento — usado por
  /// builders para evitar mostrar erro cru e evitar loop de re-disparo.
  static bool get processando => _jaProcessandoErro;

  /// Checa se um erro qualquer indica sessão expirada (token expirado/revogado,
  /// usuário sem permissão por falta de autenticação válida).
  static bool ehErroSessaoExpirada(Object? erro) {
    if (erro is FirebaseException) {
      final codigo = erro.code.toLowerCase();
      return codigo == 'permission-denied' || codigo == 'unauthenticated';
    }
    if (erro is FirebaseAuthException) {
      final codigo = erro.code.toLowerCase();
      return codigo == 'user-token-expired' ||
          codigo == 'invalid-user-token' ||
          codigo == 'user-disabled' ||
          codigo == 'user-not-found';
    }
    return false;
  }

  /// Compatibilidade: mantém o nome antigo usado em chamadas existentes.
  static bool podeInterceptarErro(Object erro) => ehErroSessaoExpirada(erro);

  /// Processa o erro de sessão expirada de forma elegante.
  ///
  /// [context] é opcional: se ausente/desmontado, usa o [navigatorKey] global.
  /// O fluxo só roda uma vez por expiração (trava [_jaProcessandoErro]).
  static Future<void> processarErroSessaoExpirada(
    BuildContext? context, {
    String mensagem = kMensagemSessaoExpirada,
  }) async {
    if (_jaProcessandoErro) return;
    _jaProcessandoErro = true;

    try {
      // Encerra a sessão localmente antes de qualquer UI (evita novos
      // listeners dispararem mais permission-denied).
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      try {
        await SessaoTimeoutService.limparSessao();
      } catch (_) {}

      final ctx = (context != null && context.mounted)
          ? context
          : navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      // Mostra modal profissional.
      await _mostrarModalSessaoExpirada(ctx, mensagem);

      // Redireciona para login (biometria/digital aparece sozinha no
      // LoginScreen quando há vínculo; senão login normal por e-mail/senha).
      final navCtx = ctx.mounted ? ctx : navigatorKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        Navigator.of(navCtx, rootNavigator: true).pushAndRemoveUntil(
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
      useRootNavigator: true,
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
                  'Sessão expirada',
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
                            'Fazer login novamente',
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
