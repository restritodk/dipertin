import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/conta_bloqueio_entregador_service.dart';
import '../../utils/entregador_voltar_perfil.dart';
import '../../widgets/entregador_radar_bloqueio_painel.dart';

const Color _roxo = Color(0xFF6A1B9A);

/// Tela informativa — bloqueio/exclusão afeta só o painel de entregas, não o app cliente.
class EntregadorPainelBloqueadoScreen extends StatelessWidget {
  const EntregadorPainelBloqueadoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Painel de entregas'),
          backgroundColor: _roxo,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Faça login para continuar.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F7),
            appBar: AppBar(
              title: const Text('Painel de entregas'),
              backgroundColor: _roxo,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator(color: _roxo)),
          );
        }

        final dados = snap.data!.data() ?? {};
        if (!ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(dados)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              voltarMeuPerfilAposAcaoEntregador(context);
            }
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => voltarMeuPerfilAposAcaoEntregador(context),
            ),
            title: const Text(
              'Painel de entregas',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: _roxo,
            foregroundColor: Colors.white,
          ),
          body: EntregadorRadarBloqueioPainel(
            dadosUsuario: dados,
            onVoltarPerfil: () => voltarMeuPerfilAposAcaoEntregador(context),
          ),
        );
      },
    );
  }
}
