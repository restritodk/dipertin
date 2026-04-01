// Arquivo: lib/screens/lojista/lojista_pedidos_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojistaPedidosScreen extends StatefulWidget {
  const LojistaPedidosScreen({super.key});

  @override
  State<LojistaPedidosScreen> createState() => _LojistaPedidosScreenState();
}

class _LojistaPedidosScreenState extends State<LojistaPedidosScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pedidosSubscription;
  bool _primeiroCarregamento = true;

  @override
  void initState() {
    super.initState();
    _iniciarVigiaDePedidos();
  }

  @override
  void dispose() {
    _pedidosSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _iniciarVigiaDePedidos() {
    _pedidosSubscription = FirebaseFirestore.instance
        .collection('pedidos')
        .where('loja_id', isEqualTo: _uid)
        .snapshots()
        .listen((snapshot) {
          if (_primeiroCarregamento) {
            _primeiroCarregamento = false;
            return;
          }

          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              var pedido = change.doc.data() as Map<String, dynamic>;
              if (pedido['status'] == 'pendente') {
                _tocarSom();
              }
            }
          }
        });
  }

  Future<void> _tocarSom() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/campainha.mp3'));
    } catch (e) {
      debugPrint("Erro ao tocar som: $e");
    }
  }

  Future<void> _atualizarStatusPedido(
    String pedidoId,
    String novoStatus,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .update({'status': novoStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido atualizado para: $novoStatus!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==========================================
  // NOVA FUNÇÃO: ESTORNO DE FRETE PARA O CLIENTE
  // ==========================================
  Future<void> _confirmarRetiradaComEstorno(
    String pedidoId,
    String clienteId,
    double taxaEntrega,
  ) async {
    // 1. Pede confirmação para o Lojista
    bool confirmacao =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              "Confirmar Retirada?",
              style: TextStyle(color: diPertinLaranja),
            ),
            content: Text(
              "O cliente decidiu vir buscar o pedido?\n\n"
              "Ao confirmar, o valor de R\$ ${taxaEntrega.toStringAsFixed(2)} referente à entrega "
              "será estornado e devolvido imediatamente para a Carteira do Cliente no aplicativo.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Cancelar",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: diPertinLaranja,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Sim, Estornar Frete",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmacao) return;

    try {
      // 2. Devolve o dinheiro para o saldo do Cliente
      if (taxaEntrega > 0) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(clienteId)
            .update({'saldo': FieldValue.increment(taxaEntrega)});
      }

      // 3. Finaliza o pedido marcando que o frete foi estornado
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .update({
            'status': 'entregue', // Entregue ao cliente em mãos
            'frete_estornado': true,
            'data_entregue': FieldValue.serverTimestamp(),
            'observacao_loja':
                'Cliente retirou na loja. Frete estornado para a carteira.',
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pedido finalizado e Frete devolvido ao Cliente!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao estornar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return "Agora";
    DateTime data = timestamp.toDate();
    return "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text(
            "Gestão de Pedidos",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: diPertinLaranja,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: "🔔 Novos", icon: Icon(Icons.notifications_active)),
              Tab(text: "👨‍🍳 Andamento", icon: Icon(Icons.soup_kitchen)),
              Tab(text: "✅ Histórico", icon: Icon(Icons.history)),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('pedidos')
              .where('loja_id', isEqualTo: _uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: diPertinLaranja),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildTelaVazia();
            }

            var todosPedidos = snapshot.data!.docs.toList();
            todosPedidos.sort((a, b) {
              Timestamp? tA = (a.data() as Map)['data_pedido'];
              Timestamp? tB = (b.data() as Map)['data_pedido'];
              if (tA == null || tB == null) return 0;
              return tB.compareTo(tA);
            });

            var novos = todosPedidos
                .where((p) => (p.data() as Map)['status'] == 'pendente')
                .toList();

            var andamento = todosPedidos
                .where(
                  (p) => [
                    'aceito',
                    'em_preparo',
                    'a_caminho',
                    'em_rota',
                    'pronto',
                  ].contains((p.data() as Map)['status']),
                )
                .toList();

            var historico = todosPedidos
                .where(
                  (p) => [
                    'entregue',
                    'cancelado',
                  ].contains((p.data() as Map)['status']),
                )
                .toList();

            return TabBarView(
              children: [
                _buildListaPedidos(novos, "Nenhum pedido novo."),
                _buildListaPedidos(andamento, "Nenhum pedido em andamento."),
                _buildListaPedidos(historico, "Histórico vazio."),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTelaVazia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text(
            "Nenhum pedido recebido ainda.",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildListaPedidos(
    List<QueryDocumentSnapshot> pedidos,
    String mensagemVazia,
  ) {
    if (pedidos.isEmpty) {
      return Center(
        child: Text(mensagemVazia, style: const TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: pedidos.length,
      itemBuilder: (context, index) {
        var pedido = pedidos[index].data() as Map<String, dynamic>;
        String id = pedidos[index].id;
        String status = pedido['status'] ?? 'pendente';
        bool isRetirada = pedido['tipo_entrega'] == 'retirada';
        List<dynamic> itens = pedido['itens'] ?? [];
        String clienteId =
            pedido['cliente_id'] ?? ''; // Essencial para o estorno

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Pedido #${id.substring(0, 5).toUpperCase()}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatarData(pedido['data_pedido']),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(
                      isRetirada ? Icons.storefront : Icons.two_wheeler,
                      color: isRetirada ? diPertinLaranja : diPertinRoxo,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRetirada
                            ? "RETIRADA NO BALCÃO"
                            : "ENTREGA: ${pedido['endereco_entrega']}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isRetirada ? diPertinLaranja : diPertinRoxo,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...itens.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Text(
                          "${item['quantidade']}x ",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(child: Text(item['nome'])),
                        Text("R\$ ${item['preco'].toStringAsFixed(2)}"),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Builder(
                  builder: (context) {
                    double subtotal = (pedido['subtotal'] ?? 0.0).toDouble();
                    double taxaEntrega = (pedido['taxa_entrega'] ?? 0.0)
                        .toDouble();
                    double seuRecebimento =
                        subtotal; // A loja fica com o subtotal dos lanches

                    return Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isRetirada
                                  ? "MODO: RETIRADA"
                                  : "MODO: ENTREGA APP/PRÓPRIA",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Produtos: R\$ ${subtotal.toStringAsFixed(2)}",
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        if (!isRetirada)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Taxa de Entrega (App):",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                "R\$ ${taxaEntrega.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "SEU RECEBIMENTO:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              "R\$ ${seuRecebimento.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 15),

                // ==========================================
                // BOTÕES DE AÇÃO DO LOJISTA
                // ==========================================
                if (status == 'pendente')
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () =>
                              _atualizarStatusPedido(id, 'cancelado'),
                          child: const Text("RECUSAR"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: () =>
                              _atualizarStatusPedido(id, 'em_preparo'),
                          child: const Text(
                            "ACEITAR",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (status == 'em_preparo')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                      ),
                      onPressed: () => _atualizarStatusPedido(
                        id,
                        isRetirada ? 'pronto' : 'a_caminho',
                      ),
                      child: Text(
                        isRetirada
                            ? "PRONTO PARA RETIRADA"
                            : "MANDAR PARA ENTREGA",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (status == 'em_rota' ||
                    status == 'a_caminho' ||
                    status == 'pronto')
                  Column(
                    children: [
                      if (isRetirada)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () =>
                                _atualizarStatusPedido(id, 'entregue'),
                            child: const Text(
                              "CONFIRMAR RETIRADA NO BALCÃO",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        // Se for pedido de entrega, a Loja tem a opção de fechar com Token (Entrega Própria)
                        // OU estornar se o cliente for lá buscar
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                "FINALIZAR ENTREGA (MOTOBOY DA LOJA)",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                decoration: const InputDecoration(
                                  hintText: "Digite o Token do Cliente",
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                                keyboardType: TextInputType.text,
                                onSubmitted: (value) async {
                                  // Lógica inteligente de Token (Fallback igual do entregador)
                                  String tokenReal =
                                      pedido['token_entrega']?.toString() ?? '';
                                  if (tokenReal.isEmpty && id.length >= 6) {
                                    tokenReal = id
                                        .substring(id.length - 6)
                                        .toUpperCase();
                                  }

                                  if (value.trim().toUpperCase() ==
                                      tokenReal.toUpperCase()) {
                                    _atualizarStatusPedido(id, 'entregue');
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Token incorreto!"),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  "Seu entregador voltou? Digite o código aqui.",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // O NOVO BOTÃO DE ESTORNO CASO O CLIENTE APAREÇA NA LOJA
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: diPertinLaranja,
                              side: const BorderSide(
                                color: diPertinLaranja,
                                width: 2,
                              ),
                            ),
                            icon: const Icon(Icons.directions_walk),
                            label: const Text(
                              "CLIENTE VEIO BUSCAR (ESTORNAR FRETE)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () {
                              double taxaEntrega =
                                  (pedido['taxa_entrega'] ?? 0.0).toDouble();
                              _confirmarRetiradaComEstorno(
                                id,
                                clienteId,
                                taxaEntrega,
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Center(
                    child: Chip(
                      label: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: status == 'entregue'
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
