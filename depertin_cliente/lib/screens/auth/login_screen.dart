// Arquivo: lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import '../../auth/google_auth_helper.dart';
import '../../services/conta_exclusao_service.dart';
import '../../services/location_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;

  Future<void> _atualizarTokenAposLogin(String uid) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
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

  Future<void> _fazerLogin() async {
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

    setState(() => _isLoading = true);
    // ... resto do código continua igual ...
    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _senhaController.text.trim(),
          );
      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;
        await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(uid);
        await _atualizarTokenAposLogin(uid);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login realizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String mensagem = 'Erro no login.';
      if (e.code == 'user-not-found') {
        mensagem = 'Usuário não encontrado.';
      } else if (e.code == 'wrong-password') {
        mensagem = 'Senha incorreta.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === FUNÇÃO DE LOGIN COM GOOGLE ===
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
          final loc = context.read<LocationService>();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
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
            'dataCadastro': FieldValue.serverTimestamp(),
            'totalConcluido': 0,
          });
        } catch (e) {
          debugPrint('Firestore novo usuário Google: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Conta Google OK, mas falhou ao salvar o perfil: $e',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
      await ContaExclusaoService.cancelarExclusaoPendenteSeNecessario(user.uid);
      await _atualizarTokenAposLogin(user.uid);
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
            content: Text('Erro Google: $e'),
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
        title: const Text('Entrar', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF6A1B9A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Icon(
                Icons.account_circle,
                size: 80,
                color: Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 30),

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
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 25),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8F00),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _isLoading ? null : _fazerLogin,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'ENTRAR',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 15),

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
              const SizedBox(height: 15),

              // BOTÃO GOOGLE
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _entrarComGoogle,
                icon: Image.network(
                  'https://cdn.freebiesupply.com/logos/thumbs/2x/google-g-2015-logo.png',
                  height: 24,
                ),
                label: const Text(
                  "Entrar com o Google",
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

              const SizedBox(height: 15),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterScreen(),
                  ),
                ),
                child: const Text(
                  'Não tem conta? Registe-se aqui.',
                  style: TextStyle(color: Color(0xFF6A1B9A)),
                ),
              ),

              const SizedBox(height: 20),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('configuracoes')
                    .doc('status_app')
                    .snapshots(),
                builder: (context, snapshot) {
                  bool estavel = true;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    var dados = snapshot.data!.data() as Map<String, dynamic>?;
                    estavel = dados?['estavel'] ?? true;
                  }

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: estavel ? Colors.green : Colors.amber[700],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            estavel
                                ? "Aplicativo Operando Normalmente."
                                : "Aplicativo instável no momento",
                            style: TextStyle(
                              color: estavel ? Colors.green : Colors.amber[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "DiPertin v1.0.0",
                        style: TextStyle(
                          color: Colors.grey[400],
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
