import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/lojista_motivo_recusa.dart';
import '../../services/conta_bloqueio_lojista_service.dart';
import '../../widgets/lojista_conta_bloqueada_overlay.dart';
import '../auth/login_screen.dart';
import 'lojista_dashboard_screen.dart';
import 'lojista_form_screen.dart';

/// Tela **ponte** que decide, a partir do documento do lojista em
/// `users/{uid}`, se abre o painel operacional ou a tela de cadastro.
///
/// Usada principalmente pelo deep-link da notificação **Conta aprovada**
/// (tipo `lojista_cadastro_aprovado`). Antes o push levava o lojista
/// direto para `LojistaFormScreen` — o que fazia a aprovação parecer
/// "voltar pro cadastro" para o usuário. Agora:
///
///   - Conta APROVADA e sem bloqueio → [LojistaDashboardScreen].
///   - Conta RECUSADA (ou requer correção) → [LojistaFormScreen].
///   - Conta BLOQUEADA → overlay de bloqueio (com opção de sair).
///   - Sem usuário autenticado → volta para [LojistaFormScreen] que
///     por sua vez redireciona ao login quando necessário.
class LojistaPainelRoteador extends StatelessWidget {
  const LojistaPainelRoteador({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const LoginScreen();
    }
    return Scaffold(
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final dados = snap.data?.data() ?? <String, dynamic>{};

          if (ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(dados)) {
            return LojistaContaBloqueadaOverlay(
              dadosUsuario: dados,
              onSair: () async {
                await FirebaseAuth.instance.signOut();
              },
            );
          }

          if (ContaBloqueioLojistaService
              .lojaRecusadaSomenteCorrecaoCadastro(dados)) {
            final bloqueioAte = LojistaMotivoRecusa.bloqueioCadastroAte(dados);
            if (bloqueioAte != null && bloqueioAte.isAfter(DateTime.now())) {
              return _CadastroEmCooldown(
                dataLiberacao: bloqueioAte,
                motivo: (dados['motivo_recusa'] ?? '').toString(),
              );
            }
            return const LojistaFormScreen();
          }

          // Caso default: conta aprovada (ou sem flag de bloqueio) →
          // painel operacional do lojista. Ao abrir o dashboard a
          // tela reage sozinha a mudanças de papel/perfil.
          return const LojistaDashboardScreen();
        },
      ),
    );
  }
}

class _CadastroEmCooldown extends StatelessWidget {
  const _CadastroEmCooldown({
    required this.dataLiberacao,
    required this.motivo,
  });

  final DateTime dataLiberacao;
  final String motivo;

  @override
  Widget build(BuildContext context) {
    final diff = dataLiberacao.difference(DateTime.now());
    String tempoTexto;
    if (diff.inHours >= 24) {
      final dias = (diff.inHours / 24).ceil();
      tempoTexto = '$dias ${dias == 1 ? 'dia' : 'dias'}';
    } else if (diff.inHours >= 1) {
      tempoTexto = '${diff.inHours}h';
    } else {
      final minutos = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      tempoTexto = '${minutos}min';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro em análise')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.hourglass_bottom_rounded,
              size: 64,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 20),
            const Text(
              'Estamos revisando seu pedido novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              'Você poderá enviar uma nova solicitação em cerca de $tempoTexto.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
            if (motivo.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  motivo.trim(),
                  style: TextStyle(color: Colors.grey.shade800, height: 1.4),
                ),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
