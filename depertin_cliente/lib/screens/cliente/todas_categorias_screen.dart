// Arquivo: lib/screens/cliente/todas_categorias_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);

class TodasCategoriasScreen extends StatefulWidget {
  const TodasCategoriasScreen({super.key});

  @override
  State<TodasCategoriasScreen> createState() => _TodasCategoriasScreenState();
}

class _TodasCategoriasScreenState extends State<TodasCategoriasScreen> {
  final TextEditingController _searchC = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
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
      case 'tv': return Icons.tv_rounded;
      case 'videogame_asset': return Icons.videogame_asset_rounded;
      case 'sports_esports': return Icons.sports_esports_rounded;
      case 'headphones': return Icons.headphones_rounded;
      case 'speaker': return Icons.speaker_rounded;
      case 'kitchen': return Icons.kitchen_rounded;
      case 'chair': return Icons.chair_rounded;
      case 'bed': return Icons.bed_rounded;
      case 'light': return Icons.light_rounded;
      case 'blender': return Icons.blender_rounded;
      case 'microwave': return Icons.microwave_rounded;
      case 'coffee_maker': return Icons.coffee_maker_rounded;
      case 'local_grocery_store': return Icons.local_grocery_store_rounded;
      case 'egg': return Icons.egg_rounded;
      case 'liquor': return Icons.liquor_rounded;
      case 'wine_bar': return Icons.wine_bar_rounded;
      case 'sports_bar': return Icons.sports_bar_rounded;
      case 'local_bar': return Icons.local_bar_rounded;
      case 'card_giftcard': return Icons.card_giftcard_rounded;
      case 'local_florist': return Icons.local_florist_rounded;
      case 'toys': return Icons.toys_rounded;
      case 'hardware': return Icons.hardware_rounded;
      case 'handyman': return Icons.handyman_rounded;
      case 'cleaning_services': return Icons.cleaning_services_rounded;
      case 'electric_bolt': return Icons.electric_bolt_rounded;
      case 'plumbing': return Icons.plumbing_rounded;
      case 'roofing': return Icons.roofing_rounded;
      case 'pest_control': return Icons.pest_control_rounded;
      case 'grass': return Icons.grass_rounded;
      case 'yard': return Icons.yard_rounded;
      case 'local_printshop': return Icons.local_printshop_rounded;
      case 'edit': return Icons.edit_rounded;
      case 'palette': return Icons.palette_rounded;
      case 'brush': return Icons.brush_rounded;
      case 'camera_alt': return Icons.camera_alt_rounded;
      case 'movie': return Icons.movie_rounded;
      case 'theaters': return Icons.theaters_rounded;
      case 'library_books': return Icons.library_books_rounded;
      case 'menu_book': return Icons.menu_book_rounded;
      case 'school': return Icons.school_rounded;
      case 'auto_stories': return Icons.auto_stories_rounded;
      case 'elderly': return Icons.elderly_rounded;
      case 'elderly_woman': return Icons.elderly_woman_rounded;
      case 'masks': return Icons.masks_rounded;
      case 'vaccines': return Icons.vaccines_rounded;
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
      case 'pedal_bike': return Icons.pedal_bike_rounded;
      case 'electric_moped': return Icons.electric_moped_rounded;
      case 'moped': return Icons.moped_rounded;
      case 'sailing': return Icons.sailing_rounded;
      case 'paragliding': return Icons.paragliding_rounded;
      case 'roller_skating': return Icons.roller_skating_rounded;
      case 'downhill_skiing': return Icons.downhill_skiing_rounded;
      case 'snowboarding': return Icons.snowboarding_rounded;
      case 'sledding': return Icons.sledding_rounded;
      case 'dry_cleaning': return Icons.dry_cleaning_rounded;
      case 'local_laundry_service': return Icons.local_laundry_service_rounded;
      case 'gas_meter': return Icons.gas_meter_rounded;
      case 'water_drop': return Icons.water_drop_rounded;
      case 'local_fire_department': return Icons.local_fire_department_rounded;
      case 'forest': return Icons.forest_rounded;
      case 'agriculture': return Icons.agriculture_rounded;
      case 'two_wheeler': return Icons.two_wheeler_rounded;
      case 'electric_bike': return Icons.electric_bike_rounded;
      case 'electric_scooter': return Icons.electric_scooter_rounded;
      case 'electric_car': return Icons.electric_car_rounded;
      // Ícones adicionais — compatibilidade painel web
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
      default: return Icons.category_rounded;
    }
  }

  /// Ícone automático por nome da categoria (fallback sem iconKey).
  static final Map<String, IconData> _categoriaIcones = {
    'alimentação': Icons.restaurant_rounded,
    'alimentacao': Icons.restaurant_rounded,
    'restaurante': Icons.restaurant_rounded,
    'comida': Icons.restaurant_rounded,
    'lanche': Icons.lunch_dining_rounded,
    'pizza': Icons.local_pizza_rounded,
    'padaria': Icons.bakery_dining_rounded,
    'doces': Icons.cake_rounded,
    'sorvete': Icons.icecream_rounded,
    'bebidas': Icons.local_bar_rounded,
    'café': Icons.local_cafe_rounded,
    'cafe': Icons.local_cafe_rounded,
    'mercado': Icons.shopping_cart_rounded,
    'supermercado': Icons.shopping_cart_rounded,
    'conveniência': Icons.store_rounded,
    'conveniencia': Icons.store_rounded,
    'farmácia': Icons.local_pharmacy_rounded,
    'farmacia': Icons.local_pharmacy_rounded,
    'saúde': Icons.health_and_safety_rounded,
    'saude': Icons.health_and_safety_rounded,
    'beleza': Icons.spa_rounded,
    'moda': Icons.checkroom_rounded,
    'vestuário': Icons.checkroom_rounded,
    'vestuario': Icons.checkroom_rounded,
    'roupa': Icons.checkroom_rounded,
    'serviços': Icons.build_rounded,
    'servicos': Icons.build_rounded,
    'vagas': Icons.work_rounded,
    'emprego': Icons.work_rounded,
    'trabalho': Icons.work_rounded,
    'eventos': Icons.celebration_rounded,
    'festa': Icons.celebration_rounded,
    'pet': Icons.pets_rounded,
    'pets': Icons.pets_rounded,
    'eletrônicos': Icons.devices_rounded,
    'eletronicos': Icons.devices_rounded,
    'tecnologia': Icons.devices_rounded,
    'informática': Icons.computer_rounded,
    'informatica': Icons.computer_rounded,
    'celular': Icons.smartphone_rounded,
    'ferramentas': Icons.hardware_rounded,
    'construção': Icons.build_rounded,
    'construcao': Icons.build_rounded,
    'automotivo': Icons.electric_car_rounded,
    'carro': Icons.electric_car_rounded,
    'esportes': Icons.sports_basketball_rounded,
    'fitness': Icons.fitness_center_rounded,
    'academia': Icons.fitness_center_rounded,
    'brinquedos': Icons.toys_rounded,
    'games': Icons.videogame_asset_rounded,
    'jogos': Icons.videogame_asset_rounded,
    'música': Icons.music_note_rounded,
    'musica': Icons.music_note_rounded,
    'livros': Icons.menu_book_rounded,
    'papelaria': Icons.edit_rounded,
    'presentes': Icons.card_giftcard_rounded,
    'flores': Icons.local_florist_rounded,
    'utilidades': Icons.category_rounded,
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
    'infantil': Icons.elderly_rounded,
    'bebê': Icons.elderly_rounded,
    'bebe': Icons.elderly_rounded,
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

  @override
  Widget build(BuildContext context) {
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
                color: _diPertinRoxo,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Categorias',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _textoPrimario,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: _fundoTela,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchC,
                onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
                style: const TextStyle(
                  fontSize: 15,
                  color: _textoPrimario,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar categoria…',
                  hintStyle: TextStyle(color: _textoMuted.withValues(alpha: 0.7)),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _diPertinRoxo.withValues(alpha: 0.6),
                    size: 22,
                  ),
                  suffixIcon: _filtro.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: _textoMuted,
                          onPressed: () {
                            _searchC.clear();
                            setState(() => _filtro = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('categorias')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _diPertinRoxo),
            );
          }

          var docs = snapshot.data!.docs.toList()
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

          // Filtro textual
          if (_filtro.isNotEmpty) {
            docs = docs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final nome = (data['nome'] ?? '').toString().toLowerCase();
              final sinonimos = data['sinonimos'];
              if (nome.contains(_filtro)) return true;
              if (sinonimos is List) {
                for (final s in sinonimos) {
                  if (s.toString().toLowerCase().contains(_filtro)) return true;
                }
              }
              return false;
            }).toList();
          }

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 56,
                      color: _textoMuted.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma categoria encontrada',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textoMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tente outro termo de busca',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textoMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.of(context).padding.bottom + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: GridView.builder(
              padding: const EdgeInsets.only(
                top: 8,
                bottom: 24,
                left: 4,
                right: 4,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final nome = data['nome'] ?? '';
                final imagem = data['imagem'] ?? '';
                final iconKey = data['iconKey']?.toString() ?? '';

                // Resolve ícone
                IconData icone;
                if (imagem.isNotEmpty) {
                  icone = Icons.image_rounded;
                } else if (iconKey.isNotEmpty) {
                  icone = _resolverIconeChave(iconKey);
                } else {
                  icone = _iconeDaCategoria(nome);
                }

                    // Todas as categorias usam o padrão roxo DiPertin
                    const Color bgColor = Color(0xFFEDE7F6);
                    const Color accentColor = _diPertinRoxo;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context, rootNavigator: true)
                          .pushNamedAndRemoveUntil(
                        '/home',
                        (_) => false,
                        arguments: 0,
                      );
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
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
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.5),
                            blurRadius: 0,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Anel gradiente ao redor do ícone
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  accentColor.withValues(alpha: 0.12),
                                  accentColor.withValues(alpha: 0.04),
                                  _diPertinRoxo.withValues(alpha: 0.06),
                                  accentColor.withValues(alpha: 0.12),
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
                                    color: accentColor.withValues(alpha: 0.12),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(icone, size: 22, color: accentColor),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              nome,
                              style: const TextStyle(
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
            ),
          );
        },
      ),
    );
  }
}
