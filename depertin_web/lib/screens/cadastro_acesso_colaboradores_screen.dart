import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/lojista_painel_context.dart';
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 48, 40, 120),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PainelAdminTheme.roxo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'EQUIPE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: PainelAdminTheme.roxo,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Controle de Acesso',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Membros do Painel',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: PainelAdminTheme.dashboardInk,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Gerencie as permissões e contas dos colaboradores que ajudam a administrar sua loja.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            color: PainelAdminTheme.textoSecundario,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
