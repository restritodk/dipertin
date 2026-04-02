// Arquivo: lib/screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:provider/provider.dart';
import '../../auth/google_auth_helper.dart';
import '../../services/location_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController(); // NOVO CAMPO
  final _cidadeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController(); // NOVO CAMPO

  bool _isLoading = false;

  Future<void> _fazerCadastro() async {
    if (_nomeController.text.isEmpty ||
        _cpfController.text.isEmpty ||
        _telefoneController.text.isEmpty ||
        _cidadeController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _senhaController.text.isEmpty ||
        _confirmarSenhaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha todos os campos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 👇 NOVO: VALIDAÇÃO DE FORMATO DE E-MAIL 👇
    if (!RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    ).hasMatch(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, digite um e-mail válido (ex: seuemail@gmail.com).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // VALIDAÇÃO DE SENHA DUPLA
    if (_senhaController.text != _confirmarSenhaController.text) {
      // ... resto do código continua igual ...
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não coincidem!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _senhaController.text.trim(),
          );

      final loc = context.read<LocationService>();
      final cidadeReg = _cidadeController.text.trim();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            'nome': _nomeController.text.trim(),
            'cpf': _cpfController.text.trim(),
            'telefone': _telefoneController.text.trim(),
            'email': _emailController.text.trim(),
            'cidade': cidadeReg,
            'uf': loc.ufDetectado ?? '',
            'cidade_normalizada': cidadeReg.isNotEmpty
                ? LocationService.normalizar(cidadeReg)
                : loc.cidadeNormalizada,
            'uf_normalizado': loc.ufNormalizado,
            'tipoUsuario': 'cliente',
            'role': 'cliente',
            'ativo': true,
            'status_conta': 'ativa',
            'dataCadastro': FieldValue.serverTimestamp(),
            'totalConcluido': 0,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cadastro realizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String mensagemErro = 'Ocorreu um erro no cadastro.';
      if (e.code == 'weak-password') {
        mensagemErro = 'A senha é muito fraca.';
      } else if (e.code == 'email-already-in-use') {
        mensagemErro = 'Este e-mail já está em uso.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagemErro), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === FUNÇÃO DE CADASTRO/LOGIN COM GOOGLE ===
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
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'nome': user.displayName ?? 'Usuário Google',
            'email': user.email ?? '',
            'cpf': '',
            'telefone': '',
            'cidade': '',
            'role': 'cliente',
            'tipoUsuario': 'cliente',
            'ativo': true,
            'dataCadastro': FieldValue.serverTimestamp(),
            'totalConcluido': 0,
          });
        } catch (e) {
          debugPrint('Firestore novo usuário Google: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Conta Google OK, perfil não guardado: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bem-vindo(a)!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on StateError catch (e) {
      if (mounted && !e.message.contains('cancelado')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Firebase: ${e.code} — ${e.message ?? ""}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao usar Google: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Cadastro'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // MÁGICA 1: Inicia a digitação com letra Maiúscula
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome Completo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 15),

            // MÁGICA 2: Formatação automática de CPF
            TextField(
              controller: _cpfController,
              keyboardType: TextInputType.number,
              inputFormatters: [MaskedInputFormatter('000.000.000-00')],
              decoration: const InputDecoration(
                labelText: 'CPF',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 15),

            // MÁGICA 3: Formatação automática de Telefone
            TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [MaskedInputFormatter('(00) 00000-0000')],
              decoration: const InputDecoration(
                labelText: 'Telefone (WhatsApp)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _cidadeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Cidade (ex: Rondonópolis)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _senhaController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha (mínimo 6 caracteres)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 15),

            // NOVO CAMPO: CONFIRMAR SENHA
            TextField(
              controller: _confirmarSenhaController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirme sua Senha',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8F00),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _isLoading ? null : _fazerCadastro,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'CADASTRAR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),

            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text("OU", style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),

            // BOTÃO GOOGLE
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _entrarComGoogle,
              icon: Image.network(
                'https://cdn.freebiesupply.com/logos/thumbs/2x/google-g-2015-logo.png',
                height: 24,
              ),
              label: const Text(
                "Cadastrar com o Google",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
