// Arquivo: lib/screens/comum/profile_screen.dart

import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/screens/comum/edit_profile_screen.dart';
import 'package:depertin_cliente/screens/entregador/entregador_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login_screen.dart';
import '../entregador/entregador_form_screen.dart';
import '../lojista/lojista_form_screen.dart';
import '../cliente/orders_screen.dart';
import '../lojista/lojista_dashboard_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // Fundo cinza para os cards destacarem
      appBar: AppBar(
        title: const Text(
          "Meu Perfil",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinRoxo),
            );
          }

          if (!authSnapshot.hasData) {
            return _construirTelaSemLogin(context);
          }

          final user = authSnapshot.data!;

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: diPertinRoxo),
                );
              }

              if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                return const Center(
                  child: Text("Ficha de utilizador não encontrada."),
                );
              }

              var userData = userSnapshot.data!.data() as Map<String, dynamic>;
              return _construirTelaComLogin(context, user.email!, userData);
            },
          );
        },
      ),
    );
  }

  // ==========================================
  // TELA QUANDO NÃO HÁ LOGIN
  // ==========================================
  Widget _construirTelaSemLogin(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 60,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Você precisa estar logado para ver seu perfil e acompanhar seus pedidos.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                "Fazer Login ou Cadastrar",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TELA COM OS DADOS DO UTILIZADOR (TURBINADA)
  // ==========================================
  Widget _construirTelaComLogin(
    BuildContext context,
    String email,
    Map<String, dynamic> userData,
  ) {
    String nome = userData['nome'] ?? 'Sem Nome';
    String role = userData['role'] ?? 'cliente';
    String cpf = userData['cpf'] ?? 'Sem CPF';
    String enderecoPadrao = userData['endereco_padrao'] ?? '';
    String nomeLoja = userData['loja_nome'] ?? '';
    String fotoPerfil = userData['foto_perfil'] ?? '';

    // === AS DUAS VARIÁVEIS MÁGICAS DE STATUS ===
    String statusLoja = userData['status_loja'] ?? 'pendente';
    String statusEntregador = userData['entregador_status'] ?? 'pendente';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // CABEÇALHO DO PERFIL COM FOTO
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 55,
                backgroundColor: diPertinRoxo.withOpacity(0.1),
                backgroundImage: fotoPerfil.isNotEmpty
                    ? NetworkImage(fotoPerfil)
                    : null,
                child: fotoPerfil.isEmpty
                    ? const Icon(Icons.person, size: 60, color: diPertinRoxo)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Text(
              nome,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: diPertinRoxo,
              ),
            ),
          ),

          if (nomeLoja.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Loja: $nomeLoja",
                  style: const TextStyle(
                    fontSize: 16,
                    color: diPertinLaranja,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          Center(
            child: Text(email, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 15),

          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProfileScreen(
                      nomeAtual: nome,
                      enderecoAtual: enderecoPadrao,
                      role: role,
                      nomeLojaAtual: nomeLoja,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit, color: diPertinRoxo, size: 16),
              label: const Text(
                "Editar Perfil",
                style: TextStyle(
                  color: diPertinRoxo,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: diPertinRoxo),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),

          const SizedBox(height: 25),

          // =======================================================
          // === NOVO: CARD DE SALDO PARA O CLIENTE SE TRANQUILIZAR ===
          // =======================================================
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              double saldo = 0.0;
              if (snapshot.hasData && snapshot.data!.exists) {
                var d = snapshot.data!.data() as Map<String, dynamic>;
                saldo = (d['saldo'] ?? 0.0).toDouble();
              }

              // Só mostra o Card se o cliente tiver dinheiro guardado (estorno)
              if (saldo <= 0) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(
                  bottom: 25,
                ), // Dá um espaço para o próximo bloco
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Saldo de Devolução",
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                          Text(
                            "R\$ ${saldo.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      "Usar na\npróxima compra",
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
          // =======================================================

          // BLOCO 1: ATIVIDADES DO CLIENTE
          const Text(
            "Minhas Atividades",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          _buildMenuCard(
            children: [
              _buildMenuItem(
                icon: Icons.receipt_long,
                color: diPertinRoxo,
                title: 'Meus Pedidos',
                subtitle: 'Acompanhe suas compras',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersScreen()),
                ),
              ),
              const Divider(height: 1),
              _buildMenuItem(
                icon: Icons.support_agent,
                color: diPertinLaranja,
                title: 'Central de Ajuda',
                subtitle: 'Fale com nossa equipe de suporte',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChatSuporteScreen(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          // BLOCO 2: INFORMAÇÕES DA CONTA
          const Text(
            "Dados da Conta",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          _buildMenuCard(
            children: [
              _buildMenuItem(
                icon: Icons.badge,
                color: Colors.grey,
                title: 'CPF',
                subtitle: cpf,
                trailing: const Icon(Icons.lock, size: 16, color: Colors.grey),
              ),
              const Divider(height: 1),
              _buildMenuItem(
                icon: Icons.security,
                color: Colors.grey,
                title: 'Tipo de Perfil',
                subtitle: role.toUpperCase(),
                trailing: const SizedBox(),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // BLOCO 3: PAINÉIS DE TRABALHO (AGORA INTELIGENTES)
          if (role == 'cliente') ...[
            const Text(
              "Seja um Parceiro DiPertin",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            _buildMenuCard(
              children: [
                _buildMenuItem(
                  icon: Icons.storefront,
                  color: diPertinLaranja,
                  title: 'Quero vender (Lojista)',
                  subtitle: 'Cadastre sua loja e venda na sua cidade',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LojistaFormScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _buildMenuItem(
                  icon: Icons.motorcycle,
                  color: diPertinLaranja,
                  title: 'Quero entregar',
                  subtitle: 'Faça entregas num raio de 3km e ganhe dinheiro',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EntregadorFormScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // BOTÃO INTELIGENTE DO LOJISTA
          if (role == 'lojista') ...[
            ElevatedButton.icon(
              onPressed: () {
                if (statusLoja == 'bloqueada') {
                  // Se foi recusado, manda ele de volta pro formulário para arrumar os dados!
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LojistaFormScreen(),
                    ),
                  );
                } else {
                  // Se tá aprovado ou pendente, manda ele tentar acessar o painel
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LojistaDashboardScreen(),
                    ),
                  );
                }
              },
              icon: Icon(
                statusLoja == 'aprovada'
                    ? Icons.dashboard
                    : (statusLoja == 'bloqueada'
                          ? Icons.error_outline
                          : Icons.hourglass_empty),
                color: Colors.white,
              ),
              label: Text(
                statusLoja == 'aprovada'
                    ? "ACESSAR PAINEL DA LOJA"
                    : (statusLoja == 'bloqueada'
                          ? "CADASTRO RECUSADO (CORRIGIR)"
                          : "LOJA EM ANÁLISE (ACOMPANHAR)"),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: statusLoja == 'aprovada'
                    ? diPertinLaranja
                    : (statusLoja == 'bloqueada'
                          ? Colors.red
                          : Colors.orange[400]),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            const SizedBox(height: 15),
          ],

          // BOTÃO INTELIGENTE DO ENTREGADOR
          if (role == 'entregador') ...[
            ElevatedButton.icon(
              onPressed: () {
                if (statusEntregador == 'bloqueado') {
                  // Se foi recusado, manda ele de volta pro formulário para reenviar as fotos!
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EntregadorFormScreen(),
                    ),
                  );
                } else {
                  // Se tá aprovado ou pendente, manda ele tentar acessar o painel de corridas
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EntregadorHomeScreen(),
                    ),
                  );
                }
              },
              icon: Icon(
                statusEntregador == 'aprovado'
                    ? Icons.motorcycle
                    : (statusEntregador == 'bloqueado'
                          ? Icons.error_outline
                          : Icons.hourglass_empty),
                color: Colors.white,
              ),
              label: Text(
                statusEntregador == 'aprovado'
                    ? "ACESSAR PAINEL DE ENTREGAS"
                    : (statusEntregador == 'bloqueado'
                          ? "CADASTRO RECUSADO (CORRIGIR)"
                          : "CADASTRO EM ANÁLISE"),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: statusEntregador == 'aprovado'
                    ? Colors.black87
                    : (statusEntregador == 'bloqueado'
                          ? Colors.red
                          : Colors.orange[400]),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            const SizedBox(height: 15),
          ],

          const SizedBox(height: 15),

          // BOTÃO DE SAIR
          TextButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              "Sair da Conta",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // WIDGET HELPER: Cria o cartão branco com bordas arredondadas
  Widget _buildMenuCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  // WIDGET HELPER: Cria os itens do menu padronizados
  Widget _buildMenuItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing:
          trailing ??
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}
