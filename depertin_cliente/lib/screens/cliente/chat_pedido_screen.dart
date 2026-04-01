// Arquivo: lib/screens/cliente/chat_pedido_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class ChatPedidoScreen extends StatefulWidget {
  final String pedidoId;
  final String lojaId;
  final String lojaNome;

  const ChatPedidoScreen({
    super.key,
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
  });

  @override
  State<ChatPedidoScreen> createState() => _ChatPedidoScreenState();
}

class _ChatPedidoScreenState extends State<ChatPedidoScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final String _meuId = FirebaseAuth.instance.currentUser?.uid ?? '';

  void _enviarMensagem() async {
    String texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;

    _mensagemController.clear();

    await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.pedidoId)
        .collection('mensagens')
        .add({
          'texto': texto,
          'remetente_id': _meuId,
          'data_envio': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.lojaNome,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            Text(
              "Pedido #${widget.pedidoId.substring(0, 5).toUpperCase()}",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .doc(widget.pedidoId)
                  .collection('mensagens')
                  .orderBy('data_envio', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinRoxo),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Nenhuma mensagem ainda.",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const Text(
                          "Envie uma mensagem para a loja!",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                var mensagens = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true, // Começa de baixo para cima (padrão WhatsApp)
                  padding: const EdgeInsets.all(15),
                  itemCount: mensagens.length,
                  itemBuilder: (context, index) {
                    var msg = mensagens[index].data() as Map<String, dynamic>;
                    bool souEu = msg['remetente_id'] == _meuId;

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
                          color: souEu ? diPertinRoxo : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(15),
                            topRight: const Radius.circular(15),
                            bottomLeft: Radius.circular(souEu ? 15 : 0),
                            bottomRight: Radius.circular(souEu ? 0 : 15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Text(
                          msg['texto'] ?? '',
                          style: TextStyle(
                            color: souEu ? Colors.white : Colors.black87,
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

          // BARRA DE DIGITAÇÃO
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensagemController,
                      decoration: InputDecoration(
                        hintText: "Digite sua mensagem...",
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: const BorderSide(color: diPertinRoxo),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: diPertinLaranja,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _enviarMensagem,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
