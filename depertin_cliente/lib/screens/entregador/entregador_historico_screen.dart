// Arquivo: lib/screens/entregador/entregador_historico_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Para formatar a data da corrida

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class EntregadorHistoricoScreen extends StatefulWidget {
  const EntregadorHistoricoScreen({super.key});

  @override
  State<EntregadorHistoricoScreen> createState() =>
      _EntregadorHistoricoScreenState();
}

class _EntregadorHistoricoScreenState extends State<EntregadorHistoricoScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    String? uid = _auth.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("Usuário não autenticado.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Histórico de Corridas",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // A MÁGICA DOS FILTROS: Traz só os pedidos DELE que estão ENTREGUES
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .where('entregador_id', isEqualTo: uid)
            .where('status', isEqualTo: 'entregue')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            );
          }

          // Se não houver corridas finalizadas
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_toggle_off,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Nenhuma corrida finalizada ainda.",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Suas entregas concluídas aparecerão aqui.",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          var pedidos = snapshot.data!.docs;

          // Ordenar localmente do mais recente para o mais antigo
          // (Fazemos isso aqui para não exigir criação de índices complexos no Firebase agora)
          pedidos.sort((a, b) {
            var dataA =
                (a.data() as Map<String, dynamic>)['data_pedido'] as Timestamp?;
            var dataB =
                (b.data() as Map<String, dynamic>)['data_pedido'] as Timestamp?;
            if (dataA == null) return 1;
            if (dataB == null) return -1;
            return dataB.compareTo(
              dataA,
            ); // Invertido para o mais novo ficar no topo
          });

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: pedidos.length,
            itemBuilder: (context, index) {
              var pedido = pedidos[index].data() as Map<String, dynamic>;

              String loja = pedido['loja_nome'] ?? 'Loja Parceira';
              String endereco =
                  pedido['endereco_entrega'] ?? 'Endereço não informado';

              // Agora ele vê apenas a taxa de entrega que ganhou!
              double valor = (pedido['taxa_entrega'] ?? 0.0).toDouble();

              String dataFormatada = "--/--/----";
              if (pedido['data_pedido'] != null) {
                DateTime data = (pedido['data_pedido'] as Timestamp).toDate();
                dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(data);
              }

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
                            dataFormatada,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "CONCLUÍDO",
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        children: [
                          const Icon(
                            Icons.store,
                            color: diPertinRoxo,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loja,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              endereco,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Ganho: R\$ ${valor.toStringAsFixed(2)}", // Adicionei a palavra "Ganho:"
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: diPertinLaranja,
                          ),
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
