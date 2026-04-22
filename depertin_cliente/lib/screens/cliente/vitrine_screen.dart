// Arquivo: lib/screens/cliente/vitrine_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:depertin_cliente/widgets/loja_rating_row.dart';

import '../../providers/cart_provider.dart';
import '../../services/location_service.dart';
import '../../utils/loja_pausa.dart';
import 'cart_screen.dart';
import 'product_details_screen.dart';
import '../lojista/loja_catalogo_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

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

  String _donoProduto(Map<String, dynamic> p) {
    return (p['lojista_id'] ?? p['loja_id'] ?? '').toString();
  }

  /// Verifica se a cidade do documento bate EXATAMENTE com a cidade do GPS.
  /// Sem fallback: documento sem cidade = não visível.
  bool _cidadeCorresponde(
    Map<String, dynamic> dados,
    String cidadeNorm,
    String ufNorm,
  ) {
    final cidadeBanco = dados['cidade_normalizada']?.toString().trim() ??
        dados['cidade']?.toString().trim() ??
        dados['endereco_cidade']?.toString().trim();
    if (cidadeBanco == null || cidadeBanco.isEmpty) return false;
    final cidadeNormBanco = LocationService.normalizar(cidadeBanco);
    if (cidadeNormBanco != cidadeNorm) return false;

    final ufBanco = dados['uf']?.toString() ?? dados['estado']?.toString();
    if (ufBanco != null && ufBanco.trim().isNotEmpty) {
      final ufNormBanco =
          LocationService.extrairUf(ufBanco) ??
          LocationService.normalizar(ufBanco);
      if (ufNormBanco != ufNorm) return false;
    }
    return true;
  }

  /// Produto deve pertencer a uma loja da cidade do GPS.
  /// Se o produto tiver cidade própria, deve coincidir; senão, depende da loja (já filtrada).
  bool _produtoNaMesmaRegiao(
    Map<String, dynamic> p,
    String cidadeNorm,
    String ufNorm,
  ) {
    final cn = p['cidade_normalizada']?.toString().trim();
    if (cn != null && cn.isNotEmpty) {
      return LocationService.normalizar(cn) == cidadeNorm;
    }
    final c = p['cidade']?.toString().trim();
    if (c != null && c.isNotEmpty) {
      if (LocationService.normalizar(c) != cidadeNorm) return false;
      final u = p['uf']?.toString() ?? p['estado']?.toString();
      if (u != null && u.trim().isNotEmpty) {
        final un =
            LocationService.extrairUf(u) ?? LocationService.normalizar(u);
        if (un != ufNorm) return false;
      }
      return true;
    }
    // Sem cidade no produto: depende exclusivamente do filtro da loja (statusLojas)
    return true;
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
      final fimDia =
          DateTime(f.year, f.month, f.day, 23, 59, 59, 999);
      if (now.isAfter(fimDia)) return false;
    }
    return true;
  }

  List<QueryDocumentSnapshot> _filtrarBannersCidade(
    List<QueryDocumentSnapshot> banners,
    String cidadeNorm,
    String ufNorm,
  ) {
    return banners.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      if (!_bannerDentroDoPeriodoVigente(data)) return false;
      String cidadeBanner = (data['cidade'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (cidadeBanner == 'todas') return true;
      return _cidadeCorresponde(data, cidadeNorm, ufNorm);
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
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: diPertinRoxo,
          elevation: 0,
          title: const Text(
            'DiPertin',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: diPertinRoxo),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: diPertinRoxo,
        elevation: 0,
        toolbarHeight: 92,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'DiPertin',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              'O que você precisa, bem aqui',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 13, color: diPertinLaranja),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Comprando em $cidadeExibicao',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.white),
            tooltip: 'Atualizar cidade pelo GPS',
            onPressed: locationService.detectandoCidade
                ? null
                : () => locationService.detectarCidade(),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                tooltip: 'Abrir carrinho',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CartScreen()),
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
        ],
      ),
      body: Column(
        children: [
          // 1. CARROSSEL DE BANNERS
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('banners')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              List<QueryDocumentSnapshot> bannersDoBanco = [];
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                bannersDoBanco = _filtrarBannersCidade(
                  snapshot.data!.docs,
                  cidadeNorm,
                  ufNorm,
                );
              }

              return Container(
                margin: EdgeInsets.symmetric(
                  vertical: bannersDoBanco.isEmpty ? 6 : 10,
                ),
                child: AutoSlidingBanner(
                  banners: bannersDoBanco,
                  altura: 150,
                  paddingHorizontal: 16,
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text(
                //   'Destaques da sua região — $cidadeExibicao',
                //   style: const TextStyle(
                //     fontSize: 18,
                //     fontWeight: FontWeight.bold,
                //     color: Colors.black87,
                //   ),
                // ),
                const SizedBox(height: 4),
                // Text(
                //   'Lojas abertas no horário aparecem primeiro. Toque no produto '
                //   'para ver detalhes ou na loja para ver o cardápio.',
                //   style: TextStyle(
                //     fontSize: 13,
                //     height: 1.35,
                //     color: Colors.grey[700],
                //   ),
                // ),
              ],
            ),
          ),

          // 2. VITRINE DE PRODUTOS
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
                  return const Center(
                    child: CircularProgressIndicator(color: diPertinRoxo),
                  );
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

                  if (!_cidadeCorresponde(lojaData, cidadeNorm, ufNorm)) {
                    continue;
                  }

                  String status = lojaData['status_loja'] ?? 'pendente';
                  if (status != 'aprovada' &&
                      status != 'aprovado' &&
                      status != 'ativo') {
                    continue;
                  }

                  statusLojas[doc.id] = _verificarSeLojaEstaAberta(lojaData);
                  nomesLojas[doc.id] = _nomeLojaParaCardVitrine(lojaData);
                  ratingMediaLojas[doc.id] =
                      (lojaData['rating_media'] as num?)?.toDouble();
                  totalAvaliacoesLojas[doc.id] =
                      (lojaData['total_avaliacoes'] as num?)?.toInt() ?? 0;
                }

                if (kDebugMode) {
                  debugPrint(
                    '[LOJAS] total: ${snapshotLojas.data!.docs.length} | '
                    "filtradas '$cidadeExibicao': ${statusLojas.length}",
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
                      .collection('banners')
                      .where('ativo', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshotBanners) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('produtos')
                          .where('ativo', isEqualTo: true)
                          .snapshots(),
                      builder: (context, snapshotProdutos) {
                        if (snapshotProdutos.connectionState ==
                                ConnectionState.waiting &&
                            !snapshotProdutos.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: diPertinRoxo,
                            ),
                          );
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
                              if (!statusLojas.containsKey(_donoProduto(p))) {
                                return false;
                              }
                              return _produtoNaMesmaRegiao(
                                p,
                                cidadeNorm,
                                ufNorm,
                              );
                            }).toList();

                        if (kDebugMode) {
                          debugPrint(
                            '[PRODUTOS] antes filtro: '
                            '${snapshotProdutos.data!.docs.length} | '
                            'após filtro cidade: ${produtosFiltrados.length}',
                          );
                        }

                        if (produtosFiltrados.isEmpty) {
                          return _listaComPullParaVazio(
                            _painelVazio(
                              Icons.shopping_bag_outlined,
                              'Nenhum produto para mostrar',
                              'Não há produtos ativos das lojas desta cidade '
                                  'no momento. Puxe para atualizar.',
                            ),
                          );
                        }

                        final bannersDoBanco = _filtrarBannersCidade(
                          snapshotBanners.data?.docs ?? [],
                          cidadeNorm,
                          ufNorm,
                        );

                        return _VitrineListaProdutosComPausa(
                          produtosFiltrados: produtosFiltrados,
                          dadosLojasPorId: dadosLojasPorId,
                          nomesLojas: nomesLojas,
                          ratingMediaLojas: ratingMediaLojas,
                          totalAvaliacoesLojas: totalAvaliacoesLojas,
                          bannersDoBanco: bannersDoBanco,
                          buildCard: _buildProductCard,
                          donoProduto: _donoProduto,
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
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaComPullParaVazio(Widget painel) {
    return RefreshIndicator(
      color: diPertinLaranja,
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      },
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

    void abrirDetalhes() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailsScreen(produto: produto),
        ),
      );
    }

    const radius = 16.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: abrirDetalhes,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFE8E6ED)),
            boxShadow: [
              BoxShadow(
                color: diPertinRoxo.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 52,
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
                              color: const Color(0xFFF4F2F8),
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
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.0),
                                Colors.black.withValues(alpha: 0.06),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!lojaAberta)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ),
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
                              gradient: LinearGradient(
                                colors: [
                                  Colors.red.shade600,
                                  Colors.red.shade700,
                                ],
                              ),
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
                              '-${((1 - precoOferta / precoOriginal) * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      if (!lojaAberta)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 148),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              motivoPausaPublico.isNotEmpty
                                  ? motivoPausaPublico
                                  : 'Fechada',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 48,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          produto['nome'] ?? 'Sem nome',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.2,
                            letterSpacing: -0.2,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Material(
                        color: const Color(0xFFF3E5F5).withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () {
                            final id =
                                produto['lojista_id'] ?? produto['loja_id'];
                            if (id != null && '$id'.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LojaCatalogoScreen(
                                    lojaId: '$id',
                                    nomeLoja:
                                        produto['loja_nome_vitrine'] ??
                                        'Loja parceira',
                                  ),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.storefront_rounded,
                                  size: 13,
                                  color: diPertinRoxo.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    produto['loja_nome_vitrine'] ??
                                        'Loja parceira',
                                    style: TextStyle(
                                      color: diPertinRoxo.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2, right: 4),
                        child: LojaRatingRow(
                          media:
                              (produto['loja_rating_media'] as num?)?.toDouble(),
                          total:
                              (produto['loja_total_avaliacoes'] as num?)?.toInt() ??
                              0,
                          dense: true,
                          fontSize: 10,
                          iconSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (temOferta)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      _fmtMoeda.format(precoOriginal),
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                Text(
                                  _fmtMoeda.format(precoFinal),
                                  style: const TextStyle(
                                    color: diPertinLaranja,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color: diPertinRoxo,
                            elevation: 2,
                            shadowColor: diPertinRoxo.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: abrirDetalhes,
                              borderRadius: BorderRadius.circular(12),
                              child: const SizedBox(
                                width: 40,
                                height: 40,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderImagemProduto() {
    return Container(
      color: const Color(0xFFF4F2F8),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 40,
        color: Colors.grey.shade400,
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
  });

  final List<QueryDocumentSnapshot> produtosFiltrados;
  final Map<String, Map<String, dynamic>> dadosLojasPorId;
  final Map<String, String> nomesLojas;
  final Map<String, double?> ratingMediaLojas;
  final Map<String, int> totalAvaliacoesLojas;
  final List<QueryDocumentSnapshot> bannersDoBanco;
  final Widget Function(BuildContext, Map<String, dynamic>) buildCard;
  final String Function(Map<String, dynamic>) donoProduto;

  @override
  State<_VitrineListaProdutosComPausa> createState() =>
      _VitrineListaProdutosComPausaState();
}

class _VitrineListaProdutosComPausaState
    extends State<_VitrineListaProdutosComPausa> {
  /// Reavalia horário de pausa sem rebuild do Scaffold/StreamBuilders externos.
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

    for (var i = 0; i < produtos.length; i += 2) {
      var prod1 = produtos[i].data() as Map<String, dynamic>;
      prod1 = Map<String, dynamic>.from(prod1);
      prod1['id_documento'] = produtos[i].id;
      final idLoja1 = widget.donoProduto(prod1);
      prod1['loja_nome_vitrine'] = widget.nomesLojas[idLoja1];
      prod1['loja_aberta'] = statusLojas[idLoja1];
      final dl1 = widget.dadosLojasPorId[idLoja1];
      prod1['loja_pausa_motivo_publico'] =
          dl1 != null ? LojaPausa.textoMotivoPublico(dl1) : '';
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
        prod2['loja_pausa_motivo_publico'] =
            dl2 != null ? LojaPausa.textoMotivoPublico(dl2) : '';
        prod2['loja_rating_media'] = widget.ratingMediaLojas[idLoja2];
        prod2['loja_total_avaliacoes'] =
            widget.totalAvaliacoesLojas[idLoja2] ?? 0;
      }

      itensDaVitrine.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 280,
            child: Row(
              children: [
                Expanded(
                  child: widget.buildCard(context, prod1),
                ),
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
        itensDaVitrine.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 15, top: 5),
            child: AutoSlidingBanner(
              banners: widget.bannersDoBanco,
              altura: 120,
              paddingHorizontal: 0,
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      color: diPertinLaranja,
      onRefresh: () async {
        try {
          await FirebaseFirestore.instance
              .collection('banners')
              .where('ativo', isEqualTo: true)
              .get(const GetOptions(source: Source.server));
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      child: RepaintBoundary(
        child: ListView(
          key: const PageStorageKey<String>('vitrine_lista_produtos'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: itensDaVitrine,
        ),
      ),
    );
  }
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

class _AutoSlidingBannerState extends State<AutoSlidingBanner> {
  late PageController _pageController;
  Timer? _timer;
  int _totalItems = 0;

  /// Índice lógico da página (inclui loop infinito).
  int _paginaAtual = 0;

  @override
  void initState() {
    super.initState();

    _totalItems = widget.banners.length;

    _paginaAtual = _totalItems > 0 ? _totalItems * 1000 : 0;

    _pageController = PageController(
      initialPage: _paginaAtual,
      viewportFraction: 1,
    );

    _iniciarAnimacao();
  }

  void _iniciarAnimacao() {
    _timer?.cancel();
    if (_totalItems > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
        if (_pageController.hasClients) {
          _paginaAtual++;
          _pageController.animateToPage(
            _paginaAtual,
            duration: const Duration(milliseconds: 800),
            curve: Curves.fastOutSlowIn,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(AutoSlidingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int novosTotal = widget.banners.length;
    if (_totalItems != novosTotal) {
      _totalItems = novosTotal;
      _paginaAtual = _totalItems > 0 ? _totalItems * 1000 : 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_paginaAtual);
      }
      _iniciarAnimacao();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
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
                    gaplessPlayback: false,
                    cacheWidth: cacheW,
                    cacheHeight: cacheH,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return SizedBox(
                          width: w,
                          height: h,
                          child: child,
                        );
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

    final int slideAtivo = _paginaAtual % _totalItems;

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
                controller: _pageController,
                onPageChanged: (int index) {
                  setState(() {
                    _paginaAtual = index;
                  });
                },
                itemCount: _totalItems > 1 ? null : 1,
                itemBuilder: (context, index) {
                  final int indexReal = index % _totalItems;

                  final Map<String, dynamic> bannerData =
                      widget.banners[indexReal].data()
                          as Map<String, dynamic>;
                  final String urlImagem =
                      bannerData['imagem'] ??
                      bannerData['url_imagem'] ??
                      '';
                  final String linkDestino =
                      bannerData['link'] ??
                      bannerData['link_destino'] ??
                      '';

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
