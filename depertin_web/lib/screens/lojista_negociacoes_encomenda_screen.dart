import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/encomenda_negociacao_status.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/lojista_painel_context.dart';
import 'lojista_encomenda_detalhe_painel_screen.dart';

/// Lista `encomendas` da loja (`loja_id`) — paridade com o app mobile.
class LojistaNegociacoesEncomendaScreen extends StatelessWidget {
  const LojistaNegociacoesEncomendaScreen({super.key});

  static final DateFormat _fmtData =
      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, _, uidLoja, _) {
        return Scaffold(
          backgroundColor: PainelAdminTheme.fundoCanvas,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Negociações de encomenda',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.roxo,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Aceite solicitações, envie propostas e acompanhe até o pagamento do saldo. '
                        'Os pedidos fechados continuam em «Meus pedidos».',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('encomendas')
                      .where('loja_id', isEqualTo: uidLoja)
                      .orderBy('atualizado_em', descending: true)
                      .limit(80)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Erro: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: PainelAdminTheme.roxo,
                        ),
                      );
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'Nenhuma solicitação de encomenda por aqui ainda.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      );
                    }
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                          itemCount: docs.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            final m = doc.data();
                            final st =
                                (m['status_negociacao'] ?? '').toString();
                            final atualizado = m['atualizado_em'];
                            String quando = '';
                            if (atualizado is Timestamp) {
                              quando = _fmtData.format(atualizado.toDate());
                            }
                            final nomeCli =
                                (m['cliente_nome_snapshot'] ?? 'Cliente')
                                    .toString();
                            return Material(
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          LojistaEncomendaDetalhePainelScreen(
                                        encomendaId: doc.id,
                                        uidLoja: uidLoja,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nomeCli,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 17,
                                                color: Color(0xFF1E1B4B),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              EncomendaNegociacaoStatus
                                                  .rotuloPt(st),
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.35,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                            if (quando.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Atualizado em $quando',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
