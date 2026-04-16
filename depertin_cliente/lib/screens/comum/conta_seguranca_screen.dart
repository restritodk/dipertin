// Arquivo: lib/screens/comum/conta_seguranca_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:depertin_cliente/screens/comum/alterar_senha_screen.dart';
import 'package:depertin_cliente/screens/comum/edit_profile_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);

/// Submenu de Configurações: conta e segurança.
class ContaSegurancaScreen extends StatelessWidget {
  const ContaSegurancaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        title: const Text(
          'Conta e segurança',
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
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Faça login para gerenciar sua conta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _diPertinRoxo),
                  );
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Center(
                    child: Text(
                      'Não foi possível carregar seus dados.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  );
                }

                final Map<String, dynamic> d =
                    snapshot.data!.data() as Map<String, dynamic>;
                final String nome = d['nome']?.toString() ?? '';
                final String endereco = d['endereco_padrao']?.toString() ?? '';
                final String? role = d['role']?.toString();
                final String lojaNome = d['loja_nome']?.toString() ?? '';
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Conta e segurança',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gerencie seus dados e acesso ao app.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _cardMenu(
                        children: [
                          _itemMenu(
                            icon: Icons.person_outline_rounded,
                            cor: _diPertinRoxo,
                            titulo: 'Editar perfil',
                            subtitulo: 'Nome, foto e dados pessoais',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditProfileScreen(
                                    nomeAtual: nome,
                                    enderecoAtual: endereco,
                                    role: role,
                                    nomeLojaAtual:
                                        lojaNome.isEmpty ? null : lojaNome,
                                  ),
                                ),
                              );
                            },
                          ),
                          Divider(height: 1, color: Colors.grey.shade200),
                          _itemMenu(
                            icon: Icons.lock_outline_rounded,
                            cor: _diPertinLaranja,
                            titulo: 'Alterar senha',
                            subtitulo: 'Senha atual e nova senha',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AlterarSenhaScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _cardMenu({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _itemMenu({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: cor, size: 22),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Color(0xFF1A1A2E),
        ),
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
      onTap: onTap,
    );
  }
}
