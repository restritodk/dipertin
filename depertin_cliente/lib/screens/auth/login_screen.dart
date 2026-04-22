// Arquivo: lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import '../../auth/google_auth_helper.dart';
import '../../services/conta_bloqueio_entregador_service.dart';
import '../../services/conta_bloqueio_lojista_service.dart';
import '../../services/conta_exclusao_service.dart';
import '../../widgets/entregador_conta_bloqueada_overlay.dart';
import '../../widgets/lojista_conta_bloqueada_overlay.dart';
import '../../services/location_service.dart';
import 'recuperar_senha_screen.dart';
import 'register_screen.dart';
import 'aceite_termos_google_screen.dart';
import 'widgets/termos_aceite_cadastro.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.emailPreenchido});

  final String? emailPreenchido;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;
  bool _senhaOculta = true;

  @override
  void initState() {
    super.initState();
    final email = (widget.emailPreenchido ?? '').trim();
    if (email.isNotEmpty) {
      _emailController.text = email;
    }
  }

  InputDecoration _decorCampo(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _diPertinRoxo.withValues(alpha: 0.88), size: 22),
      filled: true,
      fillColor: Colors.white,
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
    );
  }

  Widget _iconeGoogle() {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
        ),
      ),
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
    if (role == 'entregador' &&
        ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(data)) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: EntregadorContaBloqueadaOverlay(
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

  Future<void> _fazerLogin() async {
    if (!RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    ).hasMatch(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, digite um e-mail válido (ex: seuemail@gmail.com).',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _senhaController.text.trim(),
          );
      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;
        if (!await _podeUsarAppMobile(uid)) return;
        await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(uid);
        await _atualizarTokenAposLogin(uid);
        final podeEntrar = await _contaOperacionalPodeEntrarAposLogin(uid);
        if (!podeEntrar) return;
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
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        if (mounted) await _mostrarDialogoContaNaoEncontrada();
      } else {
        String mensagem = 'Erro no login.';
        if (e.code == 'wrong-password') {
          mensagem = 'Senha incorreta.';
        } else if (e.code == 'invalid-credential') {
          mensagem =
              'E-mail ou senha incorretos. Se não tiver conta, cadastre-se.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(mensagem),
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

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) {
        final vinculou = await _tentarVincularPerfilExistentePorEmail(user);
        if (!vinculou) {
          if (!mounted) return;
          final bool? aceitou = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              fullscreenDialog: true,
              builder: (context) => const AceiteTermosGoogleScreen(),
            ),
          );
          if (aceitou != true) {
            return;
          }
          if (!mounted) return;
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
      if (!await _podeUsarAppMobile(user.uid)) return;
      await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(user.uid);
      await _atualizarTokenAposLogin(user.uid);
      final podeEntrar = await _contaOperacionalPodeEntrarAposLogin(user.uid);
      if (!podeEntrar) return;
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
    } on StateError catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Entrar',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: _diPertinRoxo,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Navigator.canPop(context)
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Voltar à vitrine',
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/home');
                },
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  height: 108,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.storefront_rounded,
                      size: 80,
                      color: _diPertinRoxo.withValues(alpha: 0.9),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Acesse com e-mail ou conta Google',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _decorCampo('E-mail', Icons.email_outlined),
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _senhaController,
                obscureText: _senhaOculta,
                decoration: _decorCampo('Senha', Icons.lock_outline_rounded).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _senhaOculta ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() => _senhaOculta = !_senhaOculta);
                          },
                    icon: Icon(
                      _senhaOculta
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: _diPertinRoxo.withValues(alpha: 0.75),
                      size: 22,
                    ),
                  ),
                ),
                onSubmitted: (_) => _isLoading ? null : _fazerLogin(),
                enabled: !_isLoading,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RecuperarSenhaScreen(),
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
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _isLoading ? null : _fazerLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: _diPertinLaranja,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _diPertinLaranja.withValues(alpha: 0.5),
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
              const SizedBox(height: 22),
              Row(
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
              ),
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: _isLoading ? null : _entrarComGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A2E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _iconeGoogle(),
                    const SizedBox(width: 12),
                    const Text(
                      'Entrar com o Google',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
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
                  'Não tem conta? Cadastre-se',
                  style: TextStyle(
                    color: _diPertinRoxo,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('configuracoes')
                    .doc('status_app')
                    .snapshots(),
                builder: (context, snapshot) {
                  var estavel = true;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final dados = snapshot.data!.data() as Map<String, dynamic>?;
                    estavel = dados?['estavel'] ?? true;
                  }

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            estavel
                                ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: estavel
                                ? Colors.green.shade700
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              estavel
                                  ? 'Aplicativo operando normalmente.'
                                  : 'Aplicativo instável no momento.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: estavel
                                    ? Colors.green.shade700
                                    : Colors.amber.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'DiPertin v1.0.0',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
