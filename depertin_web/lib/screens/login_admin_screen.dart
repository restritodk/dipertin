import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

class LoginAdminScreen extends StatefulWidget {
  const LoginAdminScreen({super.key});

  @override
  State<LoginAdminScreen> createState() => _LoginAdminScreenState();
}

class _LoginAdminScreenState extends State<LoginAdminScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _isLoading = false;
  bool _ocultarSenha = true;

  static const Color _ink = Color(0xFF1E1B4B);

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _emailController.text = 'master@teste.com';
      _senhaController.text = 'master';
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

      var dadosUsuario = docSnap.data()!;

      String tipoUsuario =
          (dadosUsuario['role'] ??
                  dadosUsuario['tipo'] ??
                  dadosUsuario['tipoUsuario'] ??
                  'cliente')
              .toString()
              .toLowerCase();
      bool primeiroAcesso = dadosUsuario['primeiro_acesso'] ?? false;

      if (tipoUsuario != 'master' &&
          tipoUsuario != 'master_city' &&
          tipoUsuario != 'lojista') {
        _mostrarErro(
          'Acesso negado. Seu perfil não tem permissão para o painel web.',
        );
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }

      if (primeiroAcesso) {
        setState(() => _isLoading = false);
        _mostrarModalTrocaSenha(uid, dadosUsuario['nome'] ?? 'Parceiro');
        return;
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/painel');
      }
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

  void _mostrarModalTrocaSenha(String userId, String nomeUsuario) {
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
                  Navigator.pushReplacementNamed(context, '/painel');
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
        'Digite o e-mail no campo acima para receber o link de recuperação.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se existir conta com $email, enviámos um e-mail para redefinir a senha.',
              style: GoogleFonts.plusJakartaSans(),
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        _mostrarErro('E-mail inválido.');
      } else if (e.code == 'user-not-found') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Não encontrámos conta com este e-mail. Verifique o endereço.',
                style: GoogleFonts.plusJakartaSans(),
              ),
              backgroundColor: const Color(0xFFC2410C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        _mostrarErro('Não foi possível enviar o e-mail: ${e.message ?? e.code}');
      }
    } catch (e) {
      _mostrarErro('Erro ao enviar recuperação de senha.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    return Container(
      width: wide ? null : double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 56 : 32,
        vertical: wide ? 48 : 36,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PainelAdminTheme.roxoEscuro,
            PainelAdminTheme.roxo,
            PainelAdminTheme.roxoSidebarFim,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment:
            wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
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
            style: GoogleFonts.plusJakartaSans(
              fontSize: wide ? 36 : 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Painel administrativo',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.88),
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: wide ? 24 : 16),
          Text(
            'Gestão de lojas, entregadores, vitrine e operações — com segurança e clareza.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.55,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartaoLogin() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E4F0)),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withOpacity(0.08),
            blurRadius: 40,
            offset: const Offset(0, 18),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ENTRAR',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Acesso ao painel',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use o e-mail e a senha da sua conta autorizada.',
            style: GoogleFonts.plusJakartaSans(
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
            onSubmitted: (_) => _fazerLogin(),
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
              if (!_isLoading) _fazerLogin();
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _enviarRecuperacaoSenha,
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
            onPressed: _isLoading ? null : _fazerLogin,
            style: FilledButton.styleFrom(
              backgroundColor: PainelAdminTheme.laranja,
              foregroundColor: Colors.white,
              disabledBackgroundColor: PainelAdminTheme.laranja.withOpacity(0.5),
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Apenas perfis master, master_city e lojista.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: PainelAdminTheme.textoSecundario,
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
                      child: _cartaoLogin(),
                    ),
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _painelMarca(wide: false)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Container(
                  color: PainelAdminTheme.fundoCanvas,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(bottom: 32),
                  child: _cartaoLogin(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
