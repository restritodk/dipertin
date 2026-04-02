import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SidebarMenu extends StatefulWidget {
  final String rotaAtual;
  const SidebarMenu({super.key, required this.rotaAtual});

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  final Color diPertinRoxo = const Color(0xFF6A1B9A);

  String _tipoUsuario = 'carregando';

  @override
  void initState() {
    super.initState();
    _buscarPermissoes();
  }

  // === MAGIA DO CADEADO: DESCOBRE QUEM ESTÁ LOGADO ===
  Future<void> _buscarPermissoes() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final docSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (docSnap.exists) {
          var dados = docSnap.data()!;
          if (mounted) {
            setState(() {
              _tipoUsuario = perfilAdministrativo(dados);
            });
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar permissão: $e");
      }
    }
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String label,
    String rotaDestino,
  ) {
    bool isSelected = widget.rotaAtual == rotaDestino;
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      selected: isSelected,
      selectedTileColor: Colors.white12,
      onTap: () {
        if (!isSelected) {
          Navigator.pushReplacementNamed(context, rotaDestino);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se ainda está carregando o banco de dados, mostra uma barra vazia
    if (_tipoUsuario == 'carregando') {
      return Container(
        width: 250,
        color: diPertinRoxo,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Container(
      width: 250,
      color: diPertinRoxo,
      child: Column(
        children: [
          const SizedBox(height: 40),
          Image.asset(
            'assets/logo.png',
            height: 70,
            errorBuilder: (c, e, s) => const Icon(
              Icons.admin_panel_settings,
              size: 60,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          // Badge mostrando quem ele é
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _tipoUsuario.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Divider(color: Colors.white24, height: 40),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // === MENU PARA TODOS (ADMINS E LOJISTAS) ===
                _menuItem(context, Icons.dashboard, "Dashboard", '/dashboard'),

                // === STAFF: master, master_city ===
                if (perfilPodeGestaoLojasEntregadoresBanners(_tipoUsuario)) ...[
                  _menuItem(context, Icons.store, "Lojas", '/lojas'),
                  _menuItem(
                    context,
                    Icons.motorcycle,
                    "Entregadores",
                    '/entregadores',
                  ),
                  _menuItem(
                    context,
                    Icons.view_carousel,
                    "Banners Vitrine",
                    '/banners',
                  ),
                ],

                // === SE FOR APENAS LOJISTA, VÊ SÓ O DELE ===
                if (_tipoUsuario == 'lojista') ...[
                  _menuItem(
                    context,
                    Icons.shopping_bag,
                    "Meus Pedidos",
                    '/meus_pedidos',
                  ),
                  _menuItem(
                    context,
                    Icons.restaurant_menu,
                    "Meu Cardápio",
                    '/meu_cardapio',
                  ),
                  _menuItem(
                    context,
                    Icons.account_balance_wallet,
                    "Minha Carteira",
                    '/carteira_loja',
                  ),
                ],

                // === CHEFE: master ===
                if (perfilPodeMenuChefe(_tipoUsuario)) ...[
                  const Divider(color: Colors.white24),
                  _menuItem(
                    context,
                    Icons.admin_panel_settings,
                    "AdminCity",
                    '/admincity',
                  ),
                  _menuItem(
                    context,
                    Icons.campaign,
                    "Anúncios & Util.",
                    '/utilidades',
                  ),
                  _menuItem(
                    context,
                    Icons.attach_money,
                    "Financeiro Geral",
                    '/financeiro',
                  ),
                  _menuItem(
                    context,
                    Icons.settings,
                    "Configurações",
                    '/configuracoes',
                  ),
                ],
              ],
            ),
          ),

          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text("Sair", style: TextStyle(color: Colors.white)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
