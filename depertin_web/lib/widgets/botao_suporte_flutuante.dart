// lib/widgets/botao_suporte_flutuante.dart

import 'package:depertin_web/utils/admin_perfil.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BotaoSuporteFlutuante extends StatefulWidget {
  const BotaoSuporteFlutuante({super.key});

  @override
  State<BotaoSuporteFlutuante> createState() => _BotaoSuporteFlutuanteState();
}

class _BotaoSuporteFlutuanteState extends State<BotaoSuporteFlutuante> {
  String _tipoUsuario = 'carregando';
  String _minhaCidade = '';

  @override
  void initState() {
    super.initState();
    _buscarDadosAdmin();
  }

  Future<void> _buscarDadosAdmin() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (docSnap.exists) {
        final dados = docSnap.data()!;
        setState(() {
          _tipoUsuario = perfilAdministrativo(dados);
          _minhaCidade = dados['cidade'] ?? '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tipoUsuario == 'carregando') return const SizedBox.shrink();

    // Filtro Inteligente: Quem vê o quê?
    Query query = FirebaseFirestore.instance
        .collection('suporte')
        .where('status', isEqualTo: 'aguardando_admin');

    // MasterCity: só vê chamados da cidade dele
    if (_tipoUsuario == 'master_city') {
      query = query
          .where('cidade', isEqualTo: _minhaCidade)
          .where('escalado_superadmin', isEqualTo: false);
    }
    // Master: visão global (sem filtro por cidade)
    else if (_tipoUsuario == 'master') {
      // (Detalhe do filtro na tela de suporte)
    }
    // Lojista não tem botão flutuante de admin, ele usa o app dele
    else {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        int novosChamados = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton(
              backgroundColor: const Color(0xFFFF8F00), // Laranja
              onPressed: () =>
                  Navigator.pushNamed(context, '/atendimento_suporte'),
              child: const Icon(
                Icons.support_agent,
                color: Colors.white,
                size: 30,
              ),
            ),
            if (novosChamados > 0)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    novosChamados.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
