import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/painel_admin_theme.dart';

/// Mensagem profissional padrão (sem jargão técnico do Firebase).
const String kMensagemSessaoExpiradaPainel =
    'Por motivo de segurança, sua sessão expirou. '
    'Faça login novamente para continuar usando sua conta.';

/// Tratamento global de sessão expirada no painel web.
///
/// Quando o token do Firebase Auth expira/é revogado, o Firestore passa a
/// retornar `permission-denied` (ou `unauthenticated`). Em vez de mostrar o
/// erro técnico cru, este serviço detecta a situação, encerra a sessão e
/// apresenta um diálogo profissional, redirecionando para o login.
///
/// É acionado de forma reativa pelos `StreamBuilder` de `users/{uid}` que já
/// existem em toda rota do painel (shell), então cobre todas as telas
/// protegidas sem custo de leitura extra.
class SessaoPainelService {
  SessaoPainelService._();

  /// Navigator raiz do [MaterialApp] do painel — permite navegar/exibir
  /// diálogo de qualquer ponto sem depender do [BuildContext] da tela.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _processando = false;

  /// `true` enquanto o fluxo de sessão expirada está em andamento — usado por
  /// builders para evitar mostrar erro cru e evitar loop de re-disparo.
  static bool get processando => _processando;

  /// Indica se um erro qualquer representa sessão expirada.
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

  /// Encerra a sessão e mostra o diálogo profissional (uma única vez por
  /// expiração). Em seguida redireciona para `/login`.
  static Future<void> tratarSessaoExpirada({
    String mensagem = kMensagemSessaoExpiradaPainel,
  }) async {
    if (_processando) return;
    _processando = true;

    try {
      // Encerra a sessão antes da UI para parar novos listeners de errarem.
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await showDialog<void>(
          context: ctx,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => _DialogoSessaoExpirada(mensagem: mensagem),
        );
      }

      final navState = navigatorKey.currentState;
      if (navState != null) {
        navState.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } finally {
      _processando = false;
    }
  }
}

class _DialogoSessaoExpirada extends StatelessWidget {
  const _DialogoSessaoExpirada({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: PainelAdminTheme.roxo.withValues(alpha: 0.15),
                blurRadius: 32,
                offset: const Offset(0, 16),
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
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 38,
                  color: PainelAdminTheme.laranja,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Sessão expirada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: PainelAdminTheme.textoSecundario,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [PainelAdminTheme.roxo, Color(0xFF8E24AA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: PainelAdminTheme.roxo.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(14),
                      child: const Center(
                        child: Text(
                          'Fazer login novamente',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
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
    );
  }
}
