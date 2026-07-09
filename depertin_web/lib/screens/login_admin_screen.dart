import 'dart:async';
import 'dart:math' as math;

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
import '../services/login_auditoria_painel.dart';
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
  return code == 'NOT_LOJISTA' || code == 'NO_EMAIL' || code == 'NO_PROFILE';
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

class _LoginAdminScreenState extends State<LoginAdminScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _emailFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isLoadingGoogle = false;
  bool _ocultarSenha = true;
  bool _entradaAnimada = false;
  bool _ctaHover = false;
  bool _googleHover = false;
  bool _forgotHover = false;
  int _miniCardHover = -1;

  late final AnimationController _glowController;
  late final Animation<double> _glowPulse;

  String? _erroBanner;
  String? _erroEmail;
  String? _erroSenha;

  static const Color _ink = Color(0xFF1E1B4B);
  static const Color _erroCor = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.35, end: 0.72).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    if (kDebugMode) {
      _emailController.text = 'master@teste.com';
      _senhaController.text = 'master';
    }
    _emailController.addListener(_limparErrosAoDigitar);
    _senhaController.addListener(_limparErrosAoDigitar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _completarLoginGoogleAposRedirect();
      if (mounted) {
        setState(() => _entradaAnimada = true);
        _emailFocusNode.requestFocus();
      }
    });
  }

  void _limparErrosAoDigitar() {
    if (_erroEmail == null && _erroSenha == null && _erroBanner == null) return;
    setState(() {
      _erroEmail = null;
      _erroSenha = null;
      _erroBanner = null;
    });
  }

  bool _emailValido(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  void _definirErrosFormulario({
    String? banner,
    String? email,
    String? senha,
    bool snackbarTambem = false,
  }) {
    if (!mounted) return;
    setState(() {
      _erroBanner = banner;
      _erroEmail = email;
      _erroSenha = senha;
    });
    if (snackbarTambem && banner != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(banner, style: GoogleFonts.plusJakartaSans()),
          backgroundColor: _erroCor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
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
    _glowController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    Widget? prefix,
    Widget? suffix,
    String? errorText,
    String? hintText,
    bool dark = false,
  }) {
    if (!dark) {
      return InputDecoration(
        labelText: label.isNotEmpty ? label : null,
        hintText: hintText,
        errorText: errorText,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
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

    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      hintStyle: GoogleFonts.plusJakartaSans(
        color: _LoginPalette.textSecondary.withValues(alpha: 0.42),
        fontSize: 15,
      ),
      errorStyle: GoogleFonts.plusJakartaSans(
        color: const Color(0xFFF87171),
        fontSize: 12,
      ),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: _LoginPalette.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _LoginPalette.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _LoginPalette.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _LoginPalette.purpleGlow,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }

  Future<void> _fazerLogin() async {
    String email = _emailController.text.trim();
    String senha = _senhaController.text.trim();

    String? errEmail;
    String? errSenha;
    if (email.isEmpty) {
      errEmail = 'Informe seu e-mail.';
    } else if (!_emailValido(email)) {
      errEmail = 'Digite um e-mail válido.';
    }
    if (senha.isEmpty) errSenha = 'Informe sua senha.';

    if (errEmail != null || errSenha != null) {
      _definirErrosFormulario(email: errEmail, senha: errSenha);
      return;
    }

    setState(() {
      _isLoading = true;
      _erroBanner = null;
      _erroEmail = null;
      _erroSenha = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Busca o documento do usuário (sem forçar servidor — deixa o SDK decidir)
      DocumentSnapshot<Map<String, dynamic>> docSnap;
      try {
        docSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw TimeoutException(
                'O Firestore não está respondendo.\n\n'
                'Isso geralmente acontece quando o navegador não consegue se conectar '
                'aos servidores do Firestore.\n\n'
                '🔍 Para diagnosticar:\n'
                '1. Abra o DevTools (F12) → aba "Network"\n'
                '2. Recarregue a página e tente logar novamente\n'
                '3. Veja se aparecem requisições para "firestore.googleapis.com"\n\n'
                'Se não aparecer nenhuma requisição, pode ser:\n'
                '• Firewall/antivírus bloqueando o domínio firestore.googleapis.com\n'
                '• Extensão de navegador bloqueando Firebase\n'
                '• Rede corporativa com restrições\n\n'
                'Se aparecerem erros HTTP (403, 404, etc.), tire um print e me mostre.',
              ),
            );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[LoginAdmin] Firestore error type: ${e.runtimeType}');
          debugPrint('[LoginAdmin] Firestore error message: $e');
        }
        rethrow;
      }

      if (!docSnap.exists) {
        _mostrarErro(
          'Sem documento em users/$uid no Firestore. Crie o perfil com o mesmo UID do Authentication.',
        );
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }

      await _aplicarRegrasPosLoginFirestore(
        uid,
        safeWebDocData(docSnap),
        metodoLogin: 'email',
      );
    } on FirebaseAuthException catch (e) {
      String mensagem = 'Erro ao conectar (${e.code}). Tente novamente.';
      String? errSenha;
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'wrong-password') {
        mensagem = 'E-mail ou senha incorretos. Verifique e tente novamente.';
        errSenha = 'Credenciais inválidas.';
      } else if (e.code == 'network-request-failed') {
        mensagem = 'Sem conexão com a internet. Verifique sua rede.';
      } else if (e.code == 'too-many-requests') {
        mensagem =
            'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
      } else if (e.code == 'user-disabled') {
        mensagem = 'Conta desativada. Entre em contato com o suporte.';
      }
      _definirErrosFormulario(
        banner: mensagem,
        senha: errSenha,
        snackbarTambem: e.code == 'network-request-failed',
      );
      setState(() => _isLoading = false);
    } catch (e, st) {
      debugPrint('[LoginAdmin] Erro não tratado: $e\n$st');
      _mostrarErro('Erro interno: ${_mensagemErroThrowableSegura(e)}');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Regras de perfil e navegação (e-mail/senha ou após validação Google no servidor).
  Future<void> _aplicarRegrasPosLoginFirestore(
    String uid,
    Map<String, dynamic> dadosUsuario, {
    String metodoLogin = 'email',
  }) async {
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

    unawaited(registrarLoginPainelAuditoria(metodoLogin));

    if (primeiroAcesso) {
      setState(() {
        _isLoading = false;
        _isLoadingGoogle = false;
      });
      _mostrarModalTrocaSenha(
        uid,
        dadosUsuario['nome'] ?? 'Parceiro',
        rotaPosLogin: '/painel',
      );
      return;
    }

    if (tipoUsuario == 'lojista') {
      await ContaBloqueioLojistaHelper.sincronizarLiberacaoSeExpirado(uid);
      // Usa cache (já carregamos do servidor na consulta anterior)
      final docAtual = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Firestore não respondeu ao verificar bloqueio.',
            ),
          );
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
      Navigator.pushReplacementNamed(context, '/painel');
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

    final docSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final dadosFirestore = safeWebDocData(docSnap);

    if (!docSnap.exists || dadosFirestore.isEmpty) {
      await _sairSessaoGooglePainel(apagarUsuarioAuth: true);
      _mostrarErro('Sem documento em users/$uid no Firestore.');
      if (mounted) setState(() => _isLoadingGoogle = false);
      return;
    }

    await _aplicarRegrasPosLoginFirestore(
      uid,
      dadosFirestore,
      metodoLogin: 'google',
    );
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
        _mostrarErro('Não foi possível entrar com Google.\n$hint');
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
      _definirErrosFormulario(
        email: 'Informe o e-mail para recuperar a senha.',
      );
      _emailFocusNode.requestFocus();
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
    _definirErrosFormulario(banner: mensagem);
  }

  Widget _areaBranding({required double maxWidth, bool compact = false}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cabecalhoMarca(compact: compact),
          SizedBox(height: compact ? 32 : 48),
          _tituloInstitucional(compact: compact),
          SizedBox(height: compact ? 18 : 24),
          _descricaoInstitucional(compact: compact),
          SizedBox(height: compact ? 28 : 40),
          _miniCardsBeneficios(),
        ],
      ),
    );
  }

  Widget _cabecalhoMarca({bool compact = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _logoMarcaLogin(altura: compact ? 60 : 92),
        SizedBox(width: compact ? 12 : 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DiPertin',
              style: GoogleFonts.plusJakartaSans(
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w800,
                color: _LoginPalette.textPrimary,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PAINEL ADMINISTRATIVO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
                color: _LoginPalette.orangeBright,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _logoLoginAsset = 'assets/logo-tela-login.png';

  Widget _logoMarcaLogin({required double altura}) {
    return SizedBox(
      width: altura,
      height: altura,
      child: Image.asset(
        _logoLoginAsset,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (c, e, s) {
          if (kDebugMode) {
            debugPrint('[login] falha ao carregar $_logoLoginAsset: $e');
          }
          return Icon(
            Icons.apartment_rounded,
            size: altura * 0.55,
            color: _LoginPalette.purpleGlow,
          );
        },
      ),
    );
  }

  Widget _tituloInstitucional({bool compact = false}) {
    final serif = GoogleFonts.playfairDisplay(
      fontSize: compact ? 38 : 52,
      fontWeight: FontWeight.w500,
      height: 1.15,
      letterSpacing: -0.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Gestão inteligente,',
          style: serif.copyWith(color: _LoginPalette.textPrimary),
        ),
        Text(
          'entregas que conectam.',
          style: serif.copyWith(color: _LoginPalette.orangeBright),
        ),
      ],
    );
  }

  Widget _descricaoInstitucional({bool compact = false}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Text(
        'Um painel completo para administradores e lojistas\ncom segurança e clareza.',
        style: GoogleFonts.plusJakartaSans(
          fontSize: compact ? 14 : 16,
          height: 1.8,
          color: _LoginPalette.textSecondary,
        ),
      ),
    );
  }

  Widget _miniCardsBeneficios() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        const cardH = 116.0;

        Widget card(int index, IconData icon, String titulo, String texto) {
          return _miniBeneficioCard(
            index: index,
            icon: icon,
            titulo: titulo,
            texto: texto,
          );
        }

        if (constraints.maxWidth >= 360) {
          return SizedBox(
            height: cardH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: card(
                    0,
                    Icons.shield_outlined,
                    'Seguro',
                    'Seus dados protegidos',
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: card(
                    1,
                    Icons.bar_chart_rounded,
                    'Intuitivo',
                    'Experiência simplificada',
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: card(
                    2,
                    Icons.bolt_rounded,
                    'Eficiente',
                    'Gestão rápida e completa',
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: cardH,
              child: card(
                0,
                Icons.shield_outlined,
                'Seguro',
                'Seus dados protegidos',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: cardH,
              child: card(
                1,
                Icons.bar_chart_rounded,
                'Intuitivo',
                'Experiência simplificada',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: cardH,
              child: card(
                2,
                Icons.bolt_rounded,
                'Eficiente',
                'Gestão rápida e completa',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _miniBeneficioCard({
    required int index,
    required IconData icon,
    required String titulo,
    required String texto,
  }) {
    final hover = _miniCardHover == index;
    return MouseRegion(
      onEnter: (_) => setState(() => _miniCardHover = index),
      onExit: (_) => setState(() => _miniCardHover = -1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        height: double.infinity,
        transform: Matrix4.translationValues(0, hover ? -2 : 0, 0),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _LoginPalette.miniCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hover
                ? _LoginPalette.purpleGlow.withValues(alpha: 0.55)
                : _LoginPalette.borderPurple,
          ),
          boxShadow: hover
              ? [
                  BoxShadow(
                    color: _LoginPalette.purpleGlow.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _LoginPalette.bgDeep,
                border: Border.all(
                  color: _LoginPalette.purpleGlow.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _LoginPalette.purpleGlow.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(icon, size: 15, color: _LoginPalette.purplePrimary),
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: _LoginPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                height: 1.35,
                color: _LoginPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoMobileCompacto() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _logoMarcaLogin(altura: 40),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DiPertin',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _LoginPalette.textPrimary,
              ),
            ),
            Text(
              'PAINEL ADMINISTRATIVO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
                color: _LoginPalette.orangeBright,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconeCadeadoFlutuante() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_LoginPalette.purpleDark, Color(0xFF1A0A38)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _LoginPalette.purpleGlow.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _LoginPalette.purpleGlow.withValues(alpha: 0.5),
            blurRadius: 32,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(
        Icons.lock_outline_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }

  Widget _seloAcessoRestrito() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _LoginPalette.purplePrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _LoginPalette.purpleGlow.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: _LoginPalette.purpleGlow.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 7),
            Text(
              'ACESSO RESTRITO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: _LoginPalette.purpleGlow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _bannerErroLogin() {
    final msg = _erroBanner;
    if (msg == null || msg.isEmpty) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: Color(0xFFF87171),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFECACA),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelCampo(String texto) {
    return Text(
      texto,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _LoginPalette.textPrimary.withValues(alpha: 0.92),
      ),
    );
  }

  Widget _cartaoLogin({
    required bool wide,
    required bool tablet,
    required bool mobile,
  }) {
    final cardWidth = wide ? 590.0 : (tablet ? 520.0 : double.infinity);
    final horizontalPad = wide ? 48.0 : (mobile ? 24.0 : 32.0);
    final cardRadius = mobile ? 24.0 : 30.0;
    final titleSize = wide ? 42.0 : (tablet ? 36.0 : 32.0);

    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 22),
        _seloAcessoRestrito(),
        const SizedBox(height: 22),
        Text(
          'Acesso ao painel',
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: titleSize,
            fontWeight: FontWeight.w500,
            color: _LoginPalette.textPrimary,
            height: 1.15,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Entre com e-mail e senha ou continue com Google.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            height: 1.5,
            color: _LoginPalette.textSecondary,
          ),
        ),
        if (_bannerErroLogin() != null) ...[
          const SizedBox(height: 18),
          _bannerErroLogin()!,
        ],
        const SizedBox(height: 22),
        _labelCampo('E-mail'),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          child: TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _LoginPalette.textInput,
            ),
            cursorColor: _LoginPalette.purpleGlow,
            decoration: _fieldDecoration(
              label: '',
              dark: true,
              hintText: 'seu@email.com',
              errorText: _erroEmail,
              prefix: Icon(
                Icons.mail_outline_rounded,
                color: _LoginPalette.purpleGlow.withValues(alpha: 0.85),
                size: 22,
              ),
            ),
            onSubmitted: (_) {
              if (!_isLoading && !_isLoadingGoogle) _fazerLogin();
            },
          ),
        ),
        const SizedBox(height: 20),
        _labelCampo('Senha'),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          child: TextField(
            controller: _senhaController,
            obscureText: _ocultarSenha,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _LoginPalette.textInput,
            ),
            cursorColor: _LoginPalette.purpleGlow,
            decoration: _fieldDecoration(
              label: '',
              dark: true,
              errorText: _erroSenha,
              prefix: Icon(
                Icons.lock_outline_rounded,
                color: _LoginPalette.purpleGlow.withValues(alpha: 0.85),
                size: 22,
              ),
              suffix: IconButton(
                tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _ocultarSenha
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _LoginPalette.textSecondary,
                  size: 22,
                ),
                onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
              ),
            ),
            onSubmitted: (_) {
              if (!_isLoading && !_isLoadingGoogle) _fazerLogin();
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            onEnter: (_) => setState(() => _forgotHover = true),
            onExit: (_) => setState(() => _forgotHover = false),
            child: TextButton(
              onPressed: (_isLoading || _isLoadingGoogle)
                  ? null
                  : _enviarRecuperacaoSenha,
              style: TextButton.styleFrom(
                foregroundColor: _forgotHover
                    ? _LoginPalette.orangeBright
                    : _LoginPalette.purpleGlow,
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
        ),
        const SizedBox(height: 16),
        MouseRegion(
          onEnter: (_) => setState(() => _ctaHover = true),
          onExit: (_) => setState(() => _ctaHover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 62,
            transform: Matrix4.translationValues(
              0,
              _ctaHover && !_isLoading && !_isLoadingGoogle ? -2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: _LoginPalette.horizontalAccent,
              boxShadow: _ctaHover && !_isLoading && !_isLoadingGoogle
                  ? [
                      BoxShadow(
                        color: _LoginPalette.purpleGlow.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: _LoginPalette.orangePrimary.withValues(
                          alpha: 0.28,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: _LoginPalette.purplePrimary.withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: _LoginPalette.orangePrimary.withValues(
                          alpha: 0.15,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_isLoading || _isLoadingGoogle) ? null : _fazerLogin,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Entrar no painel',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Colors.white.withValues(alpha: 0.12),
                thickness: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'ou',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _LoginPalette.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: Colors.white.withValues(alpha: 0.12),
                thickness: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        MouseRegion(
          onEnter: (_) => setState(() => _googleHover = true),
          onExit: (_) => setState(() => _googleHover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: _LoginPalette.borderGradient,
            ),
            padding: const EdgeInsets.all(1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                color: _googleHover
                    ? const Color(0xFF151025).withValues(alpha: 0.95)
                    : _LoginPalette.cardBg.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(11),
                boxShadow: _googleHover
                    ? [
                        BoxShadow(
                          color: _LoginPalette.purpleGlow.withValues(
                            alpha: 0.12,
                          ),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_isLoading || _isLoadingGoogle)
                      ? null
                      : _loginComGoogle,
                  borderRadius: BorderRadius.circular(11),
                  child: _isLoadingGoogle
                      ? Center(
                          child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: _LoginPalette.purpleGlow,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _IconeGooglePainel(size: 20),
                            const SizedBox(width: 12),
                            Text(
                              'Continuar com Google',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _LoginPalette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: _LoginPalette.textFooter.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'O acesso é liberado quando o e-mail do Google for o mesmo do '
                    'lojista aprovado no DiPertin.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      height: 1.45,
                      color: _LoginPalette.textFooter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );

    final innerCard = Container(
      width: cardWidth,
      constraints: BoxConstraints(maxWidth: cardWidth),
      padding: EdgeInsets.fromLTRB(
        horizontalPad,
        36,
        horizontalPad,
        horizontalPad,
      ),
      decoration: BoxDecoration(
        color: _LoginPalette.cardBg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(cardRadius - 1),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: cardBody,
      ),
    );

    final card = Container(
      width: cardWidth,
      constraints: BoxConstraints(maxWidth: cardWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        gradient: _LoginPalette.borderGradient,
        boxShadow: [
          BoxShadow(
            color: _LoginPalette.purplePrimary.withValues(alpha: 0.2),
            blurRadius: 70,
            spreadRadius: -10,
            offset: const Offset(0, 28),
          ),
          BoxShadow(
            color: _LoginPalette.orangePrimary.withValues(alpha: 0.08),
            blurRadius: 48,
            offset: const Offset(12, 24),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 48,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: innerCard,
    );

    final cardComIcone = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        card,
        Positioned(top: -28, child: _iconeCadeadoFlutuante()),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : double.infinity;

        return Padding(
          padding: const EdgeInsets.only(top: 30),
          child: AnimatedOpacity(
            opacity: _entradaAnimada ? 1 : 0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            child: AnimatedSlide(
              offset: _entradaAnimada ? Offset.zero : const Offset(0, 0.025),
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxCardHeight),
                child: cardComIcone,
              ),
            ),
          ),
        );
      },
    );
  }

  static const double _layoutMaxWidth = 1440;

  double _paddingHorizontalLogin(double screenWidth) {
    if (screenWidth < 600) return 18;
    if (screenWidth < 860) return 32;
    if (screenWidth < 1100) return 48;
    if (screenWidth < 1360) return 64;
    return 84;
  }

  double _gapColunasLogin(double screenWidth) {
    if (screenWidth < 1100) return 56;
    if (screenWidth < 1360) return 72;
    return 88;
  }

  Widget _conteudoLoginLayout({
    required double screenWidth,
    required double screenHeight,
    required bool wide,
    required bool tablet,
    required bool mobile,
  }) {
    final hPad = _paddingHorizontalLogin(screenWidth);
    final gap = _gapColunasLogin(screenWidth);
    final areaUtil = math.min(screenWidth, _layoutMaxWidth) - hPad * 2;

    Widget corpo;
    if (mobile) {
      corpo = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logoMobileCompacto(),
          const SizedBox(height: 24),
          _cartaoLogin(wide: false, tablet: false, mobile: true),
        ],
      );
    } else {
      var cardW = wide
          ? math.min(590.0, areaUtil * 0.46)
          : math.min(520.0, areaUtil * 0.52);
      var brandW = math.min(600.0, areaUtil - gap - cardW);
      if (brandW + gap + cardW > areaUtil) {
        cardW = math.max(wide ? 460.0 : 420.0, areaUtil - gap - 320);
        brandW = math.max(320.0, areaUtil - gap - cardW);
      }
      final compactBrand = brandW < 520 || tablet;

      corpo = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: brandW,
            child: _areaBranding(maxWidth: brandW, compact: compactBrand),
          ),
          SizedBox(width: gap),
          SizedBox(
            width: cardW,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: _cartaoLogin(wide: wide, tablet: tablet, mobile: false),
            ),
          ),
        ],
      );
    }

    final conteudo = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _layoutMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
          child: corpo,
        ),
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: mobile ? 28 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screenHeight - 48),
        child: Center(child: conteudo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LoginPalette.bg,
      body: AnimatedBuilder(
        animation: _glowPulse,
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _LoginDarkBackgroundPainter(
                  glowIntensity: _glowPulse.value,
                ),
              ),
              child!,
            ],
          );
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final mobile = w < 860;
              final tablet = w >= 860 && w < 1100;
              final wide = w >= 1100;

              return _conteudoLoginLayout(
                screenWidth: w,
                screenHeight: h,
                wide: wide,
                tablet: tablet,
                mobile: mobile,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── PALETA E PAINTERS — LOGIN DARK PREMIUM ───

abstract final class _LoginPalette {
  static const bg = Color(0xFF070711);
  static const bgDeep = Color(0xFF0B0A1D);
  static const cardBg = Color(0xFF0D0B1C);
  static const purplePrimary = Color(0xFFA42CFF);
  static const purpleDark = Color(0xFF37106E);
  static const purpleMid = Color(0xFFD22CFF);
  static const purpleGlow = Color(0xFFC04BFF);
  static const orangePrimary = Color(0xFFFF7A1A);
  static const orangeBright = Color(0xFFFF9A3D);
  static const pinkTransition = Color(0xFFFF5C78);
  static const textPrimary = Color(0xFFF8F7FF);
  static const textInput = Color(0xFFD7D3E3);
  static const textSecondary = Color(0xFFB5B1C4);
  static const textFooter = Color(0xFFA9A5B7);
  static const inputBg = Color(0xFF100D20);
  static const inputBorder = Color(0x52A42CFF); // rgba(164,44,255,0.32)
  static const miniCardBg = Color(0x8C0B0A1D);
  static const borderPurple = Color(0x47B162FF);

  static const accentGradient = [
    purplePrimary,
    purpleMid,
    pinkTransition,
    orangePrimary,
  ];

  static LinearGradient get horizontalAccent =>
      const LinearGradient(colors: accentGradient);

  static LinearGradient get borderGradient => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      purpleGlow.withValues(alpha: 0.55),
      pinkTransition.withValues(alpha: 0.45),
      orangePrimary.withValues(alpha: 0.5),
    ],
  );
}

class _LoginDarkBackgroundPainter extends CustomPainter {
  _LoginDarkBackgroundPainter({required this.glowIntensity});

  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_LoginPalette.bg, _LoginPalette.bgDeep],
        ).createShader(rect),
    );

    // Glow roxo — logo (esquerda)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.55, -0.15),
          radius: 0.7,
          colors: [
            _LoginPalette.purplePrimary.withValues(alpha: 0.22 * glowIntensity),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    // Glow roxo + laranja — card (direita)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.88, 0.08),
          radius: 0.72,
          colors: [
            _LoginPalette.purpleGlow.withValues(alpha: 0.16 * glowIntensity),
            _LoginPalette.orangePrimary.withValues(alpha: 0.06 * glowIntensity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // Glow laranja sutil — inferior direita
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.95, 0.92),
          radius: 0.55,
          colors: [
            _LoginPalette.orangePrimary.withValues(alpha: 0.1 * glowIntensity),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    // Arco com gradiente roxo → rosa → laranja
    final arcRect = Rect.fromLTWH(-w * 0.12, -h * 0.1, w * 1.12, h * 1.08);
    final arcShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomCenter,
      colors: [
        _LoginPalette.purpleGlow,
        _LoginPalette.pinkTransition,
        _LoginPalette.orangeBright,
      ],
    ).createShader(arcRect);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = arcShader;
    canvas.drawArc(arcRect, -2.68, 2.15, false, arcPaint);

    final arcGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..color = _LoginPalette.purpleGlow.withValues(alpha: 0.1 * glowIntensity);
    canvas.drawArc(arcRect, -2.68, 2.15, false, arcGlow);

    _desenharMalhaDigital(canvas, w, h, glowIntensity);

    final dotPaint = Paint()..style = PaintingStyle.fill;
    const particles = [
      (Offset(0.08, 0.12), 0.08),
      (Offset(0.22, 0.08), 0.06),
      (Offset(0.55, 0.06), 0.07),
      (Offset(0.78, 0.18), 0.09),
      (Offset(0.92, 0.35), 0.05),
      (Offset(0.65, 0.72), 0.06),
      (Offset(0.35, 0.88), 0.05),
    ];
    for (final (p, a) in particles) {
      dotPaint.color = Colors.white.withValues(alpha: a * glowIntensity);
      canvas.drawCircle(Offset(w * p.dx, h * p.dy), 1.4, dotPaint);
    }
  }

  void _desenharMalhaDigital(Canvas canvas, double w, double h, double glow) {
    final baseY = h * 1.02;
    const cols = 14;
    const rows = 6;
    final points = <Offset>[];

    Color corMalha(double t) {
      if (t <= 0.45) {
        return Color.lerp(
          _LoginPalette.purplePrimary,
          _LoginPalette.pinkTransition,
          t / 0.45,
        )!;
      }
      return Color.lerp(
        _LoginPalette.pinkTransition,
        _LoginPalette.orangePrimary,
        (t - 0.45) / 0.55,
      )!;
    }

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final t = col / (cols - 1);
        final depth = row / (rows - 1);
        final x = w * (0.0 + t * 0.48);
        final y = baseY - (1 - depth) * h * 0.11 - depth * depth * h * 0.04;
        final scale = 0.4 + depth * 0.7;
        final cor = corMalha(t);

        final paintDot = Paint()
          ..color = cor.withValues(alpha: 0.22 * glow)
          ..style = PaintingStyle.fill;
        final paintLine = Paint()
          ..color = cor.withValues(alpha: 0.07 * glow)
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke;

        points.add(Offset(x, y));
        canvas.drawCircle(Offset(x, y), 1.0 * scale, paintDot);
        if (col > 0) {
          canvas.drawLine(points[points.length - 2], Offset(x, y), paintLine);
        }
        if (row > 0) {
          final idxAbove = (row - 1) * cols + col;
          if (idxAbove < points.length - cols) {
            canvas.drawLine(points[idxAbove], Offset(x, y), paintLine);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoginDarkBackgroundPainter oldDelegate) {
    return oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Logo Google colorido (padrão Sign-In) — sem dependência de asset externo.
class _IconeGooglePainel extends StatelessWidget {
  const _IconeGooglePainel({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w * 0.42;
    final c = Offset(w / 2, h / 2);

    void arco(Color cor, double start, double sweep) {
      final paint = Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.18
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        paint,
      );
    }

    arco(const Color(0xFFEA4335), -0.55, 1.35);
    arco(const Color(0xFFFBBC05), 0.80, 1.05);
    arco(const Color(0xFF34A853), 2.45, 1.05);
    arco(const Color(0xFF4285F4), 3.95, 1.05);

    final bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(w * 0.48, h * 0.44, w * 0.44, h * 0.14), bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final data = await callFirebaseFunctionSafe(
        'recuperacaoSenhaSolicitar',
        parameters: {'email': email},
      );
      _tokenId = (data['tokenId'] ?? '').toString();
      if (mounted)
        setState(() {
          _step = _RecStep.otp;
          _loading = false;
        });
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[RecSenha] FirebaseFunctionsException: ${e.code} / ${e.message}',
      );
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
    setState(() {
      _loading = true;
      _erro = null;
    });
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
      if (mounted)
        setState(() {
          _step = _RecStep.novaSenha;
          _loading = false;
        });
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[RecSenha] FirebaseFunctionsException verificarOtp: ${e.code} / ${e.message}',
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message ?? 'Código inválido ou expirado.';
        });
      }
    } on CallableHttpException catch (e) {
      debugPrint(
        '[RecSenha] CallableHttpException verificarOtp: ${e.code} / ${e.message}',
      );
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
          _erro = _extrairMensagemErro(
            e,
            'Erro ao verificar código. Tente novamente.',
          );
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
    if (!RegExp(r'[A-Za-z]').hasMatch(senha) ||
        !RegExp(r'\d').hasMatch(senha)) {
      setState(() => _erro = 'A senha deve conter letras e números.');
      return;
    }
    if (senha != conf) {
      setState(() => _erro = 'As senhas não coincidem.');
      return;
    }
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      await callFirebaseFunctionSafe(
        'recuperacaoSenhaDefinirNovaSenha',
        parameters: {'sessionId': _sessionId, 'newPassword': senha},
      );
      if (mounted)
        setState(() {
          _step = _RecStep.concluido;
          _loading = false;
        });
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[RecSenha] FirebaseFunctionsException definirNovaSenha: ${e.code} / ${e.message}',
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _erro = e.message ?? 'Erro ao alterar a senha.';
        });
      }
    } on CallableHttpException catch (e) {
      debugPrint(
        '[RecSenha] CallableHttpException definirNovaSenha: ${e.code} / ${e.message}',
      );
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
          _erro = _extrairMensagemErro(
            e,
            'Erro ao alterar a senha. Tente novamente.',
          );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
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
        subtitulo =
            'Sua senha foi redefinida com sucesso. Faça login com a nova senha.';
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Cancelar',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _solicitarOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Enviar código',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
              const Icon(
                Icons.info_outline,
                color: Color(0xFF0284C7),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verifique também a pasta de spam.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFF0369A1),
                  ),
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
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
          ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Voltar',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _verificarOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Verificar',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
              icon: Icon(
                _senhaVisivel ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
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
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: const Color(0xFF9CA3AF),
            ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Cancelar',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : _definirNovaSenha,
                style: FilledButton.styleFrom(
                  backgroundColor: PainelAdminTheme.roxo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Alterar senha',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Voltar ao login',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
