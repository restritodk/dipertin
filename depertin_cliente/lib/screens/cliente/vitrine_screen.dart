// Arquivo: lib/screens/cliente/vitrine_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/cart_provider.dart';
import '../../services/location_service.dart';
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
  String _donoProduto(Map<String, dynamic> p) {
    return (p['lojista_id'] ?? p['loja_id'] ?? '').toString();
  }

  bool _cidadeCorresponde(String? cidadeBanco, String? ufBanco,
      String cidadeNorm, String ufNorm) {
    if (cidadeBanco == null || cidadeBanco.trim().isEmpty) return false;
    final cidadeNormBanco = LocationService.normalizar(cidadeBanco);
    if (cidadeNormBanco != cidadeNorm) return false;
    if (ufBanco != null && ufBanco.trim().isNotEmpty) {
      final ufNormBanco =
          LocationService.extrairUf(ufBanco) ?? LocationService.normalizar(ufBanco);
      if (ufNormBanco != ufNorm) return false;
    }
    return true;
  }

  /// Se o produto tiver cidade/UF no documento, deve coincidir com a região do usuário.
  bool _produtoNaMesmaRegiao(Map<String, dynamic> p, String cidadeNorm, String ufNorm) {
    final cn = p['cidade_normalizada']?.toString().trim();
    if (cn != null && cn.isNotEmpty) {
      return LocationService.normalizar(cn) == cidadeNorm;
    }
    final c = p['cidade']?.toString().trim();
    if (c != null && c.isNotEmpty) {
      if (LocationService.normalizar(c) != cidadeNorm) return false;
      final u = p['uf']?.toString() ?? p['estado']?.toString();
      if (u != null && u.trim().isNotEmpty) {
        final un = LocationService.extrairUf(u) ?? LocationService.normalizar(u);
        if (un != ufNorm) return false;
      }
      return true;
    }
    return true;
  }

  List<QueryDocumentSnapshot> _filtrarBannersCidade(
      List<QueryDocumentSnapshot> banners,
      String cidadeNorm,
      String ufNorm) {
    return banners.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      String cidadeBanner =
          (data['cidade'] ?? 'todas').toString().toLowerCase().trim();
      if (cidadeBanner == 'todas') return true;
      return _cidadeCorresponde(
          data['cidade']?.toString(), data['uf']?.toString(), cidadeNorm, ufNorm);
    }).toList();
  }

  bool _verificarSeLojaEstaAberta(Map<String, dynamic> loja) {
    if (loja['pausado_manualmente'] == true) return false;
    if (!loja.containsKey('horarios') || loja['horarios'] == null) {
      return loja['loja_aberta'] ?? true;
    }

    Map<String, dynamic> horarios = loja['horarios'];
    DateTime agora = DateTime.now();
    List<String> diasDaSemana = [
      'segunda',
      'terca',
      'quarta',
      'quinta',
      'sexta',
      'sabado',
      'domingo',
    ];
    String diaDeHoje = diasDaSemana[agora.weekday - 1];

    if (horarios[diaDeHoje] == null || horarios[diaDeHoje]['ativo'] == false) {
      return false;
    }

    try {
      String horaAbre = horarios[diaDeHoje]['abre'];
      String horaFecha = horarios[diaDeHoje]['fecha'];
      int minAtual = agora.hour * 60 + agora.minute;
      int minAbre =
          int.parse(horaAbre.split(':')[0]) * 60 +
          int.parse(horaAbre.split(':')[1]);
      int minFecha =
          int.parse(horaFecha.split(':')[0]) * 60 +
          int.parse(horaFecha.split(':')[1]);

      if (minFecha < minAbre) {
        if (minAtual >= minAbre || minAtual <= minFecha) return true;
      } else {
        if (minAtual >= minAbre && minAtual <= minFecha) return true;
      }
    } catch (e) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<LocationService>();
    final cidadeNorm = locationService.cidadeNormalizada;
    final ufNorm = locationService.ufNormalizado;
    final cidadeExibicao = locationService.cidadeExibicao;

    if (!locationService.cidadePronta) {
      return Scaffold(
        backgroundColor: Colors.grey[200],
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
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: diPertinRoxo,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "DiPertin - O que você precisa, bem aqui!",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 12,
                  color: diPertinLaranja,
                ),
                const SizedBox(width: 4),
                Text(
                  cidadeExibicao,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.white),
            tooltip: "Atualizar cidade pelo GPS",
            onPressed: locationService.detectandoCidade
                ? null
                : () => locationService.detectarCidade(),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
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
                    snapshot.data!.docs, cidadeNorm, ufNorm);
              }

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: AutoSlidingBanner(banners: bannersDoBanco, altura: 150),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Destaques da sua região — $cidadeExibicao",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),

          // 2. VITRINE DE PRODUTOS
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'lojista')
                        .snapshots(),
                    builder: (context, snapshotLojas) {
                      if (snapshotLojas.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: diPertinRoxo),
                        );
                      }
                      if (!snapshotLojas.hasData ||
                          snapshotLojas.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "Nenhuma loja vendendo nesta cidade ainda.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      Map<String, bool> statusLojas = {};
                      Map<String, String> nomesLojas = {};

                      for (var doc in snapshotLojas.data!.docs) {
                        var lojaData = doc.data() as Map<String, dynamic>;

                        if (!_cidadeCorresponde(
                            lojaData['cidade']?.toString(),
                            lojaData['uf']?.toString() ??
                                lojaData['estado']?.toString(),
                            cidadeNorm,
                            ufNorm)) {
                          continue;
                        }

                        String status = lojaData['status_loja'] ?? 'pendente';
                        if (status != 'aprovada' && status != 'aprovado') {
                          continue;
                        }

                        statusLojas[doc.id] = _verificarSeLojaEstaAberta(
                          lojaData,
                        );
                        nomesLojas[doc.id] =
                            lojaData['nome_loja'] ??
                            lojaData['nome'] ??
                            'Loja Parceira';
                      }

                      debugPrint("[LOJAS] total: ${snapshotLojas.data!.docs.length} | filtradas '$cidadeExibicao': ${statusLojas.length}");

                      if (statusLojas.isEmpty) {
                        return const Center(
                          child: Text(
                            "Nenhuma loja vendendo nesta cidade ainda.",
                            style: TextStyle(color: Colors.grey),
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
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: diPertinRoxo,
                                  ),
                                );
                              }
                              if (!snapshotProdutos.hasData ||
                                  snapshotProdutos.data!.docs.isEmpty) {
                                return const Center(
                                  child: Text(
                                    "Nenhum produto disponível.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              List<QueryDocumentSnapshot> produtosFiltrados =
                                  snapshotProdutos.data!.docs.where((doc) {
                                    var p = doc.data() as Map<String, dynamic>;
                                    if (!statusLojas.containsKey(
                                        _donoProduto(p))) {
                                      return false;
                                    }
                                    return _produtoNaMesmaRegiao(
                                        p, cidadeNorm, ufNorm);
                                  }).toList();

                              debugPrint("[PRODUTOS] antes filtro: ${snapshotProdutos.data!.docs.length} | após filtro cidade: ${produtosFiltrados.length}");

                              if (produtosFiltrados.isEmpty) {
                                return const Center(
                                  child: Text(
                                    "Nenhum produto cadastrado pelas lojas desta cidade.",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              produtosFiltrados.sort((a, b) {
                                var pA = a.data() as Map<String, dynamic>;
                                var pB = b.data() as Map<String, dynamic>;
                                bool abertaA =
                                    statusLojas[_donoProduto(pA)] ?? true;
                                bool abertaB =
                                    statusLojas[_donoProduto(pB)] ?? true;
                                if (abertaA && !abertaB) return -1;
                                if (!abertaA && abertaB) return 1;
                                return 0;
                              });

                              final bannersDoBanco = _filtrarBannersCidade(
                                  snapshotBanners.data?.docs ?? [],
                                  cidadeNorm,
                                  ufNorm);
                              List<Widget> itensDaVitrine = [];

                              for (
                                int i = 0;
                                i < produtosFiltrados.length;
                                i += 2
                              ) {
                                var prod1 =
                                    produtosFiltrados[i].data()
                                        as Map<String, dynamic>;
                                prod1['id_documento'] = produtosFiltrados[i].id;
                                prod1['loja_nome_vitrine'] =
                                    nomesLojas[_donoProduto(prod1)];
                                prod1['loja_aberta'] =
                                    statusLojas[_donoProduto(prod1)];

                                Map<String, dynamic>? prod2;
                                if (i + 1 < produtosFiltrados.length) {
                                  prod2 =
                                      produtosFiltrados[i + 1].data()
                                          as Map<String, dynamic>;
                                  prod2['id_documento'] =
                                      produtosFiltrados[i + 1].id;
                                  prod2['loja_nome_vitrine'] =
                                      nomesLojas[_donoProduto(prod2)];
                                  prod2['loja_aberta'] =
                                      statusLojas[_donoProduto(prod2)];
                                }

                                itensDaVitrine.add(
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: SizedBox(
                                      height: 250,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: _buildProductCard(
                                              context,
                                              prod1,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: prod2 != null
                                                ? _buildProductCard(
                                                    context,
                                                    prod2,
                                                  )
                                                : const SizedBox(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                // BANNERS A CADA 30 PRODUTOS (10 Linhas)
                                // Removido o bloqueio. Vai exibir mesmo se só tiver o banner estático!
                                if ((i + 2) % 30 == 0 &&
                                    (i + 2) < produtosFiltrados.length) {
                                  itensDaVitrine.add(
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 15,
                                        top: 5,
                                      ),
                                      child: AutoSlidingBanner(
                                        banners: bannersDoBanco,
                                        altura: 120,
                                      ),
                                    ),
                                  );
                                }
                              }

                              return ListView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                children: itensDaVitrine,
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
        precoOferta != null && precoOriginal != null && precoOferta < precoOriginal;
    final double precoFinal =
        temOferta ? precoOferta : (precoOriginal ?? 0.0);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(produto: produto),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: imagemVitrine.isNotEmpty
                        ? Image.network(
                            imagemVitrine,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[100],
                                child: const Center(
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
                            },
                            errorBuilder: (c, e, s) => Container(
                              color: Colors.grey[100],
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                size: 32,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[100],
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              size: 32,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                  if (temOferta)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[600],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "-${((1 - precoOferta / precoOriginal) * 100).round()}%",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto["nome"] ?? "Sem nome",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: () {
                        if (produto['lojista_id'] != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LojaCatalogoScreen(
                                lojaId: produto['lojista_id'],
                                nomeLoja:
                                    produto["loja_nome_vitrine"] ??
                                    "Loja Parceira",
                              ),
                            ),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.storefront, size: 11, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              produto["loja_nome_vitrine"] ?? "Loja Parceira",
                              style: TextStyle(
                                color: Colors.grey[500],
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
                    const Spacer(),
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
                                  "R\$ ${precoOriginal.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.grey[400],
                                  ),
                                ),
                              Text(
                                "R\$ ${precoFinal.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  color: diPertinLaranja,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: diPertinRoxo,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProductDetailsScreen(produto: produto),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.add_shopping_cart_rounded,
                                color: Colors.white,
                                size: 16,
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

// ==========================================
// CARROSSEL ANIMADO INTELIGENTE E SUAVE
// ==========================================
class AutoSlidingBanner extends StatefulWidget {
  final List<QueryDocumentSnapshot> banners;
  final double altura;
  const AutoSlidingBanner({
    super.key,
    required this.banners,
    required this.altura,
  });
  @override
  State<AutoSlidingBanner> createState() => _AutoSlidingBannerState();
}

class _AutoSlidingBannerState extends State<AutoSlidingBanner> {
  late PageController _pageController;
  Timer? _timer;
  int _totalItems = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    _totalItems = widget.banners.length + 1;

    // A MÁGICA REAL: Usamos um número gigante que é MÚLTIPLO EXATO do total.
    // Assim o Flutter abre na primeira página silenciosamente e o timer só pula +1.
    _currentPage = _totalItems * 1000;

    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.9,
    );

    _iniciarAnimacao();
  }

  void _iniciarAnimacao() {
    _timer?.cancel();
    if (_totalItems > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
        if (_pageController.hasClients) {
          _currentPage++;
          _pageController.animateToPage(
            _currentPage,
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
    int novosTotal = widget.banners.length + 1;
    if (_totalItems != novosTotal) {
      _totalItems = novosTotal;
      // Se vier um novo banner do Firebase, recalcula o ponto silenciosamente
      _currentPage = _totalItems * 1000;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
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

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 1,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (int index) => _currentPage = index,
        // Loop infinito só funciona se tiver mais de 1 item
        itemCount: _totalItems > 1 ? null : 1,
        itemBuilder: (context, index) {
          final int indexReal = index % _totalItems;

          // SE FOR O ÚLTIMO ÍNDICE, MOSTRA A ARTE LOCAL "ANUNCIE AQUI"
          if (indexReal == widget.banners.length) {
            return GestureDetector(
              onTap: () async {
                String numeroWhatsApp = "5566992244000"; // Substitua pelo seu
                String mensagem =
                    "Olá! Tenho interesse em anunciar minha loja/serviço no DiPertin.";
                final Uri url = Uri.parse(
                  'https://wa.me/$numeroWhatsApp?text=${Uri.encodeComponent(mensagem)}',
                );

                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: const DecorationImage(
                    image: AssetImage('assets/banner_anuncie.jpg'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            );
          }

          // SE NÃO FOR O ÚLTIMO, MOSTRA OS BANNERS DO FIREBASE
          var bannerData =
              widget.banners[indexReal].data() as Map<String, dynamic>;
          String urlImagem =
              bannerData['imagem'] ?? bannerData['url_imagem'] ?? '';
          String linkDestino =
              bannerData['link'] ?? bannerData['link_destino'] ?? '';

          return GestureDetector(
            onTap: () async {
              if (linkDestino.isNotEmpty) {
                final Uri url = Uri.parse(linkDestino);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: Colors.grey[300],
                image: urlImagem.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(urlImagem),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
