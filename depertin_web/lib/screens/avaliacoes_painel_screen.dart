import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AvaliacoesPainelScreen extends StatefulWidget {
  const AvaliacoesPainelScreen({super.key});

  @override
  State<AvaliacoesPainelScreen> createState() =>
      _AvaliacoesPainelScreenState();
}

class _AvaliacoesPainelScreenState extends State<AvaliacoesPainelScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  int _filtroEstrelas = 0;
  String _ordenacao = 'recentes';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(child: _buildCorpo()),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _buildHeader() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Avaliações',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _roxo,
                            letterSpacing: -0.5),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Modere avaliações de clientes sobre as lojas da plataforma.',
                        style: TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: _ordenacao,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(
                        value: 'recentes', child: Text('Mais recentes')),
                    DropdownMenuItem(
                        value: 'piores', child: Text('Piores notas')),
                    DropdownMenuItem(
                        value: 'melhores', child: Text('Melhores notas')),
                  ],
                  onChanged: (v) => setState(() => _ordenacao = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _filtroChip(0, 'Todas'),
                _filtroChip(1, '★ 1'),
                _filtroChip(2, '★★ 2'),
                _filtroChip(3, '★★★ 3'),
                _filtroChip(4, '★★★★ 4'),
                _filtroChip(5, '★★★★★ 5'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtroChip(int estrelas, String label) {
    final sel = _filtroEstrelas == estrelas;
    return InkWell(
      onTap: () => setState(() => _filtroEstrelas = estrelas),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _laranja : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? _laranja : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCorpo() {
    Query query =
        FirebaseFirestore.instance.collection('avaliacoes');

    if (_ordenacao == 'recentes') {
      query = query.orderBy('data_criacao', descending: true);
    } else if (_ordenacao == 'piores') {
      query = query.orderBy('estrelas', descending: false);
    } else {
      query = query.orderBy('estrelas', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snap.data?.docs ?? [];

        if (_filtroEstrelas > 0) {
          docs = docs.where((d) {
            final e =
                (d.data() as Map<String, dynamic>)['estrelas'] as int? ?? 0;
            return e == _filtroEstrelas;
          }).toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_border_rounded,
                    size: 56, color: _laranja.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  _filtroEstrelas == 0
                      ? 'Nenhuma avaliação ainda.'
                      : 'Nenhuma avaliação com $_filtroEstrelas estrela(s).',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 16),
                ),
              ],
            ),
          );
        }

        final total = docs.length;
        final soma = docs.fold<double>(0, (acc, d) {
          final e =
              (d.data() as Map<String, dynamic>)['estrelas'] as int? ?? 0;
          return acc + e;
        });
        final media = total > 0 ? soma / total : 0.0;

        return Column(
          children: [
            _buildResumo(total, media),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCard(docs[i]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResumo(int total, double media) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Row(
            children: [
              Expanded(
                child: _statCard(
                  Icons.rate_review_outlined,
                  'Total de avaliações',
                  '$total',
                  _roxo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  Icons.star_rounded,
                  'Nota média',
                  media.toStringAsFixed(1),
                  _laranja,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String valor, Color cor) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: cor)),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final estrelas = d['estrelas'] as int? ?? 0;
    final comentario = d['comentario']?.toString() ?? '';
    final resposta = d['resposta_loja']?.toString() ?? '';
    final lojaNome = d['loja_nome']?.toString() ?? 'Loja';
    final clienteNome = d['cliente_nome']?.toString() ?? 'Cliente';
    final ts = d['data_criacao'] as Timestamp?;
    final data = ts != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
        : '—';

    final cor = estrelas <= 2
        ? const Color(0xFFB91C1C)
        : estrelas == 3
            ? const Color(0xFFB45309)
            : const Color(0xFF15803D);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$estrelas★',
                    style: TextStyle(
                        color: cor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded,
                              size: 14, color: _roxo),
                          const SizedBox(width: 4),
                          Text(lojaNome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _roxo)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(clienteNome,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                          const SizedBox(width: 12),
                          Icon(Icons.schedule_rounded,
                              size: 13, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(data,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remover avaliação',
                  icon: Icon(Icons.delete_outline_rounded,
                      color: Colors.grey.shade500),
                  onPressed: () => _confirmarExclusao(doc.id),
                ),
              ],
            ),
            if (comentario.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.grey.shade200),
                ),
                child: Text('"$comentario"',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        fontStyle: FontStyle.italic,
                        height: 1.4)),
              ),
            ],
            if (resposta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _roxo.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _roxo.withValues(alpha: 0.15)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_mall_directory_outlined,
                        size: 15, color: _roxo),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Resposta da loja: $resposta',
                        style: TextStyle(
                            fontSize: 13,
                            color: _roxo.withValues(alpha: 0.8),
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarExclusao(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _laranja),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('Remover avaliação',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        ]),
        content: const Text(
            'Esta avaliação será removida permanentemente. Confirma?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('avaliacoes')
          .doc(docId)
          .delete();
    }
  }
}
