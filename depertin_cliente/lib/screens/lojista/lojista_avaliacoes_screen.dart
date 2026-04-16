// Arquivo: lib/screens/lojista/lojista_avaliacoes_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

/// Formata data/hora sem `DateFormat` com locale (evita LocaleDataException no app).
String _formatarDataHoraAvaliacao(DateTime dt) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(dt.day)}/${dois(dt.month)}/${dt.year} · ${dois(dt.hour)}:${dois(dt.minute)}';
}

class LojistaAvaliacoesScreen extends StatelessWidget {
  const LojistaAvaliacoesScreen({super.key, this.uidLoja});

  final String? uidLoja;

  void _abrirDialogoResposta(BuildContext context, String avaliacaoId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _DialogoRespostaAvaliacao(avaliacaoId: avaliacaoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text(
          'Minhas avaliações',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: diPertinLaranja,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
      ),
      body: user == null
          ? const Center(child: Text('Sessão inválida. Faça login novamente.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('avaliacoes')
                  .where('loja_id', isEqualTo: uidLoja ?? user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinLaranja),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar as avaliações.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.star_outline_rounded,
                              size: 64,
                              color: diPertinLaranja.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Nenhuma avaliação ainda',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Quando os clientes avaliarem seus pedidos, as notas e comentários aparecem aqui.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.45,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final lista = docs.toList();
                lista.sort((a, b) {
                  final Map<String, dynamic> dataA =
                      a.data() as Map<String, dynamic>;
                  final Map<String, dynamic> dataB =
                      b.data() as Map<String, dynamic>;
                  final Timestamp timeA =
                      dataA['data'] as Timestamp? ??
                      Timestamp.fromMillisecondsSinceEpoch(0);
                  final Timestamp timeB =
                      dataB['data'] as Timestamp? ??
                      Timestamp.fromMillisecondsSinceEpoch(0);
                  return timeB.compareTo(timeA);
                });

                double soma = 0;
                for (final d in lista) {
                  final m = d.data() as Map<String, dynamic>;
                  soma += (m['nota'] ?? 5) as num;
                }
                final double media = soma / lista.length;
                final String mediaStr = media.toStringAsFixed(1);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.06),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: Colors.amber.shade700,
                                size: 40,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mediaStr,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A1A2E),
                                        height: 1,
                                      ),
                                    ),
                                    Text(
                                      'Média com base em ${lista.length} ${lista.length == 1 ? 'avaliação' : 'avaliações'}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: lista.length,
                        itemBuilder: (context, index) {
                          final docSnap = lista[index];
                          final avaliacao =
                              docSnap.data() as Map<String, dynamic>;
                          final String avaliacaoId = docSnap.id;
                          final int nota = (avaliacao['nota'] ?? 5) is num
                              ? (avaliacao['nota'] as num).toInt()
                              : 5;
                          final String comentario =
                              avaliacao['comentario']?.toString() ?? '';
                          final String respostaLoja =
                              avaliacao['resposta_loja']?.toString() ?? '';
                          final Timestamp? ts = avaliacao['data'] as Timestamp?;
                          final String? dataLegivel =
                              ts != null ? _formatarDataHoraAvaliacao(ts.toDate()) : null;
                          final String? pedidoIdRaw =
                              avaliacao['pedido_id']?.toString();
                          final String pedidoCurto = (pedidoIdRaw != null &&
                                  pedidoIdRaw.length > 8)
                              ? pedidoIdRaw.substring(pedidoIdRaw.length - 8).toUpperCase()
                              : (pedidoIdRaw ?? '').toUpperCase();
                          final String nomeCliente =
                              avaliacao['cliente_nome_exibicao']?.toString() ?? '';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              elevation: 1,
                              shadowColor: Colors.black.withValues(alpha: 0.06),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (dataLegivel != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Text(
                                          dataLegivel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    if (pedidoCurto.isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.receipt_long_outlined,
                                              size: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Pedido · $pedidoCurto',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (nomeCliente.isNotEmpty) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Text(
                                          'Cliente: $nomeCliente',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Row(
                                      children: [
                                        ...List.generate(5, (starIndex) {
                                          return Icon(
                                            starIndex < nota
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            color: Colors.amber.shade700,
                                            size: 22,
                                          );
                                        }),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF8E1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '$nota ${nota == 1 ? 'estrela' : 'estrelas'}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (comentario.isNotEmpty)
                                      Text(
                                        '“$comentario”',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontStyle: FontStyle.italic,
                                          height: 1.4,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      )
                                    else
                                      Text(
                                        'Cliente não escreveu comentário.',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    const SizedBox(height: 14),
                                    if (respostaLoja.isEmpty)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _abrirDialogoResposta(
                                                context,
                                                avaliacaoId,
                                              ),
                                          icon: const Icon(
                                            Icons.reply_rounded,
                                            size: 20,
                                          ),
                                          label: const Text('Responder'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor: diPertinRoxo,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5F4F8),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: const Border(
                                            left: BorderSide(
                                              color: diPertinLaranja,
                                              width: 4,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.storefront_outlined,
                                                  size: 16,
                                                  color: Colors.grey.shade700,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Sua resposta',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              respostaLoja,
                                              style: const TextStyle(
                                                color: Color(0xFF1A1A2E),
                                                fontSize: 14,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _DialogoRespostaAvaliacao extends StatefulWidget {
  const _DialogoRespostaAvaliacao({required this.avaliacaoId});

  final String avaliacaoId;

  @override
  State<_DialogoRespostaAvaliacao> createState() =>
      _DialogoRespostaAvaliacaoState();
}

class _DialogoRespostaAvaliacaoState extends State<_DialogoRespostaAvaliacao> {
  late final TextEditingController _controller;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite uma resposta antes de enviar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('avaliacoes')
          .doc(widget.avaliacaoId)
          .update({
            'resposta_loja': _controller.text.trim(),
            'data_resposta': FieldValue.serverTimestamp(),
          });

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Resposta publicada.'),
          backgroundColor: Colors.green,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.reply_rounded, color: diPertinLaranja),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Responder cliente',
              style: TextStyle(
                color: diPertinRoxo,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText:
                'Agradecimento, esclarecimento ou retratação — seja cordial.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFFF8F7FA),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: Text(
            'Cancelar',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          style: FilledButton.styleFrom(backgroundColor: diPertinLaranja),
          child: _enviando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Enviar resposta'),
        ),
      ],
    );
  }
}
