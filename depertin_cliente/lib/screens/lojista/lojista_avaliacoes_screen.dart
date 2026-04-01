// Arquivo: lib/screens/lojista/lojista_avaliacoes_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaAvaliacoesScreen extends StatelessWidget {
  const LojistaAvaliacoesScreen({super.key});

  // Função para abrir a caixinha de resposta do lojista
  void _responderAvaliacao(BuildContext context, String avaliacaoId) {
    final TextEditingController respostaController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(Icons.reply, color: diPertinLaranja),
              SizedBox(width: 8),
              Text(
                "Responder Cliente",
                style: TextStyle(
                  color: diPertinLaranja,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: TextField(
            controller: respostaController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: "Escreva sua resposta (agradecimento ou retratação)...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (respostaController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('A resposta não pode ser vazia.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Atualiza o documento da avaliação com a resposta da loja
                await FirebaseFirestore.instance
                    .collection('avaliacoes')
                    .doc(avaliacaoId)
                    .update({
                      'resposta_loja': respostaController.text.trim(),
                      'data_resposta': FieldValue.serverTimestamp(),
                    });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Resposta enviada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: diPertinLaranja),
              child: const Text(
                "ENVIAR RESPOSTA",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Minhas Avaliações",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinLaranja,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(child: Text("Erro de autenticação."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('avaliacoes')
                  .where('loja_id', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinLaranja),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star_border,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          "Você ainda não recebeu avaliações.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                var listaAvaliacoes = snapshot.data!.docs.toList();

                // Organiza da mais nova para a mais velha (para evitar erro de índice no Firebase)
                listaAvaliacoes.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;
                  Timestamp timeA =
                      dataA['data'] as Timestamp? ??
                      Timestamp.fromMillisecondsSinceEpoch(0);
                  Timestamp timeB =
                      dataB['data'] as Timestamp? ??
                      Timestamp.fromMillisecondsSinceEpoch(0);
                  return timeB.compareTo(timeA);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: listaAvaliacoes.length,
                  itemBuilder: (context, index) {
                    var avaliacao =
                        listaAvaliacoes[index].data() as Map<String, dynamic>;
                    String avaliacaoId = listaAvaliacoes[index].id;
                    int nota = avaliacao['nota'] ?? 5;
                    String comentario = avaliacao['comentario'] ?? '';
                    String respostaLoja = avaliacao['resposta_loja'] ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // As Estrelinhas
                            Row(
                              children: [
                                Row(
                                  children: List.generate(5, (starIndex) {
                                    return Icon(
                                      starIndex < nota
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 20,
                                    );
                                  }),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "$nota.0",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // O Comentário do Cliente
                            if (comentario.isNotEmpty)
                              Text(
                                '"$comentario"',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black87,
                                ),
                              )
                            else
                              const Text(
                                "O cliente avaliou sem deixar comentários.",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),

                            const SizedBox(height: 15),

                            // A Mágica: Mostra o botão de responder ou a resposta já enviada!
                            if (respostaLoja.isEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _responderAvaliacao(context, avaliacaoId),
                                  icon: const Icon(
                                    Icons.reply,
                                    color: diPertinLaranja,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    "RESPONDER",
                                    style: TextStyle(
                                      color: diPertinLaranja,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(10),
                                  border: const Border(
                                    left: BorderSide(
                                      color: diPertinLaranja,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.storefront,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          "Sua Resposta:",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      respostaLoja,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
