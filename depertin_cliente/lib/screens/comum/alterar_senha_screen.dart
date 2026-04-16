// Arquivo: lib/screens/comum/alterar_senha_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Alteração de senha sem código por e-mail: senha atual + nova senha + confirmação.
/// O Firebase exige reautenticação antes de [User.updatePassword].
class AlterarSenhaScreen extends StatefulWidget {
  const AlterarSenhaScreen({super.key});

  @override
  State<AlterarSenhaScreen> createState() => _AlterarSenhaScreenState();
}

class _AlterarSenhaScreenState extends State<AlterarSenhaScreen> {
  final _atualCtrl = TextEditingController();
  final _novaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();

  bool _obscureAtual = true;
  bool _obscureNova = true;
  bool _obscureConfirma = true;
  bool _salvando = false;

  @override
  void dispose() {
    _atualCtrl.dispose();
    _novaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
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

  bool _senhaNovaValida(String s) {
    if (s.length < 6) return false;
    return true;
  }

  String _mensagemErro(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'Senha atual incorreta.';
      case 'weak-password':
        return 'A nova senha é muito fraca. Use pelo menos 6 caracteres.';
      case 'requires-recent-login':
        return 'Não foi possível validar sua sessão. Saia, entre novamente e tente de novo.';
      default:
        return e.message ?? 'Não foi possível alterar a senha.';
    }
  }

  Future<void> _mostrarSucessoEVoltar() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Senha alterada',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Sua senha foi atualizada com sucesso.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: _diPertinLaranja,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _salvar() async {
    final atual = _atualCtrl.text;
    final nova = _novaCtrl.text.trim();
    final conf = _confirmaCtrl.text.trim();

    if (atual.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite sua senha atual.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_senhaNovaValida(nova)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nova senha deve ter pelo menos 6 caracteres.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (nova != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A confirmação não coincide com a nova senha.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (nova == atual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nova senha deve ser diferente da senha atual.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão inválida ou e-mail não disponível.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: atual,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(nova);
      if (!mounted) return;
      await _mostrarSucessoEVoltar();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemErro(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final bool temSenha = user != null &&
        user.providerData.any((p) => p.providerId == 'password');

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Alterar senha',
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
      ),
      body: !temSenha
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 56, color: _diPertinRoxo.withValues(alpha: 0.6)),
                    const SizedBox(height: 16),
                    Text(
                      'Esta conta usa login social (ex.: Google) e não possui senha definida por aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.45,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Informe sua senha atual e a nova senha. Não enviamos código por e-mail.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _atualCtrl,
                    obscureText: _obscureAtual,
                    textInputAction: TextInputAction.next,
                    enabled: !_salvando,
                    decoration: _decorCampo(
                      'Senha atual',
                      Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip:
                            _obscureAtual ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: _salvando
                            ? null
                            : () => setState(
                                  () => _obscureAtual = !_obscureAtual,
                                ),
                        icon: Icon(
                          _obscureAtual
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _diPertinRoxo.withValues(alpha: 0.75),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _novaCtrl,
                    obscureText: _obscureNova,
                    textInputAction: TextInputAction.next,
                    enabled: !_salvando,
                    decoration: _decorCampo(
                      'Nova senha',
                      Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: _obscureNova ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: _salvando
                            ? null
                            : () =>
                                setState(() => _obscureNova = !_obscureNova),
                        icon: Icon(
                          _obscureNova
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _diPertinRoxo.withValues(alpha: 0.75),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmaCtrl,
                    obscureText: _obscureConfirma,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _salvando ? null : _salvar(),
                    enabled: !_salvando,
                    decoration: _decorCampo(
                      'Confirmar nova senha',
                      Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip:
                            _obscureConfirma ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: _salvando
                            ? null
                            : () => setState(
                                  () => _obscureConfirma = !_obscureConfirma,
                                ),
                        icon: Icon(
                          _obscureConfirma
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _diPertinRoxo.withValues(alpha: 0.75),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A nova senha deve ter no mínimo 6 caracteres.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
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
                    child: _salvando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Salvar nova senha',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
