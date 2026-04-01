// Arquivo: lib/screens/cliente/vitrine_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pacotes de localização
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../providers/cart_provider.dart';
import 'cart_screen.dart';
import 'address_screen.dart';
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
  String cidadeUsuario = "Buscando local...";
  bool _carregandoCidade = true;

  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _inicializarApp() async {
    await _carregarCidadeSalva();
    await _buscarLocalizacaoAutomatica();
  }

  Future<void> _carregarCidadeSalva() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cidadeNaMemoria = prefs.getString('cidade_vitrine');
    if (cidadeNaMemoria != null && cidadeNaMemoria.isNotEmpty) {
      setState(() {
        cidadeUsuario = cidadeNaMemoria;
      });
    } else {
      setState(() {
        cidadeUsuario = "Selecione o local";
      });
    }
    setState(() {
      _carregandoCidade = false;
    });
  }

  Future<void> _salvarCidade(String novaCidade) async {
    String cidadeLimpa = novaCidade.trim();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('cidade_vitrine', cidadeLimpa);
    setState(() {
      cidadeUsuario = cidadeLimpa;
    });
  }

  // BUSCA A LOCALIZAÇÃO SOZINHO 1 VEZ POR SESSÃO
  Future<void> _buscarLocalizacaoAutomatica() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark lugar = placemarks[0];
        String cidadeDetectada =
            lugar.subAdministrativeArea ?? lugar.locality ?? "";

        // SE A CIDADE FOR DIFERENTE, ATUALIZA E AVISA O USUÁRIO
        if (cidadeDetectada.isNotEmpty && cidadeDetectada != cidadeUsuario) {
          await _salvarCidade(cidadeDetectada);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "📍 Localização atualizada para $cidadeDetectada",
                ),
                backgroundColor: diPertinLaranja,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar GPS: $e");
    }
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
    if (_carregandoCidade) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: diPertinRoxo)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: diPertinRoxo,
        elevation: 0,
        // APPBAR LIMPA E ELEGANTE (Sem barra de pesquisa fake)
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "DiPertin",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Row(
              children: [
                const Icon(Icons.location_on, size: 12, color: diPertinLaranja),
                const SizedBox(width: 4),
                Text(
                  cidadeUsuario,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_location_alt, color: Colors.white),
            tooltip: "Mudar Cidade",
            onPressed: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddressScreen()),
              );
              if (resultado != null && resultado is String) {
                await _salvarCidade(resultado);
              }
            },
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
          // 1. CARROSSEL DE BANNERS (Agora funciona mesmo se o Firebase estiver vazio!)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('banners')
                .snapshots(),
            builder: (context, snapshot) {
              // Pegamos os banners se existirem. Se não existirem, mandamos uma lista vazia.
              List<QueryDocumentSnapshot> bannersDoBanco = [];
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                bannersDoBanco = snapshot.data!.docs;
              }

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                // O AutoSlidingBanner agora garante a exibição do banner estático
                child: AutoSlidingBanner(banners: bannersDoBanco, altura: 150),
              );
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15.0, vertical: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Destaques da sua região",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),

          // 2. VITRINE DE PRODUTOS
          Expanded(
            child: cidadeUsuario == "Selecione o local"
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          "Selecione sua cidade no topo da tela.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'lojista')
                        .where('cidade', isEqualTo: cidadeUsuario)
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

                        // CORREÇÃO: Aceita tanto "aprovada" quanto "aprovado" para evitar bugs!
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

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('banners')
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
                                    return statusLojas.containsKey(
                                      p['lojista_id'],
                                    );
                                  }).toList();

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
                                    statusLojas[pA['lojista_id']] ?? true;
                                bool abertaB =
                                    statusLojas[pB['lojista_id']] ?? true;
                                if (abertaA && !abertaB) return -1;
                                if (!abertaA && abertaB) return 1;
                                return 0;
                              });

                              final bannersDoBanco =
                                  snapshotBanners.data?.docs ?? [];
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
                                    nomesLojas[prod1['lojista_id']];
                                prod1['loja_aberta'] =
                                    statusLojas[prod1['lojista_id']];

                                Map<String, dynamic>? prod2;
                                if (i + 1 < produtosFiltrados.length) {
                                  prod2 =
                                      produtosFiltrados[i + 1].data()
                                          as Map<String, dynamic>;
                                  prod2['id_documento'] =
                                      produtosFiltrados[i + 1].id;
                                  prod2['loja_nome_vitrine'] =
                                      nomesLojas[prod2['lojista_id']];
                                  prod2['loja_aberta'] =
                                      statusLojas[prod2['lojista_id']];
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

    return GestureDetector(
      onTap: () {
        // REMOVIDO: O bloqueio de clique. Agora sempre navega!
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        // REMOVIDO: O Opacity que deixava o card cinza
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: imagemVitrine.isNotEmpty
                    ? Image.network(imagemVitrine, fit: BoxFit.cover)
                    : const Icon(
                        Icons.image_not_supported,
                        size: 50,
                        color: Colors.grey,
                      ),
              ),
              // REMOVIDO: O Stack com o overlay "FECHADO"
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
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Nome da loja clicável (MANTIDO)
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
                      child: Text(
                        produto["loja_nome_vitrine"] ?? "Loja Parceira",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "R\$ ${((produto["oferta"] ?? produto["preco"] ?? 0.0) as num).toDouble().toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: diPertinLaranja,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: diPertinRoxo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart,
                            color: diPertinRoxo,
                            size: 16,
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
