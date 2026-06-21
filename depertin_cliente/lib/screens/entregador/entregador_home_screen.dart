// Arquivo: lib/screens/entregador/entregador_home_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/conta_bloqueio_entregador_service.dart';
import 'configuracoes/configuracoes_entregador_screen.dart';
import 'entregador_carteira_screen.dart';
import 'entregador_dashboard_screen.dart';
import 'entregador_historico_screen.dart';
import 'entregador_painel_bloqueado_screen.dart';

class EntregadorHomeScreen extends StatefulWidget {
  const EntregadorHomeScreen({super.key});

  @override
  State<EntregadorHomeScreen> createState() => _EntregadorHomeScreenState();
}

class _EntregadorHomeScreenState extends State<EntregadorHomeScreen> {
  int _indiceAtual = 0;

  final List<Widget> _telas = const [
    EntregadorDashboardScreen(),
    EntregadorHistoricoScreen(),
    EntregadorCarteiraScreen(),
    ConfiguracoesEntregadorScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Faça login para continuar.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final dados = snap.data!.data() ?? {};
        if (ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(dados)) {
          return const EntregadorPainelBloqueadoScreen();
        }

        return Scaffold(
          body: IndexedStack(index: _indiceAtual, children: _telas),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: BottomNavigationBar(
              currentIndex: _indiceAtual,
              onTap: (index) {
                setState(() {
                  _indiceAtual = index;
                });
              },
              selectedItemColor: const Color(0xFFFF8F00),
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              items: const [
              BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Radar'),
              BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: 'Histórico',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet),
                label: 'Ganhos',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_rounded),
                label: 'Configurações',
              ),
              ],
            ),
          ),
        );
      },
    );
  }
}
