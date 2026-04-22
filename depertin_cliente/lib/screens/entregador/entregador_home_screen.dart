// Arquivo: lib/screens/entregador/entregador_home_screen.dart

import 'package:flutter/material.dart';
import 'configuracoes/configuracoes_entregador_screen.dart';
import 'entregador_dashboard_screen.dart';
import 'entregador_carteira_screen.dart';
import 'entregador_historico_screen.dart';

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
    return Scaffold(
      body: IndexedStack(index: _indiceAtual, children: _telas),
      bottomNavigationBar: BottomNavigationBar(
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
    );
  }
}
