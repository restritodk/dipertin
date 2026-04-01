// Arquivo: lib/screens/cliente/chat_suporte_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(
  0xFFFF8F00,
); // ADICIONADO A COR LARANJA AQUI

class ChatSuporteScreen extends StatefulWidget {
  const ChatSuporteScreen({super.key});

  @override
  State<ChatSuporteScreen> createState() => _ChatSuporteScreenState();
}

class _ChatSuporteScreenState extends State<ChatSuporteScreen> {
  final TextEditingController _mensagemController = TextEditingController();

  Future<void> _enviarMensagem() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String meuId = user.uid;
    String texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;

    _mensagemController.clear();

    try {
      await FirebaseFirestore.instance
          .collection('suporte')
          .doc(meuId)
          .collection('mensagens')
          .add({
            'texto': texto,
            'remetente_id': meuId,
            'data_envio': FieldValue.serverTimestamp(),
          });

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(meuId)
          .get();
      String nomeCliente = (userDoc.exists && userDoc.data() != null)
          ? (userDoc.data() as Map<String, dynamic>)['nome'] ?? 'Cliente'
          : 'Cliente';

      await FirebaseFirestore.instance.collection('suporte').doc(meuId).set({
        'cliente_id': meuId,
        'cliente_nome': nomeCliente,
        'ultima_mensagem': texto,
        'data_atualizacao': FieldValue.serverTimestamp(),
        'status': 'aguardando_admin',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Erro: $e");
    }
  }

  // ==========================================
  // NOVO: REABRIR O CHAMADO
  // ==========================================
  Future<void> _reabrirChamado() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('suporte').doc(user.uid).update(
      {
        'status': 'aguardando_admin', // Volta a ficar vermelho lá no painel!
        'ultima_mensagem': 'O cliente reabriu o chamado.',
        'data_atualizacao': FieldValue.serverTimestamp(),
      },
    );

    // Manda uma mensagem automática do sistema
    await FirebaseFirestore.instance
        .collection('suporte')
        .doc(user.uid)
        .collection('mensagens')
        .add({
          'texto': '--- NOVO ATENDIMENTO INICIADO ---',
          'remetente_id': 'sistema',
          'data_envio': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text(
              "Central de Ajuda",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(child: Text("Erro de autenticação."))
          // ESCUTANDO O DOCUMENTO PRINCIPAL (Para saber o Status)
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('suporte')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshotDoc) {
                // Descobre se o chamado está encerrado
                bool estaEncerrado = false;
                if (snapshotDoc.hasData && snapshotDoc.data!.exists) {
                  estaEncerrado = snapshotDoc.data!['status'] == 'encerrado';
                }

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: estaEncerrado
                          ? Colors.green[100]
                          : Colors.amber[100],
                      child: Row(
                        children: [
                          Icon(
                            estaEncerrado
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: Colors.black87,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              estaEncerrado
                                  ? "Atendimento concluído. Precisando, é só abrir um novo chamado abaixo!"
                                  : "Nossa equipe de suporte responderá o mais rápido possível.",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ÁREA DAS MENSAGENS
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('suporte')
                            .doc(user.uid)
                            .collection('mensagens')
                            .orderBy('data_envio', descending: true)
                            .snapshots(),
                        builder: (context, snapshotMsg) {
                          if (snapshotMsg.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: diPertinRoxo,
                              ),
                            );
                          }
                          if (!snapshotMsg.hasData ||
                              snapshotMsg.data!.docs.isEmpty) {
                            return const Center(
                              child: Text(
                                "Envie a primeira mensagem.",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            );
                          }

                          var mensagens = snapshotMsg.data!.docs;

                          return ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(15),
                            itemCount: mensagens.length,
                            itemBuilder: (context, index) {
                              var msg =
                                  mensagens[index].data()
                                      as Map<String, dynamic>;

                              // Mensagem do Sistema (Divisor)
                              if (msg['remetente_id'] == 'sistema') {
                                return Center(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      msg['texto'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              bool souEu = msg['remetente_id'] == user.uid;

                              return Align(
                                alignment: souEu
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    // MUDANÇA NAS CORES AQUI: Roxo se for 'souEu', Laranja se for o outro
                                    color: souEu
                                        ? diPertinRoxo
                                        : diPertinLaranja,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(15),
                                      topRight: const Radius.circular(15),
                                      bottomLeft: souEu
                                          ? const Radius.circular(15)
                                          : const Radius.circular(0),
                                      bottomRight: souEu
                                          ? const Radius.circular(0)
                                          : const Radius.circular(15),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    msg['texto'] ?? '',
                                    // MUDANÇA NAS CORES AQUI: Texto branco sempre
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // ==========================================
                    // RODAPÉ: MOSTRA A DIGITAÇÃO OU O BOTÃO "NOVO CHAMADO"
                    // ==========================================
                    Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.white,
                      child: SafeArea(
                        child: estaEncerrado
                            ? SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _reabrirChamado,
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: diPertinRoxo,
                                  ),
                                  label: const Text(
                                    "ABRIR NOVO ATENDIMENTO",
                                    style: TextStyle(
                                      color: diPertinRoxo,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: diPertinRoxo.withOpacity(
                                      0.1,
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _mensagemController,
                                      decoration: InputDecoration(
                                        hintText:
                                            "Dúvida, sugestão ou reclamação...",
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey[100],
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 10,
                                            ),
                                      ),
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: diPertinRoxo,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.send,
                                        color: Colors.white,
                                      ),
                                      onPressed: _enviarMensagem,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
