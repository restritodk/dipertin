import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _buscaCtrl = TextEditingController();
  String _filtroChip = 'todas'; // todas | ativas | inativas | destaque | produto | servico

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8F7FC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _roxo, width: 1.5),
    ),
  );

  String _slug(String texto) {
    var t = texto.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    final buf = StringBuffer();
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      buf.write(mapa[ch] ?? ch);
    }
    t = buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return t.isEmpty ? 'categoria' : t;
  }

  List<String> _sinonimos(String texto) {
    return texto
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  String _rotuloTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return 'Serviço';
      case 'ambos':
        return 'Produto e serviço';
      case 'produto':
      default:
        return 'Produto';
    }
  }

  IconData _iconeVisualPorTipo(String tipo) {
    switch (tipo) {
      case 'servico':
        return Icons.home_repair_service_rounded;
      case 'ambos':
        return Icons.hub_rounded;
      case 'produto':
      default:
        return Icons.inventory_2_rounded;
    }
  }

  // ==========================================
  // MAPA DE PALAVRAS-CHAVE PARA ÍCONES
  // ==========================================
  static const Map<String, String> _keywordToIcon = {
    'alimentação': 'restaurant',
    'alimentacao': 'restaurant',
    'restaurante': 'local_dining',
    'lanche': 'lunch_dining',
    'lanchonete': 'lunch_dining',
    'pizza': 'local_pizza',
    'hambúrguer': 'lunch_dining',
    'hamburguer': 'lunch_dining',
    'comida': 'restaurant',
    'alimentos': 'restaurant',
    'bebidas': 'local_cafe',
    'bebida': 'local_cafe',
    'padaria': 'bakery_dining',
    'doces': 'cake',
    'doce': 'cake',
    'sorvete': 'icecream',
    'mercado': 'shopping_cart',
    'supermercado': 'shopping_cart',
    'compras': 'shopping_cart',
    'conveniência': 'store',
    'conveniencia': 'store',
    'farmácia': 'local_pharmacy',
    'farmacia': 'local_pharmacy',
    'remédio': 'local_pharmacy',
    'remedio': 'local_pharmacy',
    'saúde': 'health_and_safety',
    'saude': 'health_and_safety',
    'médico': 'medical_services',
    'medico': 'medical_services',
    'hospital': 'local_hospital',
    'beleza': 'spa',
    'salão': 'content_cut',
    'salao': 'content_cut',
    'maquiagem': 'face',
    'estética': 'spa',
    'estetica': 'spa',
    'cabelo': 'content_cut',
    'unha': 'hand_gesture',
    'barbearia': 'face',
    'moda': 'checkroom',
    'roupa': 'checkroom',
    'roupas': 'checkroom',
    'vestuário': 'checkroom',
    'vestuario': 'checkroom',
    'calçados': 'ice_skating',
    'calcados': 'ice_skating',
    'acessórios': 'watch',
    'acessorios': 'watch',
    'serviços': 'build',
    'servicos': 'build',
    'manutenção': 'build',
    'manutencao': 'build',
    'reparo': 'build',
    'conserto': 'build',
    'vaga': 'work',
    'vagas': 'work',
    'emprego': 'work',
    'trabalho': 'work',
    'carreira': 'work',
    'evento': 'celebration',
    'eventos': 'celebration',
    'festa': 'celebration',
    'show': 'music_note',
    'música': 'music_note',
    'musica': 'music_note',
    'pet': 'pets',
    'pets': 'pets',
    'animal': 'pets',
    'veterinário': 'pets',
    'veterinario': 'pets',
    'eletrônicos': 'devices',
    'eletronicos': 'devices',
    'celular': 'smartphone',
    'celulares': 'smartphone',
    'informática': 'computer',
    'informatica': 'computer',
    'tecnologia': 'devices',
    'computador': 'computer',
    'games': 'sports_esports',
    'jogos': 'sports_esports',
    'casa': 'home',
    'construção': 'construction',
    'construcao': 'construction',
    'material de construção': 'construction',
    'ferramentas': 'build',
    'ferramenta': 'build',
    'transporte': 'local_shipping',
    'entrega': 'motorcycle',
    'delivery': 'motorcycle',
    'moto': 'motorcycle',
    'carro': 'directions_car',
    'automotivo': 'directions_car',
    'veículos': 'directions_car',
    'veiculos': 'directions_car',
    'esporte': 'sports_soccer',
    'esportes': 'sports_soccer',
    'fitness': 'fitness_center',
    'academia': 'fitness_center',
    'livro': 'menu_book',
    'livros': 'menu_book',
    'papelaria': 'edit_note',
    'escolar': 'edit_note',
    'brinquedos': 'toys',
    'brinquedo': 'toys',
    'presente': 'card_giftcard',
    'presentes': 'card_giftcard',
    'flores': 'local_florist',
    'flor': 'local_florist',
    'floricultura': 'local_florist',
    'utilidades': 'home',
    'variedades': 'auto_awesome',
    'decoração': 'palette',
    'decoracao': 'palette',
    'iluminação': 'light',
    'iluminacao': 'light',
    'móveis': 'chair',
    'moveis': 'chair',
    'cama': 'bed',
    'quarto': 'bed',
    'cozinha': 'kitchen',
    'limpeza': 'cleaning_services',
    'infantil': 'child_friendly',
    'bebê': 'child_friendly',
    'bebe': 'child_friendly',
    'banho': 'bathtub',
    'elétrica': 'electrical_services',
    'eletrica': 'electrical_services',
    'ótica': 'visibility',
    'otica': 'visibility',
    'relojoaria': 'watch',
    'corte': 'content_cut',
    'costura': 'sewing',
    'artesanato': 'handyman',
    'jardinagem': 'yard',
    'piscina': 'pool',
    'segurança': 'security',
    'seguranca': 'security',
    'câmera': 'videocam',
    'camera': 'videocam',
    'impressão': 'print',
    'impressao': 'print',
    'fotografia': 'photo_camera',
    'turismo': 'flight',
    'viagem': 'flight',
    'hotel': 'hotel',
    'pousada': 'hotel',
    'educação': 'school',
    'educacao': 'school',
    'curso': 'school',
    'aula': 'school',
    'idioma': 'language',
    'tradução': 'translate',
    'traducao': 'translate',
    'contabilidade': 'account_balance',
    'advocacia': 'gavel',
    'advogado': 'gavel',
    'direito': 'gavel',
    'engenharia': 'engineering',
    'arquitetura': 'draw',
    'design': 'palette',
    'marketing': 'campaign',
    'publicidade': 'campaign',
    'ti': 'computer',
    'programação': 'code',
    'programacao': 'code',
    'software': 'code',
    'fotógrafo': 'photo_camera',
    'fotografo': 'photo_camera',
    // NOVOS — Importação & Finanças
    'importação': 'import_export',
    'importacao': 'import_export',
    'exportação': 'import_export',
    'exportacao': 'import_export',
    'documentos': 'description',
    'estoque': 'inventory',
    'inventário': 'inventory',
    'inventario': 'inventory',
    'pagamentos': 'payments',
    'financeiro': 'monetization_on',
    'orçamento': 'request_quote',
    'orcamento': 'request_quote',
    'vendas': 'sell',
    'promoção': 'sell',
    'promocao': 'sell',
    'contrato': 'post_add',
    'agronegócio': 'agriculture',
    'agronegocio': 'agriculture',
    'fazenda': 'agriculture',
    'agrícola': 'agriculture',
    'agricola': 'agriculture',
    'jardim': 'grass',
    'meio ambiente': 'forest',
    'ecologia': 'forest',
    'reciclagem': 'recycling',
    'sustentável': 'compost',
    'sustentavel': 'compost',
    'mecânico': 'car_repair',
    'mecanico': 'car_repair',
    'oficina': 'car_repair',
    'pneus': 'tire_repair',
    'imobiliária': 'real_estate_agent',
    'imobiliaria': 'real_estate_agent',
    'apartamento': 'apartment',
    'prédio': 'location_city',
    'predio': 'location_city',
    'carga': 'luggage',
    'teatro': 'theater_comedy',
    'arte': 'palette',
    'pintura': 'palette',
    'lavanderia': 'local_laundry_service',
    'dedetização': 'pest_control',
    'dedetizacao': 'pest_control',
    'encanador': 'plumbing',
    'telhado': 'roofing',
    'gás': 'gas_meter',
    'gas': 'gas_meter',
    'água': 'water_drop',
    'agua': 'water_drop',
    'máscara': 'masks',
    'mascara': 'masks',
    'vacina': 'vaccines',
    'terceira idade': 'elderly',
    'jóias': 'diamond',
    'joias': 'diamond',
    'semijoias': 'diamond',
    'bijuterias': 'diamond',
    'natureza': 'forest',
    'trilha': 'hiking',
    'esqui': 'downhill_skiing',
    'mapa': 'map',
    'praia': 'beach_access',
    'manufatura': 'precision_manufacturing',
  };

  static IconData _resolverIcone(String iconKey) {
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
      case 'hand_gesture': return Icons.pan_tool_rounded;
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
      case 'sewing': return Icons.carpenter_rounded;
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
      case 'sports_basketball': return Icons.sports_basketball_rounded;
      case 'sports_tennis': return Icons.sports_tennis_rounded;
      case 'sports_volleyball': return Icons.sports_volleyball_rounded;
      case 'sports_kabaddi': return Icons.sports_kabaddi_rounded;
      case 'sports_martial_arts': return Icons.sports_martial_arts_rounded;
      case 'sports_handball': return Icons.sports_handball_rounded;
      case 'sports': return Icons.sports_rounded;
      case 'hiking': return Icons.hiking_rounded;
      case 'kayaking': return Icons.kayaking_rounded;
      case 'camping': return Icons.nature_rounded;
      case 'skateboarding': return Icons.skateboarding_rounded;
      case 'surfing': return Icons.surfing_rounded;
      case 'cycling': return Icons.directions_bike_rounded;
      case 'dining': return Icons.dining_rounded;
      case 'liquor': return Icons.liquor_rounded;
      case 'wine_bar': return Icons.wine_bar_rounded;
      case 'coffee': return Icons.coffee_rounded;
      case 'delivery': return Icons.delivery_dining_rounded;
      case 'bike': return Icons.bike_scooter_rounded;
      case 'truck': return Icons.local_shipping_rounded;
      case 'bus': return Icons.bus_alert_rounded;
      case 'train': return Icons.train_rounded;
      case 'subway': return Icons.subway_rounded;
      case 'taxi': return Icons.taxi_alert_rounded;
      case 'two_wheeler': return Icons.two_wheeler_rounded;
      case 'electric_bike': return Icons.electric_bike_rounded;
      case 'electric_scooter': return Icons.electric_scooter_rounded;
      case 'electric_car': return Icons.electric_car_rounded;
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

  /// Descobre o iconKey a partir do nome da categoria
  static String _sugerirIconKey(String nome) {
    final chave = nome.trim().toLowerCase();
    if (_keywordToIcon.containsKey(chave)) return _keywordToIcon[chave]!;
    for (final entry in _keywordToIcon.entries) {
      if (chave.contains(entry.key) || entry.key.contains(chave)) {
        return entry.value;
      }
    }
    return '';
  }

  /// Gera cor de fundo suave sugerida — padrão roxo DiPertin.
  static String _sugerirBgColor(String nome) {
    return 'EDE7F6'; // roxo claríssimo — padrão para todas
  }

  /// Gera cor de destaque (ícone) sugerida
  /// Gera cor de destaque (ícone) sugerida — padrão roxo DiPertin.
  static String _sugerirIconColor(String nome) {
    return '6A1B9A';
  }

  /// Mapa de termos em português para chaves de ícone (busca no seletor)
  static final Map<String, String> _iconKeywordsPt = {
    // Alimentação
    'restaurante': 'restaurant',
    'comida': 'local_dining',
    'lanche': 'lunch_dining',
    'hamburguer': 'lunch_dining',
    'pizza': 'local_pizza',
    'padaria': 'bakery_dining',
    'pao': 'bakery_dining',
    'bolo': 'cake',
    'doce': 'cake',
    'sorvete': 'icecream',
    'gelado': 'icecream',
    'café': 'local_cafe',
    'cafe': 'local_cafe',
    'cafeteria': 'local_cafe',
    'bebida': 'coffee',
    'jantar': 'dining',
    'bebida alcoolica': 'liquor',
    'bar': 'wine_bar',
    'vinho': 'wine_bar',
    // Mercado & Compras
    'carrinho': 'shopping_cart',
    'compras': 'shopping_cart',
    'loja': 'store',
    'presente': 'card_giftcard',
    'flor': 'local_florist',
    'flores': 'local_florist',
    'brinquedo': 'toys',
    // Saúde & Beleza
    'farmácia': 'local_pharmacy',
    'farmacia': 'local_pharmacy',
    'remedio': 'local_pharmacy',
    'saúde': 'health_and_safety',
    'saude': 'health_and_safety',
    'medico': 'medical_services',
    'hospital': 'local_hospital',
    'beleza': 'spa',
    'corte cabelo': 'content_cut',
    'barbearia': 'content_cut',
    'cabeleireiro': 'content_cut',
    'salão': 'face',
    'salao': 'face',
    'maquiagem': 'face',
    'estetica': 'hand_gesture',
    // Moda
    'roupa': 'checkroom',
    'vestuario': 'checkroom',
    'patinação': 'ice_skating',
    'patins': 'ice_skating',
    'relogio': 'watch',
    // Casa & Construção
    'casa': 'home',
    'construção': 'construction',
    'construcao': 'construction',
    'pintura': 'palette',
    'luz': 'light',
    'iluminacao': 'light',
    'cadeira': 'chair',
    'sofa': 'chair',
    'cama': 'bed',
    'dormir': 'bed',
    'cozinha': 'kitchen',
    'limpeza': 'cleaning_services',
    'faxina': 'cleaning_services',
    'banheira': 'bathtub',
    'banho': 'bathtub',
    'jardim': 'yard',
    'piscina': 'pool',
    'eletricista': 'electrical_services',
    'reparos': 'handyman',
    'conserto': 'handyman',
    // Tecnologia
    'dispositivos': 'devices',
    'celular': 'smartphone',
    'smartphone': 'smartphone',
    'telefone': 'smartphone',
    'computador': 'computer',
    'notebook': 'computer',
    'jogos': 'sports_esports',
    'game': 'sports_esports',
    'codigo': 'code',
    'impressora': 'print',
    'camera': 'photo_camera',
    'fotografia': 'photo_camera',
    'video': 'videocam',
    'filmagem': 'videocam',
    'marketing': 'campaign',
    'promocao': 'campaign',
    // Transporte
    'moto': 'motorcycle',
    'motocicleta': 'motorcycle',
    'carro': 'directions_car',
    'automovel': 'directions_car',
    'entrega': 'local_shipping',
    'delivery': 'delivery',
    'frete': 'local_shipping',
    'caminhão': 'truck',
    'caminhao': 'truck',
    'onibus': 'bus',
    'trem': 'train',
    'metro': 'subway',
    'taxi': 'taxi',
    'bicicleta': 'bike',
    'bike': 'bike',
    'patinete': 'electric_scooter',
    'carro eletrico': 'electric_car',
    // Serviços & Profissões
    'construir': 'build',
    'ferramentas': 'build',
    'trabalho': 'work',
    'profissao': 'work',
    'escritorio': 'work',
    'engenharia': 'engineering',
    'engenheiro': 'engineering',
    'desenho': 'draw',
    'arquitetura': 'draw',
    'escola': 'school',
    'estudo': 'school',
    'idioma': 'language',
    'traducao': 'translate',
    'banco': 'account_balance',
    'financas': 'account_balance',
    'advogado': 'gavel',
    'justiça': 'gavel',
    'justica': 'gavel',
    'segurança': 'security',
    'seguranca': 'security',
    'vigilante': 'security',
    // Esportes & Lazer
    'futebol': 'sports_soccer',
    'basquete': 'sports_basketball',
    'tenis': 'sports_tennis',
    'volei': 'sports_volleyball',
    'academia': 'fitness_center',
    'musculação': 'fitness_center',
    'trilha': 'hiking',
    'caminhada': 'hiking',
    'caiuque': 'kayaking',
    'acampar': 'camping',
    'natureza': 'camping',
    'skate': 'skateboarding',
    'surfe': 'surfing',
    'pedalar': 'cycling',
    'viajar': 'flight',
    'viagem': 'flight',
    'aviao': 'flight',
    'hotel': 'hotel',
    'hospedagem': 'hotel',
    // Eventos & Cultura
    'festa': 'celebration',
    'comemoracao': 'celebration',
    'musica': 'music_note',
    'som': 'music_note',
    'cardapio': 'menu_book',
    'menu': 'menu_book',
    'livro': 'menu_book',
    'anotar': 'edit_note',
    'costura': 'sewing',
    'animal': 'pets',
    'pet': 'pets',
    'cachorro': 'pets',
    'gato': 'pets',
    // NOVOS — Importação & Finanças
    'importação': 'import_export',
    'importacao': 'import_export',
    'exportação': 'import_export',
    'exportacao': 'import_export',
    'mundo': 'public',
    'globo': 'public',
    'documento': 'assignment',
    'papel': 'description',
    'nota fiscal': 'receipt_long',
    'nf': 'receipt_long',
    'armazém': 'warehouse',
    'armazem': 'warehouse',
    'estoque': 'inventory',
    'pagamento': 'payments',
    'dinheiro': 'monetization_on',
    'orçamento': 'request_quote',
    'orcamento': 'request_quote',
    'venda': 'sell',
    'vender': 'sell',
    'contrato': 'post_add',
    'agronegócio': 'agriculture',
    'agronegocio': 'agriculture',
    'fazenda': 'agriculture',
    'planta': 'grass',
    'plantação': 'grass',
    'plantacao': 'grass',
    'árvore': 'forest',
    'arvore': 'forest',
    'reciclagem': 'recycling',
    'lixo': 'recycling',
    'adubo': 'compost',
    // Casa & Construção — novos
    'encanador': 'plumbing',
    'telhado': 'roofing',
    'dedetização': 'pest_control',
    'dedetizacao': 'pest_control',
    'lavanderia': 'local_laundry_service',
    'lavar roupa': 'dry_cleaning',
    'gás': 'gas_meter',
    'gas': 'gas_meter',
    'água': 'water_drop',
    'agua': 'water_drop',
    // Saúde — novos
    'mascara': 'masks',
    'vacina': 'vaccines',
    'idoso': 'elderly',
    'terceira idade': 'elderly_woman',
    // Moda — novos
    'joia': 'diamond',
    'jóia': 'diamond',
    'brilhante': 'diamond',
    // Automotivo — novos
    'mecânica': 'car_repair',
    'mecanica': 'car_repair',
    'oficina': 'car_repair',
    'pneu': 'tire_repair',
    'borracharia': 'tire_repair',
    // Imobiliária
    'imobiliária': 'real_estate_agent',
    'imobiliaria': 'real_estate_agent',
    'corretor': 'real_estate_agent',
    'predio': 'apartment',
    'prédio': 'apartment',
    'cidade': 'location_city',
    // Transporte novos
    'carga': 'luggage',
    'bagagem': 'luggage',
    'mapa': 'map',
    'praia': 'beach_access',
    'veleiro': 'sailing',
    'asa delta': 'paragliding',
    'esqui': 'downhill_skiing',
    'snowboard': 'snowboarding',
    'trenó': 'sledding',
    'treno': 'sledding',
    // Música & Cultura
    'piano': 'piano',
    'teatro': 'theater_comedy',
    'arte': 'theater_comedy',
    'orquestra': 'piano',
    // Tecnologia novos
    'manufatura': 'precision_manufacturing',
    'fabrica': 'precision_manufacturing',
    'design': 'design_services',
    // Transporte alternativo
    'bicicleta eletrica': 'pedal_bike',
    'moto eletrica': 'electric_moped',
  };

  /// Paleta de ícones disponíveis para seleção manual (agrupados)
  static List<_GrupoIcone> get _gruposIcones {
    return [
      _GrupoIcone('Alimentação', [
        'restaurant', 'local_dining', 'lunch_dining', 'local_pizza',
        'bakery_dining', 'cake', 'icecream', 'local_cafe',
        'coffee', 'dining', 'liquor', 'wine_bar',
      ]),
      _GrupoIcone('Mercado & Compras', [
        'shopping_cart', 'store', 'card_giftcard', 'local_florist',
        'auto_awesome', 'toys', 'sell', 'inventory',
      ]),
      _GrupoIcone('Saúde & Beleza', [
        'local_pharmacy', 'health_and_safety', 'medical_services',
        'local_hospital', 'spa', 'content_cut', 'face', 'hand_gesture',
        'masks', 'vaccines', 'elderly', 'elderly_woman',
      ]),
      _GrupoIcone('Moda & Acessórios', [
        'checkroom', 'ice_skating', 'watch', 'diamond',
      ]),
      _GrupoIcone('Casa & Construção', [
        'home', 'construction', 'palette', 'light', 'chair', 'bed',
        'kitchen', 'cleaning_services', 'bathtub', 'yard', 'pool',
        'electrical_services', 'handyman', 'house', 'plumbing',
        'roofing', 'pest_control', 'dry_cleaning',
        'local_laundry_service', 'gas_meter', 'water_drop',
      ]),
      _GrupoIcone('Tecnologia', [
        'devices', 'smartphone', 'computer', 'sports_esports', 'code',
        'print', 'photo_camera', 'videocam', 'campaign',
        'precision_manufacturing', 'design_services',
      ]),
      _GrupoIcone('Transporte', [
        'motorcycle', 'directions_car', 'local_shipping', 'delivery',
        'bike', 'truck', 'bus', 'train', 'subway', 'taxi',
        'two_wheeler', 'electric_bike', 'electric_scooter', 'electric_car',
        'car_repair', 'tire_repair', 'pedal_bike', 'electric_moped',
        'moped', 'sailing', 'luggage',
      ]),
      _GrupoIcone('Serviços & Profissões', [
        'build', 'work', 'engineering', 'draw', 'school', 'language',
        'translate', 'account_balance', 'gavel', 'security',
        'real_estate_agent', 'architecture',
      ]),
      _GrupoIcone('Esportes & Lazer', [
        'sports_soccer', 'sports_basketball', 'sports_tennis',
        'sports_volleyball', 'fitness_center', 'sports_esports',
        'hiking', 'kayaking', 'camping', 'skateboarding', 'surfing',
        'cycling', 'pool', 'flight', 'hotel', 'beach_access',
        'paragliding', 'roller_skating', 'downhill_skiing',
        'snowboarding', 'sledding', 'nature', 'map',
      ]),
      _GrupoIcone('Eventos & Cultura', [
        'celebration', 'music_note', 'menu_book', 'edit_note',
        'sewing', 'pets', 'piano', 'theater_comedy',
      ]),
      _GrupoIcone('Importação & Finanças', [
        'import_export', 'public', 'assignment', 'description',
        'receipt_long', 'warehouse', 'payments', 'monetization_on',
        'request_quote', 'book', 'post_add', 'agriculture',
        'grass', 'forest', 'recycling', 'compost',
      ]),
    ];
  }

  /// Abre o seletor de ícones e retorna o iconKey escolhido (ou null se cancelar)
  Future<String?> _abrirSeletorIcone(BuildContext ctx, String? atual) async {
    final buscaCtrl = TextEditingController();
    String busca = '';
    return showDialog<String>(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setS2) {
          final grupos = busca.isEmpty
              ? _gruposIcones
              : _gruposIcones.map((g) {
                  final filtrados = g.icones.where((i) {
                    final nomeIcone = i.replaceAll('_', ' ');
                    // Busca em português: verifica se o termo digitado corresponde a algum ícone
                    final emPt = _iconKeywordsPt.entries
                        .where((e) => e.value == i)
                        .any((e) => e.key.contains(busca.toLowerCase()));
                    return nomeIcone.contains(busca.toLowerCase()) ||
                        g.nome.toLowerCase().contains(busca.toLowerCase()) ||
                        emPt;
                  }).toList();
                  return _GrupoIcone(g.nome, filtrados);
                }).where((g) => g.icones.isNotEmpty).toList();

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _roxo.withValues(alpha: 0.10),
                          _laranja.withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.emoji_objects_rounded,
                                color: _roxo),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Escolher ícone',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _roxo,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx2),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: buscaCtrl,
                          onChanged: (v) => setS2(() => busca = v),
                          decoration: InputDecoration(
                            hintText: 'Buscar ícone…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Opção "Sem ícone / padrão"
                        _buildIconeOpcao(ctx2, setS2, atual, ''),
                        const SizedBox(height: 4),
                        ...grupos.expand((grupo) {
                          return [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12, bottom: 4, left: 4,
                              ),
                              child: Text(
                                grupo.nome,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: PainelAdminTheme.textoSecundario,
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: grupo.icones.map((ik) {
                                return _buildIconeOpcao(
                                  ctx2, setS2, atual, ik,
                                );
                              }).toList(),
                            ),
                          ];
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIconeOpcao(
    BuildContext ctx,
    void Function(void Function()) setS2,
    String? atual,
    String iconKey,
  ) {
    final selecionado = atual == iconKey;
    final isPadrao = iconKey.isEmpty;

    return Tooltip(
      message: iconKey.isEmpty ? 'Padrão' : iconKey.replaceAll('_', ' '),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(ctx, iconKey),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: selecionado
                  ? _roxo.withValues(alpha: 0.10)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selecionado
                    ? _roxo
                    : Colors.grey.shade200,
                width: selecionado ? 2 : 1,
              ),
            ),
            child: isPadrao
                ? const Icon(Icons.category_rounded,
                    color: Colors.grey, size: 26)
                : Icon(_resolverIcone(iconKey),
                    color: selecionado ? _roxo : Colors.grey.shade700,
                    size: 26),
          ),
        ),
      ),
    );
  }

  Future<bool> _abrirFormulario({
    String? docId,
    Map<String, dynamic>? dados,
    String? sugestaoNome,
  }) async {
    final isEdit = docId != null;
    final nomeC = TextEditingController(
      text: dados?['nome']?.toString() ?? sugestaoNome ?? '',
    );
    final slugC = TextEditingController(text: dados?['slug']?.toString() ?? '');
    final grupoC = TextEditingController(
      text: dados?['grupo']?.toString() ?? '',
    );
    final imagemC = TextEditingController(
      text: dados?['imagem']?.toString() ?? '',
    );
    final ordemC = TextEditingController(
      text: dados?['ordem'] != null ? dados!['ordem'].toString() : '100',
    );
    final sinonimosC = TextEditingController(
      text: (dados?['sinonimos'] is List)
          ? (dados!['sinonimos'] as List).join(', ')
          : '',
    );
    var ativo = dados?['ativo'] != false;
    var destaque = dados?['destaque'] == true;
    var tipo = (dados?['tipo'] ?? 'produto').toString();
    if (!['produto', 'servico', 'ambos'].contains(tipo)) tipo = 'produto';
    var salvando = false;

    // Estados do ícone (fora do StatefulBuilder para persistir entre rebuilds)
    var iconKeyManual = dados?['iconKey']?.toString() ?? '';
    var iconKeySugerido = _sugerirIconKey(
      dados?['nome']?.toString() ?? sugestaoNome ?? '',
    );
    var iconColorSugerido = _sugerirIconColor(
      dados?['nome']?.toString() ?? sugestaoNome ?? '',
    );
    var bgColorSugerido = _sugerirBgColor(
      dados?['nome']?.toString() ?? sugestaoNome ?? '',
    );
    // Se editando com cores salvas, usa como base inicial
    if (dados != null) {
      final bgSalvo = dados['backgroundColor']?.toString() ?? '';
      final icSalvo = dados['iconColor']?.toString() ?? '';
      if (bgSalvo.isNotEmpty) bgColorSugerido = bgSalvo;
      if (icSalvo.isNotEmpty) iconColorSugerido = icSalvo;
    }
    var iconSource = dados?['iconSource']?.toString() ?? '';
    // Se não houver source definido, determina pelo que existe
    if (iconSource.isEmpty) {
      if ((dados?['imagem']?.toString() ?? '').isNotEmpty) {
        iconSource = 'custom_image';
      } else if (iconKeyManual.isNotEmpty) {
        iconSource = 'manual_icon';
      } else if (iconKeySugerido.isNotEmpty) {
        iconSource = 'automatic_icon';
      } else {
        iconSource = 'default_icon';
      }
    }

    final salvo = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Ícone efetivo para exibição
          String iconKeyEfetivo() {
            if (imagemC.text.trim().isNotEmpty) return '';
            if (iconKeyManual.isNotEmpty) return iconKeyManual;
            if (iconKeySugerido.isNotEmpty) return iconKeySugerido;
            return '';
          }

          String bgColorEfetivo() {
            if (imagemC.text.trim().isNotEmpty) return 'FFFFFF';
            return bgColorSugerido;
          }

          String iconeColorEfetivo() {
            if (imagemC.text.trim().isNotEmpty) return '6A1B9A';
            return iconColorSugerido;
          }

          Future<void> salvar() async {
            final nome = nomeC.text.trim();
            if (nome.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Informe o nome da categoria.')),
              );
              return;
            }
            setS(() => salvando = true);
            try {
              final slug = slugC.text.trim().isEmpty
                  ? _slug(nome)
                  : _slug(slugC.text);
              final imagem = imagemC.text.trim();
              final temImagem = imagem.isNotEmpty;

              // Determina os campos de ícone
              final finalIconKey = temImagem ? '' : iconKeyManual.isNotEmpty
                  ? iconKeyManual
                  : iconKeySugerido;
              final finalIconSource = temImagem
                  ? 'custom_image'
                  : iconKeyManual.isNotEmpty
                      ? 'manual_icon'
                      : iconKeySugerido.isNotEmpty
                          ? 'automatic_icon'
                          : 'default_icon';
              final finalIconColor = temImagem ? '' : iconeColorEfetivo();
              final finalBgColor = temImagem ? '' : bgColorEfetivo();

              final patch = <String, dynamic>{
                'nome': nome,
                'slug': slug,
                'grupo': grupoC.text.trim(),
                'ordem': int.tryParse(ordemC.text.trim()) ?? 100,
                'sinonimos': _sinonimos(sinonimosC.text),
                'ativo': ativo,
                'destaque': destaque,
                'tipo': tipo,
                'imagem': imagem,
                'iconKey': finalIconKey,
                'iconColor': finalIconColor,
                'backgroundColor': finalBgColor,
                'iconSource': finalIconSource,
                'atualizada_em': FieldValue.serverTimestamp(),
              };
              final col = FirebaseFirestore.instance.collection('categorias');
              if (isEdit) {
                await col.doc(docId).update(patch);
              } else {
                patch['criada_em'] = FieldValue.serverTimestamp();
                await col.doc(slug).set(patch);
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('Erro: $e')));
              }
            } finally {
              if (ctx.mounted) setS(() => salvando = false);
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // HEADER
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _roxo.withValues(alpha: 0.10),
                          _laranja.withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(_iconeVisualPorTipo(tipo), color: _roxo),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isEdit ? 'Editar categoria' : 'Nova categoria',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _roxo,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: salvando
                              ? null
                              : () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                      child: Column(
                        children: [
                          // PRÉVIA VISUAL
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 18, horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                  'FF${bgColorEfetivo()}',
                                  radix: 16,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(
                                          int.parse(
                                            'FF${iconeColorEfetivo()}',
                                            radix: 16,
                                          ),
                                        ).withValues(alpha: 0.15),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: iconKeyEfetivo().isEmpty
                                      ? Icon(
                                          Icons.category_rounded,
                                          size: 28,
                                          color: Color(
                                            int.parse(
                                              'FF${iconeColorEfetivo()}',
                                              radix: 16,
                                            ),
                                          ),
                                        )
                                      : Icon(
                                          _resolverIcone(iconKeyEfetivo()),
                                          size: 28,
                                          color: Color(
                                            int.parse(
                                              'FF${iconeColorEfetivo()}',
                                              radix: 16,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  nomeC.text.trim().isEmpty
                                      ? 'Nome da categoria'
                                      : nomeC.text.trim(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(
                                      int.parse(
                                        'FF${iconeColorEfetivo()}',
                                        radix: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  imagemC.text.trim().isNotEmpty
                                      ? 'Usando imagem personalizada'
                                      : iconKeyManual.isNotEmpty
                                          ? 'Ícone selecionado manualmente'
                                          : iconKeySugerido.isNotEmpty
                                              ? 'Ícone sugerido automaticamente'
                                              : 'Ícone padrão',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(
                                      int.parse(
                                        'FF${iconeColorEfetivo()}',
                                        radix: 16,
                                      ),
                                    ).withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final escolhido = await _abrirSeletorIcone(
                                      ctx,
                                      iconKeyManual.isNotEmpty
                                          ? iconKeyManual
                                          : null,
                                    );
                                    if (escolhido != null && ctx.mounted) {
                                      setS(() {
                                        iconKeyManual = escolhido;
                                        iconSource = escolhido.isEmpty
                                            ? 'automatic_icon'
                                            : 'manual_icon';
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.emoji_objects_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Alterar ícone'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black87,
                                    side: BorderSide(
                                      color: Colors.black.withValues(alpha: 0.12),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Nome
                          TextField(
                            controller: nomeC,
                            decoration: _dec('Nome *'),
                            onChanged: (v) {
                              if (!isEdit && slugC.text.trim().isEmpty) {
                                setS(() {});
                              }
                              // Auto-sugestão de ícone ao digitar
                              final novoNome = v.trim();
                              if (novoNome.isNotEmpty) {
                                final novoIconKey = _sugerirIconKey(novoNome);
                                iconColorSugerido = _sugerirIconColor(novoNome);
                                bgColorSugerido = _sugerirBgColor(novoNome);
                                if (novoIconKey.isNotEmpty &&
                                    iconKeyManual.isEmpty) {
                                  iconKeySugerido = novoIconKey;
                                  iconSource = 'automatic_icon';
                                }
                              } else {
                                iconKeySugerido = '';
                                iconColorSugerido = '6A1B9A';
                                bgColorSugerido = 'F3EFF7';
                                iconSource = 'default_icon';
                              }
                              setS(() {});
                            },
                          ),
                          const SizedBox(height: 12),
                          // Slug + Grupo
                          TextField(
                            controller: slugC,
                            decoration: _dec('Slug', hint: _slug(nomeC.text)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: grupoC,
                                  decoration: _dec(
                                    'Grupo',
                                    hint: 'Ex.: Moda, Mercado, Casa',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: ordemC,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _dec('Ordem'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Tipo
                          DropdownButtonFormField<String>(
                            initialValue: tipo,
                            decoration: _dec('Tipo'),
                            items: const [
                              DropdownMenuItem(
                                value: 'produto',
                                child: Text('Produto'),
                              ),
                              DropdownMenuItem(
                                value: 'servico',
                                child: Text('Serviço'),
                              ),
                              DropdownMenuItem(
                                value: 'ambos',
                                child: Text('Produto e serviço'),
                              ),
                            ],
                            onChanged: (v) => setS(() => tipo = v ?? 'produto'),
                          ),
                          const SizedBox(height: 16),

                          // SEÇÃO AVANÇADA: Imagem
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.image_rounded,
                                      size: 18,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Imagem personalizada (opcional)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ao informar uma URL de imagem, ela substituirá o ícone selecionado.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: imagemC,
                                  decoration: _dec('URL da imagem'),
                                  onChanged: (_) => setS(() {
                                    if (imagemC.text.trim().isNotEmpty) {
                                      iconSource = 'custom_image';
                                    } else {
                                      iconSource = iconKeyManual.isNotEmpty
                                          ? 'manual_icon'
                                          : iconKeySugerido.isNotEmpty
                                              ? 'automatic_icon'
                                              : 'default_icon';
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Sinônimos
                          TextField(
                            controller: sinonimosC,
                            decoration: _dec(
                              'Sinônimos',
                              hint: 'moda, vestuário, roupa',
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Switches
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: ativo,
                            onChanged: (v) => setS(() => ativo = v),
                            title: const Text('Categoria ativa'),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: destaque,
                            onChanged: (v) => setS(() => destaque = v),
                            title: const Text('Mostrar em destaque no Buscar'),
                            subtitle: const Text(
                              'Use para as categorias principais do app.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: salvando
                              ? null
                              : () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: salvando ? null : salvar,
                          icon: salvando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(salvando ? 'Salvando...' : 'Salvar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return salvo == true;
  }

  Future<void> _aprovarSugestao(
    String sugestaoId,
    Map<String, dynamic> dados,
  ) async {
    final salvo = await _abrirFormulario(
      sugestaoNome: dados['nome']?.toString() ?? '',
    );
    if (!salvo) return;
    await FirebaseFirestore.instance
        .collection('sugestoes_categorias')
        .doc(sugestaoId)
        .update({
          'status': 'aprovada',
          'analisada_em': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _recusarSugestao(String sugestaoId) async {
    await FirebaseFirestore.instance
        .collection('sugestoes_categorias')
        .doc(sugestaoId)
        .update({
          'status': 'recusada',
          'analisada_em': FieldValue.serverTimestamp(),
        });
  }

  bool _sugestaoPendente(Map<String, dynamic> dados) {
    final status = (dados['status'] ?? '').toString().trim().toLowerCase();
    return status.isEmpty || status == 'pendente';
  }

  DateTime _dataSugestao(Map<String, dynamic> dados) {
    final raw = dados['data'] ?? dados['criada_em'] ?? dados['created_at'];
    if (raw is Timestamp) return raw.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<String> _nomeLojaSugestao(String lojistaId) async {
    if (lojistaId.trim().isEmpty) return 'Loja não identificada';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(lojistaId)
          .get();
      final dados = snap.data() ?? {};
      final nome =
          (dados['loja_nome'] ??
                  dados['nome_loja'] ??
                  dados['nome_fantasia'] ??
                  dados['nome'] ??
                  '')
              .toString()
              .trim();
      return nome.isEmpty ? 'Loja sem nome cadastrado' : nome;
    } catch (_) {
      return 'Loja não identificada';
    }
  }

  Future<void> _toggleBloqueio(
    String docId,
    Map<String, dynamic> d,
  ) async {
    final atualmenteAtivo = d['ativo'] != false;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(atualmenteAtivo ? 'Bloquear categoria' : 'Desbloquear categoria'),
        content: Text(
          atualmenteAtivo
              ? 'Tem certeza que deseja bloquear esta categoria? Ela ficará inativa.'
              : 'Tem certeza que deseja reativar esta categoria?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: atualmenteAtivo ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(atualmenteAtivo ? 'Bloquear' : 'Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await FirebaseFirestore.instance
        .collection('categorias')
        .doc(docId)
        .update({
      'ativo': !atualmenteAtivo,
      'atualizada_em': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deletarCategoria(
    String docId,
    String nome,
    Map<String, dynamic> d,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Excluir categoria'),
        content: Text('Tem certeza que deseja excluir permanentemente a categoria "$nome"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await FirebaseFirestore.instance
        .collection('categorias')
        .doc(docId)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== TOP BAR =====
          Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Breadcrumb
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {},
                        child: const Text(
                          'AdminCity',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _roxo,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '/',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Categorias',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Title row + summary
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Categorias',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Gerencie categorias oficiais e sugestões enviadas pelos lojistas.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Search + New button row
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: TextField(
                            controller: _buscaCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Buscar categoria…',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: Color(0xFF94A3B8),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _roxo, width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: _abrirFormulario,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text(
                            'Nova categoria',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _laranja,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // ===== CONTEÚDO PRINCIPAL 2 COLUNAS =====
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('categorias')
                  .snapshots(),
              builder: (context, snapCategorias) {
                final allDocs = snapCategorias.data?.docs ?? [];
                final qtdTotal = allDocs.length;
                final qtdAtivas = allDocs.where(
                  (d) => d.data()['ativo'] != false,
                ).length;

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('sugestoes_categorias')
                      .snapshots(),
                  builder: (context, snapSugestoes) {
                    final sugestoesDocs = (snapSugestoes.data?.docs ?? [])
                        .where((d) => _sugestaoPendente(d.data()))
                        .toList()
                      ..sort((a, b) {
                        final da = _dataSugestao(a.data());
                        final db = _dataSugestao(b.data());
                        return db.compareTo(da);
                      });
                    final qtdSugestoes = sugestoesDocs.length;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Coluna esquerda (75%)
                        Expanded(
                          flex: 3,
                          child: _buildCategorias(
                            docs: allDocs,
                            qtdTotal: qtdTotal,
                            qtdAtivas: qtdAtivas,
                            qtdSugestoes: qtdSugestoes,
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Coluna direita (25%)
                        SizedBox(
                          width: 340,
                          child: _buildSugestoes(
                            docs: sugestoesDocs,
                            qtdSugestoes: qtdSugestoes,
                          ),
                        ),
                        const SizedBox(width: 32),
                      ],
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

  Widget _buildCategorias({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required int qtdTotal,
    required int qtdAtivas,
    required int qtdSugestoes,
  }) {
    // Aplicar filtro de busca
    var docsFiltrados = docs.toList();
    final busca = _buscaCtrl.text.trim().toLowerCase();
    if (busca.isNotEmpty) {
      docsFiltrados = docsFiltrados.where((d) {
        final m = d.data();
        final txt = [
          m['nome'],
          m['slug'],
          m['grupo'],
          ...(m['sinonimos'] is List ? m['sinonimos'] as List : const []),
        ].join(' ').toLowerCase();
        return txt.contains(busca);
      }).toList();
    }

    // Aplicar filtro visual do chip
    if (_filtroChip != 'todas') {
      docsFiltrados = docsFiltrados.where((d) {
        final m = d.data();
        switch (_filtroChip) {
          case 'ativas':
            return m['ativo'] != false;
          case 'inativas':
            return m['ativo'] == false;
          case 'destaque':
            return m['destaque'] == true;
          case 'produto':
            return (m['tipo'] ?? 'produto').toString() == 'produto';
          case 'servico':
            return (m['tipo'] ?? 'produto').toString() == 'servico' ||
                (m['tipo'] ?? 'produto').toString() == 'ambos';
          default:
            return true;
        }
      }).toList();
    }

    // Ordenar por ordem crescente, depois por nome
    docsFiltrados.sort((a, b) {
      final ma = a.data();
      final mb = b.data();
      final oa = (ma['ordem'] as num?)?.toInt() ?? 999999;
      final ob = (mb['ordem'] as num?)?.toInt() ?? 999999;
      if (oa != ob) return oa.compareTo(ob);
      return (ma['nome'] ?? '').toString().compareTo(
        (mb['nome'] ?? '').toString(),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                // Summary card
                _buildResumoCard(qtdTotal, qtdAtivas, qtdSugestoes),
                const SizedBox(width: 20),
                // Filter chips
                _buildFiltroChip('Todas', 'todas', icone: Icons.dashboard_rounded),
                const SizedBox(width: 8),
                _buildFiltroChip('Ativas', 'ativas', cor: Colors.green),
                const SizedBox(width: 8),
                _buildFiltroChip('Inativas', 'inativas', cor: Colors.grey),
                const SizedBox(width: 8),
                _buildFiltroChip('Destaques', 'destaque', cor: _laranja,
                    icone: Icons.star_rounded),
                const SizedBox(width: 8),
                _buildFiltroChip('Produtos', 'produto', cor: _roxo,
                    icone: Icons.inventory_2_rounded),
                const SizedBox(width: 8),
                _buildFiltroChip('Serviços', 'servico', cor: const Color(0xFF3B82F6),
                    icone: Icons.home_repair_service_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Card principal da lista
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 0, 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: docsFiltrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.category_rounded,
                              size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma categoria encontrada.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12,
                      ),
                      itemCount: docsFiltrados.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docsFiltrados[i];
                        final d = doc.data();
                        final ativo = d['ativo'] != false;
                        final destaque = d['destaque'] == true;
                        final ordem = (d['ordem'] as num?)?.toInt() ?? 100;
                        final tipo = _rotuloTipo(
                          (d['tipo'] ?? 'produto').toString(),
                        );
                        final nome = d['nome']?.toString() ?? 'Categoria';
                        final img = d['imagem']?.toString() ?? '';

                        Widget? iconeWidget;
                        if (img.isNotEmpty) {
                          iconeWidget = ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(img,
                              width: 44, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_,_,_) => _buildIconFallback(d, ativo),
                            ),
                          );
                        } else {
                          iconeWidget = _buildIconFallback(d, ativo);
                        }

                        return _buildCategoriaCard(
                          nome: nome,
                          tipo: tipo,
                          ordem: ordem,
                          ativo: ativo,
                          destaque: destaque,
                          iconeWidget: iconeWidget,
                          onEditar: () => _abrirFormulario(
                            docId: doc.id, dados: d,
                          ),
                          onBloquear: () => _toggleBloqueio(doc.id, d),
                          onDeletar: () => _deletarCategoria(doc.id, nome, d),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconFallback(Map<String, dynamic> d, bool ativo) {
    final ik = d['iconKey']?.toString() ?? '';
    final nome = d['nome']?.toString() ?? '';
    if (ik.isNotEmpty) {
      return Icon(_resolverIcone(ik), size: 20,
          color: ativo ? _roxo : Colors.grey);
    }
    final autoIk = _sugerirIconKey(nome);
    if (autoIk.isNotEmpty) {
      return Icon(_resolverIcone(autoIk), size: 20,
          color: ativo ? _roxo : Colors.grey);
    }
    return Icon(
      _iconeVisualPorTipo((d['tipo'] ?? 'produto').toString()),
      size: 20,
      color: ativo ? _roxo : Colors.grey,
    );
  }

  Widget _buildResumoCard(int qtdTotal, int qtdAtivas, int qtdSugestoes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _roxo.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _roxo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.category_rounded,
                color: _roxo, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$qtdTotal categorias',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$qtdAtivas ativas',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (qtdSugestoes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _laranja.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$qtdSugestoes pendentes',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _laranja,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label, String valor,
      {Color? cor, IconData? icone}) {
    final selecionado = _filtroChip == valor;
    return GestureDetector(
      onTap: () => setState(() => _filtroChip = valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selecionado
              ? _roxo.withValues(alpha: 0.07)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado
                ? _roxo.withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: selecionado ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cor != null) ...[
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: cor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (icone != null) ...[
              Icon(icone, size: 16,
                  color: selecionado ? _roxo : Colors.grey[600]),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selecionado ? _roxo : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriaCard({
    required String nome,
    required String tipo,
    required int ordem,
    required bool ativo,
    required bool destaque,
    required Widget iconeWidget,
    required VoidCallback onEditar,
    required VoidCallback onBloquear,
    required VoidCallback onDeletar,
  }) {
    final isBloqueada = !ativo;
    final statusCor = isBloqueada ? Colors.red : Colors.green;
    final statusTexto = isBloqueada ? 'Bloqueada' : 'Ativa';
    final statusIcone = isBloqueada
        ? Icons.block_rounded
        : Icons.check_circle_rounded;

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBloqueada
              ? Colors.red.withValues(alpha: 0.25)
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        hoverColor: _roxo.withValues(alpha: 0.03),
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // Ícone
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isBloqueada
                      ? Colors.red.withValues(alpha: 0.08)
                      : _roxo.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Opacity(
                    opacity: isBloqueada ? 0.5 : 1.0,
                    child: iconeWidget,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Nome + tipo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isBloqueada
                            ? Colors.grey
                            : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.label_rounded,
                            size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          tipo,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Ordem
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ordem: $ordem',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Destaque badge
              if (destaque)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _laranja.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _laranja.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded,
                          size: 13, color: _laranja),
                      const SizedBox(width: 3),
                      Text(
                        'Destaque',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _laranja,
                        ),
                      ),
                    ],
                  ),
                ),
              if (destaque) const SizedBox(width: 8),
              // Status badge (verde para ativa, vermelho para bloqueada)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusCor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusCor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcone,
                        size: 13, color: statusCor),
                    const SizedBox(width: 3),
                    Text(
                      statusTexto,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusCor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Menu de três pontinhos (substitui lápis + pontinhos)
              PopupMenuButton<_AcaoCategoria>(
                offset: const Offset(0, 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                color: Colors.white,
                onSelected: (acao) {
                  switch (acao) {
                    case _AcaoCategoria.editar:
                      onEditar();
                    case _AcaoCategoria.bloquear:
                      onBloquear();
                    case _AcaoCategoria.deletar:
                      onDeletar();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _AcaoCategoria.editar,
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: _roxo.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_outlined,
                              size: 15, color: _roxo),
                        ),
                        const SizedBox(width: 10),
                        const Text('Editar',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _AcaoCategoria.bloquear,
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: (isBloqueada
                                    ? Colors.green
                                    : Colors.red)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isBloqueada
                                ? Icons.lock_open_rounded
                                : Icons.lock_rounded,
                            size: 15,
                            color: isBloqueada ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isBloqueada ? 'Desbloquear' : 'Bloquear',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isBloqueada ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _AcaoCategoria.deletar,
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_outline_rounded,
                              size: 15, color: Colors.red),
                        ),
                        const SizedBox(width: 10),
                        const Text('Deletar',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Icon(Icons.more_vert_rounded,
                        size: 18, color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSugestoes({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required int qtdSugestoes,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sugestões pendentes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _roxo,
                    ),
                  ),
                ),
                if (qtdSugestoes > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _roxo,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$qtdSugestoes',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          Expanded(
            child: qtdSugestoes == 0
                ? _buildSugestoesVazio()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.take(50).length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final d = doc.data();
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d['nome']?.toString() ?? 'Sugestão',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FutureBuilder<String>(
                              future: _nomeLojaSugestao(
                                (d['lojista_id'] ?? '').toString(),
                              ),
                              builder: (context, lojaSnap) {
                                return Text(
                                  'Loja: ${lojaSnap.data ?? 'Carregando...'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _recusarSugestao(doc.id),
                                      style: OutlinedButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: const Text('Recusar',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: FilledButton(
                                      onPressed: () =>
                                          _aprovarSugestao(doc.id, d),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _laranja,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: const Text('Aprovar',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSugestoesVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _roxo.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: _roxo.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const Icon(Icons.inbox_rounded,
                      size: 32, color: _roxo),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Nenhuma sugestão pendente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Quando um lojista sugerir uma nova\ncategoria, ela aparecerá aqui para análise.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AcaoCategoria { editar, bloquear, deletar }

class _GrupoIcone {
  final String nome;
  final List<String> icones;
  const _GrupoIcone(this.nome, this.icones);
}
