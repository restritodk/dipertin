// Arquivo: lib/screens/cliente/search_screen.dart

import 'package:depertin_cliente/screens/utilidades/achados_screen.dart';
import 'package:depertin_cliente/screens/utilidades/eventos_screen.dart';
import 'package:depertin_cliente/screens/utilidades/vagas_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'product_details_screen.dart';
import 'loja_perfil_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_suporte_screen.dart';
import '../auth/login_screen.dart';
import '../../services/location_service.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _buscaNome = "";
  String? _categoriaSelecionada;
  final TextEditingController _searchController = TextEditingController();

  bool get _isPesquisando =>
      _buscaNome.isNotEmpty || _categoriaSelecionada != null;

  static const Map<String, IconData> _categoriaIcones = {
    'banho': Icons.bathtub_rounded,
    'banheiro': Icons.bathtub_rounded,
    'cama': Icons.bed_rounded,
    'quarto': Icons.bed_rounded,
    'decoração': Icons.palette_rounded,
    'decoracao': Icons.palette_rounded,
    'mesa': Icons.table_restaurant_rounded,
    'mesa posta': Icons.table_restaurant_rounded,
    'cozinha': Icons.kitchen_rounded,
    'sala': Icons.weekend_rounded,
    'jardim': Icons.yard_rounded,
    'área externa': Icons.deck_rounded,
    'area externa': Icons.deck_rounded,
    'iluminação': Icons.light_rounded,
    'iluminacao': Icons.light_rounded,
    'tapetes': Icons.grid_on_rounded,
    'organização': Icons.inventory_2_rounded,
    'organizacao': Icons.inventory_2_rounded,
    'infantil': Icons.child_friendly_rounded,
    'bebê': Icons.child_friendly_rounded,
    'bebe': Icons.child_friendly_rounded,
    'pets': Icons.pets_rounded,
    'pet': Icons.pets_rounded,
    'escritório': Icons.desk_rounded,
    'escritorio': Icons.desk_rounded,
    'lavanderia': Icons.local_laundry_service_rounded,
    'cortinas': Icons.curtains_rounded,
    'tecidos': Icons.texture_rounded,
    'alimentos': Icons.restaurant_rounded,
    'alimentação': Icons.restaurant_rounded,
    'alimentacao': Icons.restaurant_rounded,
    'comida': Icons.restaurant_rounded,
    'bebidas': Icons.local_cafe_rounded,
    'doces': Icons.cake_rounded,
    'padaria': Icons.bakery_dining_rounded,
    'limpeza': Icons.cleaning_services_rounded,
    'farmácia': Icons.local_pharmacy_rounded,
    'farmacia': Icons.local_pharmacy_rounded,
    'saúde': Icons.health_and_safety_rounded,
    'saude': Icons.health_and_safety_rounded,
    'beleza': Icons.spa_rounded,
    'moda': Icons.checkroom_rounded,
    'roupas': Icons.checkroom_rounded,
    'vestuário': Icons.checkroom_rounded,
    'vestuario': Icons.checkroom_rounded,
    'calçados': Icons.ice_skating_rounded,
    'calcados': Icons.ice_skating_rounded,
    'acessórios': Icons.watch_rounded,
    'acessorios': Icons.watch_rounded,
    'jóias': Icons.diamond_rounded,
    'joias': Icons.diamond_rounded,
    'eletrônicos': Icons.devices_rounded,
    'eletronicos': Icons.devices_rounded,
    'tecnologia': Icons.devices_rounded,
    'celulares': Icons.smartphone_rounded,
    'informática': Icons.computer_rounded,
    'informatica': Icons.computer_rounded,
    'ferramentas': Icons.build_rounded,
    'construção': Icons.construction_rounded,
    'construcao': Icons.construction_rounded,
    'material de construção': Icons.construction_rounded,
    'automotivo': Icons.directions_car_rounded,
    'veículos': Icons.directions_car_rounded,
    'veiculos': Icons.directions_car_rounded,
    'esportes': Icons.sports_soccer_rounded,
    'fitness': Icons.fitness_center_rounded,
    'academia': Icons.fitness_center_rounded,
    'livros': Icons.menu_book_rounded,
    'papelaria': Icons.edit_note_rounded,
    'brinquedos': Icons.toys_rounded,
    'games': Icons.sports_esports_rounded,
    'jogos': Icons.sports_esports_rounded,
    'música': Icons.music_note_rounded,
    'musica': Icons.music_note_rounded,
    'flores': Icons.local_florist_rounded,
    'floricultura': Icons.local_florist_rounded,
    'presentes': Icons.card_giftcard_rounded,
    'utilidades': Icons.home_rounded,
    'variedades': Icons.auto_awesome_rounded,
    'mercado': Icons.shopping_cart_rounded,
    'supermercado': Icons.shopping_cart_rounded,
    'conveniência': Icons.store_rounded,
    'conveniencia': Icons.store_rounded,
    'elétrica': Icons.electrical_services_rounded,
    'eletrica': Icons.electrical_services_rounded,
    'móveis': Icons.chair_rounded,
    'moveis': Icons.chair_rounded,
    'colchões': Icons.bed_rounded,
    'colchoes': Icons.bed_rounded,
    'enxoval': Icons.dry_cleaning_rounded,
    'ar condicionado': Icons.ac_unit_rounded,
    'climatização': Icons.ac_unit_rounded,
    'climatizacao': Icons.ac_unit_rounded,
    'ótica': Icons.visibility_rounded,
    'otica': Icons.visibility_rounded,
    'relojoaria': Icons.watch_rounded,
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

  /// Ex.: "SÃO PAULO" → "São Paulo"
  static String _formatarNomeCidade(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          if (w.length == 1) return w.toUpperCase();
          return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  // ==========================================
  // FUNÇÃO MESTRA DE CONTATO (WhatsApp / Ligação)
  // ==========================================
  Future<void> _abrirContato(
    String telefoneBruto,
    String tipoContato, {
    String? nomeProfissional,
  }) async {
    String numeroLimpo = telefoneBruto.replaceAll(RegExp(r'[^0-9]'), '');

    Future<void> ligar() async {
      final Uri url = Uri.parse('tel:$numeroLimpo');
      if (await canLaunchUrl(url)) await launchUrl(url);
    }

    Future<void> chamarZap() async {
      String zap = numeroLimpo.startsWith('55')
          ? numeroLimpo
          : '55$numeroLimpo';

      String saudacao =
          (nomeProfissional != null && nomeProfissional.isNotEmpty)
          ? "Olá $nomeProfissional! "
          : "Olá! ";
      String texto = Uri.encodeComponent(
        "${saudacao}Vi seu destaque no app DiPertin e gostaria de mais informações sobre o seu serviço.",
      );

      final Uri url = Uri.parse('https://wa.me/$zap?text=$texto');

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

    if (tipoContato == 'whatsapp') {
      await chamarZap();
    } else if (tipoContato == 'ligacao') {
      await ligar();
    } else {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Como deseja entrar em contato?',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E1B4B)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: const Color(0xFF25D366).withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                chamarZap();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Column(
                                  children: [
                                    Icon(Icons.wechat, color: Color(0xFF25D366), size: 28),
                                    SizedBox(height: 6),
                                    Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF25D366))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Material(
                            color: diPertinRoxo.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                ligar();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Column(
                                  children: [
                                    Icon(Icons.phone_rounded, color: diPertinRoxo, size: 28),
                                    SizedBox(height: 6),
                                    Text('Ligar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: diPertinRoxo)),
                                  ],
                                ),
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
          ),
        );
      }
    }
  }

  void _falarComSuporteParaAnunciar() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faça login ou cadastre-se para anunciar!'),
          backgroundColor: diPertinLaranja,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ChatSuporteScreen()),
      );
    }
  }

  void _limparFiltros() {
    setState(() {
      _buscaNome = "";
      _categoriaSelecionada = null;
      _searchController.clear();
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocationService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5FA),
      body: Column(
        children: [
          _buildHeader(),
          _buildCategorias(),
          Expanded(
            child: _isPesquisando
                ? _buildResultadosPesquisa()
                : _buildGuiaDaCidade(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final loc = context.read<LocationService>();
    final cidadeExibicao = loc.cidadeExibicao;
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Buscar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (cidadeExibicao.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            cidadeExibicao,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: (val) => setState(() => _buscaNome = val.toLowerCase()),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Lojas, produtos ou categorias…',
                    hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w400, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500], size: 22),
                    suffixIcon: _isPesquisando
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: Colors.grey[500], size: 20),
                            onPressed: _limparFiltros,
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: diPertinLaranja, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorias() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('categorias')
                  .orderBy('nome')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: LinearProgressIndicator(color: diPertinLaranja));
                }
                var categorias = snapshot.data!.docs;
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: categorias.length,
                  itemBuilder: (context, index) {
                    var cat = categorias[index].data() as Map<String, dynamic>;
                    String nome = cat['nome'] ?? '';
                    String imagem = cat['imagem'] ?? '';
                    bool sel = _categoriaSelecionada == nome;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _categoriaSelecionada = sel ? null : nome);
                        FocusScope.of(context).unfocus();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel ? diPertinLaranja : Colors.grey.shade200,
                                  width: sel ? 2.5 : 1.5,
                                ),
                                boxShadow: sel
                                    ? [BoxShadow(color: diPertinLaranja.withValues(alpha: 0.25), blurRadius: 8)]
                                    : [],
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundImage: imagem.isNotEmpty ? NetworkImage(imagem) : null,
                                backgroundColor: sel ? diPertinLaranja.withValues(alpha: 0.08) : Colors.grey[100],
                                child: imagem.isEmpty
                                    ? Icon(
                                        _iconeDaCategoria(nome),
                                        color: sel ? diPertinLaranja : Colors.grey[500],
                                        size: 22,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              nome,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                color: sel ? diPertinLaranja : Colors.grey[700],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGET: O GUIA DA CIDADE
  // ==========================================
  Widget _sectionTitle(String title, IconData icon, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: diPertinRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: diPertinRoxo, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E1B4B),
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuiaDaCidade() {
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Serviços em destaque',
            Icons.star_rounded,
            subtitle: 'Profissionais com anúncio ativo na região',
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('servicos_destaque')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return SizedBox(
                  height: 124,
                  child: Center(
                    child: CircularProgressIndicator(color: diPertinRoxo),
                  ),
                );
              }

              final agora = DateTime.now();
              final anunciosValidos = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['data_inicio'] == null || data['data_fim'] == null) {
                  return false;
                }
                final inicio = (data['data_inicio'] as Timestamp).toDate();
                final vencimento = (data['data_fim'] as Timestamp).toDate();

                final passaCidade = LocationService.anuncioCidadeCorrespondeUsuario(
                  cidadeNormalizada: data['cidade_normalizada']?.toString(),
                  cidade: data['cidade']?.toString(),
                  cidadeNormUsuario: cidadeNorm,
                  ufNormUsuario: ufNorm,
                  globalSeVazio: true,
                );

                return agora.isAfter(inicio) &&
                    agora.isBefore(vencimento) &&
                    passaCidade;
              }).toList();

              anunciosValidos.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['data_criacao'] as Timestamp?;
                final timeB = dataB['data_criacao'] as Timestamp?;
                if (timeA == null || timeB == null) return 0;
                return timeB.compareTo(timeA);
              });

              if (anunciosValidos.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nenhum destaque na sua cidade no momento.',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [_buildBannerAnuncieAqui()],
                      ),
                    ),
                  ],
                );
              }

              return SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: anunciosValidos.length + 1,
                  itemBuilder: (context, i) {
                    if (i == anunciosValidos.length) {
                      return _buildBannerAnuncieAqui();
                    }

                    final ad =
                        anunciosValidos[i].data() as Map<String, dynamic>;
                    final cidadeCard = _formatarNomeCidade(
                      ad['cidade']?.toString(),
                    );
                    final imagemUrl = (ad['imagem_url'] ?? '').toString();

                    return Container(
                      width: 185,
                      margin: const EdgeInsets.only(right: 10),
                      child: Material(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _abrirContato(
                            ad['telefone'] ?? '',
                            'whatsapp',
                            nomeProfissional: ad['titulo'],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (imagemUrl.isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imagemUrl,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        ad['titulo'] ?? 'Profissional',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF1E1B4B),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: diPertinLaranja.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ad['categoria'] ?? 'Geral',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: diPertinLaranja,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (cidadeCard.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.place, size: 11, color: Colors.grey[400]),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          cidadeCard,
                                          style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.wechat, color: Color(0xFF25D366), size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Chamar',
                                        style: TextStyle(
                                          color: Color(0xFF25D366),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.5,
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
                  },
                ),
              );
            },
          ),

          const SizedBox(height: 28),

          _sectionTitle(
            'Emergência',
            Icons.emergency_rounded,
            subtitle: 'Ligações nacionais gratuitas',
          ),
          Row(
            children: [
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'Polícia',
                  numero: '190',
                  icone: Icons.local_police,
                  cor: Colors.blueGrey,
                  descricao:
                      'Use quando precisar de presença policial: crimes em '
                      'andamento, risco à segurança ou situações que exijam '
                      'apoio da polícia. Ligação gratuita.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'SAMU',
                  numero: '192',
                  icone: Icons.medical_services,
                  cor: Colors.red,
                  descricao:
                      'Serviço de atendimento móvel de urgência. Em emergência '
                      'médica, acidentes com vítimas ou quando precisar de '
                      'ambulância.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildEmergenciaBotao(
                  titulo: 'Bombeiros',
                  numero: '193',
                  icone: Icons.fire_truck,
                  cor: Colors.orange,
                  descricao:
                      'Incêndios, acidentes com vítimas, resgates e situações '
                      'com risco à vida. Informe o endereço com clareza ao '
                      'atender a ligação.',
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          _sectionTitle(
            'Acesso rápido',
            Icons.phone_in_talk_rounded,
            subtitle: 'Parceiros com telefone em destaque na região',
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('telefones_premium')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              DateTime agora = DateTime.now();
              var telefonesValidos = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['data_inicio'] == null ||
                    data['data_vencimento'] == null) {
                  return false;
                }
                DateTime inicio = (data['data_inicio'] as Timestamp).toDate();
                DateTime vencimento = (data['data_vencimento'] as Timestamp)
                    .toDate();

                bool passaCidade = LocationService.anuncioCidadeCorrespondeUsuario(
                  cidadeNormalizada: data['cidade_normalizada']?.toString(),
                  cidade: data['cidade']?.toString(),
                  cidadeNormUsuario: cidadeNorm,
                  ufNormUsuario: ufNorm,
                  globalSeVazio: true,
                );

                return agora.isAfter(inicio) &&
                    agora.isBefore(vencimento) &&
                    passaCidade;
              }).toList();

              if (telefonesValidos.isEmpty) {
                return Text(
                  'Nenhum parceiro de acesso rápido ativo no momento.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: telefonesValidos.length + 1,
                itemBuilder: (context, i) {
                  if (i == telefonesValidos.length) {
                    return _buildBotaoAnuncieTelefone();
                  }

                  var tel = telefonesValidos[i].data() as Map<String, dynamic>;
                  final telImg = (tel['imagem_url'] ?? '').toString();
                  return Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _abrirContato(
                        tel['telefone'] ?? '',
                        tel['tipo_contato'] ?? 'ligacao',
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            telImg.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      telImg,
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: diPertinRoxo.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.phone_forwarded_rounded, color: diPertinRoxo, size: 16),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: diPertinRoxo.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.phone_forwarded_rounded, color: diPertinRoxo, size: 16),
                                  ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    tel['titulo'] ?? '',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E1B4B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    tel['telefone'] ?? '',
                                    style: const TextStyle(fontSize: 12, color: diPertinRoxo, fontWeight: FontWeight.w600),
                                  ),
                                ],
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

          const SizedBox(height: 28),

          _sectionTitle(
            'Utilidade pública',
            Icons.apps_rounded,
            subtitle: 'Vagas, eventos e achados na cidade',
          ),

          _buildUtilidadeItem(
            'Vagas de emprego',
            'Oportunidades na sua região',
            Icons.work_rounded,
            const Color(0xFF059669),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VagasScreen()),
              );
            },
          ),

          _buildUtilidadeItem(
            'Eventos e festas',
            'O que vai rolar na cidade',
            Icons.celebration_rounded,
            diPertinRoxo,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EventosScreen()),
              );
            },
          ),

          _buildUtilidadeItem(
            'Achados e perdidos',
            'Documentos, pets e objetos',
            Icons.manage_search_rounded,
            diPertinLaranja,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AchadosScreen()),
              );
            },
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildBannerAnuncieAqui() {
    return Container(
      width: 185,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: diPertinLaranja.withValues(alpha: 0.3), width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _falarComSuporteParaAnunciar,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: diPertinLaranja.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: diPertinLaranja, size: 20),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Anuncie aqui',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: diPertinLaranja),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fale com o suporte',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotaoAnuncieTelefone() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.3), width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _falarComSuporteParaAnunciar,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_call, color: Color(0xFF059669), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Seu disk aqui', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                    Text('Patrocinar espaço', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarInfoEmergencia({
    required String titulo,
    required String numero,
    required IconData icone,
    required Color cor,
    required String descricao,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icone, color: cor, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1B4B),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 60),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: cor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      numero,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: cor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Número nacional de referência',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    descricao,
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Em emergência real, mantenha a calma e informe o local com clareza.',
                            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: Text('Fechar', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _abrirContato(numero, 'ligacao');
                          },
                          icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 20),
                          label: const Text('Ligar agora', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          style: FilledButton.styleFrom(
                            backgroundColor: cor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergenciaBotao({
    required String titulo,
    required String numero,
    required IconData icone,
    required Color cor,
    required String descricao,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _mostrarInfoEmergencia(
          titulo: titulo,
          numero: numero,
          icone: icone,
          cor: cor,
          descricao: descricao,
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: cor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E1B4B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                numero,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUtilidadeItem(
    String titulo,
    String subtitulo,
    IconData icone,
    Color cor,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Color(0xFF1E1B4B)),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // WIDGET: RESULTADOS DA BUSCA (LOJAS + PRODUTOS)
  // ==========================================
  Widget _buildResultadosPesquisa() {
    final loc = context.read<LocationService>();
    final cidadeNorm = loc.cidadeNormalizada;
    final ufNorm = loc.ufNormalizado;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Envolvemos tudo no StreamBuilder de Lojas primeiro para pegar os IDs
          StreamBuilder<QuerySnapshot>(
            // Fase 3G.2 — busca lê `lojas_public` (ver vitrine_screen.dart).
            stream: FirebaseFirestore.instance
                .collection('lojas_public')
                .snapshots(),
            builder: (context, snapshotLojas) {
              List<String> lojasIdsEncontradas = [];
              Set<String> lojasIdsDaCidade = {};
              Widget lojasWidget = const SizedBox.shrink();

              if (snapshotLojas.hasData) {
                for (final doc in snapshotLojas.data!.docs) {
                  final l = doc.data() as Map<String, dynamic>;
                  final cidadeLoja = (l['cidade_normalizada'] ??
                          l['cidade'] ??
                          l['endereco_cidade'] ??
                          '')
                      .toString();
                  if (LocationService.cidadeCampoCorrespondeUsuario(
                    campoCidade: cidadeLoja,
                    cidadeNormUsuario: cidadeNorm,
                    ufNormUsuario: ufNorm,
                  )) {
                    lojasIdsDaCidade.add(doc.id);
                  }
                }
              }

              if (snapshotLojas.hasData && _buscaNome.isNotEmpty) {
                var lojasEncontradas = snapshotLojas.data!.docs.where((doc) {
                  if (!lojasIdsDaCidade.contains(doc.id)) return false;
                  var l = doc.data() as Map<String, dynamic>;
                  String nomeLoja = (l['loja_nome'] ?? l['nome'] ?? '')
                      .toString()
                      .toLowerCase();
                  return nomeLoja.contains(_buscaNome);
                }).toList();

                lojasIdsEncontradas = lojasEncontradas
                    .map((e) => e.id)
                    .toList();

                // Desenha o Carrossel de Lojas no Topo
                if (lojasEncontradas.isNotEmpty) {
                  lojasWidget = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _sectionTitle('Lojas encontradas', Icons.store_rounded),
                      ),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: lojasEncontradas.length,
                          itemBuilder: (context, index) {
                            var loja =
                                lojasEncontradas[index].data()
                                    as Map<String, dynamic>;
                            String lojaId = lojasEncontradas[index].id;
                            String nome =
                                loja['loja_nome'] ?? loja['nome'] ?? 'Loja';
                            String foto = loja['foto'] ?? loja['imagem'] ?? '';

                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LojaPerfilScreen(
                                    lojistaData: loja,
                                    lojistaId: lojaId,
                                  ),
                                ),
                              ),
                              child: Container(
                                width: 130,
                                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: diPertinLaranja.withValues(alpha: 0.3), width: 2),
                                      ),
                                      child: CircleAvatar(
                                        radius: 24,
                                        backgroundColor: Colors.grey[100],
                                        backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                                        child: foto.isEmpty ? Icon(Icons.store_rounded, color: Colors.grey[400], size: 22) : null,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text(
                                        nome,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF1E1B4B)),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 30),
                    ],
                  );
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  lojasWidget,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: _sectionTitle('Produtos', Icons.inventory_2_rounded),
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('produtos')
                        .where('ativo', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshotProdutos) {
                      if (snapshotProdutos.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (!snapshotProdutos.hasData ||
                          snapshotProdutos.data!.docs.isEmpty) {
                        return const Center(
                          child: Text('Nenhum produto cadastrado.'),
                        );
                      }

                      var docs = snapshotProdutos.data!.docs.where((doc) {
                        var p = doc.data() as Map<String, dynamic>;

                        bool passaCategoria =
                            _categoriaSelecionada == null ||
                            p['categoria_nome'] == _categoriaSelecionada;

                        String nomeProduto = (p['nome'] ?? '')
                            .toString()
                            .toLowerCase();
                        String lojistaIdDoProduto = (p['lojista_id'] ?? '')
                            .toString();

                        if (!lojasIdsDaCidade.contains(lojistaIdDoProduto)) {
                          return false;
                        }

                        bool passaNomeOuLoja =
                            _buscaNome.isEmpty ||
                            nomeProduto.contains(_buscaNome) ||
                            lojasIdsEncontradas.contains(lojistaIdDoProduto);

                        return passaCategoria && passaNomeOuLoja;
                      }).toList();

                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(Icons.search_off_rounded, size: 32, color: Colors.grey[400]),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Nenhum produto encontrado',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tente buscar com outros termos',
                                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        );
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(15),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var p = docs[index].data() as Map<String, dynamic>;
                          p['id'] = docs[index].id;
                          String img =
                              (p['imagens'] != null && p['imagens'].isNotEmpty)
                              ? p['imagens'][0]
                              : '';

                          return Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailsScreen(produto: p),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                      child: Image.network(
                                        img,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          color: Colors.grey[100],
                                          child: Icon(Icons.image_not_supported_outlined, color: Colors.grey[300], size: 32),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['nome'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E1B4B)),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "R\$ ${(p['preco'] ?? 0.0).toStringAsFixed(2)}",
                                          style: const TextStyle(color: diPertinLaranja, fontWeight: FontWeight.w800, fontSize: 14.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
