// Arquivo: lib/screens/cliente/checkout_pagamento_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

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

  @override
  void initState() {
    super.initState();
    _metodoAtual = widget.metodoPreSelecionado == 'Cartão' ? 'Cartão' : 'PIX';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    _numCartaoC.dispose();
    _nomeTitularC.dispose();
    _validadeC.dispose();
    _cvvC.dispose();
    _cpfTitularC.dispose();
    super.dispose();
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
    if (snap.exists && snap.data()?['status'] == 'pendente') {
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
          if (d['status'] == 'pendente') {
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

  void _finalizarPixComSucesso() {
    if (_pixConcluido || !mounted) return;
    _pixConcluido = true;
    _pollTimer?.cancel();
    _pedidoSub?.cancel();
    _mostrarConfirmacaoPagamento();
  }

  void _mostrarConfirmacaoPagamento() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: anim,
            child: _PagamentoAprovadoDialog(
              valorTotal: widget.valorTotal,
              onContinuar: () {
                Navigator.of(ctx).pop();
                widget.onPagamentoAprovado();
              },
            ),
          ),
        );
      },
    );
  }

  String _somenteDigitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  ({int mes, int ano})? _parseValidadeCartao(String valor) {
    final partes = valor.split('/');
    if (partes.length != 2) return null;
    final mes = int.tryParse(_somenteDigitos(partes[0])) ?? 0;
    final anoRaw = int.tryParse(_somenteDigitos(partes[1])) ?? 0;
    if (mes < 1 || mes > 12 || anoRaw <= 0) return null;
    final ano = anoRaw < 100 ? 2000 + anoRaw : anoRaw;
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
          final status = (snap.data()?['status'] ?? '').toString();
          if (status == 'pendente') {
            completer.complete('aprovado');
          } else if (status == 'cancelado') {
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

  Future<void> _cancelarPedidoCartaoNaoConcluido(String pedidoId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId);
      final snap = await ref.get();
      if (!snap.exists) return;
      final d = snap.data() ?? {};
      final raw = d['checkout_grupo_pedido_ids'];
      final ids = <String>[];
      if (raw is List) {
        for (final e in raw) {
          final s = e.toString().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }
      final alvos = ids.length > 1 ? ids.toSet().toList() : [pedidoId];
      final batch = FirebaseFirestore.instance.batch();
      for (final id in alvos) {
        final r = FirebaseFirestore.instance.collection('pedidos').doc(id);
        final s = id == pedidoId ? snap : await r.get();
        if (!s.exists) continue;
        final st = (s.data()?['status'] ?? '').toString();
        if (st == 'aguardando_pagamento') {
          batch.update(r, {
            'status': 'cancelado',
            'cancelado_motivo': 'cartao_nao_concluido',
            'cancelado_em': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    } catch (_) {
      // Não bloquear navegação por falha de fallback.
    }
  }

  void _irParaMeusPedidosTodos() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/meus-pedidos',
      (route) => false,
      arguments: {'filtro': 'todos', 'mostrarVoltarVitrine': true},
    );
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
      if (msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'Pagamento recusado pelo provedor. Tente outro cartão.';
  }

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
            child: const Text('Ver meus pedidos'),
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

    if (numeroCartao.length < 13 ||
        nomeTitular.isEmpty ||
        cvv.length < 3 ||
        validade == null ||
        cpf.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha corretamente os dados do cartão e CPF.'),
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
        'parcelas': 1,
        'email': FirebaseAuth.instance.currentUser?.email,
      });

      final data = Map<String, dynamic>.from(resposta.data);
      final statusMp = (data['mp_status'] ?? '').toString();
      final aprovadoDireto = statusMp == 'approved' || statusMp == 'authorized';

      if (aprovadoDireto) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        _mostrarConfirmacaoPagamento();
        return;
      }

      // Em status intermediário, aguarda sincronização no pedido.
      final resultado = await _aguardarConclusaoPedidoCartao(pedidoId);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (resultado == 'aprovado') {
        _mostrarConfirmacaoPagamento();
      } else if (resultado == 'cancelado') {
        final msg = await _mensagemRecusaDoPedido(pedidoId);
        await _mostrarPopupPagamentoRecusado(msg);
        _irParaMeusPedidosTodos();
      } else {
        await _cancelarPedidoCartaoNaoConcluido(pedidoId);
        final msg = await _mensagemRecusaDoPedido(pedidoId);
        await _mostrarPopupPagamentoRecusado(msg);
        _irParaMeusPedidosTodos();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _cancelarPedidoCartaoNaoConcluido(pedidoId);
      final msg = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : await _mensagemRecusaDoPedido(pedidoId);
      await _mostrarPopupPagamentoRecusado(msg);
      _irParaMeusPedidosTodos();
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _cancelarPedidoCartaoNaoConcluido(pedidoId);
      final msg = await _mensagemRecusaDoPedido(pedidoId);
      await _mostrarPopupPagamentoRecusado(msg);
      _irParaMeusPedidosTodos();
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
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "Pagamento Seguro",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // CABEÇALHO DO VALOR
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.black12)),
            ),
            child: Column(
              children: [
                const Text(
                  "Total a pagar",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  "R\$ ${widget.valorTotal.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: diPertinLaranja,
                  ),
                ),
              ],
            ),
          ),

          // SELETOR SÓ APARECE SE O PIX AINDA NÃO FOI GERADO
          if (!_pixGerado)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _metodoAtual = 'PIX'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _metodoAtual == 'PIX'
                              ? Colors.green
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _metodoAtual == 'PIX'
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.qr_code,
                              color: _metodoAtual == 'PIX'
                                  ? Colors.white
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "PIX",
                              style: TextStyle(
                                color: _metodoAtual == 'PIX'
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
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _metodoAtual = 'Cartão'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _metodoAtual == 'Cartão'
                              ? diPertinRoxo
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _metodoAtual == 'Cartão'
                                ? diPertinRoxo
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.credit_card,
                              color: _metodoAtual == 'Cartão'
                                  ? Colors.white
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Cartão",
                              style: TextStyle(
                                color: _metodoAtual == 'Cartão'
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

          // ÁREA DINÂMICA
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  onPressed: _isProcessando ? null : _processarPagamento,
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
        const Text(
          "Dados do Cartão",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Crédito'),
              selected: _tipoCartaoSelecionado == 'Crédito',
              onSelected: (_) {
                setState(() => _tipoCartaoSelecionado = 'Crédito');
              },
            ),
            ChoiceChip(
              label: const Text('Débito'),
              selected: _tipoCartaoSelecionado == 'Débito',
              onSelected: (_) {
                setState(() => _tipoCartaoSelecionado = 'Débito');
              },
            ),
          ],
        ),
        const SizedBox(height: 15),

        // Campo Número do Cartão com Formatação Automática
        TextFormField(
          controller: _numCartaoC,
          keyboardType: TextInputType.number,
          inputFormatters: [CreditCardNumberInputFormatter()],
          onChanged: (valor) {
            // Detecta a bandeira automaticamente enquanto o cliente digita!
            setState(() {
              _bandeiraCartao = getCardSystemData(valor)?.system;
            });
          },
          decoration: InputDecoration(
            labelText: "Número do Cartão",
            hintText: "0000 0000 0000 0000",
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12.0),
              child: iconeBandeira,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 15),

        TextFormField(
          controller: _nomeTitularC,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: "Nome impresso no Cartão",
            prefixIcon: const Icon(Icons.person_outline, color: diPertinRoxo),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
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
          decoration: InputDecoration(
            labelText: "CPF do titular",
            hintText: "Somente números",
            prefixIcon: const Icon(Icons.badge_outlined, color: diPertinRoxo),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 15),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _validadeC,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  CreditCardExpirationDateFormatter(),
                ], // Coloca a barra MM/AA
                decoration: InputDecoration(
                  labelText: "Validade",
                  hintText: "MM/AA",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: TextFormField(
                controller: _cvvC,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [
                  CreditCardCvcInputFormatter(),
                ], // Limita a 3 ou 4 dígitos
                decoration: InputDecoration(
                  labelText: "CVV",
                  hintText: "123",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, size: 14, color: Colors.green),
            const SizedBox(width: 5),
            Text(
              "Ambiente 100% seguro",
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
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

class _PagamentoAprovadoDialog extends StatefulWidget {
  final double valorTotal;
  final VoidCallback onContinuar;

  const _PagamentoAprovadoDialog({
    required this.valorTotal,
    required this.onContinuar,
  });

  @override
  State<_PagamentoAprovadoDialog> createState() =>
      _PagamentoAprovadoDialogState();
}

class _PagamentoAprovadoDialogState extends State<_PagamentoAprovadoDialog>
    with TickerProviderStateMixin {
  late final AnimationController _checkCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _checkSize;
  late final Animation<double> _pulse;
  bool _mostrarTexto = false;
  bool _mostrarBotao = false;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkSize = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _checkCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _mostrarTexto = true);
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _mostrarBotao = true);
    });
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.18),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _checkSize,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) =>
                      Transform.scale(scale: _pulse.value, child: child),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.green.shade400, Colors.green.shade700],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedOpacity(
                opacity: _mostrarTexto ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: AnimatedSlide(
                  offset: _mostrarTexto ? Offset.zero : const Offset(0, 0.15),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: Column(
                    children: [
                      const Text(
                        'Pagamento Aprovado!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'R\$ ${widget.valorTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Seu pedido foi confirmado com sucesso.\n'
                        'Acompanhe o status pelo app!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedOpacity(
                opacity: _mostrarBotao ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                child: AnimatedSlide(
                  offset: _mostrarBotao ? Offset.zero : const Offset(0, 0.2),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: widget.onContinuar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: Colors.green.withValues(alpha: 0.3),
                      ),
                      child: const Text(
                        'Ver meus pedidos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
