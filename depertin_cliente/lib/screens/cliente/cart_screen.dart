// Arquivo: lib/screens/cliente/cart_screen.dart

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
import '../../providers/cart_provider.dart';
import '../../models/cart_item_model.dart';
import '../../services/firebase_functions_config.dart';
import '../../utils/loja_pausa.dart';

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
  final TextEditingController _trocoParaController = TextEditingController();
  String _formaPagamento = 'PIX';
  bool _processandoPedido = false;
  bool _retirarNaLoja = false;
  bool _precisaTrocoDinheiro = false;

  // Variáveis para o saldo
  double _saldoCliente = 0.0;
  bool _usarSaldo = false;

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
  /// Por loja (entrega) — usado no split multi-loja.
  Map<String, double> _taxaEntregaPorLoja = {};
  int _qtdPedidosUltimoCheckout = 1;

  double get _taxaEntregaReal => _retirarNaLoja ? 0.0 : _taxaEntregaCalculada;

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

  static double? _parseMoedaDigitada(String valor) {
    var texto = valor.trim();
    if (texto.isEmpty) return null;
    texto = texto.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }
    return double.tryParse(texto);
  }

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
  }) async {
    String cidade = '';
    String uf = '';
    double? latDoc;
    double? lngDoc;
    try {
      final clienteSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(clienteId)
          .get();
      final dados = clienteSnap.data() ?? const <String, dynamic>{};
      final endPadrao =
          dados['endereco_entrega_padrao'] as Map<String, dynamic>?;

      latDoc =
          _coordToDouble(endPadrao?['latitude']) ??
          _coordToDouble(dados['latitude']);
      lngDoc =
          _coordToDouble(endPadrao?['longitude']) ??
          _coordToDouble(dados['longitude']);

      cidade = (endPadrao?['cidade'] ?? dados['cidade'] ?? '')
          .toString()
          .trim();
      uf = (endPadrao?['estado'] ?? dados['uf'] ?? '').toString().trim();
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

  Future<Map<String, dynamic>?> _carregarRegraFrete(String cidadeLoja) async {
    final cidadeOriginal = cidadeLoja.trim().toLowerCase();
    final cidadeNormalizada = _normalizarCidadeFrete(cidadeLoja);
    final ref = FirebaseFirestore.instance.collection('tabela_fretes');
    final porId = <String, Map<String, dynamic>>{};

    Future<DocumentSnapshot<Map<String, dynamic>>> _getDoc(String id) async {
      try {
        return await ref.doc(id).get(const GetOptions(source: Source.server));
      } catch (_) {
        return ref.doc(id).get();
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>> _getCidade(String cidade) async {
      try {
        return await ref
            .where('cidade', isEqualTo: cidade)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        return ref.where('cidade', isEqualTo: cidade).get();
      }
    }

    for (final id in <String>{
      '${cidadeOriginal}_padrao',
      '${cidadeOriginal}_carro',
      '${cidadeNormalizada}_padrao',
      '${cidadeNormalizada}_carro',
      'todas_padrao',
      'todas_carro',
    }) {
      final d = await _getDoc(id);
      if (d.exists) {
        porId[id] = d.data() ?? <String, dynamic>{};
      }
    }

    for (final cidade in <String>{cidadeOriginal, cidadeNormalizada, 'todas'}) {
      final q = await _getCidade(cidade);
      for (final doc in q.docs) {
        porId[doc.id] = doc.data();
      }
    }

    if (porId.isEmpty) return null;

    final regras = porId.entries.toList();
    regras.sort((a, b) {
      final ta =
          (a.value['data_atualizacao'] as Timestamp?)?.millisecondsSinceEpoch ??
          0;
      final tb =
          (b.value['data_atualizacao'] as Timestamp?)?.millisecondsSinceEpoch ??
          0;
      return tb.compareTo(ta);
    });

    return regras.first.value;
  }

  /// Frete de uma loja até o endereço de entrega (mesma regra que o fluxo single-loja).
  Future<({double taxa, String? detalheKm})> _resolverTaxaEntregaParaLoja({
    required String clienteId,
    required String lojaId,
    required String enderecoTexto,
  }) async {
    final lojaDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(lojaId)
        .get();
    final ld = lojaDoc.data() ?? const <String, dynamic>{};
    final cidadeLoja = (ld['cidade'] ?? '').toString().trim();
    final lojaLat = _coordToDouble(ld['latitude']);
    final lojaLng = _coordToDouble(ld['longitude']);
    if (cidadeLoja.isEmpty || lojaLat == null || lojaLng == null) {
      return (taxa: _taxaBaseFallback, detalheKm: null);
    }

    final regra = await _carregarRegraFrete(cidadeLoja);
    if (regra == null) {
      return (taxa: _taxaBaseFallback, detalheKm: null);
    }

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
    );
    final entLat = coordsEntrega.lat;
    final entLng = coordsEntrega.lng;
    if (entLat == null || entLng == null) {
      return (taxa: base, detalheKm: null);
    }

    final distanciaKm =
        Geolocator.distanceBetween(lojaLat, lojaLng, entLat, entLng) / 1000;
    final kmExtra = max(0.0, distanciaKm - distBase);
    final taxa = base + (kmExtra * extraKm);
    return (
      taxa: double.parse(taxa.toStringAsFixed(2)),
      detalheKm: '${distanciaKm.toStringAsFixed(1)} km da loja',
    );
  }

  Future<void> _recalcularTaxaEntrega() async {
    if (!mounted) return;
    final cart = context.read<CartProvider>();
    final grupos = _agruparItensCarrinhoPorLoja(cart.items);

    if (_retirarNaLoja) {
      if (mounted) {
        setState(() {
          _taxaEntregaCalculada = 0;
          _taxaEntregaPorLoja = {for (final id in grupos.keys) id: 0.0};
          _detalheTaxaEntrega = 'Retirada na loja';
          _calculandoTaxaEntrega = false;
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || cart.items.isEmpty) return;

    final endereco = _enderecoController.text.trim();
    final lojaIds = grupos.keys.toList()..sort();
    if (lojaIds.isEmpty || endereco.isEmpty) return;

    if (mounted) setState(() => _calculandoTaxaEntrega = true);

    try {
      final taxas = <String, double>{};
      var soma = 0.0;
      String? primeiroDetalheKm;
      for (final lojaId in lojaIds) {
        final r = await _resolverTaxaEntregaParaLoja(
          clienteId: user.uid,
          lojaId: lojaId,
          enderecoTexto: endereco,
        );
        taxas[lojaId] = r.taxa;
        soma += r.taxa;
        primeiroDetalheKm ??= r.detalheKm;
      }
      if (mounted) {
        setState(() {
          _taxaEntregaPorLoja = taxas;
          _taxaEntregaCalculada = _round2(soma);
          if (lojaIds.length > 1) {
            _detalheTaxaEntrega =
                '${lojaIds.length} lojas — total frete R\$ ${_taxaEntregaCalculada.toStringAsFixed(2)}';
          } else {
            _detalheTaxaEntrega =
                primeiroDetalheKm ?? 'Frete calculado';
          }
          _calculandoTaxaEntrega = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _taxaEntregaCalculada = _taxaBaseFallback;
        _taxaEntregaPorLoja = {};
        _detalheTaxaEntrega = 'Frete padrão (erro ao calcular)';
        _calculandoTaxaEntrega = false;
      });
      debugPrint('Erro ao recalcular taxa de entrega: $e');
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
    _trocoParaController.dispose();
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
          setState(() {
            _saldoCliente = (dados['saldo'] ?? 0.0).toDouble();

            if (dados.containsKey('endereco_entrega_padrao') &&
                dados['endereco_entrega_padrao'] is Map) {
              var end = dados['endereco_entrega_padrao'];
              String rua = end['rua'] ?? '';
              String num = end['numero'] ?? '';
              String bairro = end['bairro'] ?? '';
              String cidade = end['cidade'] ?? '';
              String compl = end['complemento'] ?? '';

              String enderecoMontado = "$rua, $num, $bairro, $cidade";
              if (compl.isNotEmpty) enderecoMontado += " - $compl";

              _enderecoController.text = enderecoMontado;
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
      final lojaId = cart.items.isNotEmpty ? cart.items.first.lojaId : '';
      final result = await appFirebaseFunctions
          .httpsCallable('validarCupom')
          .call<Map<String, dynamic>>({
            'codigo': codigo,
            'subtotal_produtos': cart.totalAmount,
            'loja_id': lojaId,
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

  Future<bool> _verificarLojaAberta(CartProvider cart) async {
    if (cart.items.isEmpty) return true;
    final lojas = cart.items.map((e) => e.lojaId.trim()).where((id) => id.isNotEmpty).toSet();
    for (final lojaId in lojas) {
      try {
        final lojaDoc = await FirebaseFirestore.instance
            .collection('users')
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

    if (!await _verificarLojaAberta(cart)) return;
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

    double subtotal = cart.totalAmount;
    double totalParcial = subtotal + _taxaEntregaReal - _descontoCupom;
    if (totalParcial < 0) totalParcial = 0;
    double valorDesconto = _usarSaldo ? min(_saldoCliente, totalParcial) : 0.0;
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

    if (_formaPagamento == 'Dinheiro') {
      if (_precisaTrocoDinheiro) {
        final trocoPara = _parseMoedaDigitada(_trocoParaController.text);
        if (trocoPara == null || trocoPara <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Informe um valor válido para troco.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (trocoPara < totalFinal) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'O valor para troco deve ser igual ou maior que R\$ ${totalFinal.toStringAsFixed(2)}.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      final pedidoId = await _salvarPedidoNoBanco(
        cart,
        user.uid,
        subtotal,
        valorDesconto,
        totalFinal,
        fecharCarrinhoEExibirDialogo: false,
      );
      if (!mounted || pedidoId == null) return;
      await _mostrarConfirmacaoPedidoFeitoDinheiro();
      return;
    }

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
            onPagamentoAprovado: () {
              Navigator.pop(context);
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/meus-pedidos');
            },
          ),
        ),
      );
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
            onPagamentoAprovado: () {
              Navigator.pop(context);
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/meus-pedidos');
            },
          ),
        ),
      );
      return;
    }
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
      final grupos = _agruparItensCarrinhoPorLoja(cart.items);
      if (grupos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Itens sem loja identificada. Atualize o carrinho e tente de novo.'),
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

      List<CartItemModel> listaItens = cart.items;
      List<Map<String, dynamic>> itensParaSalvar = listaItens.map((item) {
        return {
          'id_produto': item.id,
          'nome': item.nome,
          'preco': item.preco,
          'quantidade': item.quantidade,
          'imagem': item.imagem,
        };
      }).toList();

      String lojaId = listaItens.isNotEmpty ? listaItens.first.lojaId : '';
      String lojaNome = listaItens.isNotEmpty ? listaItens.first.lojaNome : '';

      String enderecoDaLoja = 'Endereço não cadastrado';
      double? lojaLat;
      double? lojaLng;
      double? entregaLat;
      double? entregaLng;
      if (lojaId.isNotEmpty) {
        var lojaDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(lojaId)
            .get();
        if (lojaDoc.exists) {
          final ld = lojaDoc.data();
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
      final tokenGerado =
          (100000 + Random().nextInt(900000)).toString();

      if (!_retirarNaLoja) {
        await FirebaseFirestore.instance.collection('users').doc(clienteId).set(
          {'endereco': _enderecoController.text.trim()},
          SetOptions(merge: true),
        );
      }

      // Salva o Pedido
      final pagamentoDinheiro = totalFinal > 0 && _formaPagamento == 'Dinheiro';
      final trocoPara = pagamentoDinheiro && _precisaTrocoDinheiro
          ? _parseMoedaDigitada(_trocoParaController.text)
          : null;
      final trocoValor = trocoPara != null && trocoPara > totalFinal
          ? trocoPara - totalFinal
          : 0.0;

      final docRef = await FirebaseFirestore.instance.collection('pedidos').add(
        {
          'cliente_id': clienteId,
          'loja_id': lojaId,
          'loja_nome': lojaNome,
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
          if (pagamentoDinheiro) ...{
            'pagamento_dinheiro_precisa_troco': _precisaTrocoDinheiro,
            if (_precisaTrocoDinheiro && trocoPara != null)
              'pagamento_dinheiro_troco_para': double.parse(
                trocoPara.toStringAsFixed(2),
              ),
            if (_precisaTrocoDinheiro && trocoValor > 0)
              'pagamento_dinheiro_troco_valor': double.parse(
                trocoValor.toStringAsFixed(2),
              ),
          },
          'status': statusPedido,
          'data_pedido': FieldValue.serverTimestamp(),
        },
      );

      // Deduz o saldo do cliente
      if (valorDesconto > 0) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(clienteId)
            .update({'saldo': FieldValue.increment(-valorDesconto)});
      }

      _qtdPedidosUltimoCheckout = 1;
      cart.clearCart();

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

    final precisaMpUnificado = statusPedido == 'aguardando_pagamento' &&
        (_formaPagamento == 'PIX' || _formaPagamento == 'Cartão');

    final totalParcialCheckout = _round2(
      (subtotal + _taxaEntregaReal - _descontoCupom).clamp(0.0, double.infinity),
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
      final tx = _retirarNaLoja ? 0.0 : (_taxaEntregaPorLoja[lojaKeys[i]] ?? 0.0);
      parciais[i] = _round2(s + tx - cupoms[i]);
    }
    var sumP = parciais.fold(0.0, (a, b) => a + b);
    if ((sumP - totalParcialCheckout).abs() > 0.02) {
      parciais[n - 1] = _round2(parciais[n - 1] + (totalParcialCheckout - sumP));
    }

    final saldos = List<double>.filled(n, 0);
    if (totalParcialCheckout > 0 && valorDesconto > 0) {
      var acc = 0.0;
      for (var i = 0; i < n; i++) {
        if (i < n - 1) {
          final si = _round2(valorDesconto * (parciais[i] / totalParcialCheckout));
          saldos[i] = si;
          acc += si;
        } else {
          saldos[i] = _round2(valorDesconto - acc);
        }
      }
    }

    final totais = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      totais[i] = _round2((parciais[i] - saldos[i]).clamp(0.0, double.infinity));
    }
    var sumT = totais.fold(0.0, (a, b) => a + b);
    if ((sumT - totalFinal).abs() > 0.02) {
      totais[n - 1] = _round2(totais[n - 1] + (totalFinal - sumT));
    }

    final lojaSnapshots = await Future.wait(
      lojaKeys.map(
        (id) => FirebaseFirestore.instance.collection('users').doc(id).get(),
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

    if (!_retirarNaLoja) {
      await FirebaseFirestore.instance.collection('users').doc(clienteId).set(
        {'endereco': _enderecoController.text.trim()},
        SetOptions(merge: true),
      );
    }

    final pagamentoDinheiro = totalFinal > 0 && _formaPagamento == 'Dinheiro';
    final trocoParaGlobal = pagamentoDinheiro && _precisaTrocoDinheiro
        ? _parseMoedaDigitada(_trocoParaController.text)
        : null;

    final trocoParaPorLoja = List<double?>.filled(n, null);
    final trocoValorPorLoja = List<double>.filled(n, 0);
    if (trocoParaGlobal != null) {
      final totaisProdutos = List<double>.generate(
        n,
        (i) => _round2(_subtotalItensLista(grupos[lojaKeys[i]]!)),
      );
      final somaProdutos = totaisProdutos.fold(0.0, (a, b) => a + b);
      if (somaProdutos > 0) {
        var accTrocoPara = 0.0;
        for (var i = 0; i < n; i++) {
          if (i < n - 1) {
            final proporcao = totaisProdutos[i] / somaProdutos;
            final tp = _round2(trocoParaGlobal * proporcao);
            trocoParaPorLoja[i] = tp;
            accTrocoPara += tp;
          } else {
            trocoParaPorLoja[i] = _round2(trocoParaGlobal - accTrocoPara);
          }
          final tp = trocoParaPorLoja[i]!;
          trocoValorPorLoja[i] = tp > totaisProdutos[i]
              ? _round2(tp - totaisProdutos[i])
              : 0;
        }
      }
    }

    final checkoutGrupoId = FirebaseFirestore.instance.collection('pedidos').doc().id;
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
            },
          )
          .toList();

      final ld = lojaPorId[lojaId]!;
      final lojaNome = (ld['nome_fantasia'] ?? ld['nome'] ?? '').toString();
      var enderecoDaLoja = ld['endereco']?.toString() ?? 'Endereço não cadastrado';
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

      final docPayload = <String, dynamic>{
        'cliente_id': clienteId,
        'loja_id': lojaId,
        'loja_nome': lojaNome.isNotEmpty ? lojaNome : listaItens.first.lojaNome,
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
        'forma_pagamento': totalFinal == 0.0
            ? 'Saldo do App'
            : _formaPagamento,
        if (pagamentoDinheiro) ...{
          'pagamento_dinheiro_precisa_troco': _precisaTrocoDinheiro,
          if (_precisaTrocoDinheiro && trocoParaPorLoja[i] != null)
            'pagamento_dinheiro_troco_para': double.parse(
              trocoParaPorLoja[i]!.toStringAsFixed(2),
            ),
          if (_precisaTrocoDinheiro && trocoValorPorLoja[i] > 0)
            'pagamento_dinheiro_troco_valor': double.parse(
              trocoValorPorLoja[i].toStringAsFixed(2),
            ),
        },
        'status': statusPedido,
        'data_pedido': FieldValue.serverTimestamp(),
        'checkout_grupo_id': checkoutGrupoId,
        'checkout_grupo_pedido_ids': allIds,
        'checkout_grupo_lider': isLider,
        if (precisaMpUnificado && isLider)
          'checkout_valor_mp_total_cobranca': totalFinal,
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
    cart.clearCart();

    if (mounted) {
      if (fecharCarrinhoEExibirDialogo) {
        Navigator.pop(context);
        _mostrarSucesso();
      }
    }
    return refs.first.id;
  }

  String _textoBotaoCheckout(double totalFinal) {
    if (totalFinal <= 0) return 'Confirmar pedido';
    if (_formaPagamento == 'Dinheiro') return 'Confirmar pedido';
    return 'Ir para pagamento';
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
        if (value != 'Dinheiro') {
          _precisaTrocoDinheiro = false;
          _trocoParaController.clear();
        }
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

  Future<void> _mostrarConfirmacaoPedidoFeitoDinheiro() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 72),
            const SizedBox(height: 16),
            const Text(
              'Pedido feito!',
              textAlign: TextAlign.center,
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
                      ? 'As lojas já receberam seus pedidos. Acompanhe em Meus pedidos.'
                      : 'As lojas já receberam seus pedidos. Acompanhe a entrega em Meus pedidos.')
                  : (_retirarNaLoja
                      ? 'A loja já recebeu seu pedido. Acompanhe em Meus pedidos.'
                      : 'A loja já recebeu seu pedido. Acompanhe a entrega em Meus pedidos.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: Colors.grey[800]),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: diPertinLaranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/meus-pedidos');
              }
            },
            child: const Text(
              'Ir para Meus pedidos',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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

  static const double _alturaBarraCheckout = 56;

  /// Padding vertical do `bottomSheet` (14 acima + 14 abaixo do botão).
  static const double _paddingVerticalFaixaCheckout = 28;

  /// Espaço extra entre o card do total e a faixa laranja ao rolar até o fim.
  static const double _folgaEntreConteudoEBarra = 36;

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
    final mq = MediaQuery.of(context);
    final bottomPad = max(mq.padding.bottom, mq.viewPadding.bottom);
    final scrollBottomPad =
        _folgaEntreConteudoEBarra +
        _paddingVerticalFaixaCheckout +
        _alturaBarraCheckout +
        bottomPad;

    double subtotal = cart.totalAmount;
    double totalParcial = subtotal + _taxaEntregaReal - _descontoCupom;
    if (totalParcial < 0) totalParcial = 0;
    double valorDesconto = _usarSaldo ? min(_saldoCliente, totalParcial) : 0.0;
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
                          itemCount: cart.items.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            var item = cart.items[index];
                            final linhaTotal = item.preco * item.quantidade;
                            return Dismissible(
                              key: Key('cart_${item.id}'),
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
                              onDismissed: (_) => cart.removeItem(item.id),
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
                                                              item.id,
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
                                                              item.id,
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
                                    contentPadding: const EdgeInsets.symmetric(
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

                  if (!_retirarNaLoja) ...[
                    Text(
                      "Onde devemos entregar?",
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
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: diPertinLaranja.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: diPertinLaranja,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Endereço completo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: Colors.grey[900],
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Inclua rua, número, bairro e cidade. '
                                      'Ponto de referência ajuda na entrega.',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.35,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _enderecoController,
                            onChanged: (_) {
                              _agendarRecalculoTaxa();
                            },
                            keyboardType: TextInputType.streetAddress,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 2,
                            maxLines: 4,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              color: Colors.grey[900],
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              alignLabelWithHint: true,
                              hintText:
                                  'Ex.: Rua das Flores, 120, Centro, Toledo — apto 302',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                                height: 1.4,
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8F9FA),
                              contentPadding: const EdgeInsets.symmetric(
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
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Alterações aqui valem para este pedido. '
                                  'Para definir o endereço padrão da conta, '
                                  'use a tela inicial do app.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  if (_saldoCliente > 0) ...[
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

                  if (totalFinal > 0) ...[
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
                            titulo: 'Cartão de crédito',
                            subtitulo: 'Pagamento seguro pelo app.',
                            icon: Icons.credit_card_rounded,
                            corIcone: diPertinRoxo,
                          ),
                          Divider(height: 1, color: Colors.grey.shade200),
                          _pagamentoOpcao(
                            value: 'Dinheiro',
                            titulo: 'Dinheiro na entrega',
                            subtitulo: 'Pague em espécie ao receber o pedido.',
                            icon: Icons.payments_outlined,
                            corIcone: diPertinLaranja,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_formaPagamento == 'Dinheiro') ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _precisaTrocoDinheiro,
                                  activeColor: diPertinRoxo,
                                  onChanged: (valor) {
                                    setState(() {
                                      _precisaTrocoDinheiro = valor ?? false;
                                      if (!_precisaTrocoDinheiro) {
                                        _trocoParaController.clear();
                                      }
                                    });
                                  },
                                ),
                                const Expanded(
                                  child: Text(
                                    'Precisa de troco?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_precisaTrocoDinheiro) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _trocoParaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Troco para quanto?',
                                  hintText: 'Ex.: 50,00',
                                  prefixText: 'R\$ ',
                                  filled: true,
                                  fillColor: const Color(0xFFF8F9FA),
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
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                    borderSide: BorderSide(
                                      color: diPertinRoxo,
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Essa informação será enviada para a loja.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],

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
                        if (!_retirarNaLoja)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                if (_calculandoTaxaEntrega)
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.route_outlined,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _calculandoTaxaEntrega
                                        ? 'Calculando frete pela tabela...'
                                        : (_detalheTaxaEntrega.isEmpty
                                              ? 'Frete pela tabela de fretes'
                                              : _detalheTaxaEntrega),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_cupomAplicado && _descontoCupom > 0) ...[
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
                                "- R\$ ${_descontoCupom.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_usarSaldo && valorDesconto > 0) ...[
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
                ],
              ),
            ),
      bottomSheet: carrinhoVazio
          ? null
          : Material(
              elevation: 12,
              color: Colors.white,
              shadowColor: Colors.black26,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'R\$ ${totalFinal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: diPertinRoxo,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: _alturaBarraCheckout,
                        child: ElevatedButton(
                          onPressed: _processandoPedido
                              ? null
                              : () => _avancarParaPagamento(cart),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: diPertinLaranja,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                  _textoBotaoCheckout(totalFinal),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                    height: 1.15,
                                  ),
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
}
