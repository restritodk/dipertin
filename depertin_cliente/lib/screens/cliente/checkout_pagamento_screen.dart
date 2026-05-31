// Arquivo: lib/screens/cliente/checkout_pagamento_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:depertin_cliente/providers/cart_provider.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/services/wallet_reserva_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

bool _statusPedidoPago(String status) {
  final st = status.trim();
  return st == 'pendente' || st == 'encomenda_entrada_paga';
}

/// Mensagem de recusa com texto específico para débito vs crédito (saldo/limite).
String mensagemRecusaCartaoParaCliente({
  required String mensagem,
  String? codigoRecusa,
  String? tipoCartaoSolicitado,
}) {
  final msg = mensagem.trim();
  if (msg.isEmpty) return 'Pagamento recusado. Tente novamente ou use outro meio.';
  final cod = (codigoRecusa ?? '').toLowerCase();
  final tipo = (tipoCartaoSolicitado ?? '').toLowerCase();
  final pareceInsuficiente =
      cod.contains('insufficient') ||
      cod == 'cc_rejected_insufficient_amount' ||
      msg.toLowerCase().contains('insuficiente') ||
      msg.toLowerCase().contains('saldo') ||
      msg.toLowerCase().contains('limite');
  if (pareceInsuficiente) {
    if (tipo == 'debito' || tipo == 'debit') {
      return 'Saldo insuficiente no débito para concluir este pagamento. '
          'Verifique a conta vinculada ao cartão ou use outro meio.';
    }
    if (tipo == 'credito' || tipo == 'credit') {
      return 'Limite ou saldo insuficiente no crédito para concluir este pagamento. '
          'Tente outro cartão ou use o PIX.';
    }
  }
  return msg;
}

/// Traduz códigos crus da callable (ex.: UNAVAILABLE) para texto claro ao usuário no checkout com cartão.
String mensagemAmigavelErroPagamentoCartao(
  FirebaseFunctionsException e, {
  String? tipoCartaoUi,
}) {
  final code = e.code.toLowerCase().trim();
  final raw = (e.message ?? '').trim();
  final rawUp = raw.toUpperCase();

  if (rawUp == 'UNAVAILABLE' || rawUp.contains('UNAVAILABLE')) {
    return 'Não foi possível conectar ao serviço de pagamento. Verifique sua internet e tente novamente em instantes.';
  }

  switch (code) {
    case 'unavailable':
      return 'Não foi possível conectar ao serviço de pagamento. Verifique sua internet e tente novamente em instantes.';
    case 'deadline-exceeded':
      return 'O pagamento demorou além do esperado e não foi concluído. Confira em Meus pedidos ou tente novamente.';
    case 'resource-exhausted':
      return 'O serviço de pagamento está temporariamente sobrecarregado. Aguarde um momento e tente de novo.';
    case 'unauthenticated':
      return 'Sua sessão não foi aceita pelo servidor. Faça login novamente e tente outra vez.';
    case 'permission-denied':
      return 'Acesso negado ao pagamento. Faça login novamente ou atualize o aplicativo.';
    case 'failed-precondition':
    case 'invalid-argument':
      if (raw.isNotEmpty && raw.length <= 500) {
        return mensagemRecusaCartaoParaCliente(
          mensagem: raw,
          tipoCartaoSolicitado: tipoCartaoUi == 'Débito' ? 'debito' : 'credito',
        );
      }
      return 'Não foi possível concluir o pagamento com cartão. Verifique os dados ou tente outro cartão.';
    case 'internal':
      return 'Erro interno no serviço de pagamento. Tente novamente em alguns minutos ou use o PIX.';
    default:
      if (raw.isNotEmpty &&
          rawUp != 'INTERNAL' &&
          !rawUp.contains('UNAVAILABLE') &&
          raw.length <= 500) {
        return raw;
      }
      return 'Não foi possível processar o pagamento com cartão. Tente novamente ou use outro meio de pagamento.';
  }
}

class CheckoutPagamentoScreen extends StatefulWidget {
  final double valorTotal;
  final String metodoPreSelecionado;
  final VoidCallback onPagamentoAprovado;

  /// Quando PIX: ID do documento em [pedidos] (pedido já criado como `aguardando_pagamento`).
  final String? pedidoFirestoreId;

  const CheckoutPagamentoScreen({
    super.key,
    required this.valorTotal,
    required this.metodoPreSelecionado,
    required this.onPagamentoAprovado,
    this.pedidoFirestoreId,
  });

  @override
  State<CheckoutPagamentoScreen> createState() =>
      _CheckoutPagamentoScreenState();
}

class _CheckoutPagamentoScreenState extends State<CheckoutPagamentoScreen> {
  late String _metodoAtual;
  bool _isProcessando = false;

  // Variáveis para o PIX Real
  bool _pixGerado = false;
  String _pixCopiaECola = "";

  /// Decodificado uma vez — evita rebuild do QR a cada tick do cronômetro.
  Uint8List? _pixQrImageBytes;
  dynamic _mpPaymentId;
  bool _aguardandoConfirmacaoPix = false;
  bool _pixConcluido = false;
  StreamSubscription? _pedidoSub;
  Timer? _pollTimer;
  int _polls = 0;
  static const int _maxPolls = 50;

  /// Prazo para pagar o PIX (alinhado ao servidor quando [pix_expira_em] existir).
  DateTime? _pixPrazoFim;
  bool _pixExpiradoJaTratado = false;
  static const int _pixPrazoMinutos = 5;

  // Controladores do Cartão
  final TextEditingController _numCartaoC = TextEditingController();
  final TextEditingController _nomeTitularC = TextEditingController();
  final TextEditingController _validadeC = TextEditingController();
  final TextEditingController _cvvC = TextEditingController();
  final TextEditingController _cpfTitularC = TextEditingController();

  // Bandeira do cartão
  String? _bandeiraCartao;
  String _tipoCartaoSelecionado = 'Crédito';

  Timer? _debounceParcelas;
  bool _consultandoParcelasNoMp = false;
  String? _erroOpcoesParcelas;
  List<_OpcaoParcelaCheckout> _opcoesParcelasMp = [];
  int? _parcelasEscolhidas;

  @override
  void initState() {
    super.initState();
    _metodoAtual = widget.metodoPreSelecionado == 'Cartão' ? 'Cartão' : 'PIX';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pixGerado || _metodoAtual != 'Cartão') return;
      _agendarAtualizacaoParcelasMercadoPago();
    });
  }

  @override
  void dispose() {
    _debounceParcelas?.cancel();
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    _numCartaoC.dispose();
    _nomeTitularC.dispose();
    _validadeC.dispose();
    _cvvC.dispose();
    _cpfTitularC.dispose();
    super.dispose();
  }

  String _formatarMoedaBrlCheckout(double valor) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(valor);

  String _mensagemErroParcelasAmigavel(FirebaseFunctionsException e) {
    final codigo = e.code.toLowerCase().trim();
    final msgRaw = (e.message ?? '').toLowerCase();
    if (codigo == 'unauthenticated' || msgRaw.contains('unauthenticated')) {
      return 'Para carregar parcelas é preciso validar o app com o App Check '
          'do Firebase. Em modo debug, registre o token de debug '
          '(Logcat/console) em Firebase Console → App Check para este app.';
    }
    if (codigo == 'permission-denied') {
      return 'Pedido não pertence ao seu usuário ou não está disponível.';
    }
    if (codigo == 'deadline-exceeded' || codigo == 'unavailable') {
      return 'Serviço temporariamente indisponível. Verifique sua conexão '
          'e toque em Atualizar parcelas.';
    }
    final m = e.message?.trim();
    return (m != null && m.isNotEmpty)
        ? m
        : 'Não foi possível carregar as parcelas.';
  }

  /// Decoração unificada dos campos da tela (visual mais sóbrio/profissional).
  InputDecoration _decorCheckoutCampo(
    String label, {
    String? hintText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: diPertinRoxo, width: 2),
      ),
    );
  }

  _OpcaoParcelaCheckout? _opcaoParcelaAtualOuNull() {
    final n = _parcelasParaCheckoutCartao();
    if (n == null || _opcoesParcelasMp.isEmpty) return null;
    for (final o in _opcoesParcelasMp) {
      if (o.parcelas == n) return o;
    }
    return _opcoesParcelasMp.first;
  }

  String _resumoLinhaParcelaAtual() {
    final o = _opcaoParcelaAtualOuNull();
    if (o == null) return '--';
    final t = o.textoLinha.trim();
    return t.isEmpty ? '--' : t;
  }

  Future<void> _abrirSeletorParcelasMercadoPago() async {
    if (_opcoesParcelasMp.isEmpty) return;
    final escolhaInicial =
        _parcelasEscolhidas ?? _opcoesParcelasMp.first.parcelas;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final altura = MediaQuery.sizeOf(context).height * 0.58;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              height: altura,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: Offset(0, -4),
                      color: Color(0x22000000),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            color: diPertinRoxo,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Escolha o parcelamento',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Os valores são informados pelo Mercado Pago para o seu cartão.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _opcoesParcelasMp.length,
                        itemBuilder: (_, index) {
                          final o = _opcoesParcelasMp[index];
                          final selec = escolhaInicial == o.parcelas;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            tileColor: selec
                                ? diPertinRoxo.withValues(alpha: 0.06)
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              selec
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_off_rounded,
                              color: selec
                                  ? diPertinRoxo
                                  : Colors.grey.shade400,
                            ),
                            title: Text(
                              o.textoLinha,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: selec
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              setState(() => _parcelasEscolhidas = o.parcelas);
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
        );
      },
    );
  }

  void _agendarAtualizacaoParcelasMercadoPago() {
    _debounceParcelas?.cancel();
    _debounceParcelas = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_atualizarParcelasMercadoPagoCheckout());
    });
  }

  /// Crédito: consulta o backend (Mercado Pago). Débito: só à vista no estado local.
  Future<void> _atualizarParcelasMercadoPagoCheckout() async {
    if (_metodoAtual != 'Cartão') return;

    final pedidoId = widget.pedidoFirestoreId?.trim();
    final digitos = _somenteDigitos(_numCartaoC.text);
    final pmid = digitos.length >= 6
        ? _resolverPaymentMethodIdCartao(digitos)
        : null;

    if (pedidoId == null || pedidoId.isEmpty) {
      return;
    }

    if (digitos.length < 6) {
      setState(() {
        _opcoesParcelasMp = [];
        _parcelasEscolhidas = null;
        _erroOpcoesParcelas = null;
        _consultandoParcelasNoMp = false;
      });
      return;
    }

    if (_tipoCartaoSelecionado == 'Débito') {
      final v = widget.valorTotal;
      setState(() {
        _consultandoParcelasNoMp = false;
        _erroOpcoesParcelas = null;
        _opcoesParcelasMp = [
          _OpcaoParcelaCheckout(
            parcelas: 1,
            valorParcela: v,
            valorTotalCobrado: v,
            textoLinha:
                '1x de ${_formatarMoedaBrlCheckout(v)} (débito à vista)',
          ),
        ];
        _parcelasEscolhidas = 1;
      });
      return;
    }

    setState(() {
      _consultandoParcelasNoMp = true;
      _erroOpcoesParcelas = null;
    });

    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'mpConsultarParcelamentosCartao',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final payload = <String, dynamic>{
        'pedidoId': pedidoId,
        'bin': digitos.length > 16 ? digitos.substring(0, 16) : digitos,
        'tipoCartao': 'credito',
      };
      if (pmid != null) {
        payload['paymentMethodId'] = pmid;
      }
      final resposta = await callable.call<Map<String, dynamic>>(payload);

      final data = Map<String, dynamic>.from(resposta.data);
      final rawLista = data['opcoes'];
      final lista = <_OpcaoParcelaCheckout>[];
      if (rawLista is List) {
        for (final item in rawLista) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          lista.add(_OpcaoParcelaCheckout.doMapMercadoPago(m));
        }
      }
      if (!mounted) return;

      List<_OpcaoParcelaCheckout> opcoesFinais = lista;
      if (opcoesFinais.isEmpty) {
        final v = widget.valorTotal;
        opcoesFinais = [
          _OpcaoParcelaCheckout(
            parcelas: 1,
            valorParcela: v,
            valorTotalCobrado: v,
            textoLinha:
                '1x de ${_formatarMoedaBrlCheckout(v)} (crédito à vista)',
          ),
        ];
      }

      opcoesFinais.sort((a, b) => a.parcelas.compareTo(b.parcelas));

      setState(() {
        _consultandoParcelasNoMp = false;
        _opcoesParcelasMp = opcoesFinais;
        final idsValidos = opcoesFinais.map((o) => o.parcelas).toSet();
        if (_parcelasEscolhidas != null &&
            idsValidos.contains(_parcelasEscolhidas)) {
          // mantém escolha
        } else {
          _parcelasEscolhidas = opcoesFinais.first.parcelas;
        }
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = _mensagemErroParcelasAmigavel(e);
      setState(() {
        _consultandoParcelasNoMp = false;
        _erroOpcoesParcelas = msg;
        _opcoesParcelasMp = [];
        _parcelasEscolhidas = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consultandoParcelasNoMp = false;
        _erroOpcoesParcelas = 'Falha ao consultar parcelas: $e';
        _opcoesParcelasMp = [];
        _parcelasEscolhidas = null;
      });
    }
  }

  int? _parcelasParaCheckoutCartao() {
    if (_tipoCartaoSelecionado == 'Débito') return 1;
    if (_opcoesParcelasMp.isEmpty) return null;
    final validos = _opcoesParcelasMp.map((o) => o.parcelas).toSet();
    if (_parcelasEscolhidas != null && validos.contains(_parcelasEscolhidas)) {
      return _parcelasEscolhidas!;
    }
    return _opcoesParcelasMp.first.parcelas;
  }

  bool _habilitarBotaoPagarInferiorCheckout() {
    if (_pixGerado || _metodoAtual != 'Cartão') return true;
    if (_tipoCartaoSelecionado == 'Crédito') {
      return !_consultandoParcelasNoMp &&
          _erroOpcoesParcelas == null &&
          _parcelasParaCheckoutCartao() != null;
    }
    return !_consultandoParcelasNoMp;
  }

  bool get _temPedidoFirestore =>
      widget.pedidoFirestoreId != null &&
      widget.pedidoFirestoreId!.trim().isNotEmpty;

  void _aplicarPixExpiraEmDoDoc(Map<String, dynamic>? d) {
    if (d == null) return;
    final ts = d['pix_expira_em'];
    if (ts is Timestamp) {
      _pixPrazoFim = ts.toDate();
    }
  }

  void _handlePixExpiradoServidor() {
    if (_pixExpiradoJaTratado || _pixConcluido) return;
    _pixExpiradoJaTratado = true;
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Prazo do PIX expirou. O pedido foi cancelado automaticamente.',
        ),
        backgroundColor: Colors.red,
      ),
    );
    Navigator.of(context).pop();
  }

  void _handlePedidoCanceladoPeloClienteNoPix() {
    if (_pixExpiradoJaTratado || _pixConcluido) return;
    _pixExpiradoJaTratado = true;
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Este pedido foi cancelado. O PIX não será mais aceito.'),
        backgroundColor: Colors.red,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _onPrazoPixEsgotado() async {
    if (_pixExpiradoJaTratado || !mounted || _pixConcluido) return;
    _pixExpiradoJaTratado = true;
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    final pid = widget.pedidoFirestoreId?.trim();
    if (pid != null && pid.isNotEmpty) {
      try {
        final callable = appFirebaseFunctions.httpsCallable(
          'cancelarPedidoPixExpirado',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
        );
        await callable.call(<String, dynamic>{'pedidoId': pid});
      } on FirebaseFunctionsException catch (e) {
        debugPrint('cancelarPedidoPixExpirado: ${e.code} ${e.message}');
      } catch (e) {
        debugPrint('cancelarPedidoPixExpirado: $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Prazo do PIX expirou. O pedido foi cancelado automaticamente.',
        ),
        backgroundColor: Colors.red,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _vincularPixNoServidor({bool silencioso = false}) async {
    final pid = widget.pedidoFirestoreId;
    if (pid == null || pid.isEmpty || _mpPaymentId == null) return;
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'mpVincularPagamentoPix',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      await callable.call(<String, dynamic>{
        'pedidoId': pid,
        'paymentId': _mpPaymentId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('mpVincularPagamentoPix: ${e.code} ${e.message}');
      if (mounted && !silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ??
                  'Não foi possível sincronizar o pagamento. Tente "Verificar agora".',
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      debugPrint('mpVincularPagamentoPix: $e');
    }
    if (!mounted || _pixConcluido) return;
    final snap = await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pid)
        .get();
    final status = (snap.data()?['status'] ?? '').toString();
    if (snap.exists && _statusPedidoPago(status)) {
      _finalizarPixComSucesso();
    }
  }

  void _iniciarEscutaPedidoEPolling() {
    final pid = widget.pedidoFirestoreId;
    if (pid == null || pid.isEmpty || _pixConcluido) return;

    _pedidoSub?.cancel();
    _pedidoSub = FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pid)
        .snapshots()
        .listen((snap) {
          if (!snap.exists || _pixConcluido || _pixExpiradoJaTratado) return;
          final d = snap.data();
          if (d == null) return;
          _aplicarPixExpiraEmDoDoc(d);
          if (d['status'] == 'cancelado') {
            final motivo = d['cancelado_motivo']?.toString();
            if (motivo == 'pix_expirado') {
              _handlePixExpiradoServidor();
              return;
            }
            if (motivo == 'cliente_cancelou_pix') {
              _handlePedidoCanceladoPeloClienteNoPix();
              return;
            }
          }
          if (_statusPedidoPago((d['status'] ?? '').toString())) {
            _finalizarPixComSucesso();
          }
        });

    _pollTimer?.cancel();
    _polls = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (t) async {
      if (_pixConcluido || !mounted) {
        t.cancel();
        return;
      }
      _polls++;
      if (_polls > _maxPolls) {
        t.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ainda não detectamos o pagamento. Toque em "Verificar agora" '
                'ou aguarde a confirmação automática.',
              ),
              backgroundColor: diPertinRoxo,
            ),
          );
        }
        return;
      }
      await _vincularPixNoServidor(silencioso: true);
      if (_pixConcluido) {
        t.cancel();
      }
    });
  }

  /// Esvazia a sacola de pronta-entrega após pagamento confirmado (não mexe em
  /// itens de encomenda nem em checkout de pedido `tipo_compra: encomenda`).
  Future<void> _limparCarrinhoProntaEntregaSeAplicavel() async {
    final pid = widget.pedidoFirestoreId?.trim() ?? '';
    if (pid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pid)
          .get();
      final tipo = (snap.data()?['tipo_compra'] ?? '').toString();
      if (tipo == 'encomenda') return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await context.read<CartProvider>().removerItensPorTipo(encomenda: false);
  }

  Future<void> _finalizarPixComSucesso() async {
    if (_pixConcluido || !mounted) return;
    _pixConcluido = true;
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    await _finalizarPagamentoAprovado();
  }

  /// Aprovação: confirma saldo reservado, limpa carrinho (pronta-entrega) e vai a Meus Pedidos.
  Future<void> _finalizarPagamentoAprovado() async {
    await _confirmarReservaDeSaldo();
    await _limparCarrinhoProntaEntregaSeAplicavel();
    if (!mounted) return;
    widget.onPagamentoAprovado();
  }

  /// Confirma a reserva de saldo após aprovação de pagamento
  Future<void> _confirmarReservaDeSaldo() async {
    try {
      if (!_temPedidoFirestore) return;

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Lê o pedido para obter o reservaId
      final docSnapshot = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoFirestoreId)
          .get();

      if (!docSnapshot.exists) return;

      final reservaId = docSnapshot.data()?['reserva_id_saldo'] as String?;
      if (reservaId == null || reservaId.isEmpty) {
        // Sem reserva, nada a confirmar
        return;
      }

      // Confirma o débito da carteira
      await WalletReservaService.confirmarDebito(
        userId: userId,
        reservaId: reservaId,
      );

      if (mounted) {
        debugPrint(
          '[CheckoutPagamento] Débito de saldo confirmado: $reservaId',
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('[CheckoutPagamento] Erro ao confirmar débito: $e');
        // Não interrompe o fluxo, apenas loga
      }
    }
  }

  /// Cancela a reserva de saldo em caso de falha de pagamento
  Future<void> _cancelarReservaDeSaldo({
    String motivo = 'Pagamento não aprovado',
  }) async {
    try {
      if (!_temPedidoFirestore) return;

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      // Lê o pedido para obter o reservaId
      final docSnapshot = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoFirestoreId)
          .get();

      if (!docSnapshot.exists) return;

      final reservaId = docSnapshot.data()?['reserva_id_saldo'] as String?;
      if (reservaId == null || reservaId.isEmpty) {
        // Sem reserva, nada a cancelar
        return;
      }

      // Cancela a reserva e restaura o saldo
      await WalletReservaService.cancelarReserva(
        userId: userId,
        reservaId: reservaId,
        motivo: motivo,
      );

      if (mounted) {
        debugPrint(
          '[CheckoutPagamento] Reserva de saldo cancelada: $reservaId',
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('[CheckoutPagamento] Erro ao cancelar reserva: $e');
        // Não interrompe o fluxo, apenas loga
      }
    }
  }

  String _somenteDigitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  /// Valida CPF pelo algoritmo oficial (dois dígitos verificadores).
  /// O Mercado Pago rejeita pagamentos com CPFs que não passam nessa conferência
  /// retornando "Invalid user identification number".
  bool _cpfValido(String cpf) {
    final digitos = _somenteDigitos(cpf);
    if (digitos.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digitos)) return false;
    int calcDigito(int ate) {
      int soma = 0;
      for (int i = 0; i < ate; i++) {
        soma += int.parse(digitos[i]) * ((ate + 1) - i);
      }
      final resto = (soma * 10) % 11;
      return resto == 10 ? 0 : resto;
    }

    return calcDigito(9) == int.parse(digitos[9]) &&
        calcDigito(10) == int.parse(digitos[10]);
  }

  ({int mes, int ano})? _parseValidadeCartao(String valor) {
    final partes = valor.split('/');
    if (partes.length != 2) return null;
    final mes = int.tryParse(_somenteDigitos(partes[0])) ?? 0;
    final anoRaw = int.tryParse(_somenteDigitos(partes[1])) ?? 0;
    if (mes < 1 || mes > 12 || anoRaw <= 0) return null;
    final ano = anoRaw < 100 ? 2000 + anoRaw : anoRaw;
    final agora = DateTime.now();
    final fimDoMesCartao = DateTime(ano, mes + 1, 0, 23, 59, 59);
    if (fimDoMesCartao.isBefore(agora)) return null;
    return (mes: mes, ano: ano);
  }

  String? _resolverPaymentMethodIdCartao(String numeroCartao) {
    final bandeira = _bandeiraCartao?.toLowerCase().trim() ?? '';
    if (bandeira.contains('visa')) return 'visa';
    if (bandeira.contains('master')) return 'master';
    if (bandeira.contains('american')) return 'amex';
    if (bandeira.contains('elo')) return 'elo';
    if (bandeira.contains('hipercard')) return 'hipercard';
    if (bandeira.contains('diners')) return 'diners';

    // Fallback simples por BIN para evitar bloqueio quando a lib não detecta.
    if (numeroCartao.startsWith('4')) return 'visa';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(numeroCartao)) return 'master';
    if (RegExp(r'^3[47]').hasMatch(numeroCartao)) return 'amex';
    return null;
  }

  Future<String> _aguardarConclusaoPedidoCartao(
    String pedidoId, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription sub;
    Timer? timer;

    sub = FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pedidoId)
        .snapshots()
        .listen((snap) {
          if (!snap.exists || completer.isCompleted) return;
          final data = snap.data() ?? {};
          final status = (data['status'] ?? '').toString();
          if (_statusPedidoPago(status)) {
            completer.complete('aprovado');
            return;
          }
          final mpStatus = (data['mp_status'] ?? '').toString().toLowerCase();
          if (mpStatus == 'rejected') {
            completer.complete('recusado');
            return;
          }
          final msgRecusa =
              (data['pagamento_recusado_mensagem'] ?? '').toString().trim();
          if (status == 'aguardando_pagamento' && msgRecusa.isNotEmpty) {
            completer.complete('recusado');
            return;
          }
          if (status == 'cancelado') {
            completer.complete('cancelado');
          }
        });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete('timeout');
    });

    final resultado = await completer.future;
    await sub.cancel();
    timer.cancel();
    return resultado;
  }

  Future<String> _mensagemRecusaDoPedido(String pedidoId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .get();
      final d = snap.data() ?? const <String, dynamic>{};
      final msg =
          (d['pagamento_recusado_mensagem'] ?? d['mp_erro_detalhe'] ?? '')
              .toString()
              .trim();
      final cod = (d['pagamento_recusado_codigo'] ?? '').toString();
      final tipo = (d['pagamento_cartao_tipo_solicitado'] ?? '').toString();
      if (msg.isNotEmpty) {
        return mensagemRecusaCartaoParaCliente(
          mensagem: msg,
          codigoRecusa: cod,
          tipoCartaoSolicitado: tipo.isNotEmpty
              ? tipo
              : (_tipoCartaoSelecionado == 'Débito' ? 'debito' : 'credito'),
        );
      }
    } catch (_) {}
    return mensagemRecusaCartaoParaCliente(
      mensagem: 'Pagamento recusado pelo provedor. Tente outro cartão.',
      tipoCartaoSolicitado:
          _tipoCartaoSelecionado == 'Débito' ? 'debito' : 'credito',
    );
  }

  String _tipoCartaoCallable() =>
      _tipoCartaoSelecionado == 'Débito' ? 'debito' : 'credito';

  Future<void> _mostrarPopupPagamentoRecusado(String mensagem) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            const Expanded(child: Text('Pagamento recusado')),
          ],
        ),
        content: Text(mensagem),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: diPertinRoxo),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarPopupPagamentoEmAnalise() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.hourglass_top, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Pagamento em análise')),
          ],
        ),
        content: const Text(
          'O Mercado Pago está analisando seu pagamento. Isso pode levar alguns '
          'minutos. Você pode aguardar nesta tela ou acompanhar em Meus Pedidos.',
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: diPertinRoxo),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _processarPagamentoCartao() async {
    final pedidoId = widget.pedidoFirestoreId?.trim();
    if (pedidoId == null || pedidoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido inválido para pagamento com cartão.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final numeroCartao = _somenteDigitos(_numCartaoC.text);
    final nomeTitular = _nomeTitularC.text.trim().toUpperCase();
    final cvv = _somenteDigitos(_cvvC.text);
    final cpf = _somenteDigitos(_cpfTitularC.text);
    final validade = _parseValidadeCartao(_validadeC.text);
    final paymentMethodId = _resolverPaymentMethodIdCartao(numeroCartao);

    if (numeroCartao.length < 13 || nomeTitular.isEmpty || cvv.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha corretamente os dados do cartão.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_cpfValido(cpf)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CPF do titular inválido. Verifique os números digitados.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (validade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Validade do cartão inválida ou expirada. Use o formato MM/AA.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (paymentMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar a bandeira do cartão.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final parcelasEnvioCheckout = _parcelasParaCheckoutCartao();
    if (_tipoCartaoSelecionado == 'Crédito' && parcelasEnvioCheckout == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escolha o parcelamento ou aguarde o carregamento das opções.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessando = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PagamentoAguardandoDialog(),
    );

    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'mpProcessarPagamentoCartao',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 180)),
      );
      final resposta = await callable.call<Map<String, dynamic>>({
        'pedidoId': pedidoId,
        'numeroCartao': numeroCartao,
        'nomeTitular': nomeTitular,
        'mesExpiracao': validade.mes,
        'anoExpiracao': validade.ano,
        'cvv': cvv,
        'cpf': cpf,
        'paymentMethodId': paymentMethodId,
        'tipoCartao': _tipoCartaoSelecionado == 'Débito' ? 'debito' : 'credito',
        'parcelas': parcelasEnvioCheckout ?? 1,
        'email': FirebaseAuth.instance.currentUser?.email,
      });

      final data = Map<String, dynamic>.from(resposta.data);
      final statusMp = (data['mp_status'] ?? '').toString().toLowerCase();
      final aprovadoDireto =
          statusMp == 'approved' || statusMp == 'authorized';

      if (statusMp == 'rejected') {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await _cancelarReservaDeSaldo(motivo: 'Pagamento recusado');
        final msgRaw =
            (data['pagamento_recusado_mensagem'] ?? data['message'] ?? '')
                .toString()
                .trim();
        final msg = msgRaw.isNotEmpty
            ? mensagemRecusaCartaoParaCliente(
                mensagem: msgRaw,
                tipoCartaoSolicitado: _tipoCartaoCallable(),
              )
            : await _mensagemRecusaDoPedido(pedidoId);
        await _mostrarPopupPagamentoRecusado(msg);
        return;
      }

      if (aprovadoDireto) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await _finalizarPagamentoAprovado();
        return;
      }

      // Em status intermediário, aguarda sincronização no pedido.
      final resultado = await _aguardarConclusaoPedidoCartao(pedidoId);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (resultado == 'aprovado') {
        await _finalizarPagamentoAprovado();
      } else if (resultado == 'recusado' || resultado == 'cancelado') {
        await _cancelarReservaDeSaldo(motivo: 'Pagamento recusado');
        final msg = await _mensagemRecusaDoPedido(pedidoId);
        await _mostrarPopupPagamentoRecusado(msg);
      } else {
        // Timeout: pagamento ainda em análise no Mercado Pago.
        final statusPedido = statusMp.isNotEmpty ? statusMp : 'in_process';
        final emAnalise =
            statusPedido == 'in_process' || statusPedido == 'pending';
        if (emAnalise) {
          await _mostrarPopupPagamentoEmAnalise();
        } else {
          await _cancelarReservaDeSaldo(motivo: 'Pagamento não concluído');
          final msg = await _mensagemRecusaDoPedido(pedidoId);
          await _mostrarPopupPagamentoRecusado(msg);
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final msgErro = mensagemAmigavelErroPagamentoCartao(
        e,
        tipoCartaoUi: _tipoCartaoSelecionado,
      );
      await _cancelarReservaDeSaldo(
        motivo: 'Erro ao processar pagamento: ${e.code}',
      );
      await _mostrarPopupPagamentoRecusado(msgErro);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      const msgErro =
          'Ocorreu um erro inesperado ao processar o cartão. Tente novamente ou escolha PIX.';
      await _cancelarReservaDeSaldo(motivo: 'Exceção ao processar: $e');
      await _mostrarPopupPagamentoRecusado(msgErro);
    } finally {
      if (mounted) setState(() => _isProcessando = false);
    }
  }

  // === MÁGICA REAL: COMUNICAÇÃO COM O MERCADO PAGO ===
  Future<void> _processarPagamento() async {
    if (_metodoAtual == 'Cartão') {
      await _processarPagamentoCartao();
      return;
    }

    // === GERAÇÃO DE PIX VIA BACKEND (sem token no app) ===
    setState(() => _isProcessando = true);

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isProcessando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sua sessão expirou. Faça login novamente para gerar o PIX.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    String emailCliente = user.email ?? "cliente@depertin.com";

    try {
      await user.getIdToken(true);

      final pid = widget.pedidoFirestoreId?.trim() ?? '';
      if (pid.isEmpty) {
        setState(() => _isProcessando = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido inválido para geração de PIX.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final callable = appFirebaseFunctions.httpsCallable(
        'mpCriarPagamentoPix',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final response = await callable.call(<String, dynamic>{
        'pedidoId': pid,
        'email': emailCliente,
      });
      final dados = Map<String, dynamic>.from(response.data);

      if (!mounted) return;

      _mpPaymentId = dados['paymentId'];
      if (_mpPaymentId == null) {
        setState(() => _isProcessando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erro do provedor: ${dados['message'] ?? 'Falha ao gerar PIX'}",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _pixCopiaECola = dados['qr_code']?.toString() ?? '';
        final b64 = dados['qr_code_base64']?.toString() ?? '';
        _pixQrImageBytes = b64.isNotEmpty ? base64Decode(b64) : null;
        _pixGerado = true;
        _isProcessando = false;
        _aguardandoConfirmacaoPix = true;
        if (_temPedidoFirestore) {
          _pixPrazoFim = DateTime.now().add(
            const Duration(minutes: _pixPrazoMinutos),
          );
        }
      });

      await _vincularPixNoServidor(silencioso: true);
      if (!mounted) return;
      final snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pid)
          .get();
      _aplicarPixExpiraEmDoDoc(snap.data());
      if (mounted) setState(() {});
      _iniciarEscutaPedidoEPolling();
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isProcessando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Não foi possível gerar o PIX no servidor.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      setState(() => _isProcessando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro de conexão: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const checkoutFundo = Color(0xFFF4F2F9);
    return Scaffold(
      backgroundColor: checkoutFundo,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Pagamento seguro',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  diPertinRoxo,
                  diPertinRoxo.withValues(alpha: 0.94),
                  checkoutFundo,
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, _pixGerado ? 14 : 6),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ],
                      border: Border.all(
                        color: diPertinRoxo.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Total a pagar',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatarMoedaBrlCheckout(widget.valorTotal),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: diPertinLaranja,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_pixGerado) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => setState(() => _metodoAtual = 'PIX'),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _metodoAtual == 'PIX'
                                      ? Colors.green.shade600
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    if (_metodoAtual == 'PIX')
                                      BoxShadow(
                                        blurRadius: 16,
                                        color: Colors.green.withValues(
                                          alpha: 0.35,
                                        ),
                                        offset: const Offset(0, 8),
                                      ),
                                  ],
                                  border: Border.all(
                                    color: _metodoAtual == 'PIX'
                                        ? Colors.transparent
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.qr_code_2_rounded,
                                      color: _metodoAtual == 'PIX'
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'PIX',
                                      style: TextStyle(
                                        color: _metodoAtual == 'PIX'
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                setState(() => _metodoAtual = 'Cartão');
                                _agendarAtualizacaoParcelasMercadoPago();
                              },
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _metodoAtual == 'Cartão'
                                      ? diPertinLaranja
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    if (_metodoAtual == 'Cartão')
                                      BoxShadow(
                                        blurRadius: 16,
                                        color: diPertinLaranja.withValues(
                                          alpha: 0.35,
                                        ),
                                        offset: const Offset(0, 8),
                                      ),
                                  ],
                                  border: Border.all(
                                    color: _metodoAtual == 'Cartão'
                                        ? Colors.transparent
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.credit_card_rounded,
                                      color: _metodoAtual == 'Cartão'
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Cartão',
                                      style: TextStyle(
                                        color: _metodoAtual == 'Cartão'
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: _pixGerado
                  ? _buildPixGeradoOficial()
                  : (_metodoAtual == 'PIX'
                        ? _buildAbaPix()
                        : _buildAbaCartao()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _pixGerado
          ? null // Se gerou o pix, tira o botão de baixo para o usuário focar em pagar
          : Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed:
                      (_isProcessando ||
                          !_habilitarBotaoPagarInferiorCheckout())
                      ? null
                      : _processarPagamento,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _metodoAtual == 'PIX'
                        ? Colors.green
                        : diPertinLaranja,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isProcessando
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 15),
                            Text(
                              "Processando...",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _metodoAtual == 'PIX'
                              ? "GERAR CÓDIGO PIX"
                              : "PAGAR R\$ ${widget.valorTotal.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
    );
  }

  // === VISUAL DA ABA PIX (INICIAL) ===
  Widget _buildAbaPix() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Column(
        children: [
          Icon(Icons.pix, size: 60, color: Colors.green),
          SizedBox(height: 15),
          Text(
            "Pagamento Rápido e Seguro",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 10),
          Text(
            "Ao clicar no botão abaixo, vamos conectar com o Mercado Pago e gerar um código Copia e Cola exclusivo para o seu pedido.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // === VISUAL DO PIX GERADO E PRONTO PARA PAGAR ===
  Widget _buildPixGeradoOficial() {
    return Column(
      children: [
        const Text(
          "Pague via PIX para confirmar",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          "O seu pedido só será enviado para a loja após o pagamento.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        if (_temPedidoFirestore && _pixPrazoFim != null) ...[
          const SizedBox(height: 16),
          _PixCronometroBanner(
            key: ValueKey(_pixPrazoFim!.millisecondsSinceEpoch),
            prazoFim: _pixPrazoFim,
            onExpirado: () {
              unawaited(_onPrazoPixEsgotado());
            },
          ),
        ],
        const SizedBox(height: 20),

        // QR: bytes em cache — o cronômetro não reconstrói esta árvore.
        if (_pixQrImageBytes != null && _pixQrImageBytes!.isNotEmpty)
          RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Image.memory(
                _pixQrImageBytes!,
                width: 180,
                height: 180,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),

        const SizedBox(height: 20),

        // BOTÃO COPIA E COLA
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Pix Copia e Cola",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (_pixCopiaECola.isNotEmpty) ...[
                SelectableText(
                  _pixCopiaECola,
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pixCopiaECola.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(
                                ClipboardData(text: _pixCopiaECola),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Código copiado com sucesso'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                      icon: const Icon(Icons.copy, color: Colors.white),
                      label: const Text(
                        'Copiar código',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar',
                    icon: const Icon(Icons.copy, color: Colors.green),
                    onPressed: _pixCopiaECola.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: _pixCopiaECola),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Código copiado com sucesso'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),

        if (_aguardandoConfirmacaoPix) ...[
          const SizedBox(height: 20),
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: diPertinRoxo,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Aguardando confirmação automática do Mercado Pago…\n'
            'Você pode fechar esta tela depois de pagar; o pedido atualiza sozinho.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _pixConcluido
                ? null
                : () async {
                    await _vincularPixNoServidor();
                    if (!mounted) return;
                    if (!_pixConcluido) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pagamento ainda não confirmado. '
                            'Aguarde ou confira se o PIX foi enviado corretamente.',
                          ),
                          backgroundColor: diPertinRoxo,
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.sync_rounded, color: diPertinRoxo),
            style: OutlinedButton.styleFrom(
              foregroundColor: diPertinRoxo,
              side: const BorderSide(color: diPertinRoxo),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            label: const Text(
              'VERIFICAR AGORA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // === VISUAL DA ABA CARTÃO (AGORA COM FORMATAÇÃO E BANDEIRA) ===
  Widget _buildAbaCartao() {
    // Retorna a imagem da bandeira baseada na detecção do pacote (Agora usando Strings!)
    Widget iconeBandeira = const Icon(Icons.credit_card, color: diPertinRoxo);
    if (_bandeiraCartao == 'Visa') {
      iconeBandeira = Image.network(
        'https://www.visa.com/api/image-proxy?path=%2Fcontent%2Fdam%2Fvisa%2Fheader%2FVectorBlue.png',
        width: 30,
      );
    } else if (_bandeiraCartao == 'Mastercard') {
      iconeBandeira = Image.network(
        'https://www.mastercard.com/adobe/dynamicmedia/deliver/dm-aid--e81464e9-325f-4fe7-b7b3-6697e9719bd7/mastercard.png?preferwebp=true&quality=82',
        width: 30,
      );
    } else if (_bandeiraCartao == 'American Express') {
      iconeBandeira = Image.network(
        'https://www.aexp-static.com/cdaas/one/statics/axp-static-assets/1.8.0/package/dist/img/logos/dls-logo-bluebox-solid.svg',
        width: 30,
      );
    } else if (_bandeiraCartao == 'Elo') {
      iconeBandeira = Image.network(
        'https://media.elo.com.br/strapi-hml/principal_brand_bw_desk_66cc99bc42.png',
        width: 30,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dados do cartão',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: Colors.grey.shade900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Crédito'),
              selectedColor: diPertinRoxo.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: _tipoCartaoSelecionado == 'Crédito'
                    ? diPertinRoxo
                    : Colors.grey.shade700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _tipoCartaoSelecionado == 'Crédito'
                      ? diPertinRoxo
                      : Colors.grey.shade300,
                ),
              ),
              showCheckmark: true,
              selected: _tipoCartaoSelecionado == 'Crédito',
              onSelected: (_) {
                setState(() => _tipoCartaoSelecionado = 'Crédito');
                _agendarAtualizacaoParcelasMercadoPago();
              },
            ),
            ChoiceChip(
              label: const Text('Débito'),
              selectedColor: diPertinRoxo.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: _tipoCartaoSelecionado == 'Débito'
                    ? diPertinRoxo
                    : Colors.grey.shade700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _tipoCartaoSelecionado == 'Débito'
                      ? diPertinRoxo
                      : Colors.grey.shade300,
                ),
              ),
              showCheckmark: true,
              selected: _tipoCartaoSelecionado == 'Débito',
              onSelected: (_) {
                setState(() => _tipoCartaoSelecionado = 'Débito');
                _agendarAtualizacaoParcelasMercadoPago();
              },
            ),
          ],
        ),
        const SizedBox(height: 15),

        TextFormField(
          controller: _numCartaoC,
          keyboardType: TextInputType.number,
          inputFormatters: [CreditCardNumberInputFormatter()],
          onChanged: (valor) {
            setState(() {
              _bandeiraCartao = getCardSystemData(valor)?.system;
            });
            _agendarAtualizacaoParcelasMercadoPago();
          },
          decoration: _decorCheckoutCampo(
            'Número do cartão',
            hintText: '0000 0000 0000 0000',
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12.0),
              child: iconeBandeira,
            ),
          ),
        ),
        const SizedBox(height: 15),

        TextFormField(
          controller: _nomeTitularC,
          textCapitalization: TextCapitalization.characters,
          decoration: _decorCheckoutCampo(
            'Nome impresso no cartão',
            prefixIcon: const Icon(Icons.person_outline, color: diPertinRoxo),
          ),
        ),
        const SizedBox(height: 15),

        TextFormField(
          controller: _cpfTitularC,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: _decorCheckoutCampo(
            'CPF do titular',
            hintText: 'Somente números',
            prefixIcon: const Icon(Icons.badge_outlined, color: diPertinRoxo),
          ),
        ),
        const SizedBox(height: 15),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _validadeC,
                keyboardType: TextInputType.number,
                inputFormatters: [CreditCardExpirationDateFormatter()],
                decoration: _decorCheckoutCampo('Validade', hintText: 'MM/AA'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextFormField(
                controller: _cvvC,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [CreditCardCvcInputFormatter()],
                decoration: _decorCheckoutCampo('CVV', hintText: '•••'),
              ),
            ),
          ],
        ),

        if (_tipoCartaoSelecionado == 'Crédito')
          Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_consultandoParcelasNoMp) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Consultando opções para o seu cartão…',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_erroOpcoesParcelas != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _erroOpcoesParcelas!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _consultandoParcelasNoMp
                                ? null
                                : () {
                                    _agendarAtualizacaoParcelasMercadoPago();
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text(
                              'Atualizar parcelas',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (_somenteDigitos(_numCartaoC.text).length < 6)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.credit_card_outlined,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Digite o número completo para ver e escolher o parcelamento.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap:
                          _opcoesParcelasMp.isEmpty || _consultandoParcelasNoMp
                          ? null
                          : _abrirSeletorParcelasMercadoPago,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                _opcoesParcelasMp.isEmpty &&
                                    _somenteDigitos(_numCartaoC.text).length >=
                                        6
                                ? Colors.orange.shade200
                                : diPertinRoxo.withValues(alpha: 0.22),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: diPertinRoxo.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: diPertinRoxo,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _opcoesParcelasMp.isEmpty &&
                                            _somenteDigitos(
                                                  _numCartaoC.text,
                                                ).length >=
                                                6
                                        ? 'Aguardando dados do parcelamento…'
                                        : 'Toque para escolher as parcelas',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.05,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _resumoLinhaParcelaAtual(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_opcoesParcelasMp.length > 1)
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.grey.shade700,
                                size: 30,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_somenteDigitos(_numCartaoC.text).length >= 6 &&
                      _opcoesParcelasMp.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        icon: Icon(
                          Icons.tune_rounded,
                          color: diPertinRoxo,
                          size: 22,
                        ),
                        label: const Text(
                          'Ver todas as opções',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => _abrirSeletorParcelasMercadoPago(),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

        const SizedBox(height: 22),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 14, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              'Pagamento criptografado · Mercado Pago',
              style: TextStyle(
                fontSize: 11.8,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opções de parcelamento (valores vindos da consulta Mercado Pago na Cloud Function).
class _OpcaoParcelaCheckout {
  final int parcelas;
  final double valorParcela;
  final double valorTotalCobrado;
  final String textoLinha;

  _OpcaoParcelaCheckout({
    required this.parcelas,
    required this.valorParcela,
    required this.valorTotalCobrado,
    required this.textoLinha,
  });

  factory _OpcaoParcelaCheckout.doMapMercadoPago(Map<String, dynamic> m) {
    final p = (m['parcelas'] as num?)?.toInt() ?? 1;
    final vp = (m['valorParcela'] as num?)?.toDouble() ?? 0;
    final vt = (m['valorTotalCobrado'] as num?)?.toDouble() ?? vp;
    var texto = (m['texto'] ?? '').toString().trim();
    if (texto.isEmpty) {
      final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
      texto = '${p}x de ${nf.format(vp)} · total ${nf.format(vt)}';
    }
    return _OpcaoParcelaCheckout(
      parcelas: p,
      valorParcela: vp,
      valorTotalCobrado: vt,
      textoLinha: texto,
    );
  }
}

class _PagamentoAguardandoDialog extends StatelessWidget {
  const _PagamentoAguardandoDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aguardando confirmação do pagamento',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Seu cartão está sendo validado com segurança pelo Mercado Pago.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cronômetro isolado: [setState] só aqui — o QR e o restante da tela não piscam.
class _PixCronometroBanner extends StatefulWidget {
  final DateTime? prazoFim;
  final VoidCallback onExpirado;

  const _PixCronometroBanner({
    super.key,
    required this.prazoFim,
    required this.onExpirado,
  });

  @override
  State<_PixCronometroBanner> createState() => _PixCronometroBannerState();
}

class _PixCronometroBannerState extends State<_PixCronometroBanner> {
  Timer? _timer;
  bool _expiradoEnviado = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final fim = widget.prazoFim;
    if (fim == null) return;
    final s = fim.difference(DateTime.now()).inSeconds;
    if (s <= 0) {
      _timer?.cancel();
      if (!_expiradoEnviado) {
        _expiradoEnviado = true;
        widget.onExpirado();
      }
      return;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PixCronometroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prazoFim != widget.prazoFim) {
      _expiradoEnviado = false;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formato() {
    final fim = widget.prazoFim;
    if (fim == null) return '--:--';
    final s = fim.difference(DateTime.now()).inSeconds;
    if (s <= 0) return '0:00';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.prazoFim == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pague em ${_formato()} — após esse prazo o '
              'pedido é cancelado automaticamente.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
