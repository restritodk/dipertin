import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    // Apenas em debug: credenciais de teste (não entram em build release).
    if (kDebugMode) {
      _emailController.text = 'master@teste.com';
      _senhaController.text = 'master';
    }
  }

  final Color diPertinRoxo = const Color(0xFF6A1B9A);
  final Color diPertinLaranja = const Color(0xFFFF8F00);

  Future<void> _fazerLogin() async {
    String email = _emailController.text.trim();
    String senha = _senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      _mostrarErro("Por favor, preencha o e-mail e a senha!");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. FAZ O LOGIN OFICIAL NO FIREBASE AUTH
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      // 2. Perfil na MESMA chave que as regras Firestore: users/{auth.uid}
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!docSnap.exists) {
        _mostrarErro(
          "Sem documento em users/$uid no Firestore. Crie o perfil com o mesmo UID do Authentication.",
        );
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }

      var dadosUsuario = docSnap.data()!;

      // Suportando os dois nomes que você usou no banco
      String tipoUsuario =
          (dadosUsuario['role'] ??
                  dadosUsuario['tipo'] ??
                  dadosUsuario['tipoUsuario'] ??
                  'cliente')
              .toString()
              .toLowerCase();
      bool primeiroAcesso = dadosUsuario['primeiro_acesso'] ?? false;

      // 3. O GUARDA-COSTAS: VERIFICA QUEM PODE ENTRAR
      // Agora o Lojista também é VIP e pode entrar!
      if (tipoUsuario != 'master' &&
          tipoUsuario != 'master_city' &&
          tipoUsuario != 'lojista') {
        _mostrarErro(
          "Acesso Negado. Seu perfil não tem permissão para acessar o painel web.",
        );
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }

      // 4. VERIFICA SE É O PRIMEIRO ACESSO (Obriga a trocar a senha)
      if (primeiroAcesso) {
        setState(() => _isLoading = false);
        _mostrarModalTrocaSenha(uid, dadosUsuario['nome'] ?? 'Parceiro');
        return;
      }

      // 5. TUDO CERTO! BEM-VINDO AO PAINEL!
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
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
      _mostrarErro("Erro interno no servidor.");
      setState(() => _isLoading = false);
    }
  }

  // === MODAL COM 2 CAMPOS PARA TROCA DE SENHA ===
  void _mostrarModalTrocaSenha(String userId, String nomeUsuario) {
    TextEditingController novaSenhaC = TextEditingController();
    TextEditingController confirmarSenhaC = TextEditingController();
    bool isSalvando = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Bloqueia o clique fora do modal
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            Future<void> salvarNovaSenha() async {
              if (novaSenhaC.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("A senha deve ter pelo menos 6 caracteres."),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (novaSenhaC.text != confirmarSenhaC.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("As senhas digitadas não são iguais!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setStateModal(() => isSalvando = true);

              try {
                // 1. Muda a senha REAL no sistema de autenticação do Google
                await FirebaseAuth.instance.currentUser!.updatePassword(
                  novaSenhaC.text.trim(),
                );

                // 2. Tira a trava de "primeiro_acesso" no banco de dados
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({
                      'senha': novaSenhaC.text
                          .trim(), // Atualiza a senha no documento também, por garantia
                      'primeiro_acesso': false,
                      'data_atualizacao': FieldValue.serverTimestamp(),
                    });

                if (context.mounted) {
                  Navigator.pop(context); // Fecha o modal
                  Navigator.pushReplacementNamed(
                    context,
                    '/dashboard',
                  ); // Libera o acesso ao painel
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro ao atualizar senha: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                setStateModal(() => isSalvando = false);
              }
            }

            return AlertDialog(
              title: const Text(
                "Bem-vindo(a)! 🎉",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Olá, $nomeUsuario. Este é o seu primeiro acesso ao painel. Por motivos de segurança, defina a sua nova senha pessoal.",
                    ),
                    const SizedBox(height: 20),

                    // CAMPO 1
                    TextField(
                      controller: novaSenhaC,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Digite a Nova Senha",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // CAMPO 2 (Confirmação)
                    TextField(
                      controller: confirmarSenhaC,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Confirme a Nova Senha",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: isSalvando ? null : salvarNovaSenha,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: diPertinRoxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  child: isSalvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Salvar e Entrar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _enviarRecuperacaoSenha() async {
    String email = _emailController.text.trim();
    if (email.isEmpty) {
      _mostrarErro('Digite o e-mail no campo acima para receber o link de recuperação.');
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
            ),
            backgroundColor: Colors.green.shade700,
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
              ),
              backgroundColor: Colors.orange.shade800,
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
        SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 100,
                  errorBuilder: (c, e, s) => Icon(
                    Icons.admin_panel_settings,
                    size: 80,
                    color: diPertinRoxo,
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  "Painel DiPertin",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: diPertinRoxo,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Acesso restrito para Lojistas e Administração.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // CAMPO DE E-MAIL
                TextField(
                  controller: _emailController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: "E-mail de Acesso",
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: (_) => _fazerLogin(),
                ),
                const SizedBox(height: 20),

                // CAMPO DE SENHA
                TextField(
                  controller: _senhaController,
                  obscureText: _ocultarSenha,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: "Senha",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarSenha ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _ocultarSenha = !_ocultarSenha),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: (_) => {if (!_isLoading) _fazerLogin()},
                ),
                const SizedBox(height: 30),

                // BOTÃO DE ENTRAR
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _fazerLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Text(
                            "ENTRAR NO SISTEMA",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
                TextButton(
                  onPressed: _isLoading ? null : _enviarRecuperacaoSenha,
                  child: const Text(
                    "Esqueceu a senha?",
                    style: TextStyle(color: Colors.grey),
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
