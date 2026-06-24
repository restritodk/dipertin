// Arquivo: lib/screens/cliente/vitrine_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/cart_item_model.dart';
import '../../providers/cart_provider.dart';
import '../../services/location_service.dart';
import '../../utils/loja_pausa.dart';
import '../../utils/safe_area_insets.dart';
import '../../widgets/botao_carrinho_app_bar.dart';
import '../../widgets/favoritar_botao.dart';
import 'loja_perfil_screen.dart';
import 'product_details_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);

class VitrineScreen extends StatefulWidget {
  const VitrineScreen({super.key});

  @override
  State<VitrineScreen> createState() => _VitrineScreenState();
}

class _VitrineScreenState extends State<VitrineScreen> {
  final NumberFormat _fmtMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
    decimalDigits: 2,
  );

  StreamSubscription<QuerySnapshot>? _bannersSubscription;
  List<QueryDocumentSnapshot> _bannersDocsBrutos = [];
  bool _entradaAnimada = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showSuggestions = false;
  final GlobalKey _cabecalhoBuscaKey = GlobalKey();
  Timer? _searchDebounce;

  double get _alturaCabecalhoBusca {
    final box = _cabecalhoBuscaKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? 200;
  }

  // ============ Estado dos filtros ============
  Set<String> _filtroCategorias = {};
  double? _filtroPrecoMin;
  double? _filtroPrecoMax;
  String _filtroOrdenacao = 'mais_relevantes';
  String _filtroDisponibilidade = 'todos';

  bool get _temFiltroAtivo =>
      _filtroCategorias.isNotEmpty ||
      _filtroPrecoMin != null ||
      _filtroPrecoMax != null ||
      _filtroOrdenacao != 'mais_relevantes' ||
      _filtroDisponibilidade != 'todos';

  @override
  void initState() {
    super.initState();
    _iniciarEscutaBanners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  Widget _buildHeaderGradient(
    LocationService locationService,
    String cidadeExibicao,
  ) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DiPertin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'O que você precisa, bem aqui',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.place,
                          size: 14,
                          color: diPertinLaranja,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            cidadeExibicao.isNotEmpty
                                ? 'Comprando em $cidadeExibicao'
                                : 'Detectando sua cidade…',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.my_location,
                  color: locationService.detectandoCidade
                      ? Colors.white38
                      : Colors.white,
                ),
                tooltip: 'Atualizar cidade pelo GPS',
                onPressed: locationService.detectandoCidade
                    ? null
                    : () => locationService.detectarCidade(),
              ),
              const BotaoCarrinhoAppBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.85),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'O que você procura hoje?',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  _searchFocusNode.unfocus();
                },
                child: Container(
                  margin: const EdgeInsets.all(6),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 20,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => _abrirModalFiltro(context),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Icon(
                          Icons.tune_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 20,
                        ),
                      ),
                      if (_temFiltroAtivo)
                        Positioned(
                          top: 1,
                          right: 1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: diPertinLaranja,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSuggestionsOverlay() {
    if (!_showSuggestions || _searchController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final termo = _searchController.text.trim().toLowerCase();
    final maxAltura = MediaQuery.of(context).size.height * 0.5;
    final tecladoAltura = MediaQuery.of(context).viewInsets.bottom;

    return Positioned(
      top: _alturaCabecalhoBusca,
      left: 16,
      right: 16,
      bottom: tecladoAltura > 0 ? tecladoAltura + 16 : null,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxAltura,
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              _buildSugestaoProdutos(termo),
              _buildSugestaoLojas(termo),
              if (_searchQuery.isNotEmpty) ...[
                const Divider(height: 1, thickness: 1),
                InkWell(
                  onTap: () {
                    setState(() => _showSuggestions = false);
                    _searchFocusNode.unfocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: diPertinLaranja.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.search_rounded, color: diPertinLaranja, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pesquisar por "$termo"',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: diPertinLaranja,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSugestaoProdutos(String termo) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('produtos')
          .where('ativo', isEqualTo: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final found = snapshot.data!.docs.where((doc) {
          final p = doc.data() as Map<String, dynamic>;
          final nome = (p['nome'] as String? ?? '').toLowerCase();
          final descricao = (p['descricao'] as String? ?? '').toLowerCase();
          return nome.contains(termo) || descricao.contains(termo);
        }).take(5).toList();

        if (found.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: diPertinRoxo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: diPertinRoxo, size: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Produtos encontrados',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textoMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...found.map((doc) {
              final p = doc.data() as Map<String, dynamic>;
              p['id'] = doc.id;
              final img = (p['imagens'] is List && p['imagens'].isNotEmpty)
                  ? p['imagens'][0].toString()
                  : '';
              final preco = (p['preco'] as num?)?.toDouble() ?? 0;
              final estoque = (p['estoque_qtd'] as num?)?.toInt() ?? 0;
              final tipoVenda = (p['tipo_venda'] ?? 'estoque').toString();
              final disponivel = tipoVenda == 'encomenda' || estoque > 0;

              // Busca nome da loja via Stream - usamos cache do mapa existente
              // fallback: usa lojista_id como nome
              final lojaNome = (p['lojista_id'] ?? '').toString();

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: () {
                    setState(() => _showSuggestions = false);
                    _searchFocusNode.unfocus();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailsScreen(produto: p),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 48, height: 48,
                            child: img.isNotEmpty
                                ? Image.network(img, fit: BoxFit.cover,
                                    errorBuilder: (_,_,_) => _sugestaoPlaceholder())
                                : _sugestaoPlaceholder(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['nome'] ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _textoPrimario,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Icon(Icons.store_rounded, size: 10, color: Colors.grey[400]),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      lojaNome,
                                      style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    'R\$ ${preco.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: diPertinRoxo,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: disponivel
                                          ? Colors.green.withValues(alpha: 0.08)
                                          : Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      disponivel ? 'Disponível' : 'Indisponível',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: disponivel ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSugestaoLojas(String termo) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lojas_public')
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final found = snapshot.data!.docs.where((doc) {
          final l = doc.data() as Map<String, dynamic>;
          final nome = (l['loja_nome'] ?? l['nome'] ?? '').toString().toLowerCase();
          final descricao = (l['descricao'] ?? '').toString().toLowerCase();
          return nome.contains(termo) || descricao.contains(termo);
        }).take(5).toList();

        if (found.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: diPertinLaranja.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.store_rounded, color: diPertinLaranja, size: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Lojas encontradas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textoMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...found.map((doc) {
              final l = doc.data() as Map<String, dynamic>;
              final lojaId = doc.id;
              final nome = l['loja_nome'] ?? l['nome'] ?? 'Loja';
              final foto = (l['foto'] ?? l['foto_capa'] ?? l['imagem'] ?? '').toString();
              final aberta = _verificarSeLojaEstaAberta(l);
              final rating = (l['rating_media'] as num?)?.toDouble();
              final totalAv = (l['total_avaliacoes'] as num?)?.toInt() ?? 0;

              return FutureBuilder<int>(
                future: _contarProdutosLoja(lojaId),
                builder: (context, countSnapshot) {
                  final qtdProdutos = countSnapshot.data ?? 0;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: InkWell(
                      onTap: () {
                        setState(() => _showSuggestions = false);
                        _searchFocusNode.unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LojaPerfilScreen(
                              lojistaData: l,
                              lojistaId: lojaId,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.grey[100],
                              backgroundImage: foto.isNotEmpty
                                  ? NetworkImage(foto)
                                  : null,
                              child: foto.isEmpty
                                  ? Icon(Icons.store_rounded, color: Colors.grey[400], size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _textoPrimario,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: aberta ? Colors.green : Colors.red,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        aberta ? 'Aberta' : 'Fechada',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: aberta ? Colors.green : Colors.red,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$qtdProdutos ${qtdProdutos == 1 ? 'produto' : 'produtos'}',
                                        style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                  if (rating != null && rating > 0) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.star_rounded, size: 12, color: diPertinLaranja),
                                        const SizedBox(width: 2),
                                        Text(
                                          rating.toStringAsFixed(1),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: diPertinLaranja,
                                          ),
                                        ),
                                        Text(
                                          ' ($totalAv)',
                                          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
          ],
        );
      },
    );
  }

  Widget _sugestaoPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: Icon(Icons.image_outlined, color: Colors.grey[300], size: 22),
    );
  }

  Future<int> _contarProdutosLoja(String lojaId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('produtos')
          .where('lojista_id', isEqualTo: lojaId)
          .where('ativo', isEqualTo: true)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    if (val.trim().isEmpty) {
      _searchDebounce?.cancel();
      setState(() {
        _searchQuery = '';
        _showSuggestions = false;
      });
      return;
    }
    setState(() => _showSuggestions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = val.trim().toLowerCase();
      });
    });
  }

  // ============ MODAL DE FILTRO ============

  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _textoPrimario = Color(0xFF1A1A2E);
  static const Color _textoMuted = Color(0xFF64748B);

  void _abrirModalFiltro(BuildContext context) {
    // Estados locais do modal
    final double? precoMinLocal = _filtroPrecoMin;
    final double? precoMaxLocal = _filtroPrecoMax;
    Set<String> categoriasSelecionadas = Set.from(_filtroCategorias);
    final precoMinCtrl =
        TextEditingController(
          text: precoMinLocal != null
              ? precoMinLocal.toStringAsFixed(2)
              : '',
        );
    final precoMaxCtrl =
        TextEditingController(
          text: precoMaxLocal != null
              ? precoMaxLocal.toStringAsFixed(2)
              : '',
        );
    String ordemTemp = _filtroOrdenacao;
    String dispTemp = _filtroDisponibilidade;
    RangeValues rangeTemp = RangeValues(
      _filtroPrecoMin ?? 0,
      _filtroPrecoMax ?? 500,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // ===== Alça de arrasto =====
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ===== Header =====
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Filtrar produtos',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _textoPrimario,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Encontre exatamente o que você procura.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ===== Conteúdo scrollável =====
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Categoria ---
                          _secaoFiltroLabel(
                            Icons.category_rounded,
                            'Categoria',
                          ),
                          const SizedBox(height: 10),
                          _FiltroCategoriaDropdown(
                            categoriasSelecionadas: categoriasSelecionadas,
                            onChanged: (novas) {
                              setModalState(
                                () => categoriasSelecionadas = novas,
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // --- Faixa de preço ---
                          _secaoFiltroLabel(
                            Icons.monetization_on_outlined,
                            'Faixa de preço',
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _campoPreco(
                                  ctx,
                                  'Mínimo',
                                  precoMinCtrl,
                                  onChanged: (v) {
                                    final val = double.tryParse(
                                      v.replaceAll(',', '.'),
                                    );
                                    setModalState(() {
                                      if (val != null) {
                                        rangeTemp = RangeValues(
                                          val,
                                          rangeTemp.end,
                                        );
                                      }
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Container(
                                  width: 20,
                                  height: 2,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              Expanded(
                                child: _campoPreco(
                                  ctx,
                                  'Máximo',
                                  precoMaxCtrl,
                                  onChanged: (v) {
                                    final val = double.tryParse(
                                      v.replaceAll(',', '.'),
                                    );
                                    setModalState(() {
                                      if (val != null) {
                                        rangeTemp = RangeValues(
                                          rangeTemp.start,
                                          val,
                                        );
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          RangeSlider(
                            values: RangeValues(
                              rangeTemp.start.clamp(0, 500),
                              rangeTemp.end.clamp(0, 500),
                            ),
                            min: 0,
                            max: 500,
                            divisions: 100,
                            activeColor: _laranja,
                            inactiveColor: _laranja.withValues(alpha: 0.2),
                            overlayColor: WidgetStateProperty.all(
                              _laranja.withValues(alpha: 0.12),
                            ),
                            labels: RangeLabels(
                              'R\$ ${rangeTemp.start.toStringAsFixed(0)}',
                              'R\$ ${rangeTemp.end.toStringAsFixed(0)}',
                            ),
                            onChanged: (v) {
                              setModalState(() {
                                rangeTemp = v;
                                precoMinCtrl.text = v.start.toStringAsFixed(2);
                                precoMaxCtrl.text = v.end.toStringAsFixed(2);
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'R\$ 0',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                Text(
                                  'R\$ 500',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // --- Ordenar por ---
                          _secaoFiltroLabel(
                            Icons.sort_rounded,
                            'Ordenar por',
                          ),
                          const SizedBox(height: 10),
                          _wrapChips(
                            ctx,
                            [
                              _opcaoOrdenacao('mais_relevantes', 'Mais relevantes'),
                              _opcaoOrdenacao('menor_preco', 'Menor preço'),
                              _opcaoOrdenacao('maior_preco', 'Maior preço'),
                              _opcaoOrdenacao('melhor_avaliados', 'Melhor avaliados'),
                              _opcaoOrdenacao('mais_vendidos', 'Mais vendidos'),
                              _opcaoOrdenacao('mais_recentes', 'Mais recentes'),
                            ].map((opt) {
                              final selecionado = ordemTemp == opt.valor;
                              return _chipFiltro(
                                label: opt.rotulo,
                                selecionado: selecionado,
                                onTap: () => setModalState(
                                  () => ordemTemp = opt.valor,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // --- Disponibilidade ---
                          _secaoFiltroLabel(
                            Icons.check_circle_outline_rounded,
                            'Disponibilidade',
                          ),
                          const SizedBox(height: 10),
                          _wrapChips(
                            ctx,
                            [
                              ('todos', 'Todos'),
                              ('disponiveis', 'Apenas disponíveis'),
                              ('lojas_abertas', 'Apenas lojas abertas'),
                            ].map((opt) {
                              final selecionado = dispTemp == opt.$1;
                              return _chipFiltro(
                                label: opt.$2,
                                selecionado: selecionado,
                                onTap: () => setModalState(
                                  () => dispTemp = opt.$1,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ===== Rodapé com botões =====
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  categoriasSelecionadas = {};
                                  precoMinCtrl.clear();
                                  precoMaxCtrl.clear();
                                  rangeTemp = const RangeValues(0, 500);
                                  ordemTemp = 'mais_relevantes';
                                  dispTemp = 'todos';
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textoMuted,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Limpar filtros',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _filtroCategorias =
                                      categoriasSelecionadas;
                                  _filtroPrecoMin =
                                      rangeTemp.start > 0
                                          ? rangeTemp.start
                                          : null;
                                  _filtroPrecoMax =
                                      rangeTemp.end < 500
                                          ? rangeTemp.end
                                          : null;
                                  _filtroOrdenacao = ordemTemp;
                                  _filtroDisponibilidade = dispTemp;
                                });
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _laranja,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Aplicar filtros',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _secaoFiltroLabel(IconData icone, String texto) {
    return Row(
      children: [
        Icon(icone, size: 18, color: _roxo),
        const SizedBox(width: 8),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _textoPrimario,
          ),
        ),
      ],
    );
  }

  Widget _campoPreco(
    BuildContext ctx,
    String hint,
    TextEditingController ctrl, {
    required void Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _textoPrimario,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
          ),
          prefixText: 'R\$ ',
          prefixStyle: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _chipFiltro({
    required String label,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selecionado ? _laranja : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: selecionado
              ? Border.all(color: _laranja, width: 1)
              : Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
            color: selecionado ? Colors.white : _textoMuted,
          ),
        ),
      ),
    );
  }

  Widget _wrapChips(BuildContext ctx, List<Widget> chips) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: chips,
    );
  }

  ({String valor, String rotulo}) _opcaoOrdenacao(
    String valor,
    String rotulo,
  ) =>
      (valor: valor, rotulo: rotulo);

  Widget _buildSkeletonCarregamentoVitrine() {
    Widget linhaProduto() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 280,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: diPertinScrollPaddingTabShell(
        context,
        left: 12,
        right: 12,
        top: 8,
        extraBottom: 16,
      ),
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++) linhaProduto(),
      ],
    );
  }

  @override
  void dispose() {
    _bannersSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _iniciarEscutaBanners() {
    _bannersSubscription?.cancel();
    _bannersSubscription = FirebaseFirestore.instance
        .collection('banners')
        .where('ativo', isEqualTo: true)
        .snapshots()
        .listen(_aplicarSnapshotBanners);
  }

  void _aplicarSnapshotBanners(QuerySnapshot snapshot) {
    if (!mounted) return;
    final docs = snapshot.docs;
    if (_mesmosDocumentosBanner(_bannersDocsBrutos, docs)) return;
    setState(() => _bannersDocsBrutos = docs);
  }

  static bool _mesmosDocumentosBanner(
    List<QueryDocumentSnapshot> a,
    List<QueryDocumentSnapshot> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _atualizarBannersDoServidor() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('banners')
          .where('ativo', isEqualTo: true)
          .get(const GetOptions(source: Source.server));
      _aplicarSnapshotBanners(snap);
    } catch (_) {}
  }

  String _donoProduto(Map<String, dynamic> p) {
    return (p['lojista_id'] ?? p['loja_id'] ?? '').toString();
  }

  /// Loja na região do GPS (texto da cidade ou proximidade das coordenadas).
  bool _cidadeCorresponde(
    Map<String, dynamic> dados,
    String cidadeNorm,
    String ufNorm,
    LocationService locationService,
  ) =>
      LocationService.lojaPublicaNaRegiaoDoUsuario(
        dados: dados,
        cidadeNormUsuario: cidadeNorm,
        ufNormUsuario: ufNorm,
        usuarioLat: locationService.ultimaLatitude,
        usuarioLng: locationService.ultimaLongitude,
      );

  static bool _lojaStatusAprovadoParaVitrine(Map<String, dynamic> lojaData) {
    final status =
        (lojaData['status_loja'] ?? 'pendente').toString().trim().toLowerCase();
    return status == 'aprovada' ||
        status == 'aprovado' ||
        status == 'ativo';
  }

  /// Banner dentro do período configurado no painel (alinhado ao uso de datas).
  /// Sem `data_inicio`/`data_fim` (legado) → continua visível se `ativo`.
  bool _bannerDentroDoPeriodoVigente(Map<String, dynamic> data) {
    final now = DateTime.now();
    final di = data['data_inicio'];
    final df = data['data_fim'];
    if (di == null && df == null) return true;
    if (di is Timestamp) {
      if (now.isBefore(di.toDate())) return false;
    }
    if (df is Timestamp) {
      final f = df.toDate();
      final fimDia = DateTime(f.year, f.month, f.day, 23, 59, 59, 999);
      if (now.isAfter(fimDia)) return false;
    }
    return true;
  }

  List<QueryDocumentSnapshot> _filtrarBannersCidade(
    List<QueryDocumentSnapshot> banners,
    String cidadeNorm,
    String ufNorm,
    LocationService locationService,
  ) {
    return banners.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      if (!_bannerDentroDoPeriodoVigente(data)) return false;
      String cidadeBanner = (data['cidade'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (cidadeBanner == 'todas') return true;
      return _cidadeCorresponde(data, cidadeNorm, ufNorm, locationService);
    }).toList();
  }

  bool _verificarSeLojaEstaAberta(Map<String, dynamic> loja) {
    return LojaPausa.lojaEstaAberta(loja);
  }

  /// Nome da loja (Config. operacional: `loja_nome` em [users]), não o nome do perfil (`nome`).
  String _nomeLojaParaCardVitrine(Map<String, dynamic> lojaData) {
    for (final key in ['loja_nome', 'nome_loja']) {
      final v = lojaData[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    final n = lojaData['nome']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Loja Parceira';
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final cidadeNorm = locationService.cidadeNormalizada;
    final ufNorm = locationService.ufNormalizado;
    final cidadeExibicao = locationService.cidadeExibicao;

    if (!locationService.cidadePronta) {
      return Scaffold(
        backgroundColor: _fundoTela,
        body: Column(
          children: [
            _buildHeaderGradient(locationService, cidadeExibicao),
            Expanded(child: _buildSkeletonCarregamentoVitrine()),
          ],
        ),
      );
    }

    final bannersDoBanco = _filtrarBannersCidade(
      _bannersDocsBrutos,
      cidadeNorm,
      ufNorm,
      locationService,
    );

    return Scaffold(
      backgroundColor: _fundoTela,
      body: Stack(
        children: [
          Column(
            children: [
              Column(
                key: _cabecalhoBuscaKey,
                children: [
                  _buildHeaderGradient(locationService, cidadeExibicao),
                  _buildSearchBar(),
                ],
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_showSuggestions) {
                      setState(() => _showSuggestions = false);
                    }
                  },
              child: AnimatedOpacity(
              opacity: _entradaAnimada ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
              // Fase 3G.2 — vitrine lê `lojas_public` (mirror só com dados de
              // fachada) em vez de `users`. CPF/email/telefone pessoal/saldo
              // do lojista não são mais expostos na vitrine pública.
              stream: FirebaseFirestore.instance
                  .collection('lojas_public')
                  .snapshots(),
              builder: (context, snapshotLojas) {
                if (snapshotLojas.connectionState == ConnectionState.waiting &&
                    !snapshotLojas.hasData) {
                  return _buildSkeletonCarregamentoVitrine();
                }
                if (!snapshotLojas.hasData ||
                    snapshotLojas.data!.docs.isEmpty) {
                  return _listaComPullParaVazio(
                    _painelVazio(
                      Icons.store_mall_directory_outlined,
                      'Nenhuma loja nesta cidade ainda',
                      'Quando houver lojas parceiras aprovadas, os '
                          'produtos aparecem aqui. Você pode atualizar a '
                          'localização pelo ícone de GPS no topo.',
                    ),
                  );
                }

                Map<String, bool> statusLojas = {};
                Map<String, Map<String, dynamic>> dadosLojasPorId = {};
                Map<String, String> nomesLojas = {};
                Map<String, double?> ratingMediaLojas = {};
                Map<String, int> totalAvaliacoesLojas = {};

                for (var doc in snapshotLojas.data!.docs) {
                  var lojaData = doc.data() as Map<String, dynamic>;
                  dadosLojasPorId[doc.id] = lojaData;

                  if (!_cidadeCorresponde(
                    lojaData,
                    cidadeNorm,
                    ufNorm,
                    locationService,
                  )) {
                    continue;
                  }

                  if (!_lojaStatusAprovadoParaVitrine(lojaData)) {
                    continue;
                  }

                  statusLojas[doc.id] = _verificarSeLojaEstaAberta(lojaData);
                  nomesLojas[doc.id] = _nomeLojaParaCardVitrine(lojaData);
                  ratingMediaLojas[doc.id] = (lojaData['rating_media'] as num?)
                      ?.toDouble();
                  totalAvaliacoesLojas[doc.id] =
                      (lojaData['total_avaliacoes'] as num?)?.toInt() ?? 0;
                }

                if (kDebugMode) {
                  var rejCidade = 0;
                  var rejStatus = 0;
                  for (final doc in snapshotLojas.data!.docs) {
                    final ld = doc.data() as Map<String, dynamic>;
                    if (!_cidadeCorresponde(ld, cidadeNorm, ufNorm, locationService)) {
                      rejCidade++;
                      continue;
                    }
                    if (!_lojaStatusAprovadoParaVitrine(ld)) rejStatus++;
                  }
                  debugPrint(
                    '[LOJAS] total=${snapshotLojas.data!.docs.length} '
                    "gps='$cidadeExibicao' norm=$cidadeNorm uf=$ufNorm | "
                    'ok=${statusLojas.length} rej_cidade=$rejCidade '
                    'rej_status=$rejStatus',
                  );
                }

                if (statusLojas.isEmpty) {
                  return _listaComPullParaVazio(
                    _painelVazio(
                      Icons.store_mall_directory_outlined,
                      'Nenhuma loja disponível na sua região',
                      'Não há lojas aprovadas para esta cidade no momento. '
                          'Tente novamente mais tarde.',
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('produtos')
                      .where('ativo', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshotProdutos) {
                        if (snapshotProdutos.connectionState ==
                                ConnectionState.waiting &&
                            !snapshotProdutos.hasData) {
                          return _buildSkeletonCarregamentoVitrine();
                        }
                        if (!snapshotProdutos.hasData ||
                            snapshotProdutos.data!.docs.isEmpty) {
                          return _listaComPullParaVazio(
                            _painelVazio(
                              Icons.inventory_2_outlined,
                              'Nenhum produto cadastrado',
                              'As lojas da região ainda não publicaram '
                                  'itens. Volte em breve.',
                            ),
                          );
                        }

                        List<QueryDocumentSnapshot> produtosFiltrados =
                            snapshotProdutos.data!.docs.where((doc) {
                              var p = doc.data() as Map<String, dynamic>;
                              // Loja já validada por cidade/GPS; não repetir filtro
                              // de cidade no produto (campo pode estar desatualizado).
                              return statusLojas.containsKey(_donoProduto(p));
                            }).toList();

                        if (_searchQuery.isNotEmpty) {
                          produtosFiltrados = produtosFiltrados.where((doc) {
                            final p = doc.data() as Map<String, dynamic>;
                            final nome =
                                (p['nome'] as String? ?? '').toLowerCase();
                            final descricao =
                                (p['descricao'] as String? ?? '').toLowerCase();
                            return nome.contains(_searchQuery) ||
                                descricao.contains(_searchQuery);
                          }).toList();
                        }

                        // ===== FILTRO POR CATEGORIA =====
                        if (_filtroCategorias.isNotEmpty) {
                          produtosFiltrados = produtosFiltrados.where((doc) {
                            final p = doc.data() as Map<String, dynamic>;
                            final cat =
                                (p['categoria'] as String? ?? '').trim();
                            return cat.isNotEmpty &&
                                _filtroCategorias.contains(cat);
                          }).toList();
                        }

                        // ===== FILTRO POR FAIXA DE PREÇO =====
                        if (_filtroPrecoMin != null ||
                            _filtroPrecoMax != null) {
                          produtosFiltrados = produtosFiltrados.where((doc) {
                            final p = doc.data() as Map<String, dynamic>;
                            final preco =
                                (p['preco'] as num?)?.toDouble() ?? 0;
                            final oferta =
                                (p['oferta'] as num?)?.toDouble();
                            final validoOferta = oferta != null &&
                                preco > 0 &&
                                oferta < preco;
                            final precoFinal =
                                validoOferta ? oferta : preco;
                            if (_filtroPrecoMin != null &&
                                precoFinal < _filtroPrecoMin!) {
                              return false;
                            }
                            if (_filtroPrecoMax != null &&
                                precoFinal > _filtroPrecoMax!) {
                              return false;
                            }
                            return true;
                          }).toList();
                        }

                        // ===== FILTRO POR DISPONIBILIDADE =====
                        if (_filtroDisponibilidade == 'disponiveis') {
                          produtosFiltrados = produtosFiltrados.where((doc) {
                            final p = doc.data() as Map<String, dynamic>;
                            final tipoVenda =
                                (p['tipo_venda'] ?? 'estoque').toString();
                            if (tipoVenda == 'encomenda') return true;
                            final estoque =
                                (p['estoque_qtd'] as num?)?.toInt() ?? 0;
                            return estoque > 0;
                          }).toList();
                        } else if (_filtroDisponibilidade == 'lojas_abertas') {
                          produtosFiltrados = produtosFiltrados.where((doc) {
                            final p = doc.data() as Map<String, dynamic>;
                            final lojaId = _donoProduto(p);
                            return statusLojas[lojaId] == true;
                          }).toList();
                        }

                        // ===== ORDENAÇÃO =====
                        if (_filtroOrdenacao == 'menor_preco') {
                          produtosFiltrados.sort((a, b) {
                            final pa = a.data() as Map<String, dynamic>;
                            final pb = b.data() as Map<String, dynamic>;
                            final precoA = (pa['preco'] as num?)?.toDouble() ?? 0;
                            final ofertaA = (pa['oferta'] as num?)?.toDouble();
                            final finalA = (ofertaA != null && ofertaA < precoA) ? ofertaA : precoA;
                            final precoB = (pb['preco'] as num?)?.toDouble() ?? 0;
                            final ofertaB = (pb['oferta'] as num?)?.toDouble();
                            final finalB = (ofertaB != null && ofertaB < precoB) ? ofertaB : precoB;
                            return finalA.compareTo(finalB);
                          });
                        } else if (_filtroOrdenacao == 'maior_preco') {
                          produtosFiltrados.sort((a, b) {
                            final pa = a.data() as Map<String, dynamic>;
                            final pb = b.data() as Map<String, dynamic>;
                            final precoA = (pa['preco'] as num?)?.toDouble() ?? 0;
                            final ofertaA = (pa['oferta'] as num?)?.toDouble();
                            final finalA = (ofertaA != null && ofertaA < precoA) ? ofertaA : precoA;
                            final precoB = (pb['preco'] as num?)?.toDouble() ?? 0;
                            final ofertaB = (pb['oferta'] as num?)?.toDouble();
                            final finalB = (ofertaB != null && ofertaB < precoB) ? ofertaB : precoB;
                            return finalB.compareTo(finalA);
                          });
                        } else if (_filtroOrdenacao == 'melhor_avaliados') {
                          produtosFiltrados.sort((a, b) {
                            final pa = a.data() as Map<String, dynamic>;
                            final pb = b.data() as Map<String, dynamic>;
                            final lojaA = _donoProduto(pa);
                            final lojaB = _donoProduto(pb);
                            final ratingA = ratingMediaLojas[lojaA] ?? 0;
                            final ratingB = ratingMediaLojas[lojaB] ?? 0;
                            return ratingB.compareTo(ratingA);
                          });
                        } else if (_filtroOrdenacao == 'mais_vendidos') {
                          produtosFiltrados.sort((a, b) {
                            final pa = a.data() as Map<String, dynamic>;
                            final pb = b.data() as Map<String, dynamic>;
                            final vendaA = (pa['total_vendas'] as num?)?.toInt() ?? 0;
                            final vendaB = (pb['total_vendas'] as num?)?.toInt() ?? 0;
                            return vendaB.compareTo(vendaA);
                          });
                        } else if (_filtroOrdenacao == 'mais_recentes') {
                          produtosFiltrados.sort((a, b) {
                            return b.id.compareTo(a.id);
                          });
                        }

                        if (kDebugMode) {
                          debugPrint(
                            '[PRODUTOS] antes filtro: '
                            '${snapshotProdutos.data!.docs.length} | '
                            'após filtro cidade: ${produtosFiltrados.length}',
                          );
                        }

                        if (produtosFiltrados.isEmpty) {
                          final String vazioMsg;
                          final String vazioTitulo;
                          final IconData vazioIcone;
                          if (_searchQuery.isNotEmpty) {
                            vazioMsg = 'Nenhum produto encontrado para '
                                '"${_searchController.text}".';
                            vazioTitulo = 'Nada encontrado';
                            vazioIcone = Icons.search_off_rounded;
                          } else if (_temFiltroAtivo) {
                            vazioMsg =
                                'Tente ajustar os filtros para ver mais '
                                'resultados.';
                            vazioTitulo = 'Nenhum produto encontrado';
                            vazioIcone = Icons.tune_rounded;
                          } else {
                            vazioMsg = 'Não há produtos ativos das lojas '
                                'desta cidade no momento. Puxe para '
                                'atualizar.';
                            vazioTitulo = 'Nenhum produto para mostrar';
                            vazioIcone = Icons.inventory_2_outlined;
                          }
                          return _listaComPullParaVazio(
                            _painelVazio(vazioIcone, vazioTitulo, vazioMsg),
                          );
                        }

                        return _VitrineListaProdutosComPausa(
                          produtosFiltrados: produtosFiltrados,
                          dadosLojasPorId: dadosLojasPorId,
                          nomesLojas: nomesLojas,
                          ratingMediaLojas: ratingMediaLojas,
                          totalAvaliacoesLojas: totalAvaliacoesLojas,
                          bannersDoBanco: bannersDoBanco,
                          buildCard: _buildProductCard,
                          donoProduto: _donoProduto,
                          onRefresh: () async {
                            await locationService.detectarCidade();
                            await _atualizarBannersDoServidor();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 200),
                            );
                          },
                        );
                      },
                );
              },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    _buildSearchSuggestionsOverlay(),
  ],
  ),
);
  }

  Widget _painelVazio(IconData icon, String titulo, String subtitulo) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: _textoMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tipoVendaProdutoVitrine(Map<String, dynamic> p) =>
      (p['tipo_venda'] ?? 'estoque').toString();

  int _estoqueQtdProdutoVitrine(Map<String, dynamic> p) =>
      (p['estoque_qtd'] as num?)?.toInt() ?? 0;

  bool _vitrineAceitaNovaUnidade(Map<String, dynamic> p) {
    if (_tipoVendaProdutoVitrine(p) == 'encomenda') return true;
    return _estoqueQtdProdutoVitrine(p) > 0;
  }

  List<String> _listaVariacaoProdutoVitrine(
    Map<String, dynamic> p,
    List<String> campos,
  ) {
    for (final campo in campos) {
      final raw = p[campo];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  bool _produtoTemVariacoesVitrine(Map<String, dynamic> p) {
    final cores = _listaVariacaoProdutoVitrine(p, ['variacoes_cores', 'cores']);
    final tamanhos = _listaVariacaoProdutoVitrine(p, [
      'variacoes_tamanhos',
      'tamanhos',
      'numeracoes',
    ]);
    return p['usa_variacoes'] == true ||
        cores.isNotEmpty ||
        tamanhos.isNotEmpty;
  }

  void _abrirDetalhesProdutoVitrine(
    BuildContext context,
    Map<String, dynamic> produto,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(produto: produto),
      ),
    );
  }

  int _quantidadeProdutoJaNoCarrinho(CartProvider cart, String productId) {
    if (productId.isEmpty) return 0;
    for (final i in cart.items) {
      if (i.id == productId) return i.quantidade;
    }
    return 0;
  }

  /// Adiciona 1 unidade à sacola sem sair da vitrine (snapshot já traz dados da loja e estoque).
  void _botaoSacolaVitrineAdicionar(
    BuildContext context,
    Map<String, dynamic> produto,
  ) {
    if (_produtoTemVariacoesVitrine(produto)) {
      _abrirDetalhesProdutoVitrine(context, produto);
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Escolha cor, tamanho ou numeração do produto.'),
          backgroundColor: diPertinRoxo,
          duration: Duration(milliseconds: 1600),
        ),
      );
      return;
    }

    final lojaOk = produto['loja_aberta'] != false;
    if (!lojaOk) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Esta loja está fechada ou em pausa — não é possível adicionar à sacola agora.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(milliseconds: 2400),
        ),
      );
      return;
    }
    if (!_vitrineAceitaNovaUnidade(produto)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Este produto está sem estoque.'),
          backgroundColor: Colors.orange,
          duration: Duration(milliseconds: 2100),
        ),
      );
      return;
    }

    final cart = context.read<CartProvider>();
    final String idProduto = '${produto['id_documento'] ?? ''}'.trim();
    if (idProduto.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível identificar o produto. Abra os detalhes.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_tipoVendaProdutoVitrine(produto) != 'encomenda') {
      final maximo = _estoqueQtdProdutoVitrine(produto);
      final ja = _quantidadeProdutoJaNoCarrinho(cart, idProduto);
      if (ja >= maximo) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Limite de estoque atingido ($maximo ${maximo == 1 ? "unidade" : "unidades"}). '
              'Altere quantidades na sacola.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(milliseconds: 2400),
          ),
        );
        return;
      }
    }

    final double? po = (produto['preco'] as num?)?.toDouble();
    final double? of = (produto['oferta'] as num?)?.toDouble();
    final bool ofertaOk = of != null && po != null && of < po;
    final double precoItem = ofertaOk ? of : (of ?? po ?? 0);

    String urlImagem;
    if (produto.containsKey('imagens') &&
        produto['imagens'] is List &&
        (produto['imagens'] as List).isNotEmpty) {
      urlImagem = produto['imagens'][0].toString();
    } else {
      urlImagem = produto['imagem']?.toString() ?? '';
    }

    final item = CartItemModel(
      id: idProduto,
      nome: produto['nome']?.toString() ?? 'Produto',
      preco: precoItem,
      imagem: urlImagem,
      lojaId:
          produto['lojista_id']?.toString() ??
          produto['loja_id']?.toString() ??
          '',
      lojaNome: produto['loja_nome_vitrine']?.toString() ?? 'Loja parceira',
      requerVeiculoGrande:
          produto['requer_veiculo_grande'] == true ||
          produto['carga_maior'] == true,
      ehEncomenda: _tipoVendaProdutoVitrine(produto) == 'encomenda',
    );

    final msg = cart.addItemWithQuantity(item, 1);
    if (msg != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.orange.shade800),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('${item.nome} adicionado à sacola'),
        backgroundColor: Colors.green,
        duration: const Duration(milliseconds: 950),
      ),
    );
  }

  Future<void> _atualizarRegiaoVitrine() async {
    final loc = context.read<LocationService>();
    await loc.detectarCidade();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Widget _listaComPullParaVazio(Widget painel) {
    return RefreshIndicator(
      color: diPertinLaranja,
      onRefresh: _atualizarRegiaoVitrine,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: h.isFinite && h > 120 ? h * 0.88 : 420,
                child: painel,
              ),
            ],
          );
        },
      ),
    );
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

    final double? precoOriginal = (produto['preco'] as num?)?.toDouble();
    final double? precoOferta = (produto['oferta'] as num?)?.toDouble();
    final bool temOferta =
        precoOferta != null &&
        precoOriginal != null &&
        precoOferta < precoOriginal;
    final double precoFinal = temOferta ? precoOferta : (precoOriginal ?? 0.0);
    final bool lojaAberta = produto['loja_aberta'] != false;
    final String motivoPausaPublico =
        (produto['loja_pausa_motivo_publico'] as String?) ?? '';
    final String storeName = produto['loja_nome_vitrine'] ?? 'Loja parceira';
    final double? rating = (produto['rating_media'] as num?)?.toDouble();

    void abrirDetalhes() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailsScreen(produto: produto),
        ),
      );
    }

    const radius = 18.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: abrirDetalhes,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Imagem — altura fixa
              SizedBox(
                height: 110,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imagemVitrine.isNotEmpty)
                        Image.network(
                          imagemVitrine,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: diPertinRoxo.withValues(alpha: 0.05),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: diPertinLaranja,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (c, e, s) =>
                              _placeholderImagemProduto(),
                        )
                      else
                        _placeholderImagemProduto(),

                      // Badge de desconto (top-left)
                      if (temOferta)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '-${((1 - precoOferta / precoOriginal) * 100).round()}% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),

                      // Botão coração (top-right)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: FavoritarBotao(produto: produto),
                      ),

                      // Overlay de loja fechada
                      if (!lojaAberta)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ),
                      if (!lojaAberta)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              motivoPausaPublico.isNotEmpty
                                  ? motivoPausaPublico
                                  : 'Fechada',
                              style: const TextStyle(
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
              // Informações do produto — compactas
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nome do produto
                      Text(
                        produto['nome'] ?? 'Sem nome',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.2,
                          letterSpacing: -0.2,
                          color: Color(0xFF1A1A2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Nome da loja
                      GestureDetector(
                        onTap: () {
                          final id =
                              produto['lojista_id'] ?? produto['loja_id'];
                          if (id != null && '$id'.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LojaPerfilScreen(
                                  lojistaId: '$id',
                                  lojistaData: produto,
                                ),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.storefront_rounded,
                              size: 11,
                              color: diPertinRoxo.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                storeName,
                                style: TextStyle(
                                  color: diPertinRoxo.withValues(alpha: 0.75),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Avaliação
                      Row(
                        children: [
                          Icon(Icons.star_rounded,
                              size: 13, color: diPertinLaranja),
                          const SizedBox(width: 2),
                          Text(
                            rating != null ? rating.toStringAsFixed(1) : '--',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Preço e botão
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (temOferta)
                                  Text(
                                    _fmtMoeda.format(precoOriginal),
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: Colors.grey.shade400,
                                    ),
                                  ),
                                Text(
                                  _fmtMoeda.format(precoFinal),
                                  style: const TextStyle(
                                    color: diPertinLaranja,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color:
                                lojaAberta && _vitrineAceitaNovaUnidade(produto)
                                ? diPertinRoxo
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _botaoSacolaVitrineAdicionar(
                                context,
                                produto,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: const SizedBox(
                                width: 38,
                                height: 38,
                                child: Icon(
                                  Icons.add_shopping_cart_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _placeholderImagemProduto() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            diPertinRoxo.withValues(alpha: 0.08),
            diPertinRoxo.withValues(alpha: 0.03),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 36,
            color: diPertinRoxo.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 4),
          Text(
            'Sem imagem',
            style: TextStyle(
              fontSize: 10,
              color: diPertinRoxo.withValues(alpha: 0.3),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista da vitrine + timer só aqui: reavalia pausa/almoço sem dar `setState` na tela inteira
/// (evita “piscar” a cada leitura do Firestore ou tick do timer).
class _VitrineListaProdutosComPausa extends StatefulWidget {
  const _VitrineListaProdutosComPausa({
    required this.produtosFiltrados,
    required this.dadosLojasPorId,
    required this.nomesLojas,
    required this.ratingMediaLojas,
    required this.totalAvaliacoesLojas,
    required this.bannersDoBanco,
    required this.buildCard,
    required this.donoProduto,
    required this.onRefresh,
  });

  final List<QueryDocumentSnapshot> produtosFiltrados;
  final Map<String, Map<String, dynamic>> dadosLojasPorId;
  final Map<String, String> nomesLojas;
  final Map<String, double?> ratingMediaLojas;
  final Map<String, int> totalAvaliacoesLojas;
  final List<QueryDocumentSnapshot> bannersDoBanco;
  final Widget Function(BuildContext, Map<String, dynamic>) buildCard;
  final String Function(Map<String, dynamic>) donoProduto;
  final Future<void> Function() onRefresh;

  @override
  State<_VitrineListaProdutosComPausa> createState() =>
      _VitrineListaProdutosComPausaState();
}

class _VitrineListaProdutosComPausaState
    extends State<_VitrineListaProdutosComPausa> {
  Timer? _timerReavaliaPausa;

  @override
  void initState() {
    super.initState();
    _timerReavaliaPausa = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timerReavaliaPausa?.cancel();
    super.dispose();
  }

  Map<String, bool> _statusLojasAgora() {
    final m = <String, bool>{};
    for (final id in widget.nomesLojas.keys) {
      final d = widget.dadosLojasPorId[id];
      if (d != null) {
        m[id] = LojaPausa.lojaEstaAberta(d);
      }
    }
    return m;
  }

  // ============ SEÇÃO MAIS VENDIDOS ============
  Widget _buildMaisVendidosSection(
    List<QueryDocumentSnapshot> produtos,
    Map<String, bool> statusLojas,
  ) {
    final comVendas = produtos.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return ((d['total_vendas'] as num?)?.toInt() ?? 0) > 5;
    }).toList();

    if (comVendas.isEmpty) return const SizedBox.shrink();
    final maisVendidos = comVendas.take(10).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Text(
                      '🔥',
                      style: TextStyle(fontSize: 18),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Mais vendidos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    final sorted = List<QueryDocumentSnapshot>.from(comVendas)
                      ..sort((a, b) {
                        final vA = ((a.data() as Map<String, dynamic>)['total_vendas'] as num?)?.toInt() ?? 0;
                        final vB = ((b.data() as Map<String, dynamic>)['total_vendas'] as num?)?.toInt() ?? 0;
                        return vB.compareTo(vA);
                      });
                    _abrirGridProdutos(
                      context,
                      titulo: 'Mais vendidos',
                      icone: '🔥',
                      produtos: sorted,
                      statusLojas: statusLojas,
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: diPertinRoxo,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver todos',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 225,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 4, right: 4),
              itemCount: maisVendidos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                var prod = maisVendidos[index].data() as Map<String, dynamic>;
                prod = Map<String, dynamic>.from(prod);
                prod['id_documento'] = maisVendidos[index].id;
                final idLoja = widget.donoProduto(prod);
                prod['loja_nome_vitrine'] = widget.nomesLojas[idLoja];
                prod['loja_aberta'] = statusLojas[idLoja];
                final dl = widget.dadosLojasPorId[idLoja];
                prod['loja_pausa_motivo_publico'] = dl != null
                    ? LojaPausa.textoMotivoPublico(dl)
                    : '';
                prod['loja_rating_media'] = widget.ratingMediaLojas[idLoja];
                prod['loja_total_avaliacoes'] =
                    widget.totalAvaliacoesLojas[idLoja] ?? 0;

                return SizedBox(
                  width: 200,
                  child: widget.buildCard(context, prod),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============ SEÇÃO LOJAS EM DESTAQUE ============
  Widget _buildLojasDestaqueSection(
    List<QueryDocumentSnapshot> produtos,
    Map<String, bool> statusLojas,
  ) {
    final lojas = widget.nomesLojas.entries.toList();
    if (lojas.isEmpty) return const SizedBox.shrink();

    final vendasPorLoja = <String, int>{};
    for (final doc in produtos) {
      final d = doc.data() as Map<String, dynamic>;
      final lojaId = widget.donoProduto(d);
      final v = (d['total_vendas'] as num?)?.toInt() ?? 0;
      if (v > 0) vendasPorLoja[lojaId] = (vendasPorLoja[lojaId] ?? 0) + v;
    }

    if (vendasPorLoja.isNotEmpty) {
      lojas.sort((a, b) {
        final vb = vendasPorLoja[b.key] ?? 0;
        final va = vendasPorLoja[a.key] ?? 0;
        if (vb != va) return vb.compareTo(va);
        return a.value.compareTo(b.value);
      });
    }

    final exibir = lojas.take(8).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lojas em destaque',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.3,
                  ),
                ),
                TextButton(
                  onPressed: () => _mostrarTodasLojas(lojas, statusLojas),
                  style: TextButton.styleFrom(
                    foregroundColor: diPertinRoxo,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver todas',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 4, right: 4),
              itemCount: exibir.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = exibir[index];
                final lojaId = entry.key;
                final lojaData = widget.dadosLojasPorId[lojaId] ?? <String, dynamic>{};
                final nomeLoja = entry.value;
                final rating = widget.ratingMediaLojas[lojaId];
                final totalAval = widget.totalAvaliacoesLojas[lojaId] ?? 0;
                final aberta = statusLojas[lojaId] ?? false;
                final logoUrl = (lojaData['foto_perfil'] ??
                        lojaData['foto_logo'] ??
                        lojaData['imagem'] ??
                        '')
                    .toString();

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LojaPerfilScreen(
                          lojistaId: lojaId,
                          lojistaData: lojaData,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 160,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        // Logo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: logoUrl.isNotEmpty
                                ? Image.network(
                                    logoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => _placeholderLojaLogo(),
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: const Color(0xFFF4F2F8),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20, height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: diPertinLaranja,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : _placeholderLojaLogo(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Nome da loja
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            nomeLoja,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Avaliação
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star_rounded,
                                size: 14, color: diPertinLaranja),
                            const SizedBox(width: 2),
                            Text(
                              rating != null
                                  ? rating.toStringAsFixed(1)
                                  : '--',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(
                              ' ($totalAval)',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Status
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: aberta
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFEEBEE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: aberta
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE53935),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                aberta ? 'Aberta' : 'Fechada',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: aberta
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE53935),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Info entrega/retirada
                        Text(
                          'Entrega • Retirada',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarTodasLojas(
    List<MapEntry<String, String>> lojas,
    Map<String, bool> statusLojas,
  ) {
    final top10 = lojas.take(10).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    diPertinRoxo.withValues(alpha: 0.04),
                    Colors.white,
                  ],
                  stops: const [0.0, 0.15],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [diPertinRoxo, const Color(0xFF8E24AA)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: diPertinRoxo.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Top lojas',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A2E),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'As lojas mais vendidas do app',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    // Lista
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: top10.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final entry = top10[i];
                          final lojaId = entry.key;
                          final lojaData =
                              widget.dadosLojasPorId[lojaId] ?? {};
                          final nome = entry.value;
                          final aberta = statusLojas[lojaId] ?? false;
                          final rating = widget.ratingMediaLojas[lojaId];
                          final totalAval =
                              widget.totalAvaliacoesLojas[lojaId] ?? 0;
                          final logoUrl = (lojaData['foto_perfil'] ??
                                  lojaData['foto_logo'] ??
                                  lojaData['imagem'] ??
                                  '')
                              .toString();
                          final categoria =
                              (lojaData['categoria'] ?? '').toString();

                          final corPosicao = i == 0
                              ? diPertinRoxo
                              : i == 1
                                  ? diPertinLaranja
                                  : i == 2
                                      ? diPertinRoxo.withValues(alpha: 0.5)
                                      : Colors.transparent;
                          final iconePosicao = i == 0
                              ? Icons.emoji_events_rounded
                              : i == 1
                                  ? Icons.auto_awesome_rounded
                                  : i == 2
                                      ? Icons.star_rounded
                                      : null;

                          return _buildLojaCard(
                            ctx: ctx,
                            i: i,
                            lojaId: lojaId,
                            nome: nome,
                            aberta: aberta,
                            rating: rating,
                            totalAval: totalAval,
                            logoUrl: logoUrl,
                            categoria: categoria,
                            corPosicao: corPosicao,
                            iconePosicao: iconePosicao,
                            lojaData: lojaData,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLojaCard({
    required BuildContext ctx,
    required int i,
    required String lojaId,
    required String nome,
    required bool aberta,
    required double? rating,
    required int totalAval,
    required String logoUrl,
    required String categoria,
    required Color corPosicao,
    required IconData? iconePosicao,
    required Map<String, dynamic> lojaData,
  }) {
    // Cores do posicionamento
    final corBadge = corPosicao;
    final corTextoTrofeu = corBadge != Colors.transparent ? corBadge : diPertinRoxo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LojaPerfilScreen(
                lojistaId: lojaId,
                lojistaData: lojaData,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: corBadge != Colors.transparent
                  ? corBadge.withValues(alpha: 0.25)
                  : Colors.grey.shade100,
              width: corBadge != Colors.transparent ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: corBadge != Colors.transparent
                    ? corBadge.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Posição
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: corBadge != Colors.transparent
                      ? corBadge.withValues(alpha: 0.15)
                      : diPertinRoxo.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: iconePosicao != null
                      ? Icon(iconePosicao, color: corTextoTrofeu, size: 18)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: corTextoTrofeu,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Avatar
              Stack(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: logoUrl.isNotEmpty
                          ? Image.network(
                              logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: diPertinRoxo.withValues(alpha: 0.08),
                                child: Icon(Icons.store_rounded,
                                    color: diPertinRoxo.withValues(alpha: 0.4),
                                    size: 24),
                              ),
                            )
                          : Container(
                              color: diPertinRoxo.withValues(alpha: 0.08),
                              child: Icon(Icons.store_rounded,
                                  color: diPertinRoxo.withValues(alpha: 0.4),
                                  size: 24),
                            ),
                    ),
                  ),
                  if (aberta)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // Rating
                        if (rating != null) ...[
                          Icon(Icons.star_rounded,
                              size: 14, color: diPertinLaranja),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A2E)),
                          ),
                          if (totalAval > 0) ...[
                            const SizedBox(width: 2),
                            Text(
                              '($totalAval)',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Categoria
                        if (categoria.isNotEmpty)
                          Expanded(
                            child: Text(
                              categoria,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: aberta
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: aberta
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      aberta ? 'Aberta' : 'Fechada',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: aberta
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Seta
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirGridProdutos(
    BuildContext context, {
    required String titulo,
    required String icone,
    required List<QueryDocumentSnapshot> produtos,
    required Map<String, bool> statusLojas,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GridProdutosPage(
          titulo: titulo,
          icone: icone,
          produtos: produtos,
          statusLojas: statusLojas,
          dadosLojasPorId: widget.dadosLojasPorId,
          nomesLojas: widget.nomesLojas,
          buildCard: widget.buildCard,
          donoProduto: widget.donoProduto,
        ),
      ),
    );
  }

  Widget _placeholderLojaLogo() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            diPertinRoxo.withValues(alpha: 0.08),
            diPertinRoxo.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Icon(
          Icons.store_rounded,
          size: 28,
          color: diPertinRoxo.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  // ============ SEÇÃO OFERTAS ESPECIAIS ============
  Widget _buildOfertasEspeciaisSection(
    List<QueryDocumentSnapshot> produtos,
    Map<String, bool> statusLojas,
  ) {
    // Filtra produtos marcados como oferta especial
    final ofertasReais = produtos.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return d['is_oferta_especial'] == true && d['ativo'] != false;
    }).toList();

    if (ofertasReais.isEmpty) {
      // Fallback: só mostra os 3 cards estáticos
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOfertasHeader(
              ofertasSnapshot: null,
              statusLojas: statusLojas,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(left: 4, right: 4),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return _buildOfertaCard(index);
                },
              ),
            ),
          ],
        ),
      );
    }

    // Tem ofertas especiais reais: mostra os 3 cards + produtos reais
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOfertasHeader(
              ofertasSnapshot: ofertasReais,
              statusLojas: statusLojas,
            ),
          const SizedBox(height: 12),
          // Cards estáticos promocionais
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 4, right: 4),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _buildOfertaCard(index);
              },
            ),
          ),
          const SizedBox(height: 16),
          // Produtos reais em oferta especial
          SizedBox(
            height: 225,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 4, right: 4),
              itemCount: ofertasReais.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                var prod = ofertasReais[index].data() as Map<String, dynamic>;
                prod = Map<String, dynamic>.from(prod);
                prod['id_documento'] = ofertasReais[index].id;
                final idLoja = widget.donoProduto(prod);
                prod['loja_nome_vitrine'] = widget.nomesLojas[idLoja];
                prod['loja_aberta'] = statusLojas[idLoja];
                final dl = widget.dadosLojasPorId[idLoja];
                prod['loja_pausa_motivo_publico'] = dl != null
                    ? LojaPausa.textoMotivoPublico(dl)
                    : '';

                return SizedBox(
                  width: 170,
                  child: widget.buildCard(context, prod),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfertasHeader({
    List<QueryDocumentSnapshot>? ofertasSnapshot,
    required Map<String, bool> statusLojas,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Ofertas especiais',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.3,
            ),
          ),
          TextButton(
            onPressed: () {
              if (ofertasSnapshot != null && ofertasSnapshot.isNotEmpty) {
                _abrirGridProdutos(
                  context,
                  titulo: 'Ofertas especiais',
                  icone: '🏷️',
                  produtos: ofertasSnapshot,
                  statusLojas: statusLojas,
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: diPertinRoxo,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ver todas',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward_ios, size: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfertaCard(int index) {
    final ofertas = [
      _OfertaInfo(
        'Até 20% OFF',
        'Produtos selecionados',
        diPertinRoxo,
        diPertinRoxo.withValues(alpha: 0.08),
        Icons.local_offer_rounded,
      ),
      _OfertaInfo(
        'Frete grátis',
        r'Acima de R$ 50,00',
        diPertinLaranja,
        diPertinLaranja.withValues(alpha: 0.08),
        Icons.local_shipping_rounded,
      ),
      _OfertaInfo(
        'Pague com Pix ou Cartão',
        'Ganhe 5% OFF',
        diPertinRoxo,
        diPertinRoxo.withValues(alpha: 0.08),
        Icons.pix_rounded,
      ),
    ];

    final oferta = ofertas[index];
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            oferta.bgColor,
            oferta.bgColor.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: oferta.accentColor.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: oferta.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              oferta.icon,
              color: oferta.accentColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            oferta.titulo,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: oferta.accentColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            oferta.subtitulo,
            style: TextStyle(
              fontSize: 12,
              color: oferta.accentColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ============ GRID DE PRODUTOS ============
  List<Widget> _buildProductGrid(
    List<QueryDocumentSnapshot> produtos,
    Map<String, bool> statusLojas,
  ) {
    final itens = <Widget>[];

    // Título da grade
    itens.add(
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          'Produtos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
            letterSpacing: -0.3,
          ),
        ),
      ),
    );

    for (var i = 0; i < produtos.length; i += 2) {
      var prod1 = produtos[i].data() as Map<String, dynamic>;
      prod1 = Map<String, dynamic>.from(prod1);
      prod1['id_documento'] = produtos[i].id;
      final idLoja1 = widget.donoProduto(prod1);
      prod1['loja_nome_vitrine'] = widget.nomesLojas[idLoja1];
      prod1['loja_aberta'] = statusLojas[idLoja1];
      final dl1 = widget.dadosLojasPorId[idLoja1];
      prod1['loja_pausa_motivo_publico'] = dl1 != null
          ? LojaPausa.textoMotivoPublico(dl1)
          : '';
      prod1['loja_rating_media'] = widget.ratingMediaLojas[idLoja1];
      prod1['loja_total_avaliacoes'] =
          widget.totalAvaliacoesLojas[idLoja1] ?? 0;

      Map<String, dynamic>? prod2;
      if (i + 1 < produtos.length) {
        prod2 = produtos[i + 1].data() as Map<String, dynamic>;
        prod2 = Map<String, dynamic>.from(prod2);
        prod2['id_documento'] = produtos[i + 1].id;
        final idLoja2 = widget.donoProduto(prod2);
        prod2['loja_nome_vitrine'] = widget.nomesLojas[idLoja2];
        prod2['loja_aberta'] = statusLojas[idLoja2];
        final dl2 = widget.dadosLojasPorId[idLoja2];
        prod2['loja_pausa_motivo_publico'] = dl2 != null
            ? LojaPausa.textoMotivoPublico(dl2)
            : '';
        prod2['loja_rating_media'] = widget.ratingMediaLojas[idLoja2];
        prod2['loja_total_avaliacoes'] =
            widget.totalAvaliacoesLojas[idLoja2] ?? 0;
      }

      itens.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 225,
            child: Row(
              children: [
                Expanded(child: widget.buildCard(context, prod1)),
                const SizedBox(width: 12),
                Expanded(
                  child: prod2 != null
                      ? widget.buildCard(context, prod2)
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      );

      if ((i + 2) % 30 == 0 && (i + 2) < produtos.length) {
        final slot = (i + 2) ~/ 30;
        itens.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 15, top: 5),
            child: AutoSlidingBanner(
              key: ValueKey<String>('vitrine_banner_lista_$slot'),
              banners: widget.bannersDoBanco,
              altura: 120,
              paddingHorizontal: 0,
            ),
          ),
        );
      }
    }

    return itens;
  }

  // ==========================================
  // CATEGORIAS — Mapa de ícones
  // ==========================================
  static const Map<String, IconData> _categoriaIcones = {
    'alimentação': Icons.restaurant_rounded,
    'alimentacao': Icons.restaurant_rounded,
    'alimentos': Icons.restaurant_rounded,
    'comida': Icons.restaurant_rounded,
    'mercado': Icons.shopping_cart_rounded,
    'supermercado': Icons.shopping_cart_rounded,
    'conveniência': Icons.store_rounded,
    'conveniencia': Icons.store_rounded,
    'padaria': Icons.bakery_dining_rounded,
    'doces': Icons.cake_rounded,
    'bebidas': Icons.local_cafe_rounded,
    'farmácia': Icons.local_pharmacy_rounded,
    'farmacia': Icons.local_pharmacy_rounded,
    'saúde': Icons.health_and_safety_rounded,
    'saude': Icons.health_and_safety_rounded,
    'beleza': Icons.spa_rounded,
    'moda': Icons.checkroom_rounded,
    'vestuário': Icons.checkroom_rounded,
    'vestuario': Icons.checkroom_rounded,
    'serviços': Icons.build_rounded,
    'servicos': Icons.build_rounded,
    'vagas': Icons.work_rounded,
    'eventos': Icons.celebration_rounded,
    'pet': Icons.pets_rounded,
    'pets': Icons.pets_rounded,
    'eletrônicos': Icons.devices_rounded,
    'eletronicos': Icons.devices_rounded,
    'tecnologia': Icons.devices_rounded,
    'celulares': Icons.smartphone_rounded,
    'informática': Icons.computer_rounded,
    'informatica': Icons.computer_rounded,
    'ferramentas': Icons.build_rounded,
    'construção': Icons.construction_rounded,
    'construcao': Icons.construction_rounded,
    'automotivo': Icons.directions_car_rounded,
    'esportes': Icons.sports_soccer_rounded,
    'fitness': Icons.fitness_center_rounded,
    'academia': Icons.fitness_center_rounded,
    'brinquedos': Icons.toys_rounded,
    'games': Icons.sports_esports_rounded,
    'jogos': Icons.sports_esports_rounded,
    'música': Icons.music_note_rounded,
    'musica': Icons.music_note_rounded,
    'livros': Icons.menu_book_rounded,
    'papelaria': Icons.edit_note_rounded,
    'presentes': Icons.card_giftcard_rounded,
    'flores': Icons.local_florist_rounded,
    'utilidades': Icons.home_rounded,
    'variedades': Icons.auto_awesome_rounded,
    'decoração': Icons.palette_rounded,
    'decoracao': Icons.palette_rounded,
    'iluminação': Icons.light_rounded,
    'iluminacao': Icons.light_rounded,
    'móveis': Icons.chair_rounded,
    'moveis': Icons.chair_rounded,
    'cama': Icons.bed_rounded,
    'quarto': Icons.bed_rounded,
    'cozinha': Icons.kitchen_rounded,
    'limpeza': Icons.cleaning_services_rounded,
    'infantil': Icons.child_friendly_rounded,
    'bebê': Icons.child_friendly_rounded,
    'bebe': Icons.child_friendly_rounded,
  };

  static IconData _iconeDaCategoria(String nome) {
    final chave = nome.trim().toLowerCase();
    if (_categoriaIcones.containsKey(chave)) return _categoriaIcones[chave]!;
    for (final entry in _categoriaIcones.entries) {
      if (chave.contains(entry.key) || entry.key.contains(chave)) {
        return entry.value;
      }
    }
    return Icons.category_rounded;
  }

  /// Resolve um iconKey (string) para IconData do Material Icons.
  static IconData _resolverIconeChave(String iconKey) {
    switch (iconKey) {
      case 'restaurant': return Icons.restaurant_rounded;
      case 'local_dining': return Icons.local_dining_rounded;
      case 'lunch_dining': return Icons.lunch_dining_rounded;
      case 'local_pizza': return Icons.local_pizza_rounded;
      case 'bakery_dining': return Icons.bakery_dining_rounded;
      case 'cake': return Icons.cake_rounded;
      case 'icecream': return Icons.icecream_rounded;
      case 'local_cafe': return Icons.local_cafe_rounded;
      case 'shopping_cart': return Icons.shopping_cart_rounded;
      case 'store': return Icons.store_rounded;
      case 'local_pharmacy': return Icons.local_pharmacy_rounded;
      case 'health_and_safety': return Icons.health_and_safety_rounded;
      case 'medical_services': return Icons.medical_services_rounded;
      case 'local_hospital': return Icons.local_hospital_rounded;
      case 'spa': return Icons.spa_rounded;
      case 'content_cut': return Icons.content_cut_rounded;
      case 'face': return Icons.face_rounded;
      case 'pan_tool': return Icons.pan_tool_rounded;
      case 'checkroom': return Icons.checkroom_rounded;
      case 'ice_skating': return Icons.ice_skating_rounded;
      case 'watch': return Icons.watch_rounded;
      case 'build': return Icons.build_rounded;
      case 'work': return Icons.work_rounded;
      case 'celebration': return Icons.celebration_rounded;
      case 'music_note': return Icons.music_note_rounded;
      case 'pets': return Icons.pets_rounded;
      case 'devices': return Icons.devices_rounded;
      case 'smartphone': return Icons.smartphone_rounded;
      case 'computer': return Icons.computer_rounded;
      case 'sports_esports': return Icons.sports_esports_rounded;
      case 'home': return Icons.home_rounded;
      case 'construction': return Icons.construction_rounded;
      case 'local_shipping': return Icons.local_shipping_rounded;
      case 'motorcycle': return Icons.motorcycle_rounded;
      case 'directions_car': return Icons.directions_car_rounded;
      case 'sports_soccer': return Icons.sports_soccer_rounded;
      case 'fitness_center': return Icons.fitness_center_rounded;
      case 'menu_book': return Icons.menu_book_rounded;
      case 'edit_note': return Icons.edit_note_rounded;
      case 'toys': return Icons.toys_rounded;
      case 'card_giftcard': return Icons.card_giftcard_rounded;
      case 'local_florist': return Icons.local_florist_rounded;
      case 'auto_awesome': return Icons.auto_awesome_rounded;
      case 'palette': return Icons.palette_rounded;
      case 'light': return Icons.light_rounded;
      case 'chair': return Icons.chair_rounded;
      case 'bed': return Icons.bed_rounded;
      case 'kitchen': return Icons.kitchen_rounded;
      case 'cleaning_services': return Icons.cleaning_services_rounded;
      case 'child_friendly': return Icons.child_friendly_rounded;
      case 'bathtub': return Icons.bathtub_rounded;
      case 'electrical_services': return Icons.electrical_services_rounded;
      case 'visibility': return Icons.visibility_rounded;
      case 'carpenter': return Icons.carpenter_rounded;
      case 'handyman': return Icons.handyman_rounded;
      case 'yard': return Icons.yard_rounded;
      case 'pool': return Icons.pool_rounded;
      case 'security': return Icons.security_rounded;
      case 'videocam': return Icons.videocam_rounded;
      case 'print': return Icons.print_rounded;
      case 'photo_camera': return Icons.photo_camera_rounded;
      case 'flight': return Icons.flight_rounded;
      case 'hotel': return Icons.hotel_rounded;
      case 'school': return Icons.school_rounded;
      case 'language': return Icons.language_rounded;
      case 'translate': return Icons.translate_rounded;
      case 'account_balance': return Icons.account_balance_rounded;
      case 'gavel': return Icons.gavel_rounded;
      case 'engineering': return Icons.engineering_rounded;
      case 'draw': return Icons.draw_rounded;
      case 'campaign': return Icons.campaign_rounded;
      case 'code': return Icons.code_rounded;
      case 'nature': return Icons.nature_rounded;
      case 'directions_bike': return Icons.directions_bike_rounded;
      case 'kayaking': return Icons.kayaking_rounded;
      case 'skateboarding': return Icons.skateboarding_rounded;
      case 'surfing': return Icons.surfing_rounded;
      case 'dining': return Icons.dining_rounded;
      case 'liquor': return Icons.liquor_rounded;
      case 'wine_bar': return Icons.wine_bar_rounded;
      case 'coffee': return Icons.coffee_rounded;
      case 'delivery_dining': return Icons.delivery_dining_rounded;
      case 'bike_scooter': return Icons.bike_scooter_rounded;
      case 'bus_alert': return Icons.bus_alert_rounded;
      case 'train': return Icons.train_rounded;
      case 'subway': return Icons.subway_rounded;
      case 'taxi_alert': return Icons.taxi_alert_rounded;
      case 'two_wheeler': return Icons.two_wheeler_rounded;
      case 'electric_bike': return Icons.electric_bike_rounded;
      case 'electric_scooter': return Icons.electric_scooter_rounded;
      case 'electric_car': return Icons.electric_car_rounded;
      // Ícones adicionais do painel web (compatibilidade)
      case 'hand_gesture': return Icons.pan_tool_rounded;
      case 'sewing': return Icons.carpenter_rounded;
      case 'sports_basketball': return Icons.sports_basketball_rounded;
      case 'sports_tennis': return Icons.sports_tennis_rounded;
      case 'sports_volleyball': return Icons.sports_volleyball_rounded;
      case 'sports_kabaddi': return Icons.sports_kabaddi_rounded;
      case 'sports_martial_arts': return Icons.sports_martial_arts_rounded;
      case 'sports_handball': return Icons.sports_handball_rounded;
      case 'sports': return Icons.sports_rounded;
      case 'hiking': return Icons.hiking_rounded;
      case 'camping': return Icons.nature_rounded;
      case 'cycling': return Icons.directions_bike_rounded;
      case 'delivery': return Icons.delivery_dining_rounded;
      case 'bike': return Icons.bike_scooter_rounded;
      case 'truck': return Icons.local_shipping_rounded;
      case 'bus': return Icons.bus_alert_rounded;
      case 'taxi': return Icons.taxi_alert_rounded;
      // NOVOS ÍCONES — Importação, Logística, Finanças, etc.
      case 'import_export': return Icons.import_export_rounded;
      case 'public': return Icons.public_rounded;
      case 'assignment': return Icons.assignment_rounded;
      case 'description': return Icons.description_rounded;
      case 'receipt_long': return Icons.receipt_long_rounded;
      case 'warehouse': return Icons.warehouse_rounded;
      case 'inventory': return Icons.inventory_rounded;
      case 'payments': return Icons.payments_rounded;
      case 'monetization_on': return Icons.monetization_on_rounded;
      case 'request_quote': return Icons.request_quote_rounded;
      case 'sell': return Icons.sell_rounded;
      case 'book': return Icons.book_rounded;
      case 'post_add': return Icons.post_add_rounded;
      case 'agriculture': return Icons.agriculture_rounded;
      case 'grass': return Icons.grass_rounded;
      case 'forest': return Icons.forest_rounded;
      case 'water_drop': return Icons.water_drop_rounded;
      case 'gas_meter': return Icons.gas_meter_rounded;
      case 'plumbing': return Icons.plumbing_rounded;
      case 'roofing': return Icons.roofing_rounded;
      case 'pest_control': return Icons.pest_control_rounded;
      case 'dry_cleaning': return Icons.dry_cleaning_rounded;
      case 'local_laundry_service': return Icons.local_laundry_service_rounded;
      case 'elderly': return Icons.elderly_rounded;
      case 'diamond': return Icons.diamond_rounded;
      case 'piano': return Icons.piano_rounded;
      case 'theater_comedy': return Icons.theater_comedy_rounded;
      case 'car_repair': return Icons.car_repair_rounded;
      case 'tire_repair': return Icons.tire_repair_rounded;
      case 'real_estate_agent': return Icons.real_estate_agent_rounded;
      case 'apartment': return Icons.apartment_rounded;
      case 'location_city': return Icons.location_city_rounded;
      case 'house': return Icons.house_rounded;
      case 'luggage': return Icons.luggage_rounded;
      case 'map': return Icons.map_rounded;
      case 'beach_access': return Icons.beach_access_rounded;
      case 'architecture': return Icons.architecture_rounded;
      case 'design_services': return Icons.design_services_rounded;
      case 'precision_manufacturing': return Icons.precision_manufacturing_rounded;
      case 'recycling': return Icons.recycling_rounded;
      case 'compost': return Icons.compost_rounded;
      case 'masks': return Icons.masks_rounded;
      case 'vaccines': return Icons.vaccines_rounded;
      case 'pedal_bike': return Icons.pedal_bike_rounded;
      case 'electric_moped': return Icons.electric_moped_rounded;
      case 'moped': return Icons.moped_rounded;
      case 'sailing': return Icons.sailing_rounded;
      case 'paragliding': return Icons.paragliding_rounded;
      case 'roller_skating': return Icons.roller_skating_rounded;
      case 'downhill_skiing': return Icons.downhill_skiing_rounded;
      case 'snowboarding': return Icons.snowboarding_rounded;
      case 'sledding': return Icons.sledding_rounded;
      case 'elderly_woman': return Icons.elderly_woman_rounded;
      default: return Icons.category_rounded;
    }
  }

  /// Seção horizontal premium de categorias.
  Widget _buildCategoriasSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 0, bottom: 14),
            child: Row(
              children: [
                // Barra gradiente roxo → laranja
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [diPertinRoxo, diPertinLaranja],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Categorias',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                // Link "Ver todas" em laranja — abre tela dedicada
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pushNamed('/todas-categorias'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    foregroundColor: diPertinLaranja,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Ver todas',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: diPertinLaranja,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 122,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('categorias')
                  .where('ativo', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 4),
                    itemCount: 6,
                    itemBuilder: (_, _) => _skeletonCategoriaCard(),
                  );
                }

                final todas = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final ma = a.data() as Map<String, dynamic>;
                    final mb = b.data() as Map<String, dynamic>;
                    final oa = (ma['ordem'] as num?)?.toInt() ?? 999;
                    final ob = (mb['ordem'] as num?)?.toInt() ?? 999;
                    if (oa != ob) return oa.compareTo(ob);
                    return (ma['nome'] ?? '').toString().compareTo(
                      (mb['nome'] ?? '').toString(),
                    );
                  });

                final destaques = todas
                    .where((d) =>
                        ((d.data() as Map<String, dynamic>)['destaque']) == true)
                    .toList();
                final categorias =
                    (destaques.isNotEmpty ? destaques : todas).take(24).toList();

                if (categorias.isEmpty) return const SizedBox.shrink();

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: categorias.length,
                  itemBuilder: (context, index) {
                    final cat =
                        categorias[index].data() as Map<String, dynamic>;
                    final nome = cat['nome'] ?? '';
                    final imagem = cat['imagem'] ?? '';
                    final iconKey = cat['iconKey']?.toString() ?? '';

                    // Resolve ícone: imagem > iconKey > auto-suggest > default
                    IconData icone;
                    if (imagem.isNotEmpty) {
                      icone = Icons.image_rounded;
                    } else if (iconKey.isNotEmpty) {
                      icone = _resolverIconeChave(iconKey);
                    } else {
                      icone = _iconeDaCategoria(nome);
                    }

                    // Todas as categorias usam o padrão roxo DiPertin (ignora cores do Firestore)
                    const Color bgColor = Color(0xFFEDE7F6);
                    const Color accentColor = diPertinRoxo;

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context, rootNavigator: true)
                              .pushNamedAndRemoveUntil(
                            '/home',
                            (_) => false,
                            arguments: 0,
                          );
                        },
                        child: Container(
                          width: 88,
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: bgColor.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: bgColor.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.6),
                                blurRadius: 0,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Anel gradiente sutil ao redor do ícone
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    colors: [
                                      accentColor.withValues(alpha: 0.15),
                                      accentColor.withValues(alpha: 0.05),
                                      diPertinRoxo.withValues(alpha: 0.08),
                                      accentColor.withValues(alpha: 0.15),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            accentColor.withValues(alpha: 0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    icone,
                                    size: 24,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  nome,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: _textoPrimario,
                                    letterSpacing: -0.2,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonCategoriaCard() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.grey.shade200,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 50,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusLojas = _statusLojasAgora();
    final produtos = List<QueryDocumentSnapshot>.from(widget.produtosFiltrados)
      ..sort((a, b) {
        final pA = a.data() as Map<String, dynamic>;
        final pB = b.data() as Map<String, dynamic>;
        final abertaA = statusLojas[widget.donoProduto(pA)] ?? true;
        final abertaB = statusLojas[widget.donoProduto(pB)] ?? true;
        if (abertaA && !abertaB) return -1;
        if (!abertaA && abertaB) return 1;
        return 0;
      });

    final itensDaVitrine = <Widget>[];

    // 1. Banner principal
    if (widget.bannersDoBanco.isNotEmpty) {
      itensDaVitrine.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AutoSlidingBanner(
            key: const ValueKey<String>('vitrine_banner_topo'),
            banners: widget.bannersDoBanco,
            altura: 150,
            paddingHorizontal: 0,
          ),
        ),
      );
    }

    // 2. Categorias
    itensDaVitrine.add(_buildCategoriasSection());

    // 3. Mais Vendidos
    itensDaVitrine.add(_buildMaisVendidosSection(produtos, statusLojas));

    // 4. Lojas em Destaque
    itensDaVitrine.add(_buildLojasDestaqueSection(produtos, statusLojas));

    // 5. Ofertas Especiais
    itensDaVitrine.add(_buildOfertasEspeciaisSection(produtos, statusLojas));

    // 6. Grid de produtos
    itensDaVitrine.addAll(_buildProductGrid(produtos, statusLojas));

    return RefreshIndicator(
      color: diPertinLaranja,
      onRefresh: widget.onRefresh,
      child: RepaintBoundary(
        child: ListView(
          key: const PageStorageKey<String>('vitrine_lista_produtos'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: itensDaVitrine,
        ),
      ),
    );
  }
}

class _OfertaInfo {
  final String titulo;
  final String subtitulo;
  final Color accentColor;
  final Color bgColor;
  final IconData icon;
  const _OfertaInfo(
    this.titulo,
    this.subtitulo,
    this.accentColor,
    this.bgColor,
    this.icon,
  );
}

// ==========================================
// Carrossel de banners (altura fixa, card único, indicadores)
// ==========================================
class AutoSlidingBanner extends StatefulWidget {
  final List<QueryDocumentSnapshot> banners;
  final double altura;

  /// Recuo lateral do card. Use `0` quando o pai já tiver padding (ex.: lista da vitrine).
  final double paddingHorizontal;

  const AutoSlidingBanner({
    super.key,
    required this.banners,
    required this.altura,
    this.paddingHorizontal = 16,
  });

  @override
  State<AutoSlidingBanner> createState() => _AutoSlidingBannerState();
}

class _AutoSlidingBannerState extends State<AutoSlidingBanner>
    with WidgetsBindingObserver {
  PageController? _pageController;
  Timer? _timer;
  int _totalItems = 0;

  /// Índice lógico da página (inclui loop infinito).
  int _paginaAtual = 0;

  /// Slide visível nos indicadores (evita setState redundante).
  int _slideIndicador = 0;

  bool _animandoPagina = false;

  static String _idsBanners(List<QueryDocumentSnapshot> docs) =>
      docs.map((d) => d.id).join('|');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configurarCarrossel(widget.banners, reiniciarPagina: true);
  }

  void _configurarCarrossel(
    List<QueryDocumentSnapshot> banners, {
    required bool reiniciarPagina,
  }) {
    _totalItems = banners.length;
    if (reiniciarPagina) {
      _paginaAtual = _totalItems > 0 ? _totalItems * 1000 : 0;
      _slideIndicador = 0;
      _pageController?.dispose();
      _pageController = PageController(
        initialPage: _paginaAtual,
        viewportFraction: 1,
      );
    }
    _iniciarAnimacao();
  }

  void _iniciarAnimacao() {
    _timer?.cancel();
    _timer = null;
    if (_totalItems <= 1 || !mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final ctrl = _pageController;
      if (!mounted || _animandoPagina || ctrl == null || !ctrl.hasClients) {
        return;
      }
      _animandoPagina = true;
      final proxima = _paginaAtual + 1;
      ctrl
          .animateToPage(
            proxima,
            duration: const Duration(milliseconds: 800),
            curve: Curves.fastOutSlowIn,
          )
          .whenComplete(() {
        if (mounted) _animandoPagina = false;
      });
    });
  }

  void _pausarAutoplay() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _iniciarAnimacao();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pausarAutoplay();
    }
  }

  @override
  void didUpdateWidget(AutoSlidingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_idsBanners(oldWidget.banners) == _idsBanners(widget.banners) &&
        oldWidget.altura == widget.altura) {
      return;
    }
    if (widget.banners.isEmpty) {
      _pausarAutoplay();
      _pageController?.dispose();
      _pageController = null;
      _totalItems = 0;
      return;
    }
    final int slideAntes = _totalItems > 0 ? _slideIndicador : 0;
    final reiniciar =
        _pageController == null ||
        oldWidget.banners.length != widget.banners.length;
    _configurarCarrossel(widget.banners, reiniciarPagina: reiniciar);
    if (!reiniciar) {
      final ctrl = _pageController;
      if (ctrl != null && ctrl.hasClients) {
        final alvo = _totalItems * 1000 + (slideAntes % _totalItems);
        _paginaAtual = alvo;
        _slideIndicador = slideAntes % _totalItems;
        ctrl.jumpToPage(alvo);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pausarAutoplay();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _abrirLink(String linkDestino) async {
    if (linkDestino.isEmpty) return;
    final Uri url = Uri.parse(linkDestino);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _slideBannerRede(
    String bannerDocId,
    String urlImagem,
    String linkDestino,
  ) {
    return GestureDetector(
      onTap: () => _abrirLink(linkDestino),
      behavior: HitTestBehavior.opaque,
      child: urlImagem.trim().isEmpty
          ? ColoredBox(
              color: const Color(0xFFF0EEF5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hide_image_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Banner sem imagem',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final double w = constraints.maxWidth;
                final double h = constraints.maxHeight;
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final int cacheW = (w * dpr).round().clamp(1, 4096);
                final int cacheH = (h * dpr).round().clamp(1, 4096);

                return ClipRect(
                  child: Image.network(
                    urlImagem,
                    key: ValueKey<String>('banner_${bannerDocId}_$urlImagem'),
                    width: w,
                    height: h,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    cacheWidth: cacheW,
                    cacheHeight: cacheH,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return SizedBox(width: w, height: h, child: child);
                      }
                      return ColoredBox(
                        color: Colors.white,
                        child: Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: diPertinRoxo.withValues(alpha: 0.85),
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: const Color(0xFFF0EEF5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_tethering_error_rounded,
                            size: 36,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Não foi possível carregar',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_totalItems == 0) return const SizedBox.shrink();

    final ctrl = _pageController;
    if (ctrl == null) return const SizedBox.shrink();

    final int slideAtivo = _slideIndicador;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.paddingHorizontal),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8E6ED)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: widget.altura,
              width: double.infinity,
              child: PageView.builder(
                controller: ctrl,
                onPageChanged: (int index) {
                  _paginaAtual = index;
                  final novoSlide = _totalItems > 0 ? index % _totalItems : 0;
                  if (novoSlide != _slideIndicador) {
                    setState(() => _slideIndicador = novoSlide);
                  }
                },
                itemCount: _totalItems > 1 ? null : 1,
                itemBuilder: (context, index) {
                  final int indexReal = index % _totalItems;

                  final Map<String, dynamic> bannerData =
                      widget.banners[indexReal].data() as Map<String, dynamic>;
                  final String urlImagem =
                      bannerData['imagem'] ?? bannerData['url_imagem'] ?? '';
                  final String linkDestino =
                      bannerData['link'] ?? bannerData['link_destino'] ?? '';

                  return _slideBannerRede(
                    widget.banners[indexReal].id,
                    urlImagem,
                    linkDestino,
                  );
                },
              ),
            ),
          ),
          if (_totalItems > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalItems, (i) {
                final bool ativo = slideAtivo == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: ativo ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: ativo ? diPertinLaranja : Colors.grey.shade300,
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Página premium "Ver todos" para grid de produtos
// ============================================================
class _GridProdutosPage extends StatefulWidget {
  final String titulo;
  final String icone;
  final List<QueryDocumentSnapshot> produtos;
  final Map<String, bool> statusLojas;
  final Map<String, Map<String, dynamic>> dadosLojasPorId;
  final Map<String, String> nomesLojas;
  final Widget Function(BuildContext, Map<String, dynamic>) buildCard;
  final String Function(Map<String, dynamic>) donoProduto;

  const _GridProdutosPage({
    required this.titulo,
    required this.icone,
    required this.produtos,
    required this.statusLojas,
    required this.dadosLojasPorId,
    required this.nomesLojas,
    required this.buildCard,
    required this.donoProduto,
  });

  @override
  State<_GridProdutosPage> createState() => _GridProdutosPageState();
}

class _GridProdutosPageState extends State<_GridProdutosPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _enriquecerProdutos() {
    return widget.produtos.map((doc) {
      var prod = doc.data() as Map<String, dynamic>;
      prod = Map<String, dynamic>.from(prod);
      prod['id_documento'] = doc.id;
      final idLoja = widget.donoProduto(prod);
      prod['loja_nome_vitrine'] = widget.nomesLojas[idLoja];
      prod['loja_aberta'] = widget.statusLojas[idLoja];
      final dl = widget.dadosLojasPorId[idLoja];
      prod['loja_pausa_motivo_publico'] = dl != null
          ? LojaPausa.textoMotivoPublico(dl)
          : '';
      return prod;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final produtosEnriquecidos = _enriquecerProdutos();
    final temProdutos = produtosEnriquecidos.isNotEmpty;

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        backgroundColor: diPertinRoxo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.icone, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              widget.titulo,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (temProdutos)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${produtosEnriquecidos.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body:
          temProdutos ? _buildGrid(produtosEnriquecidos) : _buildEmptyState(),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> produtos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        final cardWidth = (constraints.maxWidth - 40) / crossAxisCount;

        return FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: cardWidth / 320,
              ),
              itemCount: produtos.length,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: cardWidth,
                  child: widget.buildCard(context, produtos[index]),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: diPertinRoxo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Icon(
                    widget.titulo == 'Ofertas especiais'
                        ? Icons.local_offer_rounded
                        : Icons.shopping_bag_rounded,
                    size: 44,
                    color: diPertinRoxo.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.titulo == 'Ofertas especiais'
                      ? 'Nenhuma oferta disponível'
                      : 'Nenhum produto disponível',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.titulo == 'Ofertas especiais'
                      ? 'No momento não há ofertas especiais ativas.\nFique de olho, em breve novidades!'
                      : 'Ainda não temos produtos cadastrados.\nVolte em breve para conferir as novidades!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade500,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: diPertinLaranja,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Disponível em breve',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: diPertinLaranja,
                        ),
                      ),
                    ],
                  ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Dropdown de categoria para o modal de filtro (economiza espaço)
// ==========================================
class _FiltroCategoriaDropdown extends StatefulWidget {
  final Set<String> categoriasSelecionadas;
  final ValueChanged<Set<String>> onChanged;

  const _FiltroCategoriaDropdown({
    required this.categoriasSelecionadas,
    required this.onChanged,
  });

  @override
  State<_FiltroCategoriaDropdown> createState() =>
      _FiltroCategoriaDropdownState();
}

class _FiltroCategoriaDropdownState extends State<_FiltroCategoriaDropdown> {
  List<QueryDocumentSnapshot>? _todasCategorias;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
  }

  Future<void> _carregarCategorias() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categorias')
          .where('ativo', isEqualTo: true)
          .get();
      if (!mounted) return;
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ma = a.data();
          final mb = b.data();
          final oa = (ma['ordem'] as num?)?.toInt() ?? 999;
          final ob = (mb['ordem'] as num?)?.toInt() ?? 999;
          if (oa != ob) return oa.compareTo(ob);
          return (ma['nome'] ?? '').toString().compareTo(
            (mb['nome'] ?? '').toString(),
          );
        });
      setState(() => _todasCategorias = docs);
    } catch (_) {
      if (mounted) setState(() => _todasCategorias = []);
    }
  }

  void _abrirSelecaoCategorias(BuildContext ctx) {
    final nomesCategorias = _todasCategorias!
        .map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return (d['nome'] ?? '').toString().trim();
        })
        .where((n) => n.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sCtx, setSheetState) {
            final selecionadas =
                Set<String>.from(widget.categoriasSelecionadas);
            return Container(
              height: MediaQuery.of(sCtx).size.height * 0.55,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Alça de arrasto
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        const Text(
                          'Selecionar categorias',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(sCtx),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.grey.shade600,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Lista de categorias com checkbox
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: nomesCategorias.map((nome) {
                        final checked = selecionadas.contains(nome);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(
                            nome,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          activeColor: const Color(0xFF6A1B9A),
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: checked
                              ? const Color(0xFF6A1B9A).withValues(alpha: 0.05)
                              : null,
                          onChanged: (v) {
                            setSheetState(() {
                              if (v == true) {
                                selecionadas.add(nome);
                              } else {
                                selecionadas.remove(nome);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  // Botão confirmar
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onChanged(selecionadas);
                            Navigator.pop(sCtx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8F00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Confirmar (${selecionadas.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_todasCategorias == null) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_todasCategorias!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Nenhuma categoria disponível',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    final selecionadas = widget.categoriasSelecionadas;
    final texto = selecionadas.isEmpty
        ? 'Todas as categorias'
        : '${selecionadas.length} selecionada${selecionadas.length > 1 ? 's' : ''}';

    return GestureDetector(
      onTap: () => _abrirSelecaoCategorias(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selecionadas.isNotEmpty
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: selecionadas.isNotEmpty
                      ? const Color(0xFF6A1B9A)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: Colors.grey.shade500,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
