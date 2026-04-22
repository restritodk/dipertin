// Arquivo: lib/screens/cliente/chat_pedido_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

/// Chat simples da subcoleção `pedidos/{id}/mensagens`.
///
/// Reutilizado pelos dois lados:
/// - Cliente: abre pelo card em "Meus pedidos".
/// - Lojista: abre pelo card em "Gestão de pedidos".
///
/// Quando o pedido vai para `entregue`/`cancelado`, a caixa de texto some e a
/// conversa fica em modo leitura (as rules do Firestore já bloqueiam novos
/// `create` nessa subcoleção nesse estado).
class ChatPedidoScreen extends StatefulWidget {
  final String pedidoId;
  final String lojaId;
  final String lojaNome;

  /// Título principal no AppBar (default = `lojaNome`, mantido para uso atual
  /// do cliente). Lojista passa o nome do cliente.
  final String? tituloOverride;

  /// Subtítulo no AppBar (default = "Pedido #XXXXX").
  final String? subtituloOverride;

  const ChatPedidoScreen({
    super.key,
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
    this.tituloOverride,
    this.subtituloOverride,
  });

  /// Chave local usada para marcar "lido até" por pedido + usuário. O valor é
  /// um timestamp em ms. Contadores do card do pedido usam isso para mostrar
  /// o badge de mensagens novas.
  static String chaveLidoAte(String pedidoId, String uid) {
    return 'chat_pedido_lido_ate_${pedidoId}_$uid';
  }

  /// Lê "lido até" deste pedido para este usuário. `0` quando ainda não leu.
  static Future<int> lidoAteMs(String pedidoId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(chaveLidoAte(pedidoId, uid)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Marca como lido no momento atual do dispositivo.
  static Future<void> marcarLidoAgora(String pedidoId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        chaveLidoAte(pedidoId, uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // best-effort — badge é apenas visual, sem persistência crítica.
    }
  }

  @override
  State<ChatPedidoScreen> createState() => _ChatPedidoScreenState();
}

class _ChatPedidoScreenState extends State<ChatPedidoScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final String _meuId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Marca "lido até agora" ao abrir, e repete sempre que chegar mensagem
    // nova (via _atualizarLidoAte na stream das mensagens).
    _atualizarLidoAte();
  }

  @override
  void dispose() {
    // Ao sair, atualiza novamente para cobrir mensagens lidas durante a sessão.
    _atualizarLidoAte();
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _atualizarLidoAte() async {
    if (_meuId.isEmpty) return;
    await ChatPedidoScreen.marcarLidoAgora(widget.pedidoId, _meuId);
  }

  Future<void> _enviarMensagem() async {
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

    // Logo após enviar minha própria mensagem, atualizo "lido até" para evitar
    // badge indevido na minha caixa.
    await _atualizarLidoAte();
  }

  static bool _chatEncerrado(String? status) {
    final s = status ?? '';
    return s == 'entregue' || s == 'cancelado';
  }

  @override
  Widget build(BuildContext context) {
    final tituloPrincipal = widget.tituloOverride?.trim().isNotEmpty == true
        ? widget.tituloOverride!.trim()
        : widget.lojaNome;
    final subtituloPadrao =
        "Pedido #${widget.pedidoId.substring(0, widget.pedidoId.length >= 5 ? 5 : widget.pedidoId.length).toUpperCase()}";
    final subtitulo = widget.subtituloOverride?.trim().isNotEmpty == true
        ? widget.subtituloOverride!.trim()
        : subtituloPadrao;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tituloPrincipal,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            Text(
              subtitulo,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .doc(widget.pedidoId)
            .snapshots(),
        builder: (context, pedidoSnap) {
          final st = pedidoSnap.data?.data()?['status']?.toString();
          final encerrado = _chatEncerrado(st);

          return Column(
            children: [
              if (encerrado)
                Material(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade900),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            st == 'cancelado'
                                ? 'Pedido cancelado. O chat está somente leitura.'
                                : 'Pedido entregue. O chat está somente leitura.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade900,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('pedidos')
                      .doc(widget.pedidoId)
                      .collection('mensagens')
                      .orderBy('data_envio', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    // Marca como lido sempre que houver mudança na stream e
                    // a tela continuar montada — assim o badge do card zera
                    // enquanto a conversa está aberta.
                    if (snapshot.hasData && mounted) {
                      _atualizarLidoAte();
                    }

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
                            Text(
                              encerrado
                                  ? 'Nenhuma conversa foi registrada neste pedido.'
                                  : 'Envie uma mensagem para iniciar.',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    var mensagens = snapshot.data!.docs;

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(15),
                      itemCount: mensagens.length,
                      itemBuilder: (context, index) {
                        var msg =
                            mensagens[index].data() as Map<String, dynamic>;
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
                                  color: Colors.black.withValues(alpha: 0.05),
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

              if (!encerrado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
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
          );
        },
      ),
    );
  }
}
