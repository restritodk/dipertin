// Arquivo: lib/screens/auth/login_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/google_auth_helper.dart';
import '../../services/audit_log_app_service.dart';
import '../../services/biometria_service.dart';
import '../../services/conta_bloqueio_entregador_service.dart';
import '../../services/conta_bloqueio_lojista_service.dart';
import '../../services/conta_exclusao_service.dart';
import '../../services/sessao_timeout_service.dart';
import '../../services/pos_login_onboarding_gate.dart';
import '../../widgets/dipertin_scroll_body.dart';
import '../../widgets/dipertin_versao_rodape.dart';
import '../../widgets/lojista_conta_bloqueada_overlay.dart';
import '../../services/location_service.dart';
import 'ativacao_biometria_screen.dart';
import 'recuperar_senha_screen.dart';
import 'register_screen.dart';
import 'aceite_termos_google_screen.dart';
import 'widgets/termos_aceite_cadastro.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _erroCampo = Color(0xFFD32F2F);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.emailPreenchido});

  final String? emailPreenchido;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;
  bool _senhaOculta = true;
  bool _biometriaDisponivelParaLogin = false;
  bool _entradaAnimada = false;
  String? _erroCampoEmail;
  String? _erroCampoSenha;

  /// Evita pedir a ativação da biometria várias vezes se o usuário
  /// declinou recentemente. Cooldown gravado em SharedPreferences.
  static const _kPrefConviteCooldownHorasAteProxima = 72;
  static const _kPrefChaveConviteDeclinadoEm = 'biometria_convite_declinado_em';
  static const _kPrefChaveConviteJaOferecidoParaUid =
      'biometria_convite_ja_oferecido_uids';

  @override
  void initState() {
    super.initState();
    final email = (widget.emailPreenchido ?? '').trim();
    if (email.isNotEmpty) {
      _emailController.text = email;
    }
    _verificarDisponibilidadeBiometriaLogin();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  void _limparErrosCampos() {
    if (_erroCampoEmail != null || _erroCampoSenha != null) {
      setState(() {
        _erroCampoEmail = null;
        _erroCampoSenha = null;
      });
    }
  }

  String? _validarCampoEmail(String? valor) {
    if (_erroCampoEmail != null) return _erroCampoEmail;
    final texto = (valor ?? '').trim();
    if (texto.isEmpty) return 'Informe seu e-mail';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(texto)) {
      return 'Digite um e-mail válido (ex: seuemail@gmail.com)';
    }
    return null;
  }

  String? _validarCampoSenha(String? valor) {
    if (_erroCampoSenha != null) return _erroCampoSenha;
    if ((valor ?? '').trim().isEmpty) return 'Informe sua senha';
    return null;
  }

  void _definirErroSenha(String mensagem) {
    setState(() => _erroCampoSenha = mensagem);
    _formKey.currentState?.validate();
  }

  Future<void> _verificarDisponibilidadeBiometriaLogin() async {
    final pode = await BiometriaService.instancia.podeUsarLoginBiometrico();
    if (!mounted) return;
    setState(() => _biometriaDisponivelParaLogin = pode);
  }

  InputDecoration _decorCampo(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _diPertinRoxo.withValues(alpha: 0.88), size: 22),
      filled: true,
      fillColor: const Color(0xFFF9F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _diPertinRoxo,
        fontWeight: FontWeight.w700,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0DEE8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _diPertinLaranja, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _erroCampo, width: 2),
      ),
      errorStyle: const TextStyle(
        color: _erroCampo,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
  }

  Widget _iconeGoogle() {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }

  Future<void> _mostrarDialogoContaNaoEncontrada() async {
    final email = _emailController.text.trim();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          elevation: 8,
          shadowColor: Colors.black26,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _diPertinRoxo.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_off_rounded,
                    size: 40,
                    color: _diPertinRoxo,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Conta não encontrada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Não encontramos uma conta DiPertin associada a este e-mail. '
                  'Confira se digitou corretamente ou crie uma conta nova.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F4F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8E6ED)),
                    ),
                    child: Text(
                      email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _diPertinRoxo,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Entendi',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _diPertinLaranja,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Criar conta',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Volta à tela anterior quando há rota; após logout só existe [LoginScreen] — vai para `/home`.
  void _fecharAposLoginSucesso() {
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _atualizarTokenAposLogin(String uid) async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcm_token': token,
          'ultimo_acesso': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Erro token: $e");
    }
  }

  /// Bloqueio operacional (lojista / entregador). Retorna false se exibir modal e barrar fluxo.
  Future<bool> _contaOperacionalPodeEntrarAposLogin(String uid) async {
    await ContaBloqueioLojistaService.sincronizarLiberacaoSeExpirado(uid);
    await ContaBloqueioEntregadorService.sincronizarLiberacaoSeExpirado(uid);
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return true;
    final data = doc.data()!;
    final role =
        (data['role'] ?? data['tipoUsuario'] ?? '').toString().toLowerCase();
    if (role == 'lojista' &&
        ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(data)) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: LojistaContaBloqueadaOverlay(
              dadosUsuario: data,
              onSair: () async {
                Navigator.of(ctx).pop();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ),
        ),
      );
      return false;
    }
    // Entregador bloqueado pode entrar no app e usar como cliente; painel de entregas é separado.
    return true;
  }

  /// Verifica se a conta pode acessar o app mobile.
  /// Contas de colaborador lojista (com `lojista_owner_uid`) são permitidas.
  Future<bool> _podeUsarAppMobile(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return true;
    final d = doc.data()!;
    if (d['acesso_app_mobile'] == false) {
      final ownerUid = d['lojista_owner_uid']?.toString().trim() ?? '';
      final role = (d['role'] ?? d['tipoUsuario'] ?? '').toString();
      if (ownerUid.isNotEmpty || role == 'lojista') {
        return true;
      }
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta conta é apenas para o painel web. Utilize o navegador.',
            ),
            backgroundColor: Colors.deepOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    return true;
  }

  /// Fluxo completo acionado pelo botão "Acessar por Digital" na tela de login.
  /// Exige vínculo biométrico ativo no dispositivo.
  Future<void> _entrarPorDigital() async {
    if (_isLoading) return;
    final bio = BiometriaService.instancia;

    final disp = await bio.consultarDisponibilidade(forcarRefresh: true);
    if (!mounted) return;
    if (!disp.disponivelParaUso) {
      _biometriaDisponivelParaLogin = false;
      await bio.desativar();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seu aparelho não tem biometria cadastrada. '
            'Configure a digital no sistema e entre com e-mail e senha.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final vinculo = await bio.lerVinculo();
    if (!mounted) return;
    if (vinculo == null) {
      setState(() => _biometriaDisponivelParaLogin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Biometria não ativada neste aparelho. Faça login normalmente '
            'e depois ative o acesso por digital.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final resultado = await bio.autenticarComBiometria(
      razao: 'Confirme sua digital para entrar no DiPertin.',
    );
    if (!mounted) return;

    switch (resultado) {
      case BiometriaResultado.cancelado:
        return;
      case BiometriaResultado.indisponivel:
        await bio.desativar();
        if (!mounted) return;
        setState(() => _biometriaDisponivelParaLogin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A biometria do aparelho foi removida. '
              'Entre com e-mail e senha e reative a digital.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      case BiometriaResultado.falhou:
      case BiometriaResultado.erro:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não conseguimos validar sua digital. Tente novamente ou '
              'entre com e-mail e senha.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      case BiometriaResultado.sucesso:
        break;
    }

    await _executarLoginAposBiometria(vinculo);
  }

  /// Executa o login real no Firebase usando o vínculo biométrico.
  /// Se a credencial salva estiver inconsistente, limpa o vínculo e redireciona
  /// o usuário para login normal.
  Future<void> _executarLoginAposBiometria(BiometriaVinculo vinculo) async {
    setState(() => _isLoading = true);
    try {
      User? user;
      if (vinculo.metodo == BiometriaMetodoLogin.emailSenha) {
        final senha = (vinculo.senhaSegura ?? '').trim();
        if (senha.isEmpty) {
          await _biometriaInconsistente(
            'Vínculo biométrico inválido. Entre com e-mail e senha para '
            'reativar o acesso por digital.',
          );
          return;
        }
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: vinculo.email,
          password: senha,
        );
        user = cred.user;
      } else {
        final cred = await signInWithGoogleSilentForFirebase(
          emailEsperado: vinculo.email,
        );
        user = cred.user;
      }

      if (user == null) {
        await _biometriaInconsistente(
          'Não foi possível completar o login. Tente com e-mail e senha.',
        );
        return;
      }

      PosLoginOnboardingGate.iniciouFluxoPosSignIn();

      final uid = user.uid;
      if (!await _podeUsarAppMobile(uid)) {
        PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
        return;
      }
      await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(uid);
      await _atualizarTokenAposLogin(uid);
      final podeEntrar = await _contaOperacionalPodeEntrarAposLogin(uid);
      if (!podeEntrar) {
        PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
        return;
      }

      // Marca o início da sessão — o `AppGuard` usa esse timestamp para
      // forçar re-login a cada 24h (política de segurança).
      await SessaoTimeoutService.registrarLoginAgora();

      final modoBiometria =
          vinculo.metodo == BiometriaMetodoLogin.emailSenha
              ? 'biometria_email_senha'
              : 'biometria_google';
      unawaited(
        AuditLogAppService.instancia.registrarLoginSessaoMobile(modoBiometria),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bem-vindo(a) de volta!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fecharAposLoginSucesso();
      }
      PosLoginOnboardingGate.concluiuFluxoLiberarOnboardingAposSairDoLogin();
    } on FirebaseAuthException catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      debugPrint('Login biométrico falhou: ${e.code} ${e.message}');
      // Credencial inválida → vínculo obsoleto, limpa tudo.
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'user-disabled') {
        await _biometriaInconsistente(
          'Suas credenciais foram alteradas. Entre com e-mail e senha '
          'e reative a digital.',
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Firebase: ${e.code} — ${e.message ?? ''}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      debugPrint('Login biométrico erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no login biométrico: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _biometriaInconsistente(String mensagem) async {
    await BiometriaService.instancia.desativar();
    if (!mounted) return;
    setState(() => _biometriaDisponivelParaLogin = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------- Oferta de ativação pós-login --------------------

  Future<bool> _jaOfereceuParaEsseUid(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista =
          prefs.getStringList(_kPrefChaveConviteJaOferecidoParaUid) ?? [];
      return lista.contains(uid);
    } catch (_) {
      return false;
    }
  }

  Future<void> _marcarConviteMostrado(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista =
          prefs.getStringList(_kPrefChaveConviteJaOferecidoParaUid) ?? [];
      if (!lista.contains(uid)) {
        lista.add(uid);
        await prefs.setStringList(
            _kPrefChaveConviteJaOferecidoParaUid, lista);
      }
    } catch (_) {}
  }

  Future<bool> _dentroDoCooldownDeDeclineRecente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kPrefChaveConviteDeclinadoEm);
      if (ms == null) return false;
      final declinouEm = DateTime.fromMillisecondsSinceEpoch(ms);
      final agora = DateTime.now();
      return agora.difference(declinouEm).inHours <
          _kPrefConviteCooldownHorasAteProxima;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registrarDeclineConvite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPrefChaveConviteDeclinadoEm,
          DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Se ainda não ativou biometria para este uid neste aparelho, abre a tela
  /// premium de convite. Só é chamado APÓS login real bem-sucedido.
  Future<void> _oferecerAtivacaoBiometriaSeNecessario({
    required String uid,
    required String email,
    required BiometriaMetodoLogin metodo,
    String? senhaParaVinculo,
  }) async {
    try {
      final bio = BiometriaService.instancia;
      // Já está ativada para este uid? Nada a fazer.
      final atual = await bio.lerVinculo();
      if (atual != null && atual.uid == uid) return;

      // Se havia outro vínculo (outro uid), limpa antes de oferecer novo.
      if (atual != null && atual.uid != uid) {
        await bio.desativar();
      }

      // O aparelho suporta e tem biometria cadastrada?
      final podeOferecer = await bio.podeOferecerAtivacao();
      if (!podeOferecer) return;

      // Cooldown de "Agora não" recente.
      if (await _dentroDoCooldownDeDeclineRecente()) {
        // Ainda assim marca como já oferecido para não insistir.
        await _marcarConviteMostrado(uid);
        return;
      }

      // Já ofereceu para esse uid neste aparelho e ele declinou antes?
      if (await _jaOfereceuParaEsseUid(uid) &&
          await _dentroDoCooldownDeDeclineRecente()) {
        return;
      }

      if (!mounted) return;
      final AtivacaoBiometriaResultado? resultado =
          await Navigator.of(context).push<AtivacaoBiometriaResultado>(
        MaterialPageRoute<AtivacaoBiometriaResultado>(
          fullscreenDialog: true,
          builder: (_) => AtivacaoBiometriaScreen(
            uid: uid,
            email: email,
            metodo: metodo,
            senhaParaVinculo: senhaParaVinculo,
          ),
        ),
      );
      await _marcarConviteMostrado(uid);
      if (!mounted) return;

      if (resultado?.ativou == true) {
        setState(() => _biometriaDisponivelParaLogin = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pronto! Da próxima vez, entre usando "Acessar por Digital".',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (resultado?.declinou == true) {
        await _registrarDeclineConvite();
      }
    } catch (e) {
      debugPrint('oferecer biometria: $e');
    }
  }

  Future<void> _fazerLogin() async {
    _limparErrosCampos();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _senhaController.text.trim(),
          );
      var loginEmailConcluiuAteFechar = false;
      if (userCredential.user != null) {
        // Imediatamente após o signIn — antes de awaits — para o
        // MainNavigator de baixo não mostrar o onboarding do endereço
        // em paralelo com a biometria.
        PosLoginOnboardingGate.iniciouFluxoPosSignIn();
        final uid = userCredential.user!.uid;
        if (!await _podeUsarAppMobile(uid)) {
          PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
          return;
        }
        await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(uid);
        await _atualizarTokenAposLogin(uid);
        final podeEntrar = await _contaOperacionalPodeEntrarAposLogin(uid);
        if (!podeEntrar) {
          PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
          return;
        }

        // Marca o início da sessão — ver SessaoTimeoutService.
        await SessaoTimeoutService.registrarLoginAgora();

        unawaited(
          AuditLogAppService.instancia.registrarLoginSessaoMobile('email_senha'),
        );

        // Primeiro login autorizado → oferece ativação biométrica.
        final emailLimpo = _emailController.text.trim();
        final senhaLimpa = _senhaController.text.trim();
        await _oferecerAtivacaoBiometriaSeNecessario(
          uid: uid,
          email: emailLimpo,
          metodo: BiometriaMetodoLogin.emailSenha,
          senhaParaVinculo: senhaLimpa,
        );
        loginEmailConcluiuAteFechar = true;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login realizado com sucesso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fecharAposLoginSucesso();
      }
      if (loginEmailConcluiuAteFechar) {
        PosLoginOnboardingGate.concluiuFluxoLiberarOnboardingAposSairDoLogin();
      }
    } on FirebaseAuthException catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      if (e.code == 'user-not-found') {
        if (mounted) await _mostrarDialogoContaNaoEncontrada();
      } else if (mounted) {
        if (e.code == 'wrong-password') {
          _definirErroSenha('Senha incorreta.');
        } else if (e.code == 'invalid-credential') {
          _definirErroSenha(
            'E-mail ou senha incorretos. Se não tiver conta, cadastre-se.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro no login: ${e.message ?? e.code}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Busca em `users` um documento com o mesmo email do Google.
  /// Se encontrar (lojista, entregador, etc.), copia os dados para `users/{uid}`.
  Future<bool> _tentarVincularPerfilExistentePorEmail(User user) async {
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isEmpty) return false;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(5)
          .get();
      if (snap.docs.isEmpty) return false;

      DocumentSnapshot? melhor;
      for (final d in snap.docs) {
        if (d.id == user.uid) continue;
        final data = d.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final role = (data['role'] ?? data['tipoUsuario'] ?? '').toString();
        if (role == 'lojista' || role == 'entregador') {
          melhor = d;
          break;
        }
        melhor ??= d;
      }
      if (melhor == null) return false;

      final src = melhor.data() as Map<String, dynamic>;
      const camposVincular = [
        'nome', 'nome_loja', 'loja_nome', 'role', 'tipoUsuario', 'tipo',
        'cidade', 'cidade_normalizada', 'uf', 'uf_normalizado',
        'status_loja', 'ativo', 'loja_aberta', 'telefone', 'cpf', 'cpf_cnpj',
        'primeiro_acesso', 'saldo', 'recusa_cadastro', 'motivo_recusa',
        'block_active', 'block_type', 'block_end_at', 'block_start_at',
        'block_reason', 'motivo_bloqueio', 'status_conta',
        'lojista_owner_uid', 'painel_colaborador_nivel',
        'entregador_status', 'foto_perfil',
        'cpf_alteracao_bloqueada',
      ];

      final merge = <String, dynamic>{'email': email};
      for (final k in camposVincular) {
        if (src.containsKey(k)) merge[k] = src[k];
      }
      merge['app_vinculado_por_email'] = true;
      merge['app_vinculado_doc_origem'] = melhor.id;
      merge['app_vinculado_em'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(merge, SetOptions(merge: true));

      debugPrint('Perfil vinculado por email: ${melhor.id} → ${user.uid}');
      return true;
    } catch (e) {
      debugPrint('Erro ao vincular perfil por email: $e');
      return false;
    }
  }

  Future<void> _entrarComGoogle() async {
    setState(() => _isLoading = true);
    try {
      final UserCredential userCred = await signInWithGoogleForFirebase();
      final User? user = userCred.user;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login Google sem usuário.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Sincronamente após o signIn — evita o onboarding de endereço a competir
      // com termos, biometria, etc. (há [MainNavigator] por baixo do login).
      PosLoginOnboardingGate.iniciouFluxoPosSignIn();

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) {
        final vinculou = await _tentarVincularPerfilExistentePorEmail(user);
        if (!vinculou) {
          if (!mounted) {
            PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
            return;
          }
          final bool? aceitou = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              fullscreenDialog: true,
              builder: (context) => const AceiteTermosGoogleScreen(),
            ),
          );
          if (aceitou != true) {
            PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
            return;
          }
          if (!mounted) {
            PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
            return;
          }
          try {
            final loc = context.read<LocationService>();
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              ...TermosCadastroFirestore.camposAceite(),
              'nome': user.displayName ?? 'Usuário Google',
              'email': user.email ?? '',
              'cpf': '',
              'telefone': '',
              'cidade': loc.cidadeDetectada ?? '',
              'uf': loc.ufDetectado ?? '',
              'cidade_normalizada': loc.cidadeNormalizada,
              'uf_normalizado': loc.ufNormalizado,
              'role': 'cliente',
              'tipoUsuario': 'cliente',
              'ativo': true,
              'status_conta': 'ativa',
              'onboarding_endereco_pendente': true,
              'onboarding_endereco_criado_em': FieldValue.serverTimestamp(),
              'cpf_alteracao_bloqueada': false,
              'dataCadastro': FieldValue.serverTimestamp(),
              'totalConcluido': 0,
            });
          } catch (e) {
            debugPrint('Firestore novo usuário Google: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Conta Google conectada, mas não foi possível salvar o perfil: $e',
                  ),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
      if (!await _podeUsarAppMobile(user.uid)) {
        PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
        return;
      }
      await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(user.uid);
      await _atualizarTokenAposLogin(user.uid);
      final podeEntrar = await _contaOperacionalPodeEntrarAposLogin(user.uid);
      if (!podeEntrar) {
        PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
        return;
      }

      // Marca o início da sessão — ver SessaoTimeoutService.
      await SessaoTimeoutService.registrarLoginAgora();

      unawaited(
        AuditLogAppService.instancia.registrarLoginSessaoMobile('google_oauth'),
      );

      // Primeiro login Google autorizado → oferece ativação biométrica
      // (sem senha, método google — re-login futuro via signInSilently).
      await _oferecerAtivacaoBiometriaSeNecessario(
        uid: user.uid,
        email: user.email ?? '',
        metodo: BiometriaMetodoLogin.google,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bem-vindo(a)!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fecharAposLoginSucesso();
      }
      PosLoginOnboardingGate.concluiuFluxoLiberarOnboardingAposSairDoLogin();
    } on StateError catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      if (mounted && !e.message.contains('cancelado')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Firebase: ${e.code} — ${e.message ?? ""}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      PosLoginOnboardingGate.abortouFluxoLiberarSemOnboarding();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro Google: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Widget _botaoAcessarPorDigital() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_diPertinRoxo, Color(0xFF8E24AA)],
        ),
        boxShadow: [
          BoxShadow(
            color: _diPertinRoxo.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _isLoading ? null : _entrarPorDigital,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Acessar por Digital',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
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

  Widget _divisorOu() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  Widget _cardFormulario() {
    final emailPreenchido = (widget.emailPreenchido ?? '').trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _diPertinRoxo.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              enabled: !_isLoading,
              autofocus: !emailPreenchido,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validarCampoEmail,
              onChanged: (_) {
                if (_erroCampoEmail != null) {
                  setState(() => _erroCampoEmail = null);
                  _formKey.currentState?.validate();
                }
              },
              decoration: _decorCampo('E-mail', Icons.email_outlined),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _senhaController,
              obscureText: _senhaOculta,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              enabled: !_isLoading,
              autofocus: emailPreenchido,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validarCampoSenha,
              onChanged: (_) {
                if (_erroCampoSenha != null) {
                  setState(() => _erroCampoSenha = null);
                  _formKey.currentState?.validate();
                }
              },
              onFieldSubmitted: (_) => _isLoading ? null : _fazerLogin(),
              decoration: _decorCampo('Senha', Icons.lock_outline_rounded)
                  .copyWith(
                suffixIcon: IconButton(
                  tooltip: _senhaOculta ? 'Mostrar senha' : 'Ocultar senha',
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _senhaOculta = !_senhaOculta),
                  icon: Icon(
                    _senhaOculta
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: _diPertinRoxo.withValues(alpha: 0.75),
                    size: 22,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const RecuperarSenhaScreen(),
                          ),
                        );
                      },
                child: const Text(
                  'Esqueci minha senha',
                  style: TextStyle(
                    color: _diPertinRoxo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _isLoading ? null : _fazerLogin,
              style: FilledButton.styleFrom(
                backgroundColor: _diPertinLaranja,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    _diPertinLaranja.withValues(alpha: 0.5),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Entrar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
            if (_biometriaDisponivelParaLogin) ...[
              const SizedBox(height: 14),
              _botaoAcessarPorDigital(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeVoltar = Navigator.canPop(context);
    final subtitulo = _biometriaDisponivelParaLogin
        ? 'Use e-mail, Google ou sua digital'
        : 'Peça das lojas da sua cidade';

    return PopScope(
      canPop: podeVoltar,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || podeVoltar) return;
        Navigator.of(context).pushReplacementNamed('/home');
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _fundoTela,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          backgroundColor: _diPertinRoxo,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: podeVoltar
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Voltar à vitrine',
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/home');
                  },
                ),
        ),
        body: DiPertinScrollBody(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: AnimatedOpacity(
            opacity: _entradaAnimada ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    height: 96,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.storefront_rounded,
                        size: 72,
                        color: _diPertinRoxo.withValues(alpha: 0.9),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Entrar na sua conta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textoPrimario,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textoMuted,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _cardFormulario(),
                const SizedBox(height: 22),
                _divisorOu(),
                const SizedBox(height: 22),
                OutlinedButton(
                  onPressed: _isLoading ? null : _entrarComGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textoPrimario,
                    backgroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _iconeGoogle(),
                      const SizedBox(width: 12),
                      const Text(
                        'Continuar com o Google',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                  child: const Text(
                    'Criar conta gratuita',
                    style: TextStyle(
                      color: _diPertinRoxo,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const DiPertinVersaoRodape(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Marca Google multicolorida (sem asset).
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final stroke = w * 0.36;
    final arco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    arco.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.45, 1.9, false, arco);
    arco.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 5.35, 1.35, false, arco);
    arco.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.85, 1.4, false, arco);
    arco.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -1.2, 2.1, false, arco);

    final barra = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.42, w * 0.44, stroke * 0.82),
      barra,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
