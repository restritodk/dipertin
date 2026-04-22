// Arquivo: lib/screens/cliente/product_details_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:depertin_cliente/widgets/loja_rating_row.dart';
import '../../providers/cart_provider.dart';
import '../../models/cart_item_model.dart';
import '../../utils/loja_pausa.dart';
import 'cart_screen.dart';
import 'loja_perfil_screen.dart';
import 'product_galeria_ampliada.dart';

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
  bool _carregandoLojista = true;
  bool _lojaAbertaReal = true;

  final PageController _pageControllerImagens = PageController();
  int _indiceImagem = 0;
  int _quantidade = 1;

  final NumberFormat _fmtMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _carregarDadosLojista();
  }

  @override
  void dispose() {
    _pageControllerImagens.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosLojista() async {
    setState(() => _carregandoLojista = true);
    final String? lojistaId =
        widget.produto['lojista_id']?.toString() ??
        widget.produto['loja_id']?.toString();
    if (lojistaId != null && lojistaId.isNotEmpty) {
      try {
        // Fase 3G.2 — detalhe do produto lê `lojas_public` p/ status/pausa da loja.
        final DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('lojas_public')
            .doc(lojistaId)
            .get();
        if (doc.exists && mounted) {
          final dados = doc.data() as Map<String, dynamic>;
          final bool aberta = LojaPausa.lojaEstaAberta(dados);
          setState(() {
            _dadosLojista = dados;
            _lojaAbertaReal = aberta;
            _carregandoLojista = false;
          });
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Erro ao carregar dados da loja: $e');
        }
      }
    }
    if (mounted) {
      setState(() => _carregandoLojista = false);
    }
  }

  double _precoVenda() {
    final num? oferta = widget.produto['oferta'] as num?;
    final num? preco = widget.produto['preco'] as num?;
    if (oferta != null && preco != null && oferta < preco) {
      return oferta.toDouble();
    }
    return (oferta ?? preco ?? 0.0).toDouble();
  }

  double? _precoOriginalRiscado() {
    final num? oferta = widget.produto['oferta'] as num?;
    final num? preco = widget.produto['preco'] as num?;
    if (oferta != null && preco != null && oferta < preco) {
      return preco.toDouble();
    }
    return null;
  }

  String _tipoVenda() => (widget.produto['tipo_venda'] ?? 'estoque').toString();

  int _estoqueQtd() => (widget.produto['estoque_qtd'] ?? 0) as int;

  int _maxQuantidadePermitida() {
    if (_tipoVenda() == 'encomenda') return 99;
    final q = _estoqueQtd();
    return q > 0 ? q : 0;
  }

  bool _podeVenderPorEstoque() {
    if (_tipoVenda() == 'encomenda') return true;
    return _estoqueQtd() > 0;
  }

  void _compartilharProduto() {
    final nome = widget.produto['nome'] ?? 'Produto';
    final preco = _fmtMoeda.format(_precoVenda());
    SharePlus.instance.share(ShareParams(text: '$nome — $preco no DiPertin'));
  }

  void _adicionarAoCarrinho(CartProvider cart) {
    final bool lojaAberta = _carregandoLojista
        ? (widget.produto['loja_aberta'] ?? true)
        : _lojaAbertaReal;
    if (!lojaAberta) return;
    if (!_podeVenderPorEstoque()) return;

    final maxQ = _maxQuantidadePermitida();
    final q = maxQ > 0 ? _quantidade.clamp(1, maxQ) : 1;

    final productItem = CartItemModel(
      id: widget.produto['id_documento'] ?? '',
      nome: widget.produto['nome'] ?? 'Produto',
      preco: _precoVenda(),
      imagem:
          (widget.produto['imagens'] != null &&
              widget.produto['imagens'] is List &&
              (widget.produto['imagens'] as List).isNotEmpty)
          ? (widget.produto['imagens'] as List).first.toString()
          : widget.produto['imagem']?.toString() ?? '',
      lojaId:
          widget.produto['lojista_id']?.toString() ??
          widget.produto['loja_id']?.toString() ??
          '',
      lojaNome: widget.produto['loja_nome_vitrine'] ?? 'Loja Parceira',
    );

    cart.addItemWithQuantity(productItem, q);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          q > 1
              ? '${productItem.nome} ($q un.) adicionado à sacola!'
              : '${productItem.nome} adicionado à sacola!',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  Widget _imagemRede(String url, {BoxFit fit = BoxFit.cover}) {
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, _, _) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          size: 56,
          color: Colors.grey[400],
        ),
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[100],
          alignment: Alignment.center,
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                : null,
            color: diPertinLaranja,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> imagens = [];
    if (widget.produto['imagens'] != null &&
        widget.produto['imagens'] is List) {
      imagens = List<String>.from(
        (widget.produto['imagens'] as List).map((e) => e.toString()),
      );
    } else if (widget.produto['imagem'] != null &&
        widget.produto['imagem'].toString().isNotEmpty) {
      imagens = [widget.produto['imagem'].toString()];
    }

    final bool lojaAberta = _carregandoLojista
        ? (widget.produto['loja_aberta'] ?? true)
        : _lojaAbertaReal;
    final double precoExibir = _precoVenda();
    final double? precoRiscado = _precoOriginalRiscado();
    final String? categoriaNome = widget.produto['categoria_nome']?.toString();
    final String? descricaoRaw = widget.produto['descricao']?.toString();
    final String descricaoTexto =
        (descricaoRaw != null && descricaoRaw.trim().isNotEmpty)
        ? descricaoRaw.trim()
        : '';

    final navBottom = MediaQuery.viewPaddingOf(context).bottom;
    final String? lojaId =
        widget.produto['lojista_id']?.toString() ??
        widget.produto['loja_id']?.toString();

    final bool podeComprar = lojaAberta && _podeVenderPorEstoque();
    final int maxQ = _maxQuantidadePermitida();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: diPertinRoxo,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'Compartilhar produto',
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                ),
                icon: const Icon(Icons.share_outlined),
                onPressed: _compartilharProduto,
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: 'Abrir sacola',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                    ),
                    icon: const Icon(Icons.shopping_cart),
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
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _pageControllerImagens,
                          itemCount: imagens.length,
                          onPageChanged: (i) {
                            setState(() => _indiceImagem = i);
                          },
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => abrirGaleriaProdutoAmpliada(
                                context,
                                urls: imagens,
                                initialIndex: index,
                              ),
                              child: _imagemRede(imagens[index]),
                            );
                          },
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: MediaQuery.paddingOf(context).top +
                              kToolbarHeight +
                              12,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.black.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (imagens.length > 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                imagens.length,
                                (i) => Container(
                                  width: i == _indiceImagem ? 18 : 7,
                                  height: 7,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i == _indiceImagem
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
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
                padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + navBottom + 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.produto['nome'] ?? 'Produto sem nome',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.2,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (categoriaNome != null && categoriaNome.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Chip(
                        label: Text(
                          categoriaNome,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: diPertinRoxo,
                          ),
                        ),
                        backgroundColor: diPertinRoxo.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: diPertinRoxo.withValues(alpha: 0.25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmtMoeda.format(precoExibir),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: diPertinLaranja,
                          ),
                        ),
                        if (precoRiscado != null) ...[
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _fmtMoeda.format(precoRiscado),
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade500,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildInfoEncomendaEstoque(widget.produto),
                    const SizedBox(height: 16),
                    if (podeComprar) _buildSeletorQuantidade(maxQ),
                    const SizedBox(height: 20),
                    _cardSecao(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLinkParaLoja(widget.produto, lojaAberta),
                          if (lojaId != null && lojaId.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildResumoAvaliacoesLoja(lojaId),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _cardSecao(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Descrição',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: diPertinRoxo,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            descricaoTexto.isNotEmpty
                                ? descricaoTexto
                                : 'O lojista ainda não cadastrou uma descrição para este produto.',
                            style: TextStyle(
                              fontSize: 15,
                              color: descricaoTexto.isNotEmpty
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade500,
                              height: 1.55,
                              fontStyle: descricaoTexto.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _buildBotaoFixoCarrinho(
        context,
        lojaAberta,
        podeComprar,
      ),
    );
  }

  Widget _buildSeletorQuantidade(int maxQ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            'Quantidade',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Diminuir quantidade',
            onPressed: _quantidade > 1
                ? () => setState(() => _quantidade--)
                : null,
            icon: Icon(
              Icons.remove_circle_outline,
              color: _quantidade > 1 ? diPertinRoxo : Colors.grey.shade400,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$_quantidade',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Aumentar quantidade',
            onPressed: _quantidade < maxQ
                ? () => setState(() => _quantidade++)
                : null,
            icon: Icon(
              Icons.add_circle_outline,
              color: _quantidade < maxQ
                  ? diPertinLaranja
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardSecao({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInfoEncomendaEstoque(Map<String, dynamic> prod) {
    String tipoVenda = prod['tipo_venda'] ?? 'estoque';
    int estoqueQtd = (prod['estoque_qtd'] ?? 0);
    String prazoEncomenda = prod['prazo_encomenda'] ?? '';

    if (tipoVenda == 'encomenda') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: diPertinLaranja.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: diPertinLaranja.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_rounded,
              color: diPertinLaranja,
              size: 22,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Produto sob encomenda',
                  style: TextStyle(
                    color: diPertinLaranja,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
                if (prazoEncomenda.isNotEmpty)
                  Text(
                    'Prazo de entrega: $prazoEncomenda',
                    style: const TextStyle(color: Colors.black87, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      );
    } else {
      if (estoqueQtd > 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade700,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$estoqueQtd unidades em estoque',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.remove_shopping_cart_rounded,
                color: Colors.red.shade700,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Sem estoque no momento',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  void _abrirPerfilLoja(String? lid) {
    if (lid == null || lid.isEmpty) return;
    if (_carregandoLojista) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carregando dados da loja…'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_dadosLojista == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível carregar o perfil da loja. Tente novamente.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LojaPerfilScreen(lojistaData: _dadosLojista!, lojistaId: lid),
      ),
    );
  }

  Widget _buildLinkParaLoja(Map<String, dynamic> prod, bool aberta) {
    String nomeLoja = prod['loja_nome_vitrine'] ?? 'Loja Parceira';
    final String? lid =
        widget.produto['lojista_id']?.toString() ??
        widget.produto['loja_id']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vendido por',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _abrirPerfilLoja(lid),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    nomeLoja,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: diPertinRoxo,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (_carregandoLojista) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: diPertinLaranja,
                    ),
                  ),
                ],
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
                      'FECHADA',
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
        ),
      ],
    );
  }

  /// Prioriza `rating_media` / `total_avaliacoes` no doc da loja; fallback: média on-demand.
  Widget _buildResumoAvaliacoesLoja(String lojaId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // Fase 3G.2 — lê `lojas_public` (rating_media/total_avaliacoes públicos).
      stream: FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(lojaId)
          .snapshots(),
      builder: (context, snapUser) {
        final d = snapUser.data?.data();
        final mediaCache = (d?['rating_media'] as num?)?.toDouble();
        final totalCache = (d?['total_avaliacoes'] as num?)?.toInt() ?? 0;
        if (totalCache > 0 &&
            mediaCache != null &&
            mediaCache > 0) {
          return LojaRatingRow(
            media: mediaCache,
            total: totalCache,
            fontSize: 14,
            iconSize: 16,
          );
        }

        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('avaliacoes')
              .where('loja_id', isEqualTo: lojaId)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 22,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: diPertinLaranja,
                    ),
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                'Sem avaliações ainda',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              );
            }

            double soma = 0;
            for (final doc in docs) {
              soma += (doc.data()['nota'] ?? 5) as num;
            }
            final media = soma / docs.length;
            return LojaRatingRow(
              media: media,
              total: docs.length,
              fontSize: 14,
              iconSize: 16,
            );
          },
        );
      },
    );
  }

  Widget _buildBotaoFixoCarrinho(
    BuildContext context,
    bool aberta,
    bool podeComprar,
  ) {
    final cart = context.read<CartProvider>();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    String label;
    VoidCallback? onPressed;
    Color bg;
    Color? disabledBg;

    if (!aberta) {
      label = 'Loja fechada — não aceitando pedidos';
      onPressed = null;
      bg = diPertinLaranja;
      disabledBg = Colors.red.shade300;
    } else if (!podeComprar) {
      label = 'Sem estoque';
      onPressed = null;
      bg = diPertinLaranja;
      disabledBg = Colors.grey.shade400;
    } else {
      label = 'Adicionar à sacola';
      onPressed = () => _adicionarAoCarrinho(cart);
      bg = diPertinLaranja;
      disabledBg = null;
    }

    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              disabledBackgroundColor: disabledBg ?? Colors.red.shade300,
              foregroundColor: Colors.white,
              elevation: onPressed != null ? 2 : 0,
              shadowColor: diPertinLaranja.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
