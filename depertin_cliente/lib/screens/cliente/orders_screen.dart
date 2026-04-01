// Arquivo: lib/screens/cliente/orders_screen.dart

import 'package:depertin_cliente/screens/cliente/chat_pedido_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  void _mostrarDetalhesPedido(
    BuildContext context,
    Map<String, dynamic> pedido,
  ) {
    List<dynamic> itens = pedido['itens'] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Resumo do Pedido",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: diPertinRoxo,
                ),
              ),
              const Divider(),
              const SizedBox(height: 10),
              ...itens.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${item['quantidade']}x ${item['nome']}",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "R\$ ${(item['preco'] * item['quantidade']).toStringAsFixed(2)}",
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              _rowFinanceira("Subtotal", pedido['subtotal']),
              _rowFinanceira("Taxa de Entrega", pedido['taxa_entrega']),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "TOTAL",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    "R\$ ${pedido['total']?.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: diPertinLaranja,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              const Text(
                "Endereço de Entrega",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                pedido['endereco_entrega'] ?? 'Não informado',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowFinanceira(String rotulo, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: const TextStyle(color: Colors.grey)),
          Text("R\$ ${(valor ?? 0.0).toStringAsFixed(2)}"),
        ],
      ),
    );
  }

  Widget _construirStatus(String statusDb) {
    String texto = "Processando";
    Color cor = Colors.grey;
    switch (statusDb) {
      case 'pendente':
        texto = "Aguardando Loja";
        cor = Colors.orange;
        break;
      case 'aceito':
      case 'em_preparo':
        texto = "Preparando";
        cor = Colors.blue;
        break;
      case 'a_caminho':
      case 'em_rota':
        texto = "Em Entrega";
        cor = Colors.teal;
        break;
      case 'entregue':
        texto = "Entregue";
        cor = Colors.green;
        break;
      case 'cancelado':
        texto = "Cancelado";
        cor = Colors.red;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meus Pedidos"),
        backgroundColor: diPertinRoxo,
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text("Faça login para ver seus pedidos"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .where('cliente_id', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data!.docs;

                // Ordenar pedidos do mais novo para o mais antigo localmente
                docs.sort((a, b) {
                  var dataA =
                      (a.data() as Map<String, dynamic>)['data_pedido']
                          as Timestamp?;
                  var dataB =
                      (b.data() as Map<String, dynamic>)['data_pedido']
                          as Timestamp?;
                  if (dataA == null) return 1;
                  if (dataB == null) return -1;
                  return dataB.compareTo(dataA);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    String pedidoId = docs[index].id;
                    var pedido = docs[index].data() as Map<String, dynamic>;
                    String statusAtual = pedido['status'] ?? 'pendente';

                    // LÓGICA DO TOKEN (pega do banco ou gera fallback com 6 letras do ID)
                    String tokenReal =
                        pedido['token_entrega']?.toString() ?? '';
                    if (tokenReal.isEmpty && pedidoId.length >= 6) {
                      tokenReal = pedidoId
                          .substring(pedidoId.length - 6)
                          .toUpperCase();
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  pedido['loja_nome'] ?? 'Loja',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                _construirStatus(statusAtual),
                              ],
                            ),

                            // ==========================================
                            // NOVA CAIXA DE TOKEN DO CLIENTE
                            // ==========================================
                            if (statusAtual == 'a_caminho' ||
                                statusAtual == 'em_rota') ...[
                              const SizedBox(height: 15),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.motorcycle,
                                          color: Colors.green,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "O Entregador está a caminho!",
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      "Informe o código abaixo ao entregador para receber seu pedido:",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.withOpacity(0.2),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: SelectableText(
                                        tokenReal,
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 8,
                                          color: diPertinRoxo,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // ==========================================
                            const Divider(height: 25),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _mostrarDetalhesPedido(context, pedido),
                                    child: const Text("VER DETALHES"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(
                                    Icons.chat_outlined,
                                    color: diPertinRoxo,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatPedidoScreen(
                                          pedidoId: pedidoId,
                                          lojaId: pedido['loja_id'] ?? '',
                                          lojaNome:
                                              pedido['loja_nome'] ?? 'Loja',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
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
