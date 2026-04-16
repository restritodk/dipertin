// Arquivo: lib/screens/cliente/loja_catalogo_screen.dart

import 'dart:async';
import 'package:depertin_cliente/screens/cliente/product_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/loja_pausa.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojaCatalogoScreen extends StatefulWidget {
  final String lojaId;
  final String nomeLoja;

  const LojaCatalogoScreen({
    super.key,
    required this.lojaId,
    required this.nomeLoja,
  });

  @override
  State<LojaCatalogoScreen> createState() => _LojaCatalogoScreenState();
}

class _LojaCatalogoScreenState extends State<LojaCatalogoScreen> {
  bool _lojaAberta = true;
  StreamSubscription<DocumentSnapshot>? _subLoja;
  Timer? _timerReavalia;

  @override
  void initState() {
    super.initState();
    _timerReavalia = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) setState(() {});
    });
    _subLoja = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.lojaId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final dados = snap.data() as Map<String, dynamic>;
      final bool aberta = LojaPausa.lojaEstaAberta(dados);
      if (aberta != _lojaAberta) setState(() => _lojaAberta = aberta);
    });
  }

  @override
  void dispose() {
    _timerReavalia?.cancel();
    _subLoja?.cancel();
    super.dispose();
  }

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imagemVitrine.isNotEmpty
                        ? Image.network(imagemVitrine, fit: BoxFit.cover)
                        : const Icon(
                            Icons.image_not_supported,
                            size: 50,
                            color: Colors.grey,
                          ),
                    if (!_lojaAberta)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    if (!_lojaAberta)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Fechada',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
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
          widget.nomeLoja,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('produtos')
            .where('lojista_id', isEqualTo: widget.lojaId)
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
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              var p = produtos[index].data() as Map<String, dynamic>;
              p['id_documento'] = produtos[index].id;
              p['loja_id'] = widget.lojaId;
              p['loja_nome_vitrine'] = widget.nomeLoja;
              p['loja_aberta'] = _lojaAberta;

              return _buildProductCard(context, p);
            },
          );
        },
      ),
    );
  }
}
