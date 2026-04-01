// Arquivo: lib/screens/cliente/loja_catalogo_screen.dart

import 'package:depertin_cliente/screens/cliente/product_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojaCatalogoScreen extends StatelessWidget {
  final String lojaId;
  final String nomeLoja;

  const LojaCatalogoScreen({
    super.key,
    required this.lojaId,
    required this.nomeLoja,
  });

  Widget _buildProductCard(BuildContext context, Map<String, dynamic> produto) {
    String imagemVitrine = '';
    if (produto.containsKey('imagens') &&
        produto['imagens'] is List &&
        (produto['imagens'] as List).isNotEmpty) {
      imagemVitrine = produto['imagens'][0];
    } else {
      imagemVitrine = produto['imagem'] ?? '';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(produto: produto),
          ),
        );
      },
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: imagemVitrine.isNotEmpty
                    ? Image.network(imagemVitrine, fit: BoxFit.cover)
                    : const Icon(
                        Icons.image_not_supported,
                        size: 50,
                        color: Colors.grey,
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto["nome"] ?? "Sem nome",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      produto["descricao"] ?? "",
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      "R\$ ${((produto["oferta"] ?? produto["preco"] ?? 0.0) as num).toDouble().toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: diPertinRoxo,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          nomeLoja,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Busca apenas os produtos DESSA loja específica e que estejam ATIVOS
        stream: FirebaseFirestore.instance
            .collection('produtos')
            .where('lojista_id', isEqualTo: lojaId)
            .where('ativo', isEqualTo: true)
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
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Esta loja ainda não possui produtos ativos.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          var produtos = snapshot.data!.docs;

          return GridView.builder(
            padding: const EdgeInsets.all(15),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // 2 produtos por linha
              childAspectRatio: 0.75, // Proporção da altura do card
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              var p = produtos[index].data() as Map<String, dynamic>;
              p['id_documento'] = produtos[index].id;

              // Injetamos a loja_id e o nome da loja no produto para o Carrinho não se perder!
              p['loja_id'] = lojaId;
              p['loja_nome_vitrine'] = nomeLoja;

              return _buildProductCard(context, p);
            },
          );
        },
      ),
    );
  }
}
