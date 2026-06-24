// Arquivo: lib/screens/cliente/meus_favoritos_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/favoritos_service.dart';
import 'product_details_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _bordaCard = Color(0xFFE8E6ED);

class MeusFavoritosScreen extends StatefulWidget {
  const MeusFavoritosScreen({super.key});

  @override
  State<MeusFavoritosScreen> createState() => _MeusFavoritosScreenState();
}

class _MeusFavoritosScreenState extends State<MeusFavoritosScreen> {
  final NumberFormat _fmtMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );

  List<QueryDocumentSnapshot> _docs = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    try {
      final snap = await FavoritosService.instance.listar(user.uid);
      if (mounted) {
        setState(() {
          _docs = snap.docs;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erro = 'Erro ao carregar favoritos';
          _carregando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _textoPrimario),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: _diPertinLaranja,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Meus favoritos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _textoPrimario,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
      body: user == null
          ? _buildSemLogin()
          : _carregando
              ? const Center(
                  child: CircularProgressIndicator(color: _diPertinRoxo),
                )
              : _erro != null
                  ? _buildErro()
                  : _docs.isEmpty
                      ? _buildVazio()
                      : RefreshIndicator(
                          color: _diPertinRoxo,
                          onRefresh: _carregar,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              24 + MediaQuery.of(context).padding.bottom,
                            ),
                            child: ListView.separated(
                              itemCount: _docs.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final data = _docs[index].data() as Map<String, dynamic>;
                                final docId = _docs[index].id;
                                final nome = data['nome'] ?? '';
                                final dynamic imagensRaw = data['imagens'];
                                final String imagem;
                                if (data['imagem'] != null && data['imagem'].toString().isNotEmpty) {
                                  imagem = data['imagem'].toString();
                                } else if (imagensRaw is List && imagensRaw.isNotEmpty) {
                                  imagem = imagensRaw[0].toString();
                                } else {
                                  imagem = '';
                                }
                                final precoOriginal = (data['preco'] ?? data['precoOriginal'] ?? 0.0).toDouble();
                                final precoOferta = (data['oferta'] ?? data['precoOferta'] ?? 0.0).toDouble();
                                final temOferta = precoOferta > 0 && precoOferta < precoOriginal;
                                final lojaNome = data['loja_nome_vitrine']?.toString() ??
                                    data['loja_nome']?.toString() ??
                                    data['lojaNome']?.toString() ?? '';

                                return _buildFavoritoCard(
                                  produtoId: docId,
                                  nome: nome,
                                  imagem: imagem,
                                  precoOriginal: precoOriginal,
                                  precoOferta: precoOferta,
                                  temOferta: temOferta,
                                  lojaNome: lojaNome,
                                  data: data,
                                );
                              },
                            ),
                          ),
                        ),
    );
  }

  Widget _buildSemLogin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: [
          // Ilustração principal
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_diPertinRoxo, _diPertinLaranja],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 46,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Favoritos DiPertin',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Salve seus produtos preferidos para\nencontrá-los rápido quando precisar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: _textoMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          // Cards de benefícios
          _buildBeneficioCard(
            Icons.directions_bike_rounded,
            'Peça depois com 1 toque',
            'Favoritou? Na próxima compra é só entrar aqui e pedir de novo.',
          ),
          const SizedBox(height: 10),
          _buildBeneficioCard(
            Icons.notifications_active_rounded,
            'Promoções dos seus favoritos',
            'Quando um produto favoritado entrar em oferta, você fica sabendo.',
          ),
          const SizedBox(height: 10),
          _buildBeneficioCard(
            Icons.shopping_bag_rounded,
            'Monte sua lista de desejos',
            'Guarde tudo o que você quer comprar e faça as compras no seu ritmo.',
          ),
          const SizedBox(height: 32),
          // CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false),
              icon: const Icon(Icons.store_rounded, size: 20),
              label: const Text(
                'Ir para a vitrine',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _diPertinRoxo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: _textoMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Não foi possível carregar seus favoritos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: _textoMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // Ilustração principal
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _diPertinRoxo.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 44,
              color: _diPertinRoxo.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Lista de favoritos vazia',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Você ainda não favoritou nenhum produto.\nQue tal começar agora?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _textoMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          // Dicas em cards visuais
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _bordaCard),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _dicaItem(
                  Icons.touch_app_rounded,
                  'Toque no coração',
                  'Ao ver um produto que gostou, toque no ícone de coração ♥',
                ),
                Divider(height: 1, color: _bordaCard.withValues(alpha: 0.6)),
                _dicaItem(
                  Icons.visibility_rounded,
                  'Veja os detalhes',
                  'Confira preço, fotos e descrição antes de favoritar.',
                ),
                Divider(height: 1, color: _bordaCard.withValues(alpha: 0.6)),
                _dicaItem(
                  Icons.favorite_rounded,
                  'Acesse quando quiser',
                  'Seus favoritos ficam salvos aqui no seu perfil.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Botão para explorar
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false),
              icon: const Icon(Icons.explore_rounded, size: 20),
              label: const Text(
                'Explorar produtos',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _diPertinRoxo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeneficioCard(IconData icon, String titulo, String descricao) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bordaCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _diPertinRoxo.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: _diPertinRoxo, size: 22),
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
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  descricao,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _textoMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dicaItem(IconData icon, String titulo, String descricao) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _diPertinRoxo.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _diPertinRoxo, size: 20),
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
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descricao,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _textoMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritoCard({
    required String produtoId,
    required String nome,
    required String imagem,
    required double precoOriginal,
    required double precoOferta,
    required bool temOferta,
    required String lojaNome,
    required Map<String, dynamic> data,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(produto: data),
          ),
        );
      },
      child: Container(
        height: 122,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _bordaCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Imagem
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(18),
              ),
              child: SizedBox(
                width: 110,
                height: 122,
                child: imagem.isNotEmpty
                    ? Image.network(
                        imagem,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: _diPertinRoxo.withValues(alpha: 0.06),
                          child: Icon(
                            Icons.image_outlined,
                            color: _diPertinRoxo.withValues(alpha: 0.3),
                            size: 36,
                          ),
                        ),
                      )
                    : Container(
                        color: _diPertinRoxo.withValues(alpha: 0.06),
                        child: Icon(
                          Icons.image_outlined,
                          color: _diPertinRoxo.withValues(alpha: 0.3),
                          size: 36,
                        ),
                      ),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (lojaNome.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lojaNome,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textoMuted.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (temOferta) ...[
                          Text(
                            _fmtMoeda.format(precoOriginal),
                            style: TextStyle(
                              fontSize: 12,
                              color: _textoMuted.withValues(alpha: 0.6),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _fmtMoeda.format(precoOferta),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                        ] else ...[
                          Text(
                            _fmtMoeda.format(precoOriginal),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _diPertinRoxo,
                            ),
                          ),
                        ],
                        const Spacer(),
                        // Botão remover
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid == null) return;
                              await FavoritosService.instance.remover(uid, produtoId);
                              _carregar();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _diPertinRoxo.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 20,
                                color: _diPertinLaranja,
                              ),
                            ),
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
    );
  }
}
