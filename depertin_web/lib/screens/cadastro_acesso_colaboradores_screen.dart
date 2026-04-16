import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/lojista_painel_context.dart';
import '../widgets/botao_suporte_flutuante.dart';
import '../widgets/colaboradores_lojista_painel_card.dart';

/// Cadastro de colaboradores do painel (nível III) — menu Configuração → Cadastro de Acesso.
class CadastroAcessoColaboradoresScreen extends StatelessWidget {
  const CadastroAcessoColaboradoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Não autenticado.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }
        final d = snap.data?.data();
        if (d == null || !podeCadastrarColaboradoresPainel(d)) {
          return painelLojistaSemPermissaoScaffold(
            mensagem:
                'Apenas usuários com nível III podem gerenciar o cadastro de acesso.',
          );
        }
        final uidLoja = uidLojaEfetivo(d, uid);
        return Scaffold(
          backgroundColor: PainelAdminTheme.fundoCanvas,
          floatingActionButton: const BotaoSuporteFlutuante(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 120),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'CONFIGURAÇÃO',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cadastro de acesso',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Crie contas para a sua equipa.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: PainelAdminTheme.textoSecundario,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ColaboradoresLojistaPainelCard(uidLoja: uidLoja),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
