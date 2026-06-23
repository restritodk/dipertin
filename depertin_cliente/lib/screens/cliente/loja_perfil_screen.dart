// Arquivo: lib/screens/cliente/loja_perfil_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'product_details_screen.dart';
import '../../providers/cart_provider.dart';
import '../../utils/loja_fachada_foto.dart';
import '../../utils/loja_pausa.dart';
import '../../utils/safe_area_insets.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class LojaPerfilScreen extends StatefulWidget {
  final Map<String, dynamic> lojistaData;
  final String lojistaId;

  const LojaPerfilScreen({
    super.key,
    required this.lojistaData,
    required this.lojistaId,
  });

  @override
  State<LojaPerfilScreen> createState() => _LojaPerfilScreenState();
}

class _LojaPerfilScreenState extends State<LojaPerfilScreen> {
  static final NumberFormat _fmtMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  Timer? _timerReavaliaPausa;
  StreamSubscription<DocumentSnapshot>? _subLoja;
  bool _lojaAberta = true;

  /// Dados atualizados de `lojas_public` (nome, fotos de fachada, pausa, etc.).
  late Map<String, dynamic> _dadosLoja;

  Future<QuerySnapshot<Map<String, dynamic>>>? _cacheAvaliacoes;

  final TextEditingController _searchCtrl = TextEditingController();
  String _termoBuscaProduto = '';
  int _categoriaSelecionada = 0;

  static const List<String> _categoriasSugeridas = [
    'Todos', 'Mais vendidos', 'Lançamentos', 'Promoções',
  ];

  static String _urlCapa(Map<String, dynamic> m) =>
      m['foto_capa']?.toString().trim() ?? '';

  @override
  void initState() {
    super.initState();
    _dadosLoja = Map<String, dynamic>.from(widget.lojistaData);
    _timerReavaliaPausa = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) setState(() {});
    });
    // Fase 3G.2 — perfil da loja lê `lojas_public` (só dados de fachada).
    _subLoja = FirebaseFirestore.instance
        .collection('lojas_public')
        .doc(widget.lojistaId)
        .snapshots()
        .listen((snap) {
          if (!mounted || !snap.exists) return;
          final dados = snap.data() as Map<String, dynamic>;
          final bool aberta = LojaPausa.lojaEstaAberta(dados);
          setState(() {
            _dadosLoja = dados;
            _lojaAberta = aberta;
          });
        });
  }

  @override
  void dispose() {
    _timerReavaliaPausa?.cancel();
    _subLoja?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _futureAvaliacoes() {
    return _cacheAvaliacoes ??= FirebaseFirestore.instance
        .collection('avaliacoes')
        .where('loja_id', isEqualTo: widget.lojistaId)
        .get();
  }

  double _precoExibir(Map<String, dynamic> p) {
    final double? precoOriginal = (p['preco'] as num?)?.toDouble();
    final double? precoOferta = (p['oferta'] as num?)?.toDouble();
    final bool temOferta =
        precoOferta != null &&
        precoOriginal != null &&
        precoOferta < precoOriginal;
    return temOferta ? precoOferta : (precoOriginal ?? precoOferta ?? 0.0);
  }

  bool _temOferta(Map<String, dynamic> p) {
    final double? precoOriginal = (p['preco'] as num?)?.toDouble();
    final double? precoOferta = (p['oferta'] as num?)?.toDouble();
    return precoOferta != null &&
        precoOriginal != null &&
        precoOferta < precoOriginal;
  }

  @override
  Widget build(BuildContext context) {
    final m = _dadosLoja;
    final String urlCapa = _urlCapa(m);
    final String urlLogo = urlFachadaLojaCliente(m);
    // Capa larga: `foto_capa`; senão, a imagem de fachada (config. operacional / vitrine).
    final String urlHero = urlCapa.isNotEmpty ? urlCapa : urlLogo;
    // Evita logo duplicada: o hero já mostra a foto quando não há capa.
    final bool mostrarAvatarCirculo = urlLogo.isNotEmpty && urlCapa.isNotEmpty;
    final String nomeLoja =
        m['loja_nome']?.toString() ?? m['nome']?.toString() ?? 'Loja parceira';
    final String descricaoLoja =
        m['descricao']?.toString() ?? 'Sempre perto de você.';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      body: Stack(
        children: [
          CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // ── TOPO / BANNER ──
          SliverAppBar(
            pinned: true,
            stretch: true,
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.white,
            expandedHeight: 260,
            leading: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 22),
                ),
                tooltip: 'Voltar',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _bannerAction(Icons.favorite_border_rounded),
                    const SizedBox(width: 4),
                    _bannerAction(Icons.ios_share_rounded),
                    const SizedBox(width: 4),
                    _bannerAction(Icons.more_horiz_rounded),
                  ],
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (urlHero.isNotEmpty)
                    Image.network(
                      urlHero,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => _capaPlaceholder(),
                    )
                  else
                    _capaPlaceholder(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  // Logo da loja sobreposto na parte inferior
                  if (mostrarAvatarCirculo)
                    Positioned(
                      left: 20,
                      bottom: -40,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.network(
                            urlLogo,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _logoPlaceholderAvatar(),
                          ),
                        ),
                      ),
                    ),
                  if (!mostrarAvatarCirculo && urlLogo.isEmpty)
                    Positioned(
                      left: 20,
                      bottom: -40,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _logoPlaceholderAvatar(),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── CARD SOBREPOSTO DA LOJA ──
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Card branco com bordas arredondadas no topo
                Container(
                  margin: const EdgeInsets.only(top: 56),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nome + selo verificado
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nomeLoja,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A2E),
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B8A5A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Status + Informações de entrega
                        FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          future: _futureAvaliacoes(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return Row(
                                children: [
                                  _chipStatusLoja(),
                                  const Spacer(),
                                  SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: diPertinLaranja.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              );
                            }
                            final docs = snap.data?.docs ?? [];
                            double media = 0;
                            if (docs.isNotEmpty) {
                              double soma = 0;
                              for (final d in docs) {
                                final m = d.data();
                                soma += (m['nota'] ?? m['estrelas'] ?? 5) as num;
                              }
                              media = soma / docs.length;
                            }
                            return Row(
                              children: [
                                _chipStatusLoja(),
                                const Spacer(),
                                if (docs.isEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.star_outline_rounded,
                                          size: 20, color: Colors.grey.shade400),
                                      const SizedBox(width: 4),
                                      Text('Sem avaliações',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ],
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded,
                                            size: 18, color: Colors.amber.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          media.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: Color(0xFF1A1A2E),
                                          ),
                                        ),
                                        Text(
                                          ' · ${docs.length}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        // Descrição da loja
                        Text(
                          descricaoLoja,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Chips de entrega/retirada
                        Row(
                          children: [
                            _chipInfo('Entrega', Icons.motorcycle_outlined, diPertinLaranja),
                            const SizedBox(width: 10),
                            _chipInfo('Retirada', Icons.store_outlined, diPertinRoxo),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ── SEÇÃO INFORMAÇÕES ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informações',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Onde estamos + Atendimento lado a lado
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final sideBySide = constraints.maxWidth >= 480;
                          if (sideBySide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _cardInfo(
                                    icon: Icons.location_on_outlined,
                                    corIcon: const Color(0xFFE53935),
                                    corFundo: const Color(0xFFFFEBEE),
                                    titulo: 'Onde estamos',
                                    child: Text(
                                      _dadosLoja['endereco']?.toString() ?? 'Endereço não informado.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildAtendimentoCard(),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              _cardInfo(
                                icon: Icons.location_on_outlined,
                                corIcon: const Color(0xFFE53935),
                                corFundo: const Color(0xFFFFEBEE),
                                titulo: 'Onde estamos',
                                child: Text(
                                  _dadosLoja['endereco']?.toString() ?? 'Endereço não informado.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildAtendimentoCard(),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // ── SEÇÃO PRODUTOS ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: diPertinLaranja.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.grid_view_rounded,
                              color: diPertinLaranja,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Produtos desta loja',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Escolha seus produtos e adicione ao carrinho.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Campo de busca
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _termoBuscaProduto = v.trim()),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Buscar produtos...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 22, color: Colors.grey.shade400),
                          suffixIcon: _termoBuscaProduto.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _termoBuscaProduto = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF5F5F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Chips de categorias (decorativos)
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categoriasSugeridas.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final selected = _categoriaSelecionada == i;
                            return GestureDetector(
                              onTap: () => setState(() => _categoriaSelecionada = i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? diPertinRoxo : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? diPertinRoxo : const Color(0xFFE0E0E0),
                                  ),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: diPertinRoxo.withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  _categoriasSugeridas[i],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── GRADE DE PRODUTOS ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('produtos')
                  .where('ativo', isEqualTo: true)
                  .where('lojista_id', isEqualTo: widget.lojistaId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: diPertinLaranja,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SliverToBoxAdapter(child: _EmptyProdutos());
                }

                // Filtro local por busca textual
                var produtos = snapshot.data!.docs;
                if (_termoBuscaProduto.isNotEmpty) {
                  final t = _termoBuscaProduto.toLowerCase();
                  produtos = produtos.where((doc) {
                    final d = doc.data()! as Map<String, dynamic>;
                    final nome = (d['nome'] ?? '').toString().toLowerCase();
                    return nome.contains(t);
                  }).toList();
                }

                if (produtos.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded, size: 44, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Nenhum produto encontrado',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Text('Tente buscar por outro termo.',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                }

                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.68,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final doc = produtos[index];
                    var p = doc.data()! as Map<String, dynamic>;
                    p = Map<String, dynamic>.from(p);
                    p['id'] = doc.id;
                    p['id_documento'] = doc.id;
                    p['lojista_id'] = widget.lojistaId;
                    p['loja_id'] = widget.lojistaId;
                    p['loja_nome_vitrine'] = nomeLoja;
                    p['loja_aberta'] = _lojaAberta;

                    final String img =
                        (p['imagens'] != null &&
                            p['imagens'] is List &&
                            (p['imagens'] as List).isNotEmpty)
                        ? (p['imagens'] as List).first.toString()
                        : '';

                    final double precoFinal = _precoExibir(p);
                    final bool oferta = _temOferta(p);
                    final double? precoOriginal = (p['preco'] as num?)?.toDouble();

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    ProductDetailsScreen(produto: p),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Imagem
                              Expanded(
                                flex: 5,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(18)),
                                      child: img.isNotEmpty
                                          ? Image.network(
                                              img,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, _, _) =>
                                                  _thumbErro(),
                                            )
                                          : _thumbErro(),
                                    ),
                                    if (!_lojaAberta)
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.42,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (!_lojaAberta)
                                      Positioned(
                                        top: 8, right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.62,
                                            ),
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
                                    if (oferta && _lojaAberta)
                                      Positioned(
                                        top: 8, left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: diPertinLaranja,
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.2,
                                                ),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Oferta',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Botão favoritar
                                    Positioned(
                                      top: 8, right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.08),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.favorite_border_rounded,
                                          size: 18,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Info
                              Expanded(
                                flex: 4,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['nome']?.toString() ?? 'Produto',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          height: 1.2,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        p['descricao']?.toString() ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const Spacer(),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (oferta &&
                                                    precoOriginal != null &&
                                                    precoOriginal > precoFinal)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 1),
                                                    child: Text(
                                                      _fmtMoeda.format(precoOriginal),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        decoration: TextDecoration.lineThrough,
                                                        color: Colors.grey.shade400,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  _fmtMoeda.format(precoFinal),
                                                  style: const TextStyle(
                                                    color: diPertinRoxo,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: diPertinRoxo,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: diPertinRoxo.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.add_shopping_cart_rounded,
                                              size: 22,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: produtos.length),
                );
              },
            ),
          ),
          // ── BENEFÍCIOS DA LOJA ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Wrap(
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 96) / 2,
                      child: _beneficioItem(
                        Icons.rocket_launch_outlined,
                        const Color(0xFF6A1B9A),
                        const Color(0xFFF3E8FF),
                        'Entrega rápida',
                        'Para Toledo e região',
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 96) / 2,
                      child: _beneficioItem(
                        Icons.verified_user_outlined,
                        const Color(0xFF1B8A5A),
                        const Color(0xFFE8F5E9),
                        'Pagamento seguro',
                        'Seus dados protegidos',
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 96) / 2,
                      child: _beneficioItem(
                        Icons.diamond_outlined,
                        const Color(0xFFE65100),
                        const Color(0xFFFFF3E0),
                        'Produtos originais',
                        'Qualidade garantida',
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 96) / 2,
                      child: _beneficioItem(
                        Icons.headset_mic_outlined,
                        const Color(0xFF1565C0),
                        const Color(0xFFE3F2FD),
                        'Atendimento',
                        'Suporte via chat',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 88),
          ),
        ],
      ),
          // ── BARRA FIXA DO CARRINHO ──
          Consumer<CartProvider>(
            builder: (_, cart, __) {
              if (cart.itemCount == 0) return const SizedBox.shrink();
              final total = cart.totalAmount;
              return Positioned(
                left: 16,
                right: 16,
                bottom: 16 + diPertinSafeAreaBottom(context),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              size: 26, color: Color(0xFF6A1B9A)),
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF8F00),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${cart.itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${cart.itemCount} item${cart.itemCount == 1 ? '' : 'ns'} no carrinho',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fmtMoeda.format(total),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A1B9A),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6A1B9A).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton.icon(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                          label: const Text(
                            'Ver carrinho',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAtendimentoCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(widget.lojistaId)
          .snapshots(),
      builder: (context, snapshot) {
        String statusLoja = 'Verificando…';
        Color corChip = Colors.grey.shade700;
        Color bgChip = Colors.grey.shade100;
        if (snapshot.hasData && snapshot.data!.exists) {
          final dados = snapshot.data!.data() as Map<String, dynamic>;
          final bool aberta = LojaPausa.lojaEstaAberta(dados);
          if (aberta) {
            statusLoja = 'Aberta para pedidos';
            corChip = const Color(0xFF1B5E20);
            bgChip = const Color(0xFFE8F5E9);
          } else {
            final motivo = LojaPausa.textoMotivoPublico(dados);
            statusLoja = motivo.isNotEmpty ? motivo : 'Fechada no momento';
            corChip = const Color(0xFFB71C1C);
            bgChip = const Color(0xFFFFEBEE);
          }
        }
        return _cardInfo(
          icon: Icons.schedule_rounded,
          corIcon: const Color(0xFF1565C0),
          corFundo: const Color(0xFFE3F2FD),
          titulo: 'Atendimento',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bgChip,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLoja,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: corChip,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bannerAction(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: Colors.white,
        onPressed: () {},
        splashRadius: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }

  Widget _cardInfo({
    required IconData icon,
    required Color corIcon,
    required Color corFundo,
    required String titulo,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: corIcon, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String texto, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _beneficioItem(IconData icone, Color cor, Color fundo, String titulo, String descricao) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, color: cor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                descricao,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipStatusLoja() {
    return StreamBuilder<DocumentSnapshot>(
      // Fase 3G.2 — lê `lojas_public`.
      stream: FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(widget.lojistaId)
          .snapshots(),
      builder: (context, snapshot) {
        bool aberta = true;
        String rotuloFechada = 'Fechada';
        if (snapshot.hasData && snapshot.data!.exists) {
          final dados = snapshot.data!.data() as Map<String, dynamic>;
          aberta = LojaPausa.lojaEstaAberta(dados);
          if (!aberta) {
            final t = LojaPausa.textoMotivoPublico(dados);
            if (t.isNotEmpty) rotuloFechada = t;
          }
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: aberta ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: aberta ? const Color(0xFFC8E6C9) : const Color(0xFFFFCDD2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                aberta
                    ? Icons.check_circle_rounded
                    : Icons.store_mall_directory,
                size: 18,
                color: aberta
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  aberta ? 'Aberta' : rotuloFechada,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: aberta
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFFB71C1C),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _logoPlaceholderAvatar() {
    return Container(
      width: 80,
      height: 80,
      color: const Color(0xFFF0EAF5),
      alignment: Alignment.center,
      child: const Icon(
        Icons.storefront_rounded,
        size: 38,
        color: diPertinRoxo,
      ),
    );
  }

  Widget _capaPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7B1FA2), diPertinRoxo],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.storefront_rounded,
          size: 88,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _thumbErro() {
    return ColoredBox(
      color: const Color(0xFFEDE7F0),
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey.shade400,
        size: 40,
      ),
    );
  }
}

class _EmptyProdutos extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E6ED)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum produto ativo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Quando a loja publicar itens, eles aparecerão aqui em destaque.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              height: 1.45,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
