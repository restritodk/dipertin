import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firebase_functions_config.dart';
import '../services/painel_google_auth_service.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../utils/conta_bloqueio_lojista.dart';
import '../utils/firestore_web_safe.dart';
import '../services/painel_google_redirect_pending.dart';
import '../widgets/lojista_conta_bloqueada_overlay.dart';

String _mensagemErroThrowableSegura(Object e) {
  try {
    final s = e.toString();
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  } catch (_) {
    return 'Erro ao processar o login. Tente e-mail e senha ou outro navegador.';
  }
}

/// Mensagens claras para falhas do login Google no web (domínio OAuth, pop-up, etc.).
String _mensagemErroGoogleFirebaseAuth(FirebaseAuthException e) {
  final code = e.code;
  final msg = (e.message ?? '').trim();
  final detalhe = (msg.isNotEmpty && msg != 'Error') ? ' $msg' : '';
  switch (code) {
    case 'unauthorized-domain':
      return 'Este site não está na lista de domínios autorizados do Firebase. '
          'No Firebase Console: Authentication → Configurações → Domínios autorizados — '
          'adicione o domínio que aparece na barra de endereços (ex.: dipertin.com.br). '
          'Se usar www, inclua também www.dipertin.com.br.';
    case 'operation-not-allowed':
      return 'O login com Google não está ativo. Ative em Authentication → '
          'Método de login → Google.';
    case 'popup-blocked':
      return 'O navegador bloqueou a janela do Google. Permita pop-ups para este site ou tente outro navegador.';
    case 'network-request-failed':
      return 'Falha de rede. Verifique sua conexão.$detalhe';
    case 'web-storage-unsupported':
      return 'Este navegador bloqueou armazenamento necessário para o login. '
          'Tente outro navegador ou desative modo restrito/privado.';
    case 'internal-error':
      return 'Erro interno do Firebase ao abrir o Google (comum em domínio próprio). '
          'Tente de novo: o sistema pode usar login por redirecionamento. '
          'Se persistir: Google Cloud Console → Credenciais → sua chave de API do '
          'navegador (Browser key) — em "Restrições de aplicativo" deixe sem restrição '
          'ou adicione referências HTTP: https://dipertin.com.br/* e https://www.dipertin.com.br/*. '
          'Em "Origens JavaScript" do cliente OAuth Web: https://dipertin.com.br e '
          'https://www.dipertin.com.br. Firebase → Authentication → Domínios autorizados: '
          'inclua o mesmo domínio que aparece no navegador.';
    default:
      return 'Código: $code.$detalhe '
          'Confira também no Google Cloud Console (APIs e serviços → Credenciais) se o '
          'cliente OAuth Web (tipo 3) tem em "Origens JavaScript autorizadas" o endereço '
          'https://dipertin.com.br e, se usar, https://www.dipertin.com.br.';
  }
}

String _mensagemErroGoogleFunctions(FirebaseFunctionsException e) {
  final code = e.code;
  switch (code) {
    case 'not-found':
      return 'Função de validação não encontrada no servidor. Faça deploy da Cloud Function '
          'painelValidarPosLoginGoogle (firebase deploy --only functions).';
    case 'permission-denied':
      return e.message ?? 'Permissão negada ao validar o login.';
    case 'unauthenticated':
      return 'Sessão inválida ao validar o login. Tente novamente.';
    default:
      return e.message ?? 'Erro ao validar acesso no servidor (código: $code).';
  }
}

/// Reforço no cliente: apaga o usuário no Firebase Auth só quando a recusa é
/// "não lojista" / sem e-mail / perfil — alinhado ao Admin SDK na Cloud Function.
/// **Nunca** para `LOJISTA_NAO_APROVADO` (há `users/{uid}` de lojista).
bool _deveApagarAuthPorCodigoRecusaPainel(String? code) {
  return code == 'NOT_LOJISTA' ||
      code == 'NO_EMAIL' ||
      code == 'NO_PROFILE';
}

Future<void> _tentarApagarUsuarioAuthAtualPosRecusaPainel() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  try {
    await u.delete();
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') return;
    if (kDebugMode) {
      debugPrint('[login] delete pós-recusa: ${e.code} ${e.message}');
    }
  } catch (_) {}
}

Future<void> _sairSessaoGooglePainel({required bool apagarUsuarioAuth}) async {
  if (apagarUsuarioAuth) {
    await _tentarApagarUsuarioAuthAtualPosRecusaPainel();
  }
  await FirebaseAuth.instance.signOut();
  await painelSignOutGoogle();
}

class LoginAdminScreen extends StatefulWidget {
  const LoginAdminScreen({super.key});

  @override
  State<LoginAdminScreen> createState() => _LoginAdminScreenState();
}

class _LoginAdminScreenState extends State<LoginAdminScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingGoogle = false;
  bool _ocultarSenha = true;

  static const Color _ink = Color(0xFF1E1B4B);

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _emailController.text = 'master@teste.com';
      _senhaController.text = 'master';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _completarLoginGoogleAposRedirect();
    });
  }

  /// Após [signInWithRedirect], [main.dart] já chamou [getRedirectResult] uma vez.
  Future<void> _completarLoginGoogleAposRedirect() async {
    if (!kIsWeb) return;
    final pending = PainelGoogleRedirectPending.uidParaCompletarLogin;
    PainelGoogleRedirectPending.uidParaCompletarLogin = null;
    if (pending == null) return;
    if (!mounted) return;
    setState(() => _isLoadingGoogle = true);
    try {
      await _executarFluxoAposGoogleAutenticado(pending);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        await painelSignOutGoogle();
        _mostrarErro(
          'Este e-mail já está registado com outro método de login. Use e-mail e senha.',
        );
      } else {
        await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
        _mostrarErro(
          'Não foi possível entrar com Google.\n${_mensagemErroGoogleFirebaseAuth(e)}',
        );
      }
      if (mounted) setState(() => _isLoadingGoogle = false);
    } on FirebaseFunctionsException catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(_mensagemErroGoogleFunctions(e));
      if (mounted) setState(() => _isLoadingGoogle = false);
    } on CallableHttpException catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(e.message);
      if (mounted) setState(() => _isLoadingGoogle = false);
    } on TimeoutException catch (_) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(
        'A validação no servidor demorou demais ou a rede falhou. '
        'Tente de novo em instantes.',
      );
      if (mounted) setState(() => _isLoadingGoogle = false);
    } catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(
        'Erro ao entrar com Google: ${_mensagemErroThrowableSegura(e)}',
      );
      if (mounted) setState(() => _isLoadingGoogle = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.plusJakartaSans(
        color: PainelAdminTheme.textoSecundario,
        fontSize: 14,
      ),
      floatingLabelStyle: GoogleFonts.plusJakartaSans(
        color: PainelAdminTheme.roxo,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F7FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8E4F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8E4F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  Future<void> _fazerLogin() async {
    String email = _emailController.text.trim();
    String senha = _senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      _mostrarErro('Por favor, preencha o e-mail e a senha.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!docSnap.exists) {
        _mostrarErro(
          'Sem documento em users/$uid no Firestore. Crie o perfil com o mesmo UID do Authentication.',
        );
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }

      await _aplicarRegrasPosLoginFirestore(uid, safeWebDocData(docSnap));
    } on FirebaseAuthException catch (e) {
      String mensagem = 'Erro ao conectar. Tente novamente.';
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'wrong-password') {
        mensagem = 'E-mail ou senha incorretos.';
      }
      _mostrarErro(mensagem);
      setState(() => _isLoading = false);
    } catch (e) {
      _mostrarErro('Erro interno no servidor.');
      setState(() => _isLoading = false);
    }
  }

  /// Regras de perfil e navegação (e-mail/senha ou após validação Google no servidor).
  Future<void> _aplicarRegrasPosLoginFirestore(
    String uid,
    Map<String, dynamic> dadosUsuario,
  ) async {
    // Maior privilégio entre campos — evita role legado "cliente" com tipoUsuario "lojista".
    String tipoUsuario = perfilAdministrativoPainel(dadosUsuario);
    bool primeiroAcesso = dadosUsuario['primeiro_acesso'] ?? false;

    const perfisPainel = <String>{
      'master',
      'master_city',
      'lojista',
      'superadmin',
      'super_admin',
    };
    if (!perfisPainel.contains(tipoUsuario)) {
      _mostrarErro(
        'Acesso negado. Seu perfil não tem permissão para o painel web.',
      );
      await FirebaseAuth.instance.signOut();
      setState(() {
        _isLoading = false;
        _isLoadingGoogle = false;
      });
      return;
    }

    if (primeiroAcesso) {
      setState(() {
        _isLoading = false;
        _isLoadingGoogle = false;
      });
      _mostrarModalTrocaSenha(
        uid,
        dadosUsuario['nome'] ?? 'Parceiro',
        rotaPosLogin: tipoUsuario == 'lojista' ? '/meus_pedidos' : '/painel',
      );
      return;
    }

    if (tipoUsuario == 'lojista') {
      await ContaBloqueioLojistaHelper.sincronizarLiberacaoSeExpirado(uid);
      final docAtual =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final dadosAtual = safeWebDocData(docAtual);
      if (dadosAtual.isNotEmpty &&
          ContaBloqueioLojistaHelper.estaBloqueadoParaOperacoes(dadosAtual)) {
        setState(() {
          _isLoading = false;
          _isLoadingGoogle = false;
        });
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: LojistaContaBloqueadaOverlayWeb(
                dadosUsuario: dadosAtual,
                onSair: () async {
                  Navigator.of(ctx).pop();
                  await FirebaseAuth.instance.signOut();
                  await painelSignOutGoogle();
                },
              ),
            ),
          ),
        );
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingGoogle = false;
      });
      if (tipoUsuario == 'lojista') {
        Navigator.pushReplacementNamed(context, '/meus_pedidos');
      } else {
        Navigator.pushReplacementNamed(context, '/painel');
      }
    }
  }

  /// Callable + Firestore + navegação, depois de haver sessão Google (popup ou redirect).
  Future<void> _executarFluxoAposGoogleAutenticado(String uid) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    final data = await callFirebaseFunctionSafe(
      'painelValidarPosLoginGoogle',
      timeout: const Duration(seconds: 60),
    );
    if (data['ok'] != true) {
      final code = data['code']?.toString();
      await _sairSessaoGooglePainel(
        apagarUsuarioAuth: _deveApagarAuthPorCodigoRecusaPainel(code),
      );
      if (mounted) setState(() => _isLoadingGoogle = false);
      if (!mounted) return;
      if (code == 'LOJISTA_NAO_APROVADO') {
        _mostrarDialogBloqueioGoogle(
          icone: Icons.hourglass_top_rounded,
          corIcone: const Color(0xFFD97706),
          fundoIcone: const Color(0xFFFEF3C7),
          titulo: 'Cadastro em análise',
          mensagem:
              'Sua loja ainda está em processo de aprovação. Assim que o '
              'cadastro for aprovado, você poderá acessar o painel com o '
              'mesmo e-mail do Google.\n\n'
              'Caso precise de ajuda, entre em contato pelo aplicativo '
              'DiPertin ou pelo nosso suporte.',
          textoBotao: 'Entendido',
        );
      } else if (code == 'NO_EMAIL' || code == 'NO_PROFILE') {
        _mostrarDialogBloqueioGoogle(
          icone: Icons.error_outline_rounded,
          corIcone: const Color(0xFFDC2626),
          fundoIcone: const Color(0xFFFEE2E2),
          titulo: 'E-mail não identificado',
          mensagem:
              'Não foi possível confirmar o e-mail da sua conta Google. '
              'Tente com outra conta Google ou utilize e-mail e senha para '
              'acessar o painel.',
          textoBotao: 'Fechar',
        );
      } else {
        _mostrarDialogBloqueioGoogle(
          icone: Icons.storefront_rounded,
          corIcone: PainelAdminTheme.roxo,
          fundoIcone: const Color(0xFFF3E8FF),
          titulo: 'Acesso exclusivo para lojistas',
          mensagem:
              'O acesso ao painel via Google é exclusivo para lojistas '
              'cadastrados e aprovados na plataforma DiPertin.\n\n'
              'Para se tornar um lojista parceiro, baixe o aplicativo '
              'DiPertin na sua loja de aplicativos e realize seu cadastro.',
          textoBotao: 'Entendido',
        );
      }
      return;
    }

    final docSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final dadosFirestore = safeWebDocData(docSnap);

    if (!docSnap.exists || dadosFirestore.isEmpty) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: true);
      _mostrarErro(
        'Sem documento em users/$uid no Firestore.',
      );
      if (mounted) setState(() => _isLoadingGoogle = false);
      return;
    }

    await _aplicarRegrasPosLoginFirestore(uid, dadosFirestore);
  }

  Future<void> _loginComGoogle() async {
    if (_isLoading || _isLoadingGoogle) return;

    setState(() => _isLoadingGoogle = true);

    try {
      final cred = await painelSignInWithGoogle();
      if (cred == null) {
        // Redirecionamento para Google iniciado (fallback ao internal-error no popup).
        if (mounted) setState(() => _isLoadingGoogle = false);
        return;
      }
      final uid = cred.user!.uid;
      await _executarFluxoAposGoogleAutenticado(uid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        await painelSignOutGoogle();
        _mostrarErro(
          'Este e-mail já está registado com outro método de login. Use e-mail e senha.',
        );
      } else if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        // Usuário fechou o popup do Google — sem mensagem de erro.
      } else {
        await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
        final hint = _mensagemErroGoogleFirebaseAuth(e);
        _mostrarErro(
          'Não foi possível entrar com Google.\n$hint',
        );
      }
      setState(() => _isLoadingGoogle = false);
    } on FirebaseFunctionsException catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(_mensagemErroGoogleFunctions(e));
      setState(() => _isLoadingGoogle = false);
    } on CallableHttpException catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(e.message);
      setState(() => _isLoadingGoogle = false);
    } on TimeoutException catch (_) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(
        'A validação no servidor demorou demais ou a rede falhou. '
        'Tente de novo em instantes.',
      );
      setState(() => _isLoadingGoogle = false);
    } on StateError catch (e) {
      if (e.message.contains('cancelado')) {
        setState(() => _isLoadingGoogle = false);
        return;
      }
      _mostrarErro(e.message);
      setState(() => _isLoadingGoogle = false);
    } catch (e) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: false);
      _mostrarErro(
        'Erro ao entrar com Google: ${_mensagemErroThrowableSegura(e)}',
      );
      setState(() => _isLoadingGoogle = false);
    }
  }

  void _mostrarDialogBloqueioGoogle({
    required IconData icone,
    required Color corIcone,
    required Color fundoIcone,
    required String titulo,
    required String mensagem,
    String textoBotao = 'Entendido',
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 8,
          shadowColor: Colors.black26,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: fundoIcone,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone, color: corIcone, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.3,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 40,
                    height: 3,
                    decoration: BoxDecoration(
                      color: corIcone.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      height: 1.6,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.roxo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        textoBotao,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarModalTrocaSenha(
    String userId,
    String nomeUsuario, {
    String rotaPosLogin = '/painel',
  }) {
    TextEditingController novaSenhaC = TextEditingController();
    TextEditingController confirmarSenhaC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            Future<void> salvarNovaSenha() async {
              if (novaSenhaC.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'A senha deve ter pelo menos 6 caracteres.',
                      style: GoogleFonts.plusJakartaSans(),
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return;
              }
              if (novaSenhaC.text != confirmarSenhaC.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'As senhas digitadas não são iguais.',
                      style: GoogleFonts.plusJakartaSans(),
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return;
              }

              setStateModal(() => isSalvando = true);

              try {
                await FirebaseAuth.instance.currentUser!.updatePassword(
                  novaSenhaC.text.trim(),
                );

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({
                      'senha': novaSenhaC.text.trim(),
                      'primeiro_acesso': false,
                      'data_atualizacao': FieldValue.serverTimestamp(),
                    });

                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, rotaPosLogin);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao atualizar senha: $e',
                        style: GoogleFonts.plusJakartaSans(),
                      ),
                      backgroundColor: const Color(0xFFDC2626),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              } finally {
                setStateModal(() => isSalvando = false);
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.verified_user_rounded,
                          color: const Color(0xFF059669),
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Primeiro acesso',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Olá, $nomeUsuario. Por segurança, defina uma nova senha para continuar.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          height: 1.5,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: novaSenhaC,
                        obscureText: true,
                        decoration: _fieldDecoration(
                          label: 'Nova senha',
                          prefix: const Icon(
                            Icons.lock_rounded,
                            color: PainelAdminTheme.roxo,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: confirmarSenhaC,
                        obscureText: true,
                        decoration: _fieldDecoration(
                          label: 'Confirmar senha',
                          prefix: const Icon(
                            Icons.lock_outline_rounded,
                            color: PainelAdminTheme.roxo,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: isSalvando ? null : salvarNovaSenha,
                        style: FilledButton.styleFrom(
                          backgroundColor: PainelAdminTheme.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isSalvando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Salvar e entrar',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _enviarRecuperacaoSenha() async {
    String email = _emailController.text.trim();
    if (email.isEmpty) {
      _mostrarErro(
        'Digite o e-mail no campo acima para recuperar a senha.',
      );
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RecuperacaoSenhaDialog(emailInicial: email),
    );
  }

  void _mostrarErro(String mensagem) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem, style: GoogleFonts.plusJakartaSans()),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Widget _painelMarca({required bool wide}) {
    const baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        PainelAdminTheme.roxoEscuro,
        PainelAdminTheme.roxo,
        PainelAdminTheme.roxoSidebarFim,
      ],
    );

    final stack = ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: baseGradient)),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.92, -0.72),
                  radius: 1.05,
                  colors: [
                    PainelAdminTheme.laranja.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.85, 0.85),
                  radius: 0.95,
                  colors: [
                    Colors.white.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 56 : 32,
              vertical: wide ? 48 : 36,
            ),
            child: Column(
              crossAxisAlignment: wide
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Image.asset(
                    'assets/logo.png',
                    height: wide ? 72 : 64,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: wide ? 28 : 20),
                Text(
                  'DiPertin',
                  style: TextStyle(
                    fontSize: wide ? 36 : 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Painel administrativo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.88),
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: wide ? 24 : 16),
                Text(
                  'Gestão de lojas, entregadores, vitrine e operações — com segurança e clareza.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PainelAdminTheme.laranja.withValues(alpha: 0),
                      PainelAdminTheme.laranja.withValues(alpha: 0.85),
                      PainelAdminTheme.laranjaSuave.withValues(alpha: 0.65),
                      PainelAdminTheme.laranja.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (wide) return stack;
    return SizedBox(width: double.infinity, child: stack);
  }

  Widget _cartaoLogin({required bool wide}) {
    final sombras = wide
        ? <BoxShadow>[
            BoxShadow(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      margin: EdgeInsets.symmetric(
        horizontal: wide ? 24 : 20,
        vertical: wide ? 32 : 24,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 36 : 28,
        vertical: wide ? 40 : 32,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E4F0)),
        boxShadow: sombras,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ENTRAR',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Acesso ao painel',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: wide ? 26 : 24,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Acesso exclusivo para administradores e lojistas cadastrados.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _emailController,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.plusJakartaSans(fontSize: 15),
            decoration: _fieldDecoration(
              label: 'E-mail',
              prefix: const Icon(
                Icons.mail_outline_rounded,
                color: PainelAdminTheme.roxo,
                size: 22,
              ),
            ),
            onSubmitted: (_) {
              if (!_isLoading && !_isLoadingGoogle) _fazerLogin();
            },
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _senhaController,
            obscureText: _ocultarSenha,
            textInputAction: TextInputAction.done,
            style: GoogleFonts.plusJakartaSans(fontSize: 15),
            decoration: _fieldDecoration(
              label: 'Senha',
              prefix: const Icon(
                Icons.lock_outline_rounded,
                color: PainelAdminTheme.roxo,
                size: 22,
              ),
              suffix: IconButton(
                tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _ocultarSenha
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: PainelAdminTheme.textoSecundario,
                ),
                onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
              ),
            ),
            onSubmitted: (_) {
              if (!_isLoading && !_isLoadingGoogle) _fazerLogin();
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed:
                  (_isLoading || _isLoadingGoogle) ? null : _enviarRecuperacaoSenha,
              style: TextButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                'Esqueceu a senha?',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_isLoading || _isLoadingGoogle) ? null : _fazerLogin,
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.laranja,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  PainelAdminTheme.laranja.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Entrar no painel',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.25),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ou',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.textoSecundario,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.25),
                  thickness: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: (_isLoading || _isLoadingGoogle) ? null : _loginComGoogle,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1F1F1F),
              side: const BorderSide(color: Color(0xFFDADCE0)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoadingGoogle
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: PainelAdminTheme.roxo,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_circle_rounded,
                        size: 24,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Continuar com Google',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'O acesso é liberado quando o e-mail do Google for o mesmo do '
                'lojista aprovado no DiPertin.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  height: 1.35,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ),
          const SizedBox(height: 22),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F1F8),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE4DFEE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: PainelAdminTheme.roxo.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Acesso Restrito',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.15,
                      color: PainelAdminTheme.textoSecundario,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 46,
                  child: _painelMarca(wide: true),
                ),
                Expanded(
                  flex: 54,
                  child: Container(
                    color: PainelAdminTheme.fundoCanvas,
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _cartaoLogin(wide: true),
                    ),
                  ),
                ),
              ],
            );
          }

          // Um único scroll: evita SliverFillRemaining(hasScrollBody: false), que cortava
          // o final do cartão (selo "Acesso Restrito") quando a altura restante era curta.
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _painelMarca(wide: false)),
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  color: PainelAdminTheme.fundoCanvas,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _cartaoLogin(wide: false),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Diálogo de Recuperação de Senha (OTP via Cloud Functions + SMTP) ───

enum _RecStep { email, otp, novaSenha, concluido }

class _RecuperacaoSenhaDialog extends StatefulWidget {
  final String emailInicial;
  const _RecuperacaoSenhaDialog({required this.emailInicial});

  @override
  State<_RecuperacaoSenhaDialog> createState() =>
      _RecuperacaoSenhaDialogState();
}

class _RecuperacaoSenhaDialogState extends State<_RecuperacaoSenhaDialog> {
  _RecStep _step = _RecStep.email;
  bool _loading = false;
  String? _erro;

  late final TextEditingController _emailCtrl;
  final _otpCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _senhaConfCtrl = TextEditingController();

  String _tokenId = '';
  String _sessionId = '';
  bool _senhaVisivel = false;

  static String _extrairMensagemErro(Object e, String fallback) {
    if (e is FirebaseFunctionsException) return e.message ?? fallback;
    if (e is CallableHttpException) return e.message;
    final s = e.toString();
    if (s.contains('firebase_functions/')) {
      final match = RegExp(r'\]\s*(.+)$').firstMatch(s);
      if (match != null) return match.group(1)!.trim();
    }
    if (kDebugMode) return '$fallback\n($s)';
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.emailInicial);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _senhaCtrl.dispose();
    _senhaConfCtrl.dispose();
    super.dispose();
  }

  Future<void> _solicitarOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _erro = 'Informe um e-mail válido.');
      return;
    }
    setState(() { _loading = true; _erro = null; });
    try {
      final data = await callFirebaseFunctionSafe(
        'recuperacaoSenhaSolicitar',
        parameters: {'email': email},
      );
      _tokenId = (data['tokenId'] ?? '').toString();
      if (mounted) setState(() { _step = _RecStep.otp; _loading = false; });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RecSenha] FirebaseFunctionsException: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message ?? 'Erro ao solicitar código.';
        });
      }
    } on CallableHttpException catch (e) {
      debugPrint('[RecSenha] CallableHttpException: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message;
        });
      }
    } catch (e) {
      debugPrint('[RecSenha] Erro genérico _solicitarOtp: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = _extrairMensagemErro(
            e,
            'Não foi possível conectar ao servidor. '
            'Verifique sua conexão e tente novamente.',
          );
        });
      }
    }
  }

  Future<void> _verificarOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 4) {
      setState(() => _erro = 'O código deve ter 4 dígitos.');
      return;
    }
    setState(() { _loading = true; _erro = null; });
    try {
      final data = await callFirebaseFunctionSafe(
        'recuperacaoSenhaVerificarOtp',
        parameters: {
          'email': _emailCtrl.text.trim(),
          'otp': otp,
          'tokenId': _tokenId,
        },
      );
      _sessionId = (data['sessionId'] ?? '').toString();
      if (mounted) setState(() { _step = _RecStep.novaSenha; _loading = false; });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RecSenha] FirebaseFunctionsException verificarOtp: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message ?? 'Código inválido ou expirado.';
        });
      }
    } on CallableHttpException catch (e) {
      debugPrint('[RecSenha] CallableHttpException verificarOtp: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message;
        });
      }
    } catch (e) {
      debugPrint('[RecSenha] Erro genérico _verificarOtp: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = _extrairMensagemErro(e, 'Erro ao verificar código. Tente novamente.');
        });
      }
    }
  }

  Future<void> _definirNovaSenha() async {
    final senha = _senhaCtrl.text;
    final conf = _senhaConfCtrl.text;
    if (senha.length < 8) {
      setState(() => _erro = 'A senha deve ter pelo menos 8 caracteres.');
      return;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(senha) || !RegExp(r'\d').hasMatch(senha)) {
      setState(() => _erro = 'A senha deve conter letras e números.');
      return;
    }
    if (senha != conf) {
      setState(() => _erro = 'As senhas não coincidem.');
      return;
    }
    setState(() { _loading = true; _erro = null; });
    try {
      await callFirebaseFunctionSafe(
        'recuperacaoSenhaDefinirNovaSenha',
        parameters: {'sessionId': _sessionId, 'newPassword': senha},
      );
      if (mounted) setState(() { _step = _RecStep.concluido; _loading = false; });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RecSenha] FirebaseFunctionsException definirNovaSenha: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message ?? 'Erro ao alterar a senha.';
        });
      }
    } on CallableHttpException catch (e) {
      debugPrint('[RecSenha] CallableHttpException definirNovaSenha: ${e.code} / ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message;
        });
      }
    } catch (e) {
      debugPrint('[RecSenha] Erro genérico _definirNovaSenha: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = _extrairMensagemErro(e, 'Erro ao alterar a senha. Tente novamente.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              if (_step == _RecStep.email) _buildStepEmail(),
              if (_step == _RecStep.otp) _buildStepOtp(),
              if (_step == _RecStep.novaSenha) _buildStepNovaSenha(),
              if (_step == _RecStep.concluido) _buildStepConcluido(),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _erro!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    IconData icon;
    String titulo;
    String subtitulo;
    switch (_step) {
      case _RecStep.email:
        icon = Icons.lock_reset_rounded;
        titulo = 'Recuperar senha';
        subtitulo = 'Informe o e-mail da sua conta para receber o código.';
        break;
      case _RecStep.otp:
        icon = Icons.pin_rounded;
        titulo = 'Código de verificação';
        subtitulo = 'Digite o código de 4 dígitos enviado para o seu e-mail.';
        break;
      case _RecStep.novaSenha:
        icon = Icons.vpn_key_rounded;
        titulo = 'Nova senha';
        subtitulo = 'Defina sua nova senha de acesso.';
        break;
      case _RecStep.concluido:
        icon = Icons.check_circle_rounded;
        titulo = 'Senha alterada!';
        subtitulo = 'Sua senha foi redefinida com sucesso. Faça login com a nova senha.';
        break;
    }
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _step == _RecStep.concluido
                ? const Color(0xFFECFDF5)
                : const Color(0xFFF3E8FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: _step == _RecStep.concluido
                ? const Color(0xFF059669)
                : PainelAdminTheme.roxo,
            size: 26,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E1B4B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitulo,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            color: const Color(0xFF6B7280),
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildStepEmail() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'E-mail',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          enabled: !_loading,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Cancelar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _solicitarOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Enviar código', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepOtp() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF0284C7), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verifique também a pasta de spam.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF0369A1)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'Código de 4 dígitos',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 8),
          enabled: !_loading,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _step = _RecStep.email;
                          _erro = null;
                          _otpCtrl.clear();
                        }),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Voltar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _verificarOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Verificar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepNovaSenha() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _senhaCtrl,
          obscureText: !_senhaVisivel,
          decoration: InputDecoration(
            labelText: 'Nova senha',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_senhaVisivel ? Icons.visibility_off : Icons.visibility, size: 20),
              onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          enabled: !_loading,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _senhaConfCtrl,
          obscureText: !_senhaVisivel,
          decoration: InputDecoration(
            labelText: 'Confirmar senha',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          enabled: !_loading,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Mínimo 8 caracteres, com letras e números.',
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF9CA3AF)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Cancelar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _definirNovaSenha,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Alterar senha', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepConcluido() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Voltar ao login', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
