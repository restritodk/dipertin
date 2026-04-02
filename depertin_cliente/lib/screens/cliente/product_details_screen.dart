// Arquivo: lib/screens/cliente/product_details_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/cart_provider.dart';
import '../../models/cart_item_model.dart';
import 'cart_screen.dart';
import 'loja_perfil_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class ProductDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> produto;

  const ProductDetailsScreen({super.key, required this.produto});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Map<String, dynamic>? _dadosLojista;

  @override
  void initState() {
    super.initState();
    _carregarDadosLojista();
  }

  Future<void> _carregarDadosLojista() async {
    String? lojistaId = widget.produto['lojista_id'] ?? widget.produto['loja_id'];
    if (lojistaId != null) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(lojistaId)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _dadosLojista = doc.data() as Map<String, dynamic>;
          });
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados da loja: $e");
      }
    }
  }

  void _adicionarAoCarrinho(CartProvider cart) {
    if (widget.produto['loja_aberta'] == false) return;

    final productItem = CartItemModel(
      id: widget.produto['id_documento'] ?? '',
      nome: widget.produto['nome'] ?? 'Produto',
      preco:
          ((widget.produto['oferta'] ?? widget.produto['preco'] ?? 0.0) as num)
              .toDouble(),
      imagem:
          (widget.produto['imagens'] != null &&
              widget.produto['imagens'].isNotEmpty)
          ? widget.produto['imagens'][0]
          : widget.produto['imagem'] ?? '',
      lojaId: widget.produto['lojista_id'] ?? widget.produto['loja_id'] ?? '',
      lojaNome: widget.produto['loja_nome_vitrine'] ?? 'Loja Parceira',
    );

    cart.addItem(productItem);

    // === AJUSTE 1: MSG RÁPIDA (800ms) QUE NÃO ATRAPALHA O USUÁRIO ===
    ScaffoldMessenger.of(
      context,
    ).clearSnackBars(); // Limpa as anteriores para não acumular
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${productItem.nome} adicionado à sacola!'),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 800), // Rápido, como no iFood
      ),
    );
  }

  // === AJUSTE 2: FUNÇÃO PARA MOSTRAR A FOTO COM ZOOM (INTERACTIVE VIEW) ===
  void _mostrarImagemFullScreen(String urlImagem) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero, // Tela cheia
        child: Stack(
          alignment: Alignment.center,
          children: [
            // InteractiveViewer permite dar pinça (zoom) e arrastar
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                urlImagem,
                fit: BoxFit.contain, // Garante que a foto toda apareça
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            // Botão de fechar elegante no topo
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> imagens = [];
    if (widget.produto['imagens'] != null &&
        widget.produto['imagens'] is List) {
      imagens = List<String>.from(widget.produto['imagens']);
    } else if (widget.produto['imagem'] != null &&
        widget.produto['imagem'].toString().isNotEmpty) {
      imagens = [widget.produto['imagem'].toString()];
    }

    bool lojaAberta = widget.produto['loja_aberta'] ?? true;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: diPertinRoxo,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart, color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CartScreen(),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: diPertinLaranja,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        context.watch<CartProvider>().itemCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: imagens.isNotEmpty
                  ? PageView.builder(
                      itemCount: imagens.length,
                      itemBuilder: (context, index) {
                        // === AJUSTE 3: TORNA A FOTO CLICÁVEL PARA ZOOM ===
                        return GestureDetector(
                          onTap: () => _mostrarImagemFullScreen(imagens[index]),
                          child: Image.network(
                            imagens[index],
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.image_not_supported,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),

          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.produto['nome'] ?? 'Produto sem nome',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "R\$ ${((widget.produto['oferta'] ?? widget.produto['preco'] ?? 0.0) as num).toDouble().toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: diPertinLaranja,
                      ),
                    ),
                    const SizedBox(height: 15),

                    // === AJUSTE 4: INFO DE ENCOMENDA/ESTOQUE USANDO CAMPOS REAIS DO BANCO ===
                    _buildInfoEncomendaEstoque(widget.produto),

                    const SizedBox(height: 25),
                    const Divider(),
                    const SizedBox(height: 15),

                    // === AJUSTE 5: MUDANÇA DE ORDEM (NOME LOJA E AVALIAÇÕES ACIMA DA DESCRIÇÃO) ===
                    _buildLinkParaLoja(widget.produto, lojaAberta),

                    const SizedBox(height: 25),

                    _buildComentariosAvaliacoes(),

                    const SizedBox(height: 25),
                    const Divider(),
                    const SizedBox(height: 15),

                    // Descrição (AGORA É A ÚLTIMA PARTE)
                    const Text(
                      "Descrição",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: diPertinRoxo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.produto['descricao'] ??
                          'Sem descrição disponível.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _buildBotaoFixoCarrinho(lojaAberta),
    );
  }

  // WIDGET HELPER: INFO DE ENCOMENDA OU ESTOQUE (TURBINADO)
  Widget _buildInfoEncomendaEstoque(Map<String, dynamic> prod) {
    // Usando os campos reais que você informou
    String tipoVenda =
        prod['tipo_venda'] ?? 'estoque'; // 'estoque' ou 'encomenda'
    int estoqueQtd = (prod['estoque_qtd'] ?? 0);
    String prazoEncomenda = prod['prazo_encomenda'] ?? '';

    if (tipoVenda == 'encomenda') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: diPertinLaranja.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: diPertinLaranja.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2, color: diPertinLaranja, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "📦 PRODUTO SOB ENCOMENDA",
                  style: TextStyle(
                    color: diPertinLaranja,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (prazoEncomenda.isNotEmpty)
                  Text(
                    "Prazo de entrega: $prazoEncomenda",
                    style: const TextStyle(color: Colors.black87, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      );
    } else {
      // É venda por estoque
      if (estoqueQtd > 0) {
        return Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 16),
            const SizedBox(width: 6),
            Text(
              "$estoqueQtd unidades disponíveis em estoque",
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      } else {
        return Row(
          children: [
            Icon(Icons.remove_shopping_cart, color: Colors.red[700], size: 16),
            const SizedBox(width: 6),
            Text(
              "Produto temporariamente sem estoque",
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }
    }
  }

  Widget _buildLinkParaLoja(Map<String, dynamic> prod, bool aberta) {
    String nomeLoja = prod['loja_nome_vitrine'] ?? "Loja Parceira";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Vendido por",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () {
            String? lid = widget.produto['lojista_id'] ?? widget.produto['loja_id'];
            if (_dadosLojista != null && lid != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LojaPerfilScreen(
                    lojistaData: _dadosLojista!,
                    lojistaId: lid,
                  ),
                ),
              );
            }
          },
          child: Row(
            children: [
              Text(
                nomeLoja,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: diPertinRoxo,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(width: 8),
              if (!aberta)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    "FECHADA",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComentariosAvaliacoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Avaliações da Loja",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 18),
                SizedBox(width: 5),
                // Nível geral da LOJA (puxar do banco futuramente)
                const Text(
                  "4.8",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Text(
                  " (23)",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBotaoFixoCarrinho(bool aberta) {
    final cart = context.read<CartProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          onPressed: aberta ? () => _adicionarAoCarrinho(cart) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: aberta ? diPertinLaranja : Colors.red,
            disabledBackgroundColor: Colors.red[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: aberta ? 3 : 0,
          ),
          child: Text(
            aberta
                ? "ADICIONAR À SACOLA"
                : "Loja Fechada - Não aceitando pedidos",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
