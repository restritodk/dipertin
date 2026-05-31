// Arquivo: lib/screens/cliente/cart_screen.dart

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/screens/auth/login_screen.dart';
import 'checkout_pagamento_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, max, min;
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import '../../providers/cart_provider.dart';
import '../../models/cart_item_model.dart';
import '../../services/firebase_functions_config.dart';
import '../../services/wallet_reserva_service.dart';
import '../../utils/loja_pausa.dart';
import '../../utils/loja_fachada_foto.dart';
import '../../constants/tipos_entrega.dart';
import '../../services/location_service.dart';
import 'cliente_encomenda_detalhe_screen.dart';
import 'selecionar_endereco_entrega_sheet.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _enderecoController = TextEditingController();
  final TextEditingController _cupomController = TextEditingController();

  /// Endereço estruturado do sheet — só frete/geocoding do pedido.
  /// Não altera [LocationService] (vitrine/busca = GPS do dispositivo).
  Map<String, dynamic>? _enderecoEntregaMapa;
  String _formaPagamento = 'PIX';
  bool _processandoPedido = false;
  bool _retirarNaLoja = false;

  // Variáveis para o saldo (apenas perfil cliente pode usar na compra)
  double _saldoCliente = 0.0;
  bool _usarSaldo = false;
  bool _clientePodeUsarSaldoCarteira = true;

  // Variáveis para o cupom
  bool _validandoCupom = false;
  bool _cupomAplicado = false;
  double _descontoCupom = 0.0;
  String? _cupomId;
  String? _cupomCodigo;
  String _cupomMensagem = '';
  bool _cupomErro = false;

  static const double _taxaBaseFallback = 5.00;
  double _taxaEntregaCalculada = _taxaBaseFallback;
  bool _calculandoTaxaEntrega = false;
  String _detalheTaxaEntrega = '';
  Timer? _debounceTaxa;
  String _ultimaLojaIdTaxa = '';

  /// Evita que um recálculo antigo (endereço anterior) sobrescreva o frete atual.
  int _freteRecalcGeracao = 0;

  /// Por loja (entrega) — usado no split multi-loja.
  Map<String, double> _taxaEntregaPorLoja = {};

  /// Memória detalhada da regra aplicada por loja (para mostrar a
  /// composição do frete no card Subtotal — auditoria visual).
  Map<String, _DetalheFreteLoja> _detalhesFretePorLoja = {};

  /// Cache dos `tipos_entrega_permitidos` por loja (lido uma vez em
  /// `_recalcularTaxaEntrega` e reaproveitado na criação dos pedidos para
  /// persistir snapshot no subpedido). Chave = lojaId; valor = lista
  /// canônica normalizada (pode estar vazia quando a loja é legado).
  Map<String, List<String>> _tiposEntregaAceitosPorLoja = {};
  int _qtdPedidosUltimoCheckout = 1;

  /// Frete por loja só para itens de encomenda (não entra no total da pronta-entrega).
  Map<String, double> _taxaEntregaEncomendaPorLoja = {};
  Map<String, _DetalheFreteLoja> _detalhesFreteEncomendaPorLoja = {};
  bool _calculandoTaxaEncomenda = false;

  double get _taxaEntregaReal => _retirarNaLoja ? 0.0 : _taxaEntregaCalculada;

  double _taxaEntregaEncomendaParaLoja(String lojaId) {
    if (_retirarNaLoja) return 0.0;
    final id = lojaId.trim();
    if (id.isEmpty) return 0.0;
    return _taxaEntregaEncomendaPorLoja[id] ?? _taxaBaseFallback;
  }

  Future<void> _abrirSelecaoEndereco() async {
    final res = await mostrarSelecionarEnderecoEntregaSheet(context);
    if (res == null || !mounted) return;
    setState(() {
      _enderecoController.text = res.textoEntrega;
      _enderecoEntregaMapa = Map<String, dynamic>.from(res.mapa);
      _calculandoTaxaEncomenda = true;
      _calculandoTaxaEntrega = true;
      _detalhesFreteEncomendaPorLoja = {};
      _detalhesFretePorLoja = {};
    });
    _agendarRecalculoTaxa(atraso: const Duration(milliseconds: 120));
  }

  static Map<String, List<CartItemModel>> _agruparItensCarrinhoPorLoja(
    List<CartItemModel> items,
  ) {
    final m = <String, List<CartItemModel>>{};
    for (final item in items) {
      final id = item.lojaId.trim();
      if (id.isEmpty) continue;
      m.putIfAbsent(id, () => []).add(item);
    }
    return m;
  }

  static double _subtotalItensLista(List<CartItemModel> list) {
    var t = 0.0;
    for (final i in list) {
      t += i.preco * i.quantidade;
    }
    return t;
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  static double? _coordToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  /// Fase 3G.3 — lê nome + foto_perfil do cliente uma única vez pra gravar
  /// denormalizado no pedido (`cliente_nome`, `cliente_foto_perfil`). Assim
  /// lojista e entregador mostram a identificação sem precisar ler `users/{cliente_id}`,
  /// o que permite fechar a rule de `users` pra proteger CPF/email/telefone/saldo.
  static Future<Map<String, String>> _lerIdentidadeClienteParaPedido(
    String clienteId,
  ) async {
    if (clienteId.trim().isEmpty) {
      return const {'nome': '', 'foto': '', 'telefone': ''};
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(clienteId)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final nome =
          (data['nome'] ??
                  data['nomeCompleto'] ??
                  data['nome_completo'] ??
                  data['displayName'] ??
                  '')
              .toString()
              .trim();
      final foto = (data['foto_perfil'] ?? data['foto'] ?? '')
          .toString()
          .trim();
      final telefone =
          (data['telefone'] ??
                  data['whatsapp'] ??
                  data['celular'] ??
                  data['telefone_contato'] ??
                  '')
              .toString()
              .trim();
      return {'nome': nome, 'foto': foto, 'telefone': telefone};
    } catch (_) {
      return const {'nome': '', 'foto': '', 'telefone': ''};
    }
  }

  /// Extrai o telefone comercial da loja do mirror público (`lojas_public`).
  static String _telefoneLoja(Map<String, dynamic>? ld) {
    if (ld == null) return '';
    for (final k in const ['telefone', 'whatsapp', 'celular']) {
      final v = (ld[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Extrai a imagem da loja em `lojas_public` para gravar como `loja_foto` no pedido.
  /// Prioriza foto de **fachada** (config. operacional): `foto` → `foto_logo` → `imagem`
  /// → legado `foto_perfil` → `foto_capa`.
  static String _melhorFotoLoja(Map<String, dynamic>? ld) =>
      urlFachadaLojaCliente(ld);

  static String _normalizarCidadeFrete(String valor) {
    var s = valor.trim().toLowerCase();
    if (s.isEmpty) return s;
    const mapa = <String, String>{
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
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      sb.write(mapa[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Chave de cidade igual ao painel (`tabela_fretes/{cidade}_{slug}`):
  /// remove acentos e sufixo de UF (ex.: "Toledo — PR" → "toledo").
  static String _chaveCidadeTabelaFrete(String valor) {
    final bruto = valor.trim();
    if (bruto.isEmpty) return '';
    final nome = LocationService.nomeCidadeParaFiltroAnuncio(bruto);
    return _normalizarCidadeFrete(nome.isNotEmpty ? nome : bruto);
  }

  /// Cidade da loja para buscar regras em `tabela_fretes`.
  static String _cidadeLojaParaFrete(Map<String, dynamic> ld) {
    for (final k in const [
      'cidade_normalizada',
      'cidade',
      'endereco_cidade',
    ]) {
      final chave = _chaveCidadeTabelaFrete((ld[k] ?? '').toString());
      if (chave.isNotEmpty) return chave;
    }
    return '';
  }

  /// Cidade usada para escolher a linha em `tabela_fretes` (zona de entrega).
  static String _cidadeEntregaParaTabelaFrete(
    String enderecoTexto,
    Map<String, dynamic>? enderecoMap,
  ) {
    String cidadeDoTexto() {
      final texto = enderecoTexto.trim();
      if (texto.isEmpty) return '';
      final partes = texto.split(',');
      if (partes.length >= 2) {
        final trecho = partes.last.trim();
        final c = _chaveCidadeTabelaFrete(trecho);
        if (c.isNotEmpty && c.length > 2) return c;
      }
      return '';
    }

    final doTexto = cidadeDoTexto();
    if (enderecoMap == null || enderecoMap.isEmpty) return doTexto;

    final doMapa = _chaveCidadeTabelaFrete(
      (enderecoMap['cidade'] ?? '').toString(),
    );
    if (doMapa.isEmpty) return doTexto;
    if (doTexto.isEmpty) return doMapa;
    // Texto exibido no carrinho é a fonte mais recente após trocar endereço.
    if (doMapa != doTexto) return doTexto;
    return doMapa;
  }

  Future<({double? lat, double? lng})> _resolverViaNominatim(
    String consulta,
  ) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': consulta,
        'format': 'jsonv2',
        'limit': '1',
      });
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': 'DiPertin/1.0 (frete-calculo)',
          'Accept': 'application/json',
        },
      );
      if (resp.statusCode != 200) return (lat: null, lng: null);
      final data = jsonDecode(resp.body);
      if (data is! List || data.isEmpty) return (lat: null, lng: null);
      final first = data.first;
      if (first is! Map) return (lat: null, lng: null);
      final lat = double.tryParse((first['lat'] ?? '').toString());
      final lng = double.tryParse((first['lon'] ?? '').toString());
      return (lat: lat, lng: lng);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  Future<({double? lat, double? lng})> _resolverCoordenadasEntrega({
    required String clienteId,
    required String enderecoTexto,
    Map<String, dynamic>? enderecoMap,
  }) async {
    String cidade = '';
    String uf = '';
    double? latDoc;
    double? lngDoc;

    final mapa = enderecoMap;
    if (mapa != null && mapa.isNotEmpty) {
      cidade = (mapa['cidade'] ?? '').toString().trim();
      uf = (mapa['estado'] ?? mapa['uf'] ?? '').toString().trim();
      latDoc = _coordToDouble(mapa['latitude']);
      lngDoc = _coordToDouble(mapa['longitude']);
    }

    try {
      final clienteSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(clienteId)
          .get();
      final dados = clienteSnap.data() ?? const <String, dynamic>{};
      final endPadrao =
          dados['endereco_entrega_padrao'] as Map<String, dynamic>?;

      latDoc ??=
          _coordToDouble(endPadrao?['latitude']) ??
          _coordToDouble(dados['latitude']);
      lngDoc ??=
          _coordToDouble(endPadrao?['longitude']) ??
          _coordToDouble(dados['longitude']);

      if (cidade.isEmpty) {
        cidade = (endPadrao?['cidade'] ?? dados['cidade'] ?? '')
            .toString()
            .trim();
      }
      if (uf.isEmpty) {
        uf = (endPadrao?['estado'] ?? dados['uf'] ?? '').toString().trim();
      }
    } catch (e) {
      debugPrint('Coordenadas da entrega não resolvidas: $e');
    }

    final baseEndereco = enderecoTexto.trim();
    final consultas = <String>[
      baseEndereco,
      if (cidade.isNotEmpty) '$baseEndereco, $cidade',
      if (cidade.isNotEmpty && uf.isNotEmpty) '$baseEndereco, $cidade, $uf',
      '$baseEndereco, ${cidade.isNotEmpty ? '$cidade, ' : ''}${uf.isNotEmpty ? '$uf, ' : ''}Brasil',
    ];

    for (final consulta in consultas) {
      try {
        final locs = await locationFromAddress(consulta);
        if (locs.isNotEmpty) {
          return (lat: locs.first.latitude, lng: locs.first.longitude);
        }
      } catch (_) {
        // tenta próxima variação de consulta
      }
    }

    for (final consulta in consultas) {
      final nominatim = await _resolverViaNominatim(consulta);
      if (nominatim.lat != null && nominatim.lng != null) {
        return nominatim;
      }
    }

    // Último fallback: coordenadas já salvas no perfil.
    if (latDoc != null && lngDoc != null) {
      return (lat: latDoc, lng: lngDoc);
    }
    return (lat: null, lng: null);
  }

  void _agendarRecalculoTaxa({
    Duration atraso = const Duration(milliseconds: 450),
  }) {
    _debounceTaxa?.cancel();
    _debounceTaxa = Timer(atraso, () {
      if (!mounted) return;
      unawaited(_recalcularTaxaEntrega());
    });
  }

  /// Carrega a regra de frete respeitando o tipo de veículo canônico aceito
  /// pela loja (`bicicleta`, `moto`, `carro` ou `carro_frete`).
  ///
  /// A decisão de qual tipo usar é do `_recalcularTaxaEntrega`, que lê
  /// `lojas_public/{lojaId}.tipos_entrega_permitidos` e aplica a regra
  /// mestre do projeto: usar o tipo de MAIOR hierarquia aceito pela loja
  /// (carro_frete > carro > moto > bicicleta).
  ///
  /// Cadeia de fallback se a linha primária não existir para a cidade.
  /// - `carro_frete` → carro_frete → carro → moto → bicicleta → padrao
  /// - `carro`       → carro → moto → bicicleta → padrao
  /// - `moto`        → moto → padrao → bicicleta
  /// - `bicicleta`   → bicicleta → padrao → moto (`padrao` agrupa legado combinado).
  ///
  /// `veiculoEfetivo` pode divergir de `veiculoAlvoCanonico` quando a
  /// tabela preferida não existe e caímos em um fallback — é o valor
  /// exibido no card Subtotal para auditoria visual.
  Future<({Map<String, dynamic> regra, String veiculoEfetivo})?>
  _carregarRegraFrete(
    String cidadeLoja, {
    required String veiculoAlvoCanonico,
  }) async {
    final cidadeChave = _chaveCidadeTabelaFrete(cidadeLoja);
    if (cidadeChave.isEmpty) return null;
    final ref = FirebaseFirestore.instance.collection('tabela_fretes');
    final porId = <String, Map<String, dynamic>>{};

    Future<DocumentSnapshot<Map<String, dynamic>>> getDoc(String id) async {
      try {
        return await ref.doc(id).get(const GetOptions(source: Source.server));
      } catch (_) {
        return ref.doc(id).get();
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>> getCidade(String cidade) async {
      try {
        return await ref
            .where('cidade', isEqualTo: cidade)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        return ref.where('cidade', isEqualTo: cidade).get();
      }
    }

    // Carrega combinações por doc-id `{cidade}_{slug}` para todos os níveis da
    // cadeia (bicicleta, moto, legado combinado padrao, carro, carro_frete).
    const sufixosTabela = <String>[
      'bicicleta',
      'moto',
      'padrao',
      'carro',
      'carro_frete',
    ];
    for (final cidade in <String>{cidadeChave, 'todas'}) {
      for (final sufixo in sufixosTabela) {
        final id = '${cidade}_$sufixo';
        final d = await getDoc(id);
        if (d.exists) {
          porId[id] = d.data() ?? <String, dynamic>{};
        }
      }
    }

    // Fallback por query (documentos que têm campo `cidade` mas nome
    // diferente do convencional).
    for (final cidade in <String>{cidadeChave, 'todas'}) {
      final q = await getCidade(cidade);
      for (final doc in q.docs) {
        porId[doc.id] = doc.data();
      }
    }

    if (porId.isEmpty) return null;

    // Classifica cada documento pelo campo `tipo_tabela` quando existir; senão,
    // pelo sufixo do id ou texto legado em `veiculo`.
    String tabelaDaRegra(String id, Map<String, dynamic> dados) {
      final tc = (dados['tipo_tabela'] ?? '').toString().trim().toLowerCase();
      if (tc == 'bicicleta' ||
          tc == 'moto' ||
          tc == 'padrao' ||
          tc == 'carro' ||
          tc == 'carro_frete') {
        return tc;
      }
      if (id.endsWith('_carro_frete')) return 'carro_frete';
      // `_carro` antes de outros sufixos que contenham «car».
      if (id.endsWith('_carro')) return 'carro';
      if (id.endsWith('_bicicleta')) return 'bicicleta';
      if (id.endsWith('_moto')) return 'moto';
      if (id.endsWith('_padrao')) return 'padrao';

      final campo = (dados['veiculo'] ?? '').toString().toLowerCase();
      if (campo.contains('frete') ||
          campo.contains('fiorino') ||
          campo.contains('pick') ||
          campo.contains('kombi') ||
          campo.contains('utilit') ||
          campo == 'carro_frete') {
        return 'carro_frete';
      }
      if (campo.contains('carro')) return 'carro';
      final legPadrao =
          campo.contains('moto/bike') ||
          campo.contains('moto / bike') ||
          (campo.contains('padra') && campo.contains('moto'));
      if (legPadrao) return 'padrao';
      if (campo.contains('bicicl') || campo.contains('bike')) {
        return 'bicicleta';
      }
      if (campo.contains('moto')) return 'moto';
      return 'padrao';
    }

    int cmpAtualizacao(
      MapEntry<String, Map<String, dynamic>> a,
      MapEntry<String, Map<String, dynamic>> b,
    ) {
      final ta =
          (a.value['data_atualizacao'] as Timestamp?)?.millisecondsSinceEpoch ??
          0;
      final tb =
          (b.value['data_atualizacao'] as Timestamp?)?.millisecondsSinceEpoch ??
          0;
      return tb.compareTo(ta);
    }

    // Cadeia de preferência por tipo canônico (ver TiposEntrega.cadeiaFallbackTabela).
    final cadeia =
        TiposEntrega.cadeiaFallbackTabela[veiculoAlvoCanonico] ??
        const <String>['padrao'];

    for (final tabelaPreferida in cadeia) {
      final candidatas =
          porId.entries
              .where((e) => tabelaDaRegra(e.key, e.value) == tabelaPreferida)
              .toList()
            ..sort(cmpAtualizacao);
      if (candidatas.isNotEmpty) {
        // `veiculoEfetivo` mantém o código canônico do alvo se a tabela
        // bate; se caiu em fallback, sinaliza qual tabela foi usada.
        final efetivo =
            tabelaPreferida ==
                TiposEntrega.tabelaFretePorTipo[veiculoAlvoCanonico]
            ? veiculoAlvoCanonico
            : tabelaPreferida;
        return (regra: candidatas.first.value, veiculoEfetivo: efetivo);
      }
    }

    return null;
  }

  /// Frete de uma loja até o endereço de entrega (mesma regra que o fluxo single-loja).
  ///
  /// [veiculoAlvoCanonico] é um dos 4 tipos canônicos
  /// (`bicicleta` | `moto` | `carro` | `carro_frete`), derivado da config
  /// `tipos_entrega_permitidos` da loja. Ver `TiposEntrega.maiorTipoDaLista`.
  Future<_DetalheFreteLoja> _resolverTaxaEntregaParaLoja({
    required String clienteId,
    required String lojaId,
    required String enderecoTexto,
    Map<String, dynamic>? enderecoMap,
    required String veiculoAlvoCanonico,
    required List<String> tiposAceitosLoja,
  }) async {
    // Fase 3G.2 — carrinho lê dados da loja em `lojas_public` (cidade + coords
    // para calcular frete). Dados sensíveis do lojista ficam em `users`.
    final lojaDoc = await FirebaseFirestore.instance
        .collection('lojas_public')
        .doc(lojaId)
        .get();
    final ld = lojaDoc.data() ?? const <String, dynamic>{};
    final cidadeLoja = _cidadeLojaParaFrete(ld);
    final cidadeEntrega =
        _cidadeEntregaParaTabelaFrete(enderecoTexto, enderecoMap);
    final cidadeTabela =
        cidadeEntrega.isNotEmpty ? cidadeEntrega : cidadeLoja;
    final lojaLat = _coordToDouble(ld['latitude']);
    final lojaLng = _coordToDouble(ld['longitude']);
    if (cidadeTabela.isEmpty || lojaLat == null || lojaLng == null) {
      return _DetalheFreteLoja.fallback(
        lojaId: lojaId,
        taxa: _taxaBaseFallback,
        motivo: 'Loja sem cidade/coordenadas cadastradas',
        veiculoAlvo: veiculoAlvoCanonico,
        tiposAceitosLoja: tiposAceitosLoja,
      );
    }

    final resultado = await _carregarRegraFrete(
      cidadeTabela,
      veiculoAlvoCanonico: veiculoAlvoCanonico,
    );
    if (resultado == null) {
      return _DetalheFreteLoja.fallback(
        lojaId: lojaId,
        taxa: _taxaBaseFallback,
        motivo:
            'Sem tabela de frete para $cidadeTabela '
            '(alvo: ${TiposEntrega.rotulo(veiculoAlvoCanonico)})',
        cidade: cidadeTabela,
        veiculoAlvo: veiculoAlvoCanonico,
        tiposAceitosLoja: tiposAceitosLoja,
      );
    }

    final regra = resultado.regra;
    final base =
        _coordToDouble(regra['valor_base']) ??
        _coordToDouble(regra['valor_fixo_base']) ??
        _taxaBaseFallback;
    final distBase =
        _coordToDouble(regra['distancia_base_km']) ??
        _coordToDouble(regra['km_incluso']) ??
        3.0;
    final extraKm =
        _coordToDouble(regra['valor_km_adicional']) ??
        _coordToDouble(regra['km_adicional_valor']) ??
        0.0;

    final coordsEntrega = await _resolverCoordenadasEntrega(
      clienteId: clienteId,
      enderecoTexto: enderecoTexto,
      enderecoMap: enderecoMap,
    );
    final entLat = coordsEntrega.lat;
    final entLng = coordsEntrega.lng;
    if (entLat == null || entLng == null) {
      return _DetalheFreteLoja(
        lojaId: lojaId,
        cidade: cidadeTabela,
        veiculoAlvo: veiculoAlvoCanonico,
        veiculoEfetivo: resultado.veiculoEfetivo,
        tiposAceitosLoja: tiposAceitosLoja,
        base: base,
        distanciaBaseKm: distBase,
        valorKmAdicional: extraKm,
        distanciaKm: null,
        kmExtra: 0,
        taxa: double.parse(base.toStringAsFixed(2)),
        fallback: false,
        motivo: 'Endereço de entrega sem coordenadas (usando só valor base)',
      );
    }

    final distanciaKm =
        Geolocator.distanceBetween(lojaLat, lojaLng, entLat, entLng) / 1000;
    final kmExtra = max(0.0, distanciaKm - distBase);
    final taxa = base + (kmExtra * extraKm);
    return _DetalheFreteLoja(
      lojaId: lojaId,
      cidade: cidadeTabela,
      veiculoAlvo: veiculoAlvoCanonico,
      veiculoEfetivo: resultado.veiculoEfetivo,
      tiposAceitosLoja: tiposAceitosLoja,
      base: base,
      distanciaBaseKm: distBase,
      valorKmAdicional: extraKm,
      distanciaKm: distanciaKm,
      kmExtra: kmExtra,
      taxa: double.parse(taxa.toStringAsFixed(2)),
      fallback: false,
    );
  }

  /// Lê `tipos_entrega_permitidos` da loja em `lojas_public/{lojaId}`.
  ///
  /// **Retorna lista vazia** quando `lojas_public` ainda não espelha a config
  /// (ex.: espelho desatualizado antes de a loja fazer qualquer edição após
  /// o deploy do trigger `sincronizarLojaPublicOnWrite`). Isso é PROPOSITAL:
  ///
  /// - o cliente não pode ler `users/{lojaId}` por rules de segurança;
  /// - se cairmos em default adivinhado aqui, arriscamos gravar um snapshot
  ///   ERRADO em `pedidos/{id}.tipos_entrega_permitidos_loja`, que por sua
  ///   vez filtra entregadores incompatíveis na corrida;
  /// - snapshot vazio faz o backend (`obterTiposEntregaDaLoja`) resolver
  ///   pela fonte da verdade (`users/{lojaId}`) com admin SDK.
  ///
  /// Nunca lança — em caso de erro retorna lista vazia.
  Future<List<String>> _lerTiposEntregaAceitos({
    required String lojaId,
    required List<CartItemModel> itensDaLoja,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(lojaId)
          .get();
      final data = snap.data();
      final config = TiposEntrega.lerDeDoc(data);
      if (config.isNotEmpty) return config;
      debugPrint(
        '[tipos_entrega] lojas_public/$lojaId sem config — '
        'usando default legado para tabela de frete.',
      );
    } catch (e) {
      debugPrint('[tipos_entrega] erro lendo lojas_public/$lojaId: $e');
    }
    final temGrande = itensDaLoja.any((i) => i.requerVeiculoGrande);
    return TiposEntrega.defaultLegado(
      temProdutoRequerVeiculoGrande: temGrande,
    );
  }

  Future<void> _recalcularTaxaEntrega() async {
    if (!mounted) return;
    final geracao = ++_freteRecalcGeracao;
    bool aindaValido() => mounted && geracao == _freteRecalcGeracao;

    final cart = context.read<CartProvider>();
    final gruposPronta =
        _agruparItensCarrinhoPorLoja(cart.itensProntaEntrega);
    final gruposEncomenda =
        _agruparItensCarrinhoPorLoja(cart.itensEncomenda);

    if (_retirarNaLoja) {
      if (aindaValido()) {
        setState(() {
          _taxaEntregaCalculada = 0;
          _taxaEntregaPorLoja = {
            for (final id in {...gruposPronta.keys, ...gruposEncomenda.keys})
              id: 0.0,
          };
          _taxaEntregaEncomendaPorLoja = {
            for (final id in gruposEncomenda.keys) id: 0.0,
          };
          _detalhesFreteEncomendaPorLoja = {};
          _detalhesFretePorLoja = {};
          _detalheTaxaEntrega = 'Retirada na loja';
          _calculandoTaxaEntrega = false;
          _calculandoTaxaEncomenda = false;
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final endereco = _enderecoController.text.trim();
    final mapaEntrega = _enderecoEntregaMapa == null
        ? null
        : Map<String, dynamic>.from(_enderecoEntregaMapa!);
    final temPronta = cart.itensProntaEntrega.isNotEmpty;
    final temEncomenda = cart.itensEncomenda.isNotEmpty;
    if (!temPronta && !temEncomenda) return;
    if (endereco.isEmpty) return;

    if (aindaValido()) {
      setState(() {
        _calculandoTaxaEntrega = temPronta;
        _calculandoTaxaEncomenda = temEncomenda;
      });
    }

    Future<({
      Map<String, double> taxas,
      Map<String, _DetalheFreteLoja> detalhes,
    })> calcularGrupo(
      Map<String, List<CartItemModel>> grupos,
    ) async {
      final taxas = <String, double>{};
      final detalhes = <String, _DetalheFreteLoja>{};
      final lojaIds = grupos.keys.toList()..sort();
      for (final lojaId in lojaIds) {
        final itens = grupos[lojaId] ?? const <CartItemModel>[];
        final tiposAceitos = await _lerTiposEntregaAceitos(
          lojaId: lojaId,
          itensDaLoja: itens,
        );
        final veiculoAlvoCanonico =
            TiposEntrega.maiorTipoDaLista(tiposAceitos) ?? TiposEntrega.codMoto;
        try {
          final det = await _resolverTaxaEntregaParaLoja(
            clienteId: user.uid,
            lojaId: lojaId,
            enderecoTexto: endereco,
            enderecoMap: mapaEntrega,
            veiculoAlvoCanonico: veiculoAlvoCanonico,
            tiposAceitosLoja: tiposAceitos,
          );
          if (!aindaValido()) return (taxas: taxas, detalhes: detalhes);
          taxas[lojaId] = det.taxa;
          detalhes[lojaId] = det;
        } catch (e) {
          if (!aindaValido()) return (taxas: taxas, detalhes: detalhes);
          taxas[lojaId] = _taxaBaseFallback;
          detalhes[lojaId] = _DetalheFreteLoja.fallback(
            lojaId: lojaId,
            taxa: _taxaBaseFallback,
            motivo: 'Erro ao calcular frete',
            veiculoAlvo: veiculoAlvoCanonico,
            tiposAceitosLoja: tiposAceitos,
          );
          debugPrint(
            'Erro frete loja $lojaId (fallback R\$ $_taxaBaseFallback): $e',
          );
        }
      }
      return (taxas: taxas, detalhes: detalhes);
    }

    if (temPronta) {
      final lojaIds = gruposPronta.keys.toList()..sort();
      final taxas = <String, double>{};
      final detalhes = <String, _DetalheFreteLoja>{};
      final tiposPorLoja = <String, List<String>>{};
      var soma = 0.0;
      _DetalheFreteLoja? primeiroDetalhe;
      var qtdFalhas = 0;

      for (final lojaId in lojaIds) {
        final itens = gruposPronta[lojaId] ?? const <CartItemModel>[];
        final tiposAceitos = await _lerTiposEntregaAceitos(
          lojaId: lojaId,
          itensDaLoja: itens,
        );
        tiposPorLoja[lojaId] = tiposAceitos;
        final veiculoAlvoCanonico =
            TiposEntrega.maiorTipoDaLista(tiposAceitos) ?? TiposEntrega.codMoto;

        try {
          final det = await _resolverTaxaEntregaParaLoja(
            clienteId: user.uid,
            lojaId: lojaId,
            enderecoTexto: endereco,
            enderecoMap: mapaEntrega,
            veiculoAlvoCanonico: veiculoAlvoCanonico,
            tiposAceitosLoja: tiposAceitos,
          );
          if (!aindaValido()) return;
          taxas[lojaId] = det.taxa;
          detalhes[lojaId] = det;
          soma += det.taxa;
          primeiroDetalhe ??= det;
          if (det.fallback) qtdFalhas++;
        } catch (e) {
          if (!aindaValido()) return;
          qtdFalhas++;
          taxas[lojaId] = _taxaBaseFallback;
          final fallbackDet = _DetalheFreteLoja.fallback(
            lojaId: lojaId,
            taxa: _taxaBaseFallback,
            motivo: 'Erro ao calcular frete — usando valor padrão',
            veiculoAlvo: veiculoAlvoCanonico,
            tiposAceitosLoja: tiposAceitos,
          );
          detalhes[lojaId] = fallbackDet;
          soma += _taxaBaseFallback;
          primeiroDetalhe ??= fallbackDet;
          debugPrint(
            'Erro ao calcular taxa para loja $lojaId (usando fallback R\$ $_taxaBaseFallback): $e',
          );
        }
      }

      if (!aindaValido()) return;
      setState(() {
        _taxaEntregaPorLoja = taxas;
        _detalhesFretePorLoja = detalhes;
        _tiposEntregaAceitosPorLoja = tiposPorLoja;
        _taxaEntregaCalculada = _round2(soma);
        if (lojaIds.length > 1) {
          final sufixo = qtdFalhas > 0 ? ' (frete padrão em $qtdFalhas)' : '';
          _detalheTaxaEntrega =
              '${lojaIds.length} lojas — total frete R\$ ${_taxaEntregaCalculada.toStringAsFixed(2)}$sufixo';
        } else {
          _detalheTaxaEntrega =
              primeiroDetalhe?.resumoCurto() ??
              (qtdFalhas > 0
                  ? 'Frete padrão (erro ao calcular)'
                  : 'Frete calculado');
        }
        _calculandoTaxaEntrega = false;
      });
    } else if (aindaValido()) {
      setState(() {
        _taxaEntregaCalculada = 0;
        _taxaEntregaPorLoja = {};
        _detalhesFretePorLoja = {};
        _calculandoTaxaEntrega = false;
      });
    }

    if (temEncomenda) {
      final enc = await calcularGrupo(gruposEncomenda);
      if (!aindaValido()) return;
      setState(() {
        _taxaEntregaEncomendaPorLoja = enc.taxas;
        _detalhesFreteEncomendaPorLoja = enc.detalhes;
        _calculandoTaxaEncomenda = false;
      });
    } else if (aindaValido()) {
      setState(() {
        _taxaEntregaEncomendaPorLoja = {};
        _detalhesFreteEncomendaPorLoja = {};
        _calculandoTaxaEncomenda = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _enderecoController.addListener(_agendarRecalculoTaxa);
    _carregarDadosCliente();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _agendarRecalculoTaxa(atraso: const Duration(milliseconds: 250));
    });
  }

  @override
  void dispose() {
    _debounceTaxa?.cancel();
    _enderecoController.dispose();
    _cupomController.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosCliente() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          var dados = doc.data() as Map<String, dynamic>;
          final role = (dados['role'] ?? dados['tipoUsuario'] ?? 'cliente')
              .toString()
              .trim()
              .toLowerCase();
          final podeUsarSaldo =
              role != 'lojista' && role != 'entregador';
          setState(() {
            _saldoCliente = (dados['saldo'] ?? 0.0).toDouble();
            _clientePodeUsarSaldoCarteira = podeUsarSaldo;
            if (!podeUsarSaldo) _usarSaldo = false;

            if (dados.containsKey('endereco_entrega_padrao') &&
                dados['endereco_entrega_padrao'] is Map) {
              final end = Map<String, dynamic>.from(
                dados['endereco_entrega_padrao'] as Map,
              );
              _enderecoEntregaMapa = end;
              _enderecoController.text = formatarEnderecoEntregaMapa(end);
            } else if (dados['endereco'] != null &&
                dados['endereco'].toString().isNotEmpty) {
              _enderecoController.text = dados['endereco'].toString();
            }
          });
          _agendarRecalculoTaxa(atraso: const Duration(milliseconds: 150));
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados: $e");
      }
    }
  }

  Future<void> _validarCupom(CartProvider cart) async {
    final codigo = _cupomController.text.trim();
    if (codigo.isEmpty) return;

    setState(() {
      _validandoCupom = true;
      _cupomMensagem = '';
      _cupomErro = false;
    });

    try {
      // Envia TODAS as lojas únicas do carrinho. A function rejeita
      // cupom restrito a 1 loja se o carrinho tem itens de outras lojas
      // (cupom de loja específica não pode ser dividido entre lojas).
      // `loja_id` continua sendo enviado (compat retroativa) com a primeira.
      final lojaIds =
          cart.itensProntaEntrega
              .map((e) => e.lojaId.trim())
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final lojaIdPrincipal = lojaIds.isNotEmpty ? lojaIds.first : '';
      final result = await appFirebaseFunctions
          .httpsCallable('validarCupom')
          .call<Map<String, dynamic>>({
            'codigo': codigo,
            'subtotal_produtos': cart.totalProntaEntrega,
            'loja_id': lojaIdPrincipal,
            'loja_ids': lojaIds,
          });

      final data = result.data;
      if (data['valid'] == true) {
        setState(() {
          _cupomAplicado = true;
          _descontoCupom = (data['valor_desconto'] as num).toDouble();
          _cupomId = data['cupom_id'] as String?;
          _cupomCodigo = codigo.toUpperCase();
          _cupomMensagem = data['mensagem'] as String? ?? 'Cupom aplicado!';
          _cupomErro = false;
        });
      } else {
        setState(() {
          _cupomAplicado = false;
          _descontoCupom = 0.0;
          _cupomId = null;
          _cupomCodigo = null;
          _cupomMensagem = data['mensagem'] as String? ?? 'Cupom inválido.';
          _cupomErro = true;
        });
      }
    } catch (e) {
      setState(() {
        _cupomAplicado = false;
        _descontoCupom = 0.0;
        _cupomMensagem = 'Erro ao validar cupom. Tente novamente.';
        _cupomErro = true;
      });
      debugPrint('Erro validarCupom: $e');
    } finally {
      if (mounted) setState(() => _validandoCupom = false);
    }
  }

  void _removerCupom() {
    setState(() {
      _cupomAplicado = false;
      _descontoCupom = 0.0;
      _cupomId = null;
      _cupomCodigo = null;
      _cupomMensagem = '';
      _cupomErro = false;
      _cupomController.clear();
    });
  }

  Future<bool> _verificarLojaAberta(List<CartItemModel> itens) async {
    if (itens.isEmpty) return true;
    final lojas = itens
        .map((e) => e.lojaId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final lojaId in lojas) {
      try {
        // Fase 3G.2 — verifica se a loja está aberta via `lojas_public`.
        final lojaDoc = await FirebaseFirestore.instance
            .collection('lojas_public')
            .doc(lojaId)
            .get();
        if (lojaDoc.exists) {
          final dados = lojaDoc.data() as Map<String, dynamic>;
          bool aberta = dados['loja_aberta'] ?? true;
          if (LojaPausa.lojaEfetivamentePausada(dados)) aberta = false;
          if (!aberta && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  lojas.length > 1
                      ? 'Uma das lojas está fechada no momento. Remova os itens dessa loja ou tente mais tarde.'
                      : 'A loja está fechada no momento. Não é possível finalizar o pedido.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            return false;
          }
        }
      } catch (e) {
        debugPrint('Erro ao verificar status da loja: $e');
      }
    }
    return true;
  }

  Future<void> _enviarSolicitacaoEncomenda(CartProvider cart) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final itensEncomenda = cart.itensEncomenda;
    if (itensEncomenda.isEmpty) return;

    if (!await _verificarLojaAberta(itensEncomenda)) return;

    if (!_retirarNaLoja) {
      await _recalcularTaxaEntrega();
    }

    if (!_retirarNaLoja && _enderecoController.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um endereço de entrega completo.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final mensagemCtrl = TextEditingController();
    final confirmar =
        await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withOpacity(0.45),
          builder: (ctx) {
            final media = MediaQuery.of(ctx);
            final largura = media.size.width;
            final compacto = largura < 380;
            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: compacto ? 14 : 22,
                vertical: 20,
              ),
              backgroundColor: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth > 520
                      ? 520.0
                      : constraints.maxWidth;
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                        maxHeight: media.size.height * 0.88,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            bottom: media.viewInsets.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: EdgeInsets.fromLTRB(
                                  compacto ? 18 : 22,
                                  22,
                                  compacto ? 18 : 22,
                                  20,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [diPertinRoxo, Color(0xFF8E24AA)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(11),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.16),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Enviar encomenda',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                          SizedBox(height: 5),
                                          Text(
                                            'A loja receberá sua lista para negociar valores e prazo.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.all(compacto ? 16 : 20),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: diPertinLaranja.withOpacity(
                                          0.09,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: diPertinLaranja.withOpacity(
                                            0.22,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            _retirarNaLoja
                                                ? Icons.storefront
                                                : Icons.delivery_dining,
                                            color: diPertinLaranja,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _retirarNaLoja
                                                  ? 'Retirada no balcão. A loja verá os itens e sua mensagem.'
                                                  : 'A cobrança do frete será realizada na etapa final do pedido. O valor de entrada corresponde exclusivamente ao produto.',
                                              style: const TextStyle(
                                                color: Color(0xFF2A2030),
                                                fontWeight: FontWeight.w700,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: mensagemCtrl,
                                      minLines: compacto ? 3 : 4,
                                      maxLines: compacto ? 5 : 6,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Mensagem para a loja (opcional)',
                                        hintText:
                                            'Ex.: preciso para sábado, pode confirmar as cores e medidas?',
                                        alignLabelWithHint: true,
                                        filled: true,
                                        fillColor: const Color(0xFFF8F5FA),
                                        prefixIcon: const Padding(
                                          padding: EdgeInsets.only(bottom: 58),
                                          child: Icon(Icons.edit_note),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          borderSide: const BorderSide(
                                            color: diPertinRoxo,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    compacto
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              FilledButton.icon(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                icon: const Icon(Icons.send),
                                                label: const Text('Enviar'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      diPertinLaranja,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 14,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancelar'),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Expanded(
                                                child: TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        diPertinRoxo,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 14,
                                                        ),
                                                  ),
                                                  child: const Text('Cancelar'),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: FilledButton.icon(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  icon: const Icon(Icons.send),
                                                  label: const Text('Enviar'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        diPertinLaranja,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 14,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
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
        ) ??
        false;

    if (!confirmar || !mounted) return;

    setState(() => _processandoPedido = true);
    try {
      final lojaId = itensEncomenda.first.lojaId.trim();
      final itens = itensEncomenda
          .map(
            (CartItemModel i) => <String, dynamic>{
              'id_produto': i.id,
              'nome': i.nome,
              'preco_ref': i.preco,
              'quantidade': i.quantidade,
              'imagem': i.imagem,
              'variacoes': i.variacoesSelecionadas,
              'variacoes_resumo': i.variacoesResumo,
              'tipo_venda': i.ehEncomenda ? 'encomenda' : 'pronta_entrega',
            },
          )
          .toList();

      final callable = appFirebaseFunctions.httpsCallable(
        'encomendaClienteCriar',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final res = await callable.call({
        'loja_id': lojaId,
        'itens': itens,
        'mensagem_cliente': mensagemCtrl.text.trim(),
        'tipo_entrega': _retirarNaLoja ? 'retirada' : 'entrega',
        'endereco_entrega': _retirarNaLoja
            ? ''
            : _enderecoController.text.trim(),
        'taxa_entrega_snapshot': _taxaEntregaEncomendaParaLoja(lojaId),
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final encId = data['encomendaId']?.toString() ?? '';
      if (encId.isEmpty) {
        throw Exception('Resposta sem encomendaId');
      }

      await cart.removerItensPorTipo(encomenda: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solicitação enviada!')));
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ClienteEncomendaDetalheScreen(encomendaId: encId),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Não foi possível enviar.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _processandoPedido = false);
    }
  }

  Future<void> _avancarParaPagamento(CartProvider cart) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você precisa fazer login para finalizar o pedido!'),
          backgroundColor: diPertinRoxo,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    // Finaliza apenas os itens de pronta-entrega; a encomenda tem botão próprio.
    if (!cart.temProntaEntrega) return;

    if (!await _verificarLojaAberta(cart.itensProntaEntrega)) return;
    if (!_retirarNaLoja) {
      await _recalcularTaxaEntrega();
    }

    if (!_retirarNaLoja && _enderecoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, informe o endereço de entrega!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    double subtotal = cart.totalProntaEntrega;
    double totalParcial = subtotal + _taxaEntregaReal - _descontoCupom;
    if (totalParcial < 0) totalParcial = 0;
    double valorDesconto = (_usarSaldo && _clientePodeUsarSaldoCarteira)
        ? min(_saldoCliente, totalParcial)
        : 0.0;
    double totalFinal = totalParcial - valorDesconto;
    if (totalFinal < 0) totalFinal = 0;

    // Saldo cobre tudo: grava pedido direto.
    if (totalFinal <= 0) {
      await _salvarPedidoNoBanco(
        cart,
        user.uid,
        subtotal,
        valorDesconto,
        totalFinal,
      );
      return;
    }

    // DESABILITADO TEMPORARIAMENTE: Pagamento por Dinheiro
    // if (_formaPagamento == 'Dinheiro') {
    //   if (_precisaTrocoDinheiro) {
    //     final trocoPara = _parseMoedaDigitada(_trocoParaController.text);
    //     if (trocoPara == null || trocoPara <= 0) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(
    //           content: Text('Informe um valor válido para troco.'),
    //           backgroundColor: Colors.red,
    //         ),
    //       );
    //       return;
    //     }
    //     if (trocoPara < totalFinal) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         SnackBar(
    //           content: Text(
    //             'O valor para troco deve ser igual ou maior que R\$ ${totalFinal.toStringAsFixed(2)}.',
    //           ),
    //           backgroundColor: Colors.red,
    //         ),
    //       );
    //       return;
    //     }
    //   }
    //   final pedidoId = await _salvarPedidoNoBanco(
    //     cart,
    //     user.uid,
    //     subtotal,
    //     valorDesconto,
    //     totalFinal,
    //     fecharCarrinhoEExibirDialogo: false,
    //   );
    //   if (!mounted || pedidoId == null) return;
    //   await _mostrarConfirmacaoPedidoFeitoDinheiro();
    //   return;
    // }

    // PIX: cria pedido aguardando pagamento, gera cobrança no checkout e confirma via webhook/polling.
    if (_formaPagamento == 'PIX') {
      final pedidoId = await _salvarPedidoNoBanco(
        cart,
        user.uid,
        subtotal,
        valorDesconto,
        totalFinal,
        statusPedido: 'aguardando_pagamento',
        fecharCarrinhoEExibirDialogo: false,
      );
      if (!mounted || pedidoId == null) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutPagamentoScreen(
            valorTotal: totalFinal,
            metodoPreSelecionado: 'PIX',
            pedidoFirestoreId: pedidoId,
            onPagamentoAprovado: () => _navegarAposPagamentoProntaEntrega(),
          ),
        ),
      );
      await _reforcarLimpezaCarrinhoSePedidoPago(pedidoId, cart);
      // Pedido permanece em `aguardando_pagamento` para repagamento em Meus Pedidos.
      return;
    }

    // Cartão: cria pedido aguardando pagamento e confirma no checkout.
    if (_formaPagamento == 'Cartão') {
      final pedidoId = await _salvarPedidoNoBanco(
        cart,
        user.uid,
        subtotal,
        valorDesconto,
        totalFinal,
        statusPedido: 'aguardando_pagamento',
        fecharCarrinhoEExibirDialogo: false,
      );
      if (!mounted || pedidoId == null) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutPagamentoScreen(
            valorTotal: totalFinal,
            metodoPreSelecionado: 'Cartão',
            pedidoFirestoreId: pedidoId,
            onPagamentoAprovado: () => _navegarAposPagamentoProntaEntrega(),
          ),
        ),
      );
      await _reforcarLimpezaCarrinhoSePedidoPago(pedidoId, cart);
      // Pedido permanece em `aguardando_pagamento` para repagamento em Meus Pedidos.
      return;
    }
  }

  static bool _pedidoProntaEntregaConfirmadoPago(String status) {
    final st = status.trim();
    return st == 'pendente' || st == PedidoStatus.encomendaEntradaPaga;
  }

  /// Garante sacola vazia de pronta-entrega se o pagamento já foi confirmado
  /// (ex.: webhook PIX antes do usuário tocar em Continuar).
  Future<void> _reforcarLimpezaCarrinhoSePedidoPago(
    String pedidoId,
    CartProvider cart,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if ((data['tipo_compra'] ?? '').toString() == 'encomenda') return;
      final status = (data['status'] ?? '').toString();
      if (_pedidoProntaEntregaConfirmadoPago(status)) {
        await cart.removerItensPorTipo(encomenda: false);
      }
    } catch (_) {}
  }

  void _navegarAposPagamentoProntaEntrega() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/meus-pedidos',
      (route) => route.isFirst,
      arguments: {
        'filtro': 'todos',
        'mostrarVoltarVitrine': true,
      },
    );
  }

  /// Retorna o ID do documento em [pedidos] quando o salvamento conclui com sucesso.
  Future<String?> _salvarPedidoNoBanco(
    CartProvider cart,
    String clienteId,
    double subtotal,
    double valorDesconto,
    double totalFinal, {
    String statusPedido = 'pendente',
    bool fecharCarrinhoEExibirDialogo = true,
  }) async {
    setState(() => _processandoPedido = true);

    try {
      final grupos = _agruparItensCarrinhoPorLoja(cart.itensProntaEntrega);
      if (grupos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Itens sem loja identificada. Atualize o carrinho e tente de novo.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      if (grupos.length > 1) {
        return await _salvarVariosPedidosPorLoja(
          cart,
          clienteId,
          subtotal,
          valorDesconto,
          totalFinal,
          grupos,
          statusPedido: statusPedido,
          fecharCarrinhoEExibirDialogo: fecharCarrinhoEExibirDialogo,
        );
      }

      List<CartItemModel> listaItens = cart.itensProntaEntrega;
      List<Map<String, dynamic>> itensParaSalvar = listaItens.map((item) {
        return {
          'id_produto': item.id,
          'nome': item.nome,
          'preco': item.preco,
          'quantidade': item.quantidade,
          'imagem': item.imagem,
          'variacoes': item.variacoesSelecionadas,
          'variacoes_resumo': item.variacoesResumo,
          'tipo_venda': item.ehEncomenda ? 'encomenda' : 'pronta_entrega',
        };
      }).toList();

      String lojaId = listaItens.isNotEmpty ? listaItens.first.lojaId : '';
      String lojaNome = listaItens.isNotEmpty ? listaItens.first.lojaNome : '';

      String enderecoDaLoja = 'Endereço não cadastrado';
      String lojaFoto = '';
      double? lojaLat;
      double? lojaLng;
      double? entregaLat;
      double? entregaLng;
      String lojaTelefone = '';
      if (lojaId.isNotEmpty) {
        // Fase 3G.2 — copia dados públicos da loja pro pedido via `lojas_public`.
        var lojaDoc = await FirebaseFirestore.instance
            .collection('lojas_public')
            .doc(lojaId)
            .get();
        if (lojaDoc.exists) {
          final ld = lojaDoc.data();
          lojaFoto = _melhorFotoLoja(ld);
          lojaTelefone = _telefoneLoja(ld);
          bool aberta = ld?['loja_aberta'] ?? true;
          if (ld != null && LojaPausa.lojaEfetivamentePausada(ld)) {
            aberta = false;
          }
          if (!aberta) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'A loja fechou antes da conclusão do pedido. Tente novamente quando estiver aberta.',
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return null;
          }
          enderecoDaLoja =
              ld?['endereco']?.toString() ?? 'Endereço não cadastrado';
          final rawLat = ld?['latitude'];
          final rawLng = ld?['longitude'];
          if (rawLat != null && rawLng != null) {
            lojaLat = (rawLat is num)
                ? rawLat.toDouble()
                : double.tryParse(rawLat.toString());
            lojaLng = (rawLng is num)
                ? rawLng.toDouble()
                : double.tryParse(rawLng.toString());
          }
        }
      }

      if (!_retirarNaLoja && _enderecoController.text.trim().isNotEmpty) {
        final coords = await _resolverCoordenadasEntrega(
          clienteId: clienteId,
          enderecoTexto: _enderecoController.text.trim(),
        );
        entregaLat = coords.lat;
        entregaLng = coords.lng;
      }

      // Sempre 6 dígitos (100000–999999), alinhado à validação no app do entregador.
      final tokenGerado = (100000 + Random().nextInt(900000)).toString();

      if (!_retirarNaLoja) {
        await FirebaseFirestore.instance.collection('users').doc(clienteId).set(
          {'endereco': _enderecoController.text.trim()},
          SetOptions(merge: true),
        );
      }

      // Salva o Pedido (pagamento em dinheiro desabilitado na UI — sem campos de troco)

      // Fase 3G.3 — denormaliza identidade do cliente no pedido pra que lojista e
      // entregador não precisem mais ler `users/{cliente_id}` (permite fechar rule).
      final identidadeCliente = await _lerIdentidadeClienteParaPedido(
        clienteId,
      );

      final docRef = await FirebaseFirestore.instance.collection('pedidos').add(
        {
          'cliente_id': clienteId,
          'cliente_nome': identidadeCliente['nome'] ?? '',
          'cliente_foto_perfil': identidadeCliente['foto'] ?? '',
          'cliente_telefone': identidadeCliente['telefone'] ?? '',
          'loja_id': lojaId,
          'loja_nome': lojaNome,
          'loja_foto': lojaFoto,
          'loja_telefone': lojaTelefone,
          'loja_endereco': enderecoDaLoja,
          if (lojaLat != null && lojaLng != null) ...{
            'loja_latitude': lojaLat,
            'loja_longitude': lojaLng,
          },
          if (entregaLat != null && entregaLng != null) ...{
            'entrega_latitude': entregaLat,
            'entrega_longitude': entregaLng,
          },
          'token_entrega': tokenGerado,
          'itens': itensParaSalvar,
          'subtotal': subtotal,
          'total_produtos': subtotal,
          'taxa_entrega': _taxaEntregaReal,
          'desconto_saldo': valorDesconto,
          if (_cupomAplicado && _descontoCupom > 0) ...{
            'desconto_cupom': _descontoCupom,
            'cupom_id': _cupomId,
            'cupom_codigo': _cupomCodigo,
          },
          'total': totalFinal,
          'tipo_entrega': _retirarNaLoja ? 'retirada' : 'entrega',
          'endereco_entrega': _retirarNaLoja
              ? 'Retirada no Balcão'
              : _enderecoController.text.trim(),
          'forma_pagamento': totalFinal == 0.0
              ? 'Saldo do App'
              : _formaPagamento,
          'status': statusPedido,
          'data_pedido': FieldValue.serverTimestamp(),
        },
      );

      // ===== SISTEMA DE RESERVA DE SALDO (Novo) =====
      String? reservaIdSaldo;

      // Se usando saldo + pagamento externo (PIX/Cartão), RESERVA ao invés de debitar
      if (valorDesconto > 0 && statusPedido == 'aguardando_pagamento') {
        try {
          final reserva = await WalletReservaService.reservarSaldo(
            userId: clienteId,
            pedidoId: docRef.id,
            valor: valorDesconto,
          );
          reservaIdSaldo = reserva['reservaId'] as String?;

          // Atualiza pedido com ID da reserva
          await docRef.update({
            'reserva_id_saldo': reservaIdSaldo,
            'saldo_reservado': valorDesconto,
          });

          if (mounted) {
            print(
              '[CartScreen] Saldo reservado: R\$ ${valorDesconto.toStringAsFixed(2)} | '
              'ReservaId: $reservaIdSaldo',
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao reservar saldo: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _processandoPedido = false);
          return null;
        }
      }
      // Se usando saldo COMPLETO para pagar (status final), debita agora
      else if (valorDesconto > 0 && totalFinal == 0.0) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(clienteId)
            .update({'saldo': FieldValue.increment(-valorDesconto)});

        if (mounted) {
          print(
            '[CartScreen] Saldo debitado (pagamento completo): '
            'R\$ ${valorDesconto.toStringAsFixed(2)}',
          );
        }
      }

      _qtdPedidosUltimoCheckout = 1;

      // Só limpa o carrinho quando o pedido é imediatamente finalizado
      // (Dinheiro / saldo). Para PIX e Cartão, o status é
      // `aguardando_pagamento` e o carrinho só é limpo após aprovação,
      // permitindo que o cliente volte para esta tela e ajuste a compra.
      if (fecharCarrinhoEExibirDialogo) {
        await cart.removerItensPorTipo(encomenda: false);
      }

      if (mounted) {
        if (fecharCarrinhoEExibirDialogo) {
          Navigator.pop(context);
          _mostrarSucesso();
        }
      }
      return docRef.id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processandoPedido = false);
    }
    return null;
  }

  /// Vários pedidos (um por loja), mesmo checkout. O primeiro [loja_id] após ordenação é o líder do MP (PIX/cartão).
  Future<String?> _salvarVariosPedidosPorLoja(
    CartProvider cart,
    String clienteId,
    double subtotal,
    double valorDesconto,
    double totalFinal,
    Map<String, List<CartItemModel>> grupos, {
    String statusPedido = 'pendente',
    bool fecharCarrinhoEExibirDialogo = true,
  }) async {
    final lojaKeys = grupos.keys.toList()..sort();
    final n = lojaKeys.length;
    if (n < 2) return null;

    if (!_retirarNaLoja) {
      var faltaTaxa = false;
      for (final id in lojaKeys) {
        if (!_taxaEntregaPorLoja.containsKey(id)) {
          faltaTaxa = true;
          break;
        }
      }
      if (faltaTaxa) await _recalcularTaxaEntrega();
    }

    final precisaMpUnificado =
        statusPedido == 'aguardando_pagamento' &&
        (_formaPagamento == 'PIX' || _formaPagamento == 'Cartão');

    final totalParcialCheckout = _round2(
      (subtotal + _taxaEntregaReal - _descontoCupom).clamp(
        0.0,
        double.infinity,
      ),
    );

    final cupoms = List<double>.filled(n, 0);
    if (subtotal > 0 && _descontoCupom > 0) {
      var acc = 0.0;
      for (var i = 0; i < n; i++) {
        final s = _subtotalItensLista(grupos[lojaKeys[i]]!);
        if (i < n - 1) {
          final c = _round2(_descontoCupom * (s / subtotal));
          cupoms[i] = c;
          acc += c;
        } else {
          cupoms[i] = _round2(_descontoCupom - acc);
        }
      }
    }

    final parciais = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final s = _subtotalItensLista(grupos[lojaKeys[i]]!);
      final tx = _retirarNaLoja
          ? 0.0
          : (_taxaEntregaPorLoja[lojaKeys[i]] ?? 0.0);
      parciais[i] = _round2(s + tx - cupoms[i]);
    }
    var sumP = parciais.fold(0.0, (a, b) => a + b);
    if ((sumP - totalParcialCheckout).abs() > 0.02) {
      parciais[n - 1] = _round2(
        parciais[n - 1] + (totalParcialCheckout - sumP),
      );
    }

    final saldos = List<double>.filled(n, 0);
    if (totalParcialCheckout > 0 && valorDesconto > 0) {
      var acc = 0.0;
      for (var i = 0; i < n; i++) {
        if (i < n - 1) {
          final si = _round2(
            valorDesconto * (parciais[i] / totalParcialCheckout),
          );
          saldos[i] = si;
          acc += si;
        } else {
          saldos[i] = _round2(valorDesconto - acc);
        }
      }
    }

    final totais = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      totais[i] = _round2(
        (parciais[i] - saldos[i]).clamp(0.0, double.infinity),
      );
    }
    var sumT = totais.fold(0.0, (a, b) => a + b);
    if ((sumT - totalFinal).abs() > 0.02) {
      totais[n - 1] = _round2(totais[n - 1] + (totalFinal - sumT));
    }

    // Fase 3G.2 — múltiplas lojas no mesmo checkout (múltiplos carrinhos) leem
    // `lojas_public`. Cada doc contém só dados de fachada (cidade, endereço,
    // coords, pausa), suficiente para o pedido.
    final lojaSnapshots = await Future.wait(
      lojaKeys.map(
        (id) =>
            FirebaseFirestore.instance.collection('lojas_public').doc(id).get(),
      ),
    );
    final lojaPorId = <String, Map<String, dynamic>>{
      for (var k = 0; k < lojaKeys.length; k++)
        lojaKeys[k]: Map<String, dynamic>.from(lojaSnapshots[k].data() ?? {}),
    };

    for (final lojaId in lojaKeys) {
      final ld = lojaPorId[lojaId]!;
      var aberta = ld['loja_aberta'] ?? true;
      if (LojaPausa.lojaEfetivamentePausada(ld)) aberta = false;
      if (!aberta) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'A loja "${(ld['nome_fantasia'] ?? ld['nome'] ?? lojaId).toString()}" está indisponível.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    }

    double? entregaLat;
    double? entregaLng;
    if (!_retirarNaLoja && _enderecoController.text.trim().isNotEmpty) {
      final coords = await _resolverCoordenadasEntrega(
        clienteId: clienteId,
        enderecoTexto: _enderecoController.text.trim(),
      );
      entregaLat = coords.lat;
      entregaLng = coords.lng;
    }

    // Fase 3G.3 — lê identidade do cliente uma vez só pra gravar em todos os pedidos do batch.
    final identidadeCliente = await _lerIdentidadeClienteParaPedido(clienteId);

    if (!_retirarNaLoja) {
      await FirebaseFirestore.instance.collection('users').doc(clienteId).set({
        'endereco': _enderecoController.text.trim(),
      }, SetOptions(merge: true));
    }

    // Pagamento em dinheiro desabilitado na UI — sem troco por loja.

    final checkoutGrupoId = FirebaseFirestore.instance
        .collection('pedidos')
        .doc()
        .id;
    final refs = lojaKeys
        .map((_) => FirebaseFirestore.instance.collection('pedidos').doc())
        .toList();
    final allIds = refs.map((r) => r.id).toList();

    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < n; i++) {
      final lojaId = lojaKeys[i];
      final listaItens = grupos[lojaId]!;
      final itensParaSalvar = listaItens
          .map(
            (item) => {
              'id_produto': item.id,
              'nome': item.nome,
              'preco': item.preco,
              'quantidade': item.quantidade,
              'imagem': item.imagem,
              'variacoes': item.variacoesSelecionadas,
              'variacoes_resumo': item.variacoesResumo,
              'tipo_venda': item.ehEncomenda ? 'encomenda' : 'pronta_entrega',
            },
          )
          .toList();

      final ld = lojaPorId[lojaId]!;
      final lojaNome = (ld['nome_fantasia'] ?? ld['nome'] ?? '').toString();
      var enderecoDaLoja =
          ld['endereco']?.toString() ?? 'Endereço não cadastrado';
      if (enderecoDaLoja.isEmpty) enderecoDaLoja = 'Endereço não cadastrado';

      double? lojaLat;
      double? lojaLng;
      final rawLat = ld['latitude'];
      final rawLng = ld['longitude'];
      if (rawLat != null && rawLng != null) {
        lojaLat = (rawLat is num)
            ? rawLat.toDouble()
            : double.tryParse(rawLat.toString());
        lojaLng = (rawLng is num)
            ? rawLng.toDouble()
            : double.tryParse(rawLng.toString());
      }

      final tokenGerado = (100000 + Random().nextInt(900000)).toString();
      final isLider = i == 0;
      final subL = _subtotalItensLista(listaItens);
      final taxaL = _retirarNaLoja ? 0.0 : (_taxaEntregaPorLoja[lojaId] ?? 0.0);

      // Snapshot dos tipos aceitos pela loja no momento do checkout.
      // Usado pelo backend para filtrar entregadores compatíveis (Fase 3)
      // e auditoria — mesmo que a loja altere depois, o pedido preserva
      // a regra do momento da compra.
      final tiposAceitosLoja =
          _tiposEntregaAceitosPorLoja[lojaId] ?? const <String>[];
      final veiculoAlvoFrete =
          _detalhesFretePorLoja[lojaId]?.veiculoAlvo ??
          TiposEntrega.maiorTipoDaLista(tiposAceitosLoja) ??
          TiposEntrega.codMoto;
      final freteTabelaEfetiva =
          _detalhesFretePorLoja[lojaId]?.veiculoEfetivo ?? veiculoAlvoFrete;

      final docPayload = <String, dynamic>{
        'cliente_id': clienteId,
        'cliente_nome': identidadeCliente['nome'] ?? '',
        'cliente_foto_perfil': identidadeCliente['foto'] ?? '',
        'cliente_telefone': identidadeCliente['telefone'] ?? '',
        'loja_id': lojaId,
        'loja_nome': lojaNome.isNotEmpty ? lojaNome : listaItens.first.lojaNome,
        'loja_foto': _melhorFotoLoja(ld),
        'loja_telefone': _telefoneLoja(ld),
        'loja_endereco': enderecoDaLoja,
        if (lojaLat != null && lojaLng != null) ...{
          'loja_latitude': lojaLat,
          'loja_longitude': lojaLng,
        },
        if (entregaLat != null && entregaLng != null) ...{
          'entrega_latitude': entregaLat,
          'entrega_longitude': entregaLng,
        },
        'token_entrega': tokenGerado,
        'itens': itensParaSalvar,
        'subtotal': subL,
        'total_produtos': subL,
        'taxa_entrega': taxaL,
        'desconto_saldo': saldos[i],
        if (_cupomAplicado && cupoms[i] > 0) ...{
          'desconto_cupom': cupoms[i],
          if (_cupomId != null) 'cupom_id': _cupomId,
          if (_cupomCodigo != null) 'cupom_codigo': _cupomCodigo,
        },
        'total': totais[i],
        'tipo_entrega': _retirarNaLoja ? 'retirada' : 'entrega',
        'endereco_entrega': _retirarNaLoja
            ? 'Retirada no Balcão'
            : _enderecoController.text.trim(),
        'forma_pagamento': totalFinal == 0.0 ? 'Saldo do App' : _formaPagamento,
        'status': statusPedido,
        'data_pedido': FieldValue.serverTimestamp(),
        'checkout_grupo_id': checkoutGrupoId,
        'checkout_grupo_pedido_ids': allIds,
        'checkout_grupo_lider': isLider,
        if (precisaMpUnificado && isLider)
          'checkout_valor_mp_total_cobranca': totalFinal,
        // Logística por tipos de entrega aceitos pela loja (Fase 2):
        // - `tipos_entrega_permitidos_loja`: snapshot no momento do checkout
        //   (usado pelo filtro de entregadores; imutável após criação).
        // - `veiculo_alvo_frete`: tipo canônico de maior hierarquia escolhido
        //   para calcular o frete (ex.: "carro" quando loja aceita moto+carro).
        // - `frete_tabela_efetiva`: tabela que REALMENTE bateu (pode divergir
        //   do alvo quando caímos em fallback; útil para auditoria).
        if (tiposAceitosLoja.isNotEmpty)
          'tipos_entrega_permitidos_loja': tiposAceitosLoja,
        'veiculo_alvo_frete': veiculoAlvoFrete,
        'frete_tabela_efetiva': freteTabelaEfetiva,
      };

      batch.set(refs[i], docPayload);
    }

    try {
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar pedidos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    if (valorDesconto > 0) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(clienteId)
          .update({'saldo': FieldValue.increment(-valorDesconto)});
    }

    _qtdPedidosUltimoCheckout = n;

    // Só limpa o carrinho quando o pedido é imediatamente finalizado
    // (Dinheiro / saldo). Para PIX e Cartão, o status é
    // `aguardando_pagamento` e o carrinho só é limpo após aprovação,
    // permitindo que o cliente volte para esta tela e ajuste a compra.
    if (fecharCarrinhoEExibirDialogo) {
      await cart.removerItensPorTipo(encomenda: false);
    }

    if (mounted) {
      if (fecharCarrinhoEExibirDialogo) {
        Navigator.pop(context);
        _mostrarSucesso();
      }
    }
    return refs.first.id;
  }

  String _textoBotaoCheckout(double totalFinal, bool carrinhoSoEncomenda) {
    if (carrinhoSoEncomenda) return 'Enviar solicitação';
    if (totalFinal <= 0) return 'Confirmar pedido';
    // DESABILITADO: if (_formaPagamento == 'Dinheiro') return 'Confirmar pedido';
    return 'Ir para pagamento';
  }

  /// Botão de finalização inline da seção de pronta-entrega.
  Widget _botaoFinalizarPronta(CartProvider cart, double totalFinal) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _processandoPedido
            ? null
            : () => _avancarParaPagamento(cart),
        style: ElevatedButton.styleFrom(
          backgroundColor: diPertinLaranja,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _processandoPedido
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                _textoBotaoCheckout(totalFinal, false),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  /// Tile compacto de item de encomenda (imagem, nome, variações, qtd, remover).
  Widget _itemEncomendaTile(CartProvider cart, CartItemModel item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item.imagem.isNotEmpty
                  ? item.imagem
                  : 'https://via.placeholder.com/50',
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                width: 58,
                height: 58,
                color: Colors.grey[300],
                child: const Icon(Icons.fastfood, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.lojaNome.trim().isNotEmpty
                      ? item.lojaNome.trim()
                      : 'Loja parceira',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.variacoesResumo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.variacoesSelecionadas.entries
                        .map(
                          (e) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: diPertinRoxo.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${e.key == 'cor' ? 'Cor' : 'Tamanho'}: ${e.value}',
                              style: const TextStyle(
                                color: diPertinRoxo,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Qtde. ${item.quantidade} · preço a combinar',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => cart.decrementarQuantidade(
                                item.chaveCarrinho,
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(9),
                              ),
                              child: const SizedBox(
                                width: 42,
                                height: 42,
                                child: Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: diPertinRoxo,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '${item.quantidade}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => cart.incrementarQuantidade(
                                item.chaveCarrinho,
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(9),
                              ),
                              child: const SizedBox(
                                width: 42,
                                height: 42,
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: diPertinRoxo,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () => cart.removeItem(item.chaveCarrinho),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumoEncomenda(
    String rotulo,
    String valor, {
    bool destaque = false,
    Color? valorCor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: destaque ? 14 : 13,
                color: destaque ? Colors.grey[900] : Colors.grey[600],
                fontWeight: destaque ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            valor,
            style: TextStyle(
              fontSize: destaque ? 15 : 13,
              fontWeight: destaque ? FontWeight.w900 : FontWeight.w700,
              color: valorCor ?? (destaque ? diPertinRoxo : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// Card Subtotal / valor da encomenda / frete / total (antes da negociação).
  Widget _cardResumoFinanceiroEncomenda({
    required List<CartItemModel> itens,
    required String lojaId,
    required _DetalheFreteLoja? detFrete,
  }) {
    final subtotalRef = _subtotalItensLista(itens);
    final frete = _retirarNaLoja ? 0.0 : _taxaEntregaEncomendaParaLoja(lojaId);
    final temReferenciaCatalogo = subtotalRef > 0.009;
    final totalEstimado = subtotalRef + frete;
    final textoSubtotal = temReferenciaCatalogo
        ? 'R\$ ${subtotalRef.toStringAsFixed(2)}'
        : '—';
    final textoValorEncomenda = 'A combinar';
    final textoFrete = _calculandoTaxaEncomenda
        ? 'Calculando…'
        : (_retirarNaLoja
              ? 'Retirada na loja'
              : 'R\$ ${frete.toStringAsFixed(2)}');
    final textoTotal = temReferenciaCatalogo
        ? 'R\$ ${totalEstimado.toStringAsFixed(2)}'
        : (_retirarNaLoja ? textoValorEncomenda : 'A combinar + frete');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: diPertinRoxo.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resumo da encomenda',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 8),
          _linhaResumoEncomenda('Subtotal', textoSubtotal),
          _linhaResumoEncomenda('Valor da encomenda', textoValorEncomenda),
          _linhaResumoEncomenda('Taxa de entrega', textoFrete),
          if (detFrete?.fallback == true && !_retirarNaLoja) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                detFrete!.motivo ??
                    'Frete estimado — confira com a loja após o envio.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.orange.shade800,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const Divider(height: 16),
          _linhaResumoEncomenda('Total', textoTotal, destaque: true),
          const SizedBox(height: 8),
          Text(
            'A entrada refere-se apenas ao produto. O frete entra no pagamento final.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Seção "Por encomenda": banner + itens + botão de envio próprio.
  Widget _secaoEncomenda(CartProvider cart) {
    final itens = cart.itensEncomenda;
    final lojaId = itens.isNotEmpty ? itens.first.lojaId.trim() : '';
    final detFrete = lojaId.isNotEmpty
        ? _detalhesFreteEncomendaPorLoja[lojaId]
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: diPertinRoxo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: diPertinRoxo.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.handshake_outlined, color: diPertinRoxo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Itens por encomenda: envie a solicitação para a loja '
                  'negociar preço e entrada. O pagamento pelo app só vale '
                  'para a entrada depois que você aceitar a proposta.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Itens por encomenda',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.grey[900],
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itens.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) =>
                _itemEncomendaTile(cart, itens[index]),
          ),
        ),
        const SizedBox(height: 14),
        if (lojaId.isNotEmpty)
          _cardResumoFinanceiroEncomenda(
            itens: itens,
            lojaId: lojaId,
            detFrete: detFrete,
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _processandoPedido
                ? null
                : () => _enviarSolicitacaoEncomenda(cart),
            style: ElevatedButton.styleFrom(
              backgroundColor: diPertinRoxo,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _processandoPedido
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            label: const Text(
              'Enviar encomenda',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pagamentoOpcao({
    required String value,
    required String titulo,
    required String subtitulo,
    required IconData icon,
    required Color corIcone,
  }) {
    final sel = _formaPagamento == value;
    return InkWell(
      onTap: () => setState(() {
        _formaPagamento = value;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              selected: sel,
              label: titulo,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sel ? diPertinRoxo : Colors.grey.shade400,
                    width: sel ? 2.2 : 1.8,
                  ),
                  color: sel ? diPertinRoxo : Colors.transparent,
                ),
                child: sel
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: corIcone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: corIcone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarSucesso() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text(
              "Pedido Confirmado!",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: diPertinRoxo,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _qtdPedidosUltimoCheckout > 1
                  ? (_retirarNaLoja
                        ? "As lojas já receberam os seus pedidos. Acompanhe em Meus pedidos."
                        : "As lojas já receberam os seus pedidos. Acompanhe a entrega pelo app!")
                  : (_retirarNaLoja
                        ? "A loja já recebeu o seu pedido. Aguarde a confirmação para ir buscar!"
                        : "A loja já recebeu o seu pedido. Acompanhe a entrega pelo app!"),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: diPertinLaranja,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Entendi",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloco de detalhamento do frete exibido abaixo do valor "Taxa de Entrega"
  /// no card Subtotal. Mostra:
  /// - calculando... enquanto roda;
  /// - resumo da regra aplicada (cidade · veículo · base + km extras);
  /// - alerta amigável quando o endereço ainda não foi informado;
  /// - no multi-loja, o valor e a regra de cada loja.
  Widget _blocoDetalheFrete() {
    final textoEnderecoVazio = _enderecoController.text.trim().isEmpty;
    final detalhes = _detalhesFretePorLoja;
    final veiculoGrande = detalhes.values.any(
      (d) => d.veiculoEfetivo == 'carro',
    );
    final corBorda = veiculoGrande
        ? diPertinLaranja.withValues(alpha: 0.35)
        : Colors.grey.shade200;
    final corFundo = veiculoGrande
        ? diPertinLaranja.withValues(alpha: 0.06)
        : const Color(0xFFF8F7FC);

    Widget icone() {
      if (_calculandoTaxaEntrega) {
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return Icon(
        veiculoGrande
            ? Icons.local_shipping_rounded
            : Icons.two_wheeler_rounded,
        size: 16,
        color: veiculoGrande ? diPertinLaranja : Colors.grey[600],
      );
    }

    Widget conteudo;
    if (_calculandoTaxaEntrega) {
      conteudo = const Text(
        'Calculando frete pela tabela...',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    } else if (textoEnderecoVazio) {
      conteudo = Text(
        'Informe o endereço de entrega para calcular o frete pela tabela.',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    } else if (detalhes.isEmpty) {
      conteudo = Text(
        _detalheTaxaEntrega.isEmpty
            ? 'Valor tabelado de acordo com a distância entre a loja e o cliente.'
            : _detalheTaxaEntrega,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    } else if (detalhes.length == 1) {
      final d = detalhes.values.first;
      conteudo = Text(
        d.fallback
            ? (d.motivo ?? 'Frete padrão aplicado.')
            : 'Frete calculado pela loja conforme a distância até o endereço.',
        style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.35),
      );
    } else {
      final nomesPorLoja = <String, String>{};
      for (final item in context.read<CartProvider>().items) {
        final id = item.lojaId.trim();
        if (id.isEmpty) continue;
        nomesPorLoja.putIfAbsent(id, () => item.lojaNome.trim());
      }

      String rotuloLoja(String lojaId, int ordem) {
        final nome = nomesPorLoja[lojaId]?.trim() ?? '';
        if (nome.isNotEmpty) return nome;
        return 'Loja $ordem';
      }

      final entradas = detalhes.entries.toList();
      conteudo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Frete por loja',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < entradas.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  Expanded(
                    child: Text(
                      rotuloLoja(entradas[i].key, i + 1),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey[800],
                        height: 1.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entradas[i].value.resumoClienteSimples(),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[800],
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: corBorda),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: icone()),
            const SizedBox(width: 8),
            Expanded(child: conteudo),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final lojaAtualId = cart.items.isNotEmpty
        ? cart.items.first.lojaId.trim()
        : '';
    if (lojaAtualId != _ultimaLojaIdTaxa) {
      _ultimaLojaIdTaxa = lojaAtualId;
      _agendarRecalculoTaxa(atraso: const Duration(milliseconds: 120));
    }
    bool carrinhoVazio = cart.items.isEmpty;
    final temEncomenda = cart.temEncomenda;
    final temProntaEntrega = cart.temProntaEntrega;
    // Mantido para gating de cupom/saldo/pagamento (equivale a !temProntaEntrega
    // quando a sacola não está vazia).
    final carrinhoSoEncomenda = temEncomenda && !temProntaEntrega;
    final mq = MediaQuery.of(context);
    final bottomPad = max(mq.padding.bottom, mq.viewPadding.bottom);
    // Sem barra fixa de checkout: os botões de finalizar são inline em cada seção.
    final scrollBottomPad = 24 + bottomPad;

    double subtotal = cart.totalProntaEntrega;
    final descontoCupomEfetivo = temProntaEntrega ? _descontoCupom : 0.0;
    double totalParcial = subtotal + _taxaEntregaReal - descontoCupomEfetivo;
    if (totalParcial < 0) totalParcial = 0;
    final usarSaldoEfetivo = carrinhoSoEncomenda
        ? false
        : (_usarSaldo && _clientePodeUsarSaldoCarteira);
    double valorDesconto = usarSaldoEfetivo
        ? min(_saldoCliente, totalParcial)
        : 0.0;
    double totalFinal = totalParcial - valorDesconto;
    if (totalFinal < 0) totalFinal = 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Meu Carrinho',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Revise e finalize seu pedido',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.normal,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
      body: carrinhoVazio
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 96,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sua sacola está vazia',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Explore a vitrine, escolha seus produtos favoritos e monte seu pedido por aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: diPertinLaranja,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Ver ofertas na vitrine',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, scrollBottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: diPertinRoxo.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _retirarNaLoja = false);
                              _agendarRecalculoTaxa(
                                atraso: const Duration(milliseconds: 120),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(
                                color: !_retirarNaLoja
                                    ? diPertinRoxo
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(14),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.two_wheeler,
                                    color: !_retirarNaLoja
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    "Entregar",
                                    style: TextStyle(
                                      color: !_retirarNaLoja
                                          ? Colors.white
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _retirarNaLoja = true);
                              _agendarRecalculoTaxa(
                                atraso: const Duration(milliseconds: 120),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(
                                color: _retirarNaLoja
                                    ? diPertinLaranja
                                    : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(14),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.storefront,
                                    color: _retirarNaLoja
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    "Retirar na Loja",
                                    style: TextStyle(
                                      color: _retirarNaLoja
                                          ? Colors.white
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color: diPertinRoxo.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: diPertinRoxo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.store_rounded,
                            color: diPertinRoxo,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pedido em',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cart.items.isNotEmpty &&
                                        cart.items.first.lojaNome
                                            .trim()
                                            .isNotEmpty
                                    ? cart.items.first.lojaNome.trim()
                                    : 'Loja',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: diPertinRoxo,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (temProntaEntrega) ...[
                  Text(
                    "Itens do pedido",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[900],
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cart.itensProntaEntrega.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            var item = cart.itensProntaEntrega[index];
                            final linhaTotal = item.preco * item.quantidade;
                            return Dismissible(
                              key: Key('cart_${item.chaveCarrinho}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                color: const Color(0xFFFFEBEE),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red.shade700,
                                  size: 28,
                                ),
                              ),
                              onDismissed: (_) =>
                                  cart.removeItem(item.chaveCarrinho),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        item.imagem.isNotEmpty
                                            ? item.imagem
                                            : 'https://via.placeholder.com/50',
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          width: 64,
                                          height: 64,
                                          color: Colors.grey[300],
                                          child: const Icon(
                                            Icons.fastfood,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.lojaNome.trim().isNotEmpty
                                                ? item.lojaNome.trim()
                                                : 'Loja parceira',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey[700],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.nome,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (item
                                              .variacoesResumo
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: item
                                                  .variacoesSelecionadas
                                                  .entries
                                                  .map(
                                                    (e) => Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: diPertinRoxo
                                                            .withOpacity(0.08),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '${e.key == 'cor' ? 'Cor' : 'Tamanho'}: ${e.value}',
                                                        style: const TextStyle(
                                                          color: diPertinRoxo,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            'R\$ ${item.preco.toStringAsFixed(2)} × ${item.quantidade}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                'R\$ ${linhaTotal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: diPertinLaranja,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const Spacer(),
                                              Container(
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap: () => cart
                                                            .decrementarQuantidade(
                                                              item.chaveCarrinho,
                                                            ),
                                                        borderRadius:
                                                            const BorderRadius.horizontal(
                                                              left:
                                                                  Radius.circular(
                                                                    9,
                                                                  ),
                                                            ),
                                                        child: const SizedBox(
                                                          width: 44,
                                                          height: 44,
                                                          child: Icon(
                                                            Icons.remove,
                                                            size: 18,
                                                            color: diPertinRoxo,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      child: Text(
                                                        '${item.quantidade}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                    Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap: () => cart
                                                            .incrementarQuantidade(
                                                              item.chaveCarrinho,
                                                            ),
                                                        borderRadius:
                                                            const BorderRadius.horizontal(
                                                              right:
                                                                  Radius.circular(
                                                                    9,
                                                                  ),
                                                            ),
                                                        child: const SizedBox(
                                                          width: 44,
                                                          height: 44,
                                                          child: Icon(
                                                            Icons.add,
                                                            size: 18,
                                                            color: diPertinRoxo,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Deslize o item para a esquerda para remover do pedido.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.3,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ],

                  if (!carrinhoSoEncomenda) ...[
                    // ── Cupom de desconto ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: _cupomAplicado
                              ? Colors.green.shade300
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _cupomAplicado
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : diPertinLaranja.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _cupomAplicado
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.local_offer_outlined,
                                  color: _cupomAplicado
                                      ? Colors.green
                                      : diPertinLaranja,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _cupomAplicado
                                      ? 'Cupom aplicado'
                                      : 'Tem cupom de desconto?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: _cupomAplicado
                                        ? Colors.green.shade700
                                        : Colors.grey[900],
                                  ),
                                ),
                              ),
                              if (_cupomAplicado)
                                GestureDetector(
                                  onTap: _removerCupom,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Remover',
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (!_cupomAplicado) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _cupomController,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: 'Digite o código',
                                      hintStyle: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[400],
                                        fontWeight: FontWeight.normal,
                                        letterSpacing: 0,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFFF8F9FA),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 14,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: diPertinRoxo,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _validandoCupom
                                        ? null
                                        : () => _validarCupom(cart),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: diPertinRoxo,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _validandoCupom
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Aplicar',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_cupomMensagem.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  _cupomErro
                                      ? Icons.error_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: _cupomErro
                                      ? Colors.red.shade600
                                      : Colors.green.shade600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _cupomMensagem,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _cupomErro
                                          ? Colors.red.shade600
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_cupomAplicado && _descontoCupom > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _cupomCodigo ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: Colors.green.shade800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '- R\$ ${_descontoCupom.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  if (!_retirarNaLoja) ...[
                    Text(
                      "Onde devemos entregar?",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[900],
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                color: diPertinLaranja.withValues(alpha: 0.9),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Endereço de entrega',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Colors.grey[900],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _enderecoController.text.trim().isEmpty
                                          ? 'Nenhum endereço selecionado'
                                          : _enderecoController.text.trim(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: _enderecoController.text
                                                .trim()
                                                .isEmpty
                                            ? Colors.grey[500]
                                            : Colors.grey[900],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _abrirSelecaoEndereco,
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                                size: 18,
                              ),
                              label: const Text('Trocar endereço'),
                              style: TextButton.styleFrom(
                                foregroundColor: diPertinRoxo,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  if (_saldoCliente > 0 &&
                      !carrinhoSoEncomenda &&
                      _clientePodeUsarSaldoCarteira) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: CheckboxListTile(
                        activeColor: Colors.green,
                        title: const Text(
                          "Usar Saldo da Carteira",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        subtitle: Text(
                          "Você tem R\$ ${_saldoCliente.toStringAsFixed(2)} disponíveis.",
                        ),
                        value: _usarSaldo,
                        onChanged: (val) =>
                            setState(() => _usarSaldo = val ?? false),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  if (totalFinal > 0 && !carrinhoSoEncomenda) ...[
                    Text(
                      "Como quer pagar o restante?",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[900],
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _pagamentoOpcao(
                            value: 'PIX',
                            titulo: 'PIX (pelo app)',
                            subtitulo:
                                'Aprovação na hora; você paga com QR Code.',
                            icon: Icons.qr_code_2_rounded,
                            corIcone: const Color(0xFF00A650),
                          ),
                          Divider(height: 1, color: Colors.grey.shade200),
                          _pagamentoOpcao(
                            value: 'Cartão',
                            titulo: 'Cartão',
                            subtitulo: 'Pagamento seguro pelo app.',
                            icon: Icons.credit_card_rounded,
                            corIcone: diPertinRoxo,
                          ),
                          // DESABILITADO TEMPORARIAMENTE: Pagamento por Dinheiro
                          // Divider(height: 1, color: Colors.grey.shade200),
                          // _pagamentoOpcao(
                          //   value: 'Dinheiro',
                          //   titulo: 'Dinheiro na entrega',
                          //   subtitulo:
                          //       'Pague em espécie ao entregador ao receber o pedido.',
                          //   icon: Icons.payments_outlined,
                          //   corIcone: diPertinLaranja,
                          // ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // DESABILITADO TEMPORARIAMENTE: Opções de troco para pagamento em dinheiro
                    // if (_formaPagamento == 'Dinheiro') ...[
                    //   Container(
                    //     padding: const EdgeInsets.all(14),
                    //     decoration: BoxDecoration(
                    //       color: Colors.white,
                    //       borderRadius: BorderRadius.circular(14),
                    //       border: Border.all(color: Colors.grey.shade200),
                    //     ),
                    //     child: Column(
                    //       crossAxisAlignment: CrossAxisAlignment.start,
                    //       children: [
                    //         Row(
                    //           children: [
                    //             Checkbox(
                    //               value: _precisaTrocoDinheiro,
                    //               activeColor: diPertinRoxo,
                    //               onChanged: (valor) {
                    //                 setState(() {
                    //                   _precisaTrocoDinheiro = valor ?? false;
                    //                   if (!_precisaTrocoDinheiro) {
                    //                     _trocoParaController.clear();
                    //                   }
                    //                 });
                    //               },
                    //             ),
                    //             const Expanded(
                    //               child: Text(
                    //                 'Precisa de troco?',
                    //                 style: TextStyle(
                    //                   fontWeight: FontWeight.w600,
                    //                   fontSize: 15,
                    //                 ),
                    //               ),
                    //             ),
                    //           ],
                    //         ),
                    //         if (_precisaTrocoDinheiro) ...[
                    //           const SizedBox(height: 8),
                    //           TextField(
                    //             controller: _trocoParaController,
                    //             keyboardType:
                    //                 const TextInputType.numberWithOptions(
                    //                   decimal: true,
                    //                 ),
                    //             decoration: InputDecoration(
                    //               labelText: 'Troco para quanto?',
                    //               hintText: 'Ex.: 50,00',
                    //               prefixText: 'R\$ ',
                    //               filled: true,
                    //               fillColor: const Color(0xFFF8F9FA),
                    //               border: OutlineInputBorder(
                    //                 borderRadius: BorderRadius.circular(12),
                    //                 borderSide: BorderSide(
                    //                   color: Colors.grey.shade300,
                    //                 ),
                    //               ),
                    //               enabledBorder: OutlineInputBorder(
                    //                 borderRadius: BorderRadius.circular(12),
                    //                 borderSide: BorderSide(
                    //                   color: Colors.grey.shade300,
                    //                 ),
                    //               ),
                    //               focusedBorder: const OutlineInputBorder(
                    //                 borderRadius: BorderRadius.all(
                    //                   Radius.circular(12),
                    //                 ),
                    //                 borderSide: BorderSide(
                    //                   color: diPertinRoxo,
                    //                   width: 1.4,
                    //                 ),
                    //               ),
                    //             ),
                    //           ),
                    //           const SizedBox(height: 6),
                    //           Text(
                    //             'Essa informação será enviada para a loja.',
                    //             style: TextStyle(
                    //               fontSize: 12,
                    //               color: Colors.grey[600],
                    //             ),
                    //           ),
                    //         ],
                    //       ],
                    //     ),
                    //   ),
                    //   const SizedBox(height: 24),
                    // ],
                  ],

                  if (temProntaEntrega) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: diPertinRoxo.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Subtotal",
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              "R\$ ${subtotal.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _retirarNaLoja
                                  ? "Taxa (Retirada)"
                                  : "Taxa de Entrega",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              "R\$ ${_taxaEntregaReal.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _retirarNaLoja
                                    ? Colors.green
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (!_retirarNaLoja) _blocoDetalheFrete(),
                        if (_cupomAplicado && descontoCupomEfetivo > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_offer_outlined,
                                    size: 16,
                                    color: Colors.green.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Cupom (${_cupomCodigo ?? ''})",
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                "- R\$ ${descontoCupomEfetivo.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (usarSaldoEfetivo && valorDesconto > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Desconto (Saldo)",
                                style: TextStyle(color: Colors.green),
                              ),
                              Text(
                                "- R\$ ${valorDesconto.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                        Divider(height: 28, color: Colors.grey.shade200),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "TOTAL",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: diPertinRoxo,
                              ),
                            ),
                            Text(
                              "R\$ ${totalFinal.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: diPertinLaranja,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _botaoFinalizarPronta(cart, totalFinal),
                  ],

                  if (temEncomenda) ...[
                    SizedBox(height: temProntaEntrega ? 28 : 0),
                    _secaoEncomenda(cart),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Snapshot imutável da regra de frete aplicada a UMA loja, usado para:
/// 1. calcular e persistir o valor final por loja;
/// 2. exibir a composição no card Subtotal (auditoria visual pro cliente).
class _DetalheFreteLoja {
  final String lojaId;
  final String? cidade;

  /// Tipo canônico de entrega que o carrinho PEDIU (um dos 4 valores
  /// em [TiposEntrega] — bicicleta/moto/carro/carro_frete). Derivado do
  /// maior tipo da lista `tipos_entrega_permitidos` da loja.
  final String veiculoAlvo;

  /// Tabela que a regra realmente respondeu. Pode divergir de [veiculoAlvo]
  /// quando o alvo não existia e caímos em fallback na cadeia
  /// [TiposEntrega.cadeiaFallbackTabela]. Valores possíveis:
  /// `bicicleta` | `moto` | `carro` | `carro_frete` | `padrao`.
  final String veiculoEfetivo;

  /// Lista de tipos aceitos pela loja no momento do cálculo (snapshot).
  /// Vazia quando a loja é legado sem configuração — nesse caso foi
  /// aplicado o default de [TiposEntrega.defaultLegado].
  final List<String> tiposAceitosLoja;

  final double base;
  final double distanciaBaseKm;
  final double valorKmAdicional;

  /// Distância em km entre loja e endereço de entrega (linha reta). Pode ser
  /// `null` quando não conseguimos geocodificar o endereço — nesse caso só
  /// aplicamos o valor base.
  final double? distanciaKm;

  final double kmExtra;
  final double taxa;

  /// Marcado quando não houve regra aplicável (usamos _taxaBaseFallback).
  final bool fallback;

  /// Mensagem curta explicando por que caímos em fallback ou regra incompleta.
  final String? motivo;

  const _DetalheFreteLoja({
    required this.lojaId,
    required this.cidade,
    required this.veiculoAlvo,
    required this.veiculoEfetivo,
    required this.tiposAceitosLoja,
    required this.base,
    required this.distanciaBaseKm,
    required this.valorKmAdicional,
    required this.distanciaKm,
    required this.kmExtra,
    required this.taxa,
    required this.fallback,
    this.motivo,
  });

  factory _DetalheFreteLoja.fallback({
    required String lojaId,
    required double taxa,
    required String motivo,
    required String veiculoAlvo,
    List<String> tiposAceitosLoja = const <String>[],
    String? cidade,
  }) => _DetalheFreteLoja(
    lojaId: lojaId,
    cidade: cidade,
    veiculoAlvo: veiculoAlvo,
    veiculoEfetivo: veiculoAlvo,
    tiposAceitosLoja: tiposAceitosLoja,
    base: taxa,
    distanciaBaseKm: 0,
    valorKmAdicional: 0,
    distanciaKm: null,
    kmExtra: 0,
    taxa: double.parse(taxa.toStringAsFixed(2)),
    fallback: true,
    motivo: motivo,
  );

  /// Rótulo genérico ao cliente — NUNCA expõe o tipo técnico. O cliente
  /// não precisa saber se é moto, carro ou carro-frete; pra ele isso é
  /// decisão da loja. Mostramos só "Frete calculado pela loja".
  String get rotuloVeiculo => 'Frete calculado pela loja';

  /// Resumo enxuto exibido ao cliente no card Subtotal. Não vaza regra,
  /// base, distância base ou km adicional — apenas o valor final (ou, em
  /// caso de fallback, o motivo amigável).
  ///
  /// Exemplo: "R$ 3,70" (sucesso) · "Frete padrão aplicado" (fallback sem motivo).
  String resumoClienteSimples() {
    if (fallback) {
      return motivo ?? 'Frete padrão aplicado';
    }
    return 'R\$ ${taxa.toStringAsFixed(2)}';
  }

  /// Resumo técnico — uso INTERNO (logs, auditoria, tela de lojista). NÃO
  /// exibir ao cliente final. Mostra cidade, cálculo base/km e distância.
  String resumoCurto() {
    if (fallback) {
      return motivo ?? 'Frete padrão aplicado';
    }
    final cidadeTxt = (cidade ?? '').trim();
    final cidadeFmt = cidadeTxt.isEmpty
        ? ''
        : '${cidadeTxt[0].toUpperCase()}${cidadeTxt.substring(1)} · ';
    final partes = <String>[
      'R\$ ${base.toStringAsFixed(2)} base',
      'até ${_fmtKm(distanciaBaseKm)}',
    ];
    if (valorKmAdicional > 0 && kmExtra > 0) {
      partes.add(
        '+ R\$ ${valorKmAdicional.toStringAsFixed(2)}/km × ${_fmtKm(kmExtra)}',
      );
    }
    final distanciaTxt = distanciaKm == null
        ? ''
        : ' (distância ${_fmtKm(distanciaKm!)})';
    return '$cidadeFmt$rotuloVeiculo · ${partes.join(' ')} = '
        'R\$ ${taxa.toStringAsFixed(2)}$distanciaTxt';
  }

  static String _fmtKm(double v) => '${v.toStringAsFixed(1)} km';
}
