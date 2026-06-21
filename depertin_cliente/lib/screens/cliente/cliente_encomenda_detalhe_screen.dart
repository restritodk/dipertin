import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/encomenda_negociacao_status.dart';
import '../../services/firebase_functions_config.dart';
import '../../utils/safe_area_insets.dart';
import '../../widgets/dipertin_safe_bottom_panel.dart';
import 'checkout_pagamento_screen.dart';
import 'chat_pedido_screen.dart';
import 'selecionar_endereco_entrega_sheet.dart';

/// Detalhe da negociação + ações do cliente (aceitar proposta, pagamento entrada).
/// Design premium DiPertin com cards, gradientes e hierarquia visual clara.
class ClienteEncomendaDetalheScreen extends StatefulWidget {
  const ClienteEncomendaDetalheScreen({super.key, required this.encomendaId});

  final String encomendaId;

  @override
  State<ClienteEncomendaDetalheScreen> createState() =>
      _ClienteEncomendaDetalheScreenState();
}

class _ClienteEncomendaDetalheScreenState
    extends State<ClienteEncomendaDetalheScreen> {
  bool _processando = false;
  bool _entradaAnimada = false;
  String? _chaveFutLojaNome;
  Future<String>? _futLojaNomeRemoto;
  String? _chaveFutEndereco;
  Future<String>? _futEnderecoPerfil;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _roxoClaro = Color(0xFFF3E5F5);
  static const Color _laranjaClaro = Color(0xFFFFF3E0);
  static const Color _fundo = Color(0xFFF5F4F8);
  static const Color _textoPrimario = Color(0xFF1A1A2E);
  static const Color _textoMuted = Color(0xFF6B7280);
  static const Color _bordaCampo = Color(0xFFE8E6EF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  String _idCurtoEncomenda() {
    final id = widget.encomendaId;
    final n = id.length >= 5 ? 5 : id.length;
    return id.substring(0, n).toUpperCase();
  }

  BoxDecoration _decorCartaoPro({
    Color? corBorda,
    bool destacado = false,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: _roxo.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
      border: Border.all(
        color: corBorda ??
            (destacado
                ? _roxo.withValues(alpha: 0.15)
                : _bordaCampo),
      ),
    );
  }

  Widget _tituloSecao(String titulo, {IconData? icone}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icone != null) ...[
            Icon(icone, size: 20, color: _roxo),
            const SizedBox(width: 8),
          ],
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _criarOuRenovarPedidoEntrada({
    String pedidoExistente = '',
  }) async {
    final callable = appFirebaseFunctions.httpsCallable(
      'encomendaClienteAceitarPropostaECriarPedidoEntrada',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    );
    final res = await callable.call({'encomendaId': widget.encomendaId});
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['pedidoEntradaId'] ?? pedidoExistente).toString().trim();
  }

  Future<void> _abrirCheckoutEntrada(String pedidoId) async {
    final pid = pedidoId.trim();
    if (pid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido de entrada não encontrado. Atualize a tela.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final snapValor = await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pid)
        .get();
    final ped = snapValor.data() ?? {};
    final status = (ped['status'] ?? '').toString();
    if (status != 'aguardando_pagamento') {
      await _aceitarPropostaGerarPedido(pid);
      return;
    }
    final total = (ped['total'] is num)
        ? (ped['total'] as num).toDouble()
        : 0.0;

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPagamentoScreen(
          valorTotal: total > 0 ? total : 0,
          metodoPreSelecionado: 'PIX',
          pedidoFirestoreId: pid,
          onPagamentoAprovado: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/meus-pedidos', (route) => false);
          },
        ),
      ),
    );
  }

  Future<void> _aceitarPropostaGerarPedido(String pedidoExistente) async {
    setState(() => _processando = true);
    try {
      final pid = await _criarOuRenovarPedidoEntrada(
        pedidoExistente: pedidoExistente,
      );
      if (!mounted || pid == null || pid.isEmpty) return;
      await _abrirCheckoutEntrada(pid);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Não foi possível gerar o pedido.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _enviarContraproposta(double entrada, String mensagem) async {
    setState(() => _processando = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'encomendaClienteEnviarContraproposta',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      await callable.call({
        'encomendaId': widget.encomendaId,
        'valor_entrada_cliente': entrada,
        'mensagem': mensagem,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraproposta enviada à loja.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Falha ao enviar contraproposta.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _mostrarDialogContraproposta(double totalProposta) async {
    final entradaCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.handshake, color: _roxo),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Contrapropor entrada',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _laranjaClaro,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _laranja.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total da proposta da loja',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _moeda.format(totalProposta),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _laranja,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: entradaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Quanto pode pagar de entrada?',
                      hintText: r'Ex.: R$ 50,00',
                      prefixText: r'R$ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _roxo, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Mensagem para a loja (opcional)',
                      hintText: 'Explique sua proposta...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _laranja,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Enviar contraproposta'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    final v = double.tryParse(entradaCtrl.text.replaceAll(',', '.').trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor de entrada válido.')),
      );
      return;
    }
    await _enviarContraproposta(v, msgCtrl.text.trim());
  }

  Future<void> _confirmarCancelarNegociacao() async {
    final ok =
        await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.shade100,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.cancel_outlined,
                      color: Colors.red.shade700,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Cancelar encomenda?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A negociação com a loja será encerrada e não poderá ser retomada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _roxoClaro.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _roxo.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: _roxo.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Cobrança da entrada ainda não paga (PIX ou cartão), '
                            'se existir, será cancelada automaticamente.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Sim, cancelar negociação',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: _roxo,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Voltar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _processando = true);
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'encomendaClienteCancelarNegociacao',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      await callable.call(<String, dynamic>{'encomendaId': widget.encomendaId});
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Negociação cancelada.')));
      Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagemFirebaseFunctionsException(e)),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirCheckoutPedidoSaldo(String pedidoSaldoId) async {
    if (pedidoSaldoId.isEmpty) return;
    setState(() => _processando = true);
    try {
      final snapValor = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoSaldoId)
          .get();
      final ped = snapValor.data() ?? {};
      final total = (ped['total'] is num)
          ? (ped['total'] as num).toDouble()
          : 0.0;
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CheckoutPagamentoScreen(
            valorTotal: total > 0 ? total : 0,
            metodoPreSelecionado: 'PIX',
            pedidoFirestoreId: pedidoSaldoId,
            onPagamentoAprovado: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  int _passoTimeline(String status) {
    switch (status) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
        return 0;
      case EncomendaNegociacaoStatus.propostaEnviada:
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        return 1;
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        return 2;
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        return 3;
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        return 4;
      default:
        return -1;
    }
  }

  Widget _buildHeroEncomenda({
    required String status,
    required String lojaNome,
    required String tipoEntrega,
  }) {
    final retirada = tipoEntrega == 'retirada';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), _roxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -24,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encomenda #${_idCurtoEncomenda()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.82),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  lojaNome,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipHero(
                      EncomendaNegociacaoStatus.rotuloPt(status),
                      Icons.sync_alt_rounded,
                    ),
                    _chipHero(
                      retirada ? 'Retirar na loja' : 'Entrega',
                      retirada
                          ? Icons.storefront_outlined
                          : Icons.local_shipping_outlined,
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

  Widget _chipHero(String texto, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: Colors.white.withValues(alpha: 0.95)),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNegociacao(String status) {
    if (EncomendaNegociacaoStatus.encerradaDefinitivamente(status)) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: _decorCartaoPro(corBorda: Colors.red.shade100),
        child: Row(
          children: [
            Icon(Icons.block, color: Colors.red.shade700, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                EncomendaNegociacaoStatus.rotuloPt(status),
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    const passos = ['Enviado', 'Proposta', 'Entrada', 'Saldo', 'Entrega'];
    final ativo = _passoTimeline(status);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: _decorCartaoPro(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Andamento da negociação',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textoMuted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(passos.length * 2 - 1, (i) {
              if (i.isOdd) {
                final linhaIdx = i ~/ 2;
                final concluida = linhaIdx < ativo;
                return Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: concluida
                        ? _laranja
                        : _bordaCampo,
                  ),
                );
              }
              final passoIdx = i ~/ 2;
              final concluido = passoIdx < ativo;
              final atual = passoIdx == ativo;
              final corCirculo = concluido || atual ? _roxo : _bordaCampo;
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: atual
                            ? _laranja
                            : (concluido ? _roxo : Colors.white),
                        border: Border.all(color: corCirculo, width: 2),
                      ),
                      child: concluido
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : (atual
                                ? const Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Colors.white,
                                  )
                                : null),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      passos[passoIdx],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: atual ? FontWeight.w800 : FontWeight.w600,
                        color: atual ? _roxo : _textoMuted,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    final cor = iconColor ?? _roxo;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _decorCartaoPro(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textoMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textoPrimario,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _formasPagamentoEntrada(Map<String, dynamic> m) {
    final raw = m['formas_pagamento_entrada_loja'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e == 'pix' || e == 'cartao')
        .toSet()
        .toList();
  }

  String _formasPagamentoTexto(Map<String, dynamic> m) {
    final formas = _formasPagamentoEntrada(m);
    if (formas.isEmpty) return 'A loja ainda vai informar';
    if (formas.contains('pix') && formas.contains('cartao')) {
      return 'Pix ou cartão';
    }
    if (formas.contains('pix')) return 'Pix';
    return 'Cartão';
  }

  /// Considera a entrada paga a partir do momento em que a produção começa.
  bool _entradaJaPaga(String st) {
    return st == EncomendaNegociacaoStatus.entradaPagaEmProducao ||
        st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto ||
        st == EncomendaNegociacaoStatus.emExecucaoLogistica;
  }

  /// Texto do campo "Pagamento da entrada": valor pago quando a entrada já foi
  /// confirmada; caso contrário, as formas combinadas com a loja.
  String _textoPagamentoEntrada(Map<String, dynamic> m, String st) {
    final entrada = (m['valor_entrada_loja'] is num)
        ? (m['valor_entrada_loja'] as num).toDouble()
        : null;
    if (_entradaJaPaga(st) && entrada != null && entrada > 0) {
      return 'Entrada paga: ${_moeda.format(entrada)}';
    }
    return _formasPagamentoTexto(m);
  }

  static String _stringCampo(
    Map<String, dynamic> m,
    String chave, {
    String fallback = '',
  }) {
    final raw = m[chave];
    if (raw == null) return fallback;
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'null') return fallback;
    return s;
  }

  String _tipoEntregaDoMapa(Map<String, dynamic> m) {
    return _stringCampo(m, 'tipo_entrega', fallback: 'entrega');
  }

  String _lojaNomeExibicao(Map<String, dynamic> m) {
    final nome = _stringCampo(m, 'loja_nome_snapshot');
    if (nome.isNotEmpty) return nome;
    final legado = _stringCampo(m, 'loja_nome');
    return legado.isNotEmpty ? legado : 'Loja';
  }

  /// Endereço síncrono a partir do doc da encomenda (sem Future).
  String _textoEntregaDoMapa(Map<String, dynamic> m) {
    final tipo = _tipoEntregaDoMapa(m);
    if (tipo == 'retirada') return 'Retirada no balcão';

    final endereco = _stringCampo(m, 'endereco_entrega');
    if (endereco.isNotEmpty) return endereco;

    final cidade = _stringCampo(m, 'cidade_entrega');
    final uf = _stringCampo(m, 'uf_entrega');
    if (cidade.isNotEmpty && uf.isNotEmpty) return '$cidade - $uf';
    if (cidade.isNotEmpty) return cidade;
    if (uf.isNotEmpty) return uf;
    return '-';
  }

  Future<String> _resolverLojaNomeRemoto(Map<String, dynamic> m) async {
    final lojaId = _stringCampo(m, 'loja_id');
    if (lojaId.isEmpty) return 'Loja';
    try {
      final s = await FirebaseFirestore.instance
          .collection('lojas_public')
          .doc(lojaId)
          .get();
      final d = s.data() ?? {};
      for (final chave in [
        'loja_nome',
        'nome_loja',
        'nome_fantasia',
        'nome',
      ]) {
        final nome = _stringCampo(d, chave);
        if (nome.isNotEmpty) return nome;
      }
    } catch (_) {}
    return 'Loja';
  }

  Future<String> _resolverEnderecoFallbackPerfil(Map<String, dynamic> m) async {
    if (_tipoEntregaDoMapa(m) == 'retirada') return 'Retirada no balcão';

    final sync = _textoEntregaDoMapa(m);
    if (sync != '-') return sync;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return '-';

    try {
      final s = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final d = s.data() ?? {};
      final endPadrao = d['endereco_entrega_padrao'];
      if (endPadrao is Map) {
        final texto = formatarEnderecoEntregaMapa(
          Map<String, dynamic>.from(endPadrao),
        );
        if (texto != 'Endereço não informado') return texto;
      }
      final legado = _stringCampo(d, 'endereco');
      if (legado.isNotEmpty) return legado;
    } catch (_) {}
    return '-';
  }

  Future<String> _futuroLojaNomeRemoto(Map<String, dynamic> m) {
    final chave = _stringCampo(m, 'loja_id');
    if (_chaveFutLojaNome == chave && _futLojaNomeRemoto != null) {
      return _futLojaNomeRemoto!;
    }
    _chaveFutLojaNome = chave;
    _futLojaNomeRemoto = _resolverLojaNomeRemoto(m);
    return _futLojaNomeRemoto!;
  }

  Future<String> _futuroEnderecoPerfil(Map<String, dynamic> m) {
    final chave =
        '${_stringCampo(m, 'endereco_entrega')}|${_tipoEntregaDoMapa(m)}';
    if (_chaveFutEndereco == chave && _futEnderecoPerfil != null) {
      return _futEnderecoPerfil!;
    }
    _chaveFutEndereco = chave;
    _futEnderecoPerfil = _resolverEnderecoFallbackPerfil(m);
    return _futEnderecoPerfil!;
  }

  Widget _buildHeroEncomendaResolvido({
    required String status,
    required Map<String, dynamic> m,
    required String tipoEntrega,
  }) {
    final nomeSync = _lojaNomeExibicao(m);
    final precisaRemoto =
        nomeSync == 'Loja' && _stringCampo(m, 'loja_id').isNotEmpty;

    if (!precisaRemoto) {
      return _buildHeroEncomenda(
        status: status,
        lojaNome: nomeSync,
        tipoEntrega: tipoEntrega,
      );
    }

    return FutureBuilder<String>(
      future: _futuroLojaNomeRemoto(m),
      builder: (context, snap) {
        final nome = (snap.data ?? '').trim();
        return _buildHeroEncomenda(
          status: status,
          lojaNome: nome.isNotEmpty ? nome : nomeSync,
          tipoEntrega: tipoEntrega,
        );
      },
    );
  }

  Widget _buildCardEntrega(Map<String, dynamic> m) {
    final tipo = _tipoEntregaDoMapa(m);
    final textoSync = _textoEntregaDoMapa(m);
    final icone = tipo == 'retirada'
        ? Icons.storefront_outlined
        : Icons.location_on_outlined;
    final rotulo = tipo == 'retirada' ? 'Retirada em' : 'Entregar em';

    if (textoSync != '-') {
      return _buildInfoCard(
        icon: icone,
        label: rotulo,
        value: textoSync,
        iconColor: _laranja,
      );
    }

    return FutureBuilder<String>(
      future: _futuroEnderecoPerfil(m),
      builder: (context, snap) {
        final valor = (snap.data ?? '-').trim();
        return _buildInfoCard(
          icon: icone,
          label: rotulo,
          value: valor.isEmpty ? '-' : valor,
          iconColor: _laranja,
        );
      },
    );
  }

  Widget _linhaFinanceira(
    String label,
    String valor, {
    bool destaque = false,
    bool divisorApos = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: destaque ? 14 : 13,
                    fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
                    color: destaque ? _textoPrimario : _textoMuted,
                  ),
                ),
              ),
              Text(
                valor,
                style: TextStyle(
                  fontSize: destaque ? 18 : 15,
                  fontWeight: FontWeight.w800,
                  color: destaque ? _laranja : _roxo,
                ),
              ),
            ],
          ),
        ),
        if (divisorApos)
          Divider(height: 1, color: _bordaCampo.withValues(alpha: 0.9)),
      ],
    );
  }

  Widget _buildResumoFinanceiro({
    required Map<String, dynamic> m,
    required String st,
    required double? totalRef,
    required double? entradaRef,
    required double freteEnc,
    required double? restanteProduto,
    required double? totalGeral,
    required double? totalPagamentoFinal,
  }) {
    if (totalRef == null || totalRef <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: _decorCartaoPro(destacado: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloSecao('Resumo financeiro', icone: Icons.receipt_long_outlined),
          _linhaFinanceira(
            'Produto (negociado)',
            _moeda.format(totalRef),
            destaque: true,
          ),
          if (freteEnc > 0)
            _linhaFinanceira('Frete', _moeda.format(freteEnc)),
          if (totalGeral != null)
            _linhaFinanceira(
              'Total (produto + frete)',
              _moeda.format(totalGeral),
              divisorApos: true,
            ),
          if (entradaRef != null && entradaRef > 0)
            _linhaFinanceira(
              _entradaJaPaga(st)
                  ? 'Entrada paga (produto)'
                  : 'Entrada combinada (produto)',
              _moeda.format(entradaRef),
            ),
          if (restanteProduto != null && restanteProduto > 0)
            _linhaFinanceira(
              'Restante do produto',
              _moeda.format(restanteProduto),
            ),
          if (totalPagamentoFinal != null &&
              totalPagamentoFinal > 0 &&
              !_entradaJaPaga(st)) ...[
            if (freteEnc > 0)
              _linhaFinanceira(
                'Frete no pagamento final',
                _moeda.format(freteEnc),
              ),
            _linhaFinanceira(
              'Total do pagamento final',
              _moeda.format(totalPagamentoFinal),
              destaque: true,
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _roxoClaro.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'A entrada cobre só o produto. O frete entra no pagamento final, '
              'junto com o restante.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: _textoMuted.withValues(alpha: 0.95),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _linhaFinanceira(
            'Forma da entrada',
            _textoPagamentoEntrada(m, st),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertaContextual(String st, {required bool pagoIntegralmente}) {
    if (pagoIntegralmente) {
      return _alertaCard(
        icone: Icons.verified_outlined,
        texto: 'Pago integralmente — entrada e saldo confirmados.',
        corFundo: const Color(0xFFE8F5E9),
        corIcone: const Color(0xFF2E7D32),
        corTexto: const Color(0xFF1B5E20),
      );
    }
    if (st == EncomendaNegociacaoStatus.entradaPagaEmProducao) {
      return _alertaCard(
        icone: Icons.build_circle_outlined,
        texto:
            'Sua entrada foi confirmada! A loja está produzindo seu pedido. '
            'Quando ela gerar a cobrança do saldo, você poderá pagar aqui.',
        corFundo: _laranjaClaro,
        corIcone: _laranja,
        corTexto: const Color(0xFFE65100),
      );
    }
    if (st == EncomendaNegociacaoStatus.emExecucaoLogistica) {
      return _alertaCard(
        icone: Icons.local_shipping_outlined,
        texto: 'Saldo pago! Acompanhe a entrega em «Meus pedidos».',
        corFundo: const Color(0xFFE8F5E9),
        corIcone: const Color(0xFF2E7D32),
        corTexto: const Color(0xFF1B5E20),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _alertaCard({
    required IconData icone,
    required String texto,
    required Color corFundo,
    required Color corIcone,
    required Color corTexto,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: corIcone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: corIcone, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: corTexto,
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCarregamento() {
    Widget bloco({double h = 16, double w = double.infinity}) {
      return Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: _bordaCampo,
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bloco(h: 120),
          const SizedBox(height: 16),
          bloco(h: 88),
          const SizedBox(height: 16),
          bloco(h: 200),
          const SizedBox(height: 16),
          bloco(h: 140),
        ],
      ),
    );
  }

  /// Item da lista de produtos
  Widget _buildItemEncomenda(Map<String, dynamic> item) {
    final nome = (item['nome'] ?? 'Produto').toString();
    final q = (item['quantidade'] is num)
        ? (item['quantidade'] as num).toInt()
        : 1;
    final preco = (item['preco_ref'] is num)
        ? (item['preco_ref'] as num).toDouble()
        : 0.0;
    final imagemUrl = (item['imagem'] ?? '').toString();
    final variacoes = item['variacoes'] is Map
        ? Map<String, dynamic>.from(item['variacoes'] as Map)
        : <String, dynamic>{};
    final cor = (variacoes['cor'] ?? '').toString().trim();
    final tamanho = (variacoes['tamanho'] ?? '').toString().trim();
    final resumo = (item['variacoes_resumo'] ?? '').toString().trim();

    final subtotal = preco * q;
    final refNegociado = preco <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fundo.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCampo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imagemUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imagemUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbItemPlaceholder(),
              ),
            )
          else
            _thumbItemPlaceholder(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _textoPrimario,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Qtd: $q',
                  style: const TextStyle(fontSize: 12, color: _textoMuted),
                ),
                if (cor.isNotEmpty ||
                    tamanho.isNotEmpty ||
                    resumo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (cor.isNotEmpty) _miniChipItem('Cor: $cor'),
                      if (tamanho.isNotEmpty)
                        _miniChipItem('Tamanho: $tamanho'),
                      if (cor.isEmpty && tamanho.isEmpty && resumo.isNotEmpty)
                        _miniChipItem(resumo),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (refNegociado)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _laranjaClaro,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'A combinar',
                          style: TextStyle(
                            color: _laranja,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Text(
                      refNegociado ? 'Ref. sob consulta' : _moeda.format(subtotal),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: refNegociado ? _textoMuted : _roxo,
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

  Widget _thumbItemPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: _roxoClaro,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.shopping_bag_outlined, color: _roxo, size: 26),
    );
  }

  Widget _miniChipItem(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _roxoClaro,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: _roxo,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Botão primário com gradiente
  Widget _buildBotaoPrimario({
    required String texto,
    required VoidCallback onPressed,
    Color cor = _laranja,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor, cor.withOpacity(0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _processando ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: _processando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    texto,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _abrirChatEncomenda(Map<String, dynamic> m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPedidoScreen(
          pedidoId: widget.encomendaId,
          lojaId: (m['loja_id'] ?? '').toString(),
          lojaNome: (m['loja_nome'] ?? '').toString(),
          colecaoRaiz: 'encomendas',
          remetenteTipo: 'cliente',
          tituloOverride: (m['loja_nome'] ?? 'Loja').toString(),
          subtituloOverride:
              'Encomenda #${_idCurtoEncomenda()}',
        ),
      ),
    );
  }

  Widget? _buildPainelInferiorAcoes({
    required String st,
    required double? totalRef,
    required double? entradaRef,
    required String pedidoEntrada,
    required String pedidoSaldo,
    required bool podeAceitarPagamento,
    required bool podeContrapropor,
  }) {
    final filhos = <Widget>[];

    if (podeAceitarPagamento &&
        totalRef != null &&
        entradaRef != null) {
      filhos.add(
        _buildBotaoPrimario(
          texto: 'Aceitar proposta e pagar entrada',
          onPressed: () => _aceitarPropostaGerarPedido(pedidoEntrada),
        ),
      );
      if (podeContrapropor) {
        filhos.add(const SizedBox(height: 10));
        filhos.add(
          _buildBotaoSecundario(
            onPressed: () => _mostrarDialogContraproposta(totalRef),
            texto: 'Enviar contraproposta',
          ),
        );
      }
    } else if (st == EncomendaNegociacaoStatus.entradaAguardandoPagamento &&
        pedidoEntrada.isNotEmpty) {
      filhos.add(
        _buildBotaoPrimario(
          texto: 'Continuar pagamento da entrada',
          onPressed: () => _abrirCheckoutEntrada(pedidoEntrada),
        ),
      );
    } else if (st == EncomendaNegociacaoStatus.saldoFinalAguardandoPgto &&
        pedidoSaldo.isNotEmpty) {
      filhos.add(
        _buildBotaoPrimario(
          texto: 'Pagar saldo da encomenda',
          onPressed: () => _abrirCheckoutPedidoSaldo(pedidoSaldo),
        ),
      );
    }

    if (filhos.isEmpty) return null;

    return DiPertinSafeBottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filhos,
      ),
    );
  }

  /// Botão secundário
  Widget _buildBotaoSecundario({
    required String texto,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: _roxo.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _processando ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: _processando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_roxo),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake, color: _roxo, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        texto,
                        style: TextStyle(
                          color: _roxo,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = FirebaseFirestore.instance
        .collection('encomendas')
        .doc(widget.encomendaId);

    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Detalhe da Encomenda',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (uid != null)
            IconButton(
              tooltip: 'Chat da encomenda',
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              onPressed: () {
                ref.get().then((snap) {
                  if (!mounted || !snap.exists) return;
                  _abrirChatEncomenda(snap.data() ?? {});
                });
              },
            ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Login necessário.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return _buildSkeletonCarregamento();
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return _buildSkeletonCarregamento();
                }
                final m = snap.data!.data() ?? {};
                if (m['cliente_id']?.toString() != uid) {
                  return const Center(
                    child: Text('Você não tem acesso a esta encomenda.'),
                  );
                }

                final st = (m['status_negociacao'] ?? '').toString();
                final totalRef = (m['valor_total_referencia'] is num)
                    ? (m['valor_total_referencia'] as num).toDouble()
                    : null;
                final entradaRef = (m['valor_entrada_loja'] is num)
                    ? (m['valor_entrada_loja'] as num).toDouble()
                    : null;
                final pedidoEntrada = (m['pedido_entrada_id'] ?? '')
                    .toString()
                    .trim();
                final pedidoSaldo = (m['pedido_saldo_final_id'] ?? '')
                    .toString()
                    .trim();
                final msgCliente = (m['mensagem_cliente'] ?? '').toString();
                final tipoEntrega =
                    (m['tipo_entrega'] ?? 'entrega').toString();
                final freteEnc = tipoEntrega == 'retirada'
                    ? 0.0
                    : ((m['taxa_entrega_snapshot'] is num)
                        ? (m['taxa_entrega_snapshot'] as num).toDouble()
                        : 0.0);
                final restanteProduto =
                    (totalRef != null && entradaRef != null)
                    ? (totalRef - entradaRef).clamp(0.0, double.infinity)
                    : null;
                final totalGeral = totalRef != null
                    ? totalRef + freteEnc
                    : null;
                final totalPagamentoFinal = restanteProduto != null
                    ? restanteProduto + freteEnc
                    : null;
                final pagoIntegralmente =
                    st == EncomendaNegociacaoStatus.emExecucaoLogistica;

                final podeAceitarPagamento =
                    st == EncomendaNegociacaoStatus.propostaEnviada ||
                    st ==
                        EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada;

                final podeContrapropor =
                    st == EncomendaNegociacaoStatus.propostaEnviada &&
                    totalRef != null &&
                    totalRef > 0;

                final painelInferior = _buildPainelInferiorAcoes(
                  st: st,
                  totalRef: totalRef,
                  entradaRef: entradaRef,
                  pedidoEntrada: pedidoEntrada,
                  pedidoSaldo: pedidoSaldo,
                  podeAceitarPagamento: podeAceitarPagamento,
                  podeContrapropor: podeContrapropor,
                );

                final paddingRodape = painelInferior != null
                    ? 140.0 + diPertinSafeAreaBottom(context)
                    : 24.0 + diPertinSafeAreaBottom(context);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AnimatedOpacity(
                        opacity: _entradaAnimada ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeroEncomendaResolvido(
                                status: st,
                                m: m,
                                tipoEntrega: tipoEntrega,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTimelineNegociacao(st),
                                    const SizedBox(height: 16),
                                    _buildCardEntrega(m),
                                    const SizedBox(height: 16),
                                    _buildAlertaContextual(
                                      st,
                                      pagoIntegralmente: pagoIntegralmente,
                                    ),
                                    if (pagoIntegralmente ||
                                        st ==
                                            EncomendaNegociacaoStatus
                                                .entradaPagaEmProducao ||
                                        st ==
                                            EncomendaNegociacaoStatus
                                                .emExecucaoLogistica)
                                      const SizedBox(height: 16),
                                    _buildResumoFinanceiro(
                                      m: m,
                                      st: st,
                                      totalRef: totalRef,
                                      entradaRef: entradaRef,
                                      freteEnc: freteEnc,
                                      restanteProduto: restanteProduto,
                                      totalGeral: totalGeral,
                                      totalPagamentoFinal: totalPagamentoFinal,
                                    ),
                                    if (totalRef != null && totalRef > 0)
                                      const SizedBox(height: 20),
                                    if (msgCliente.isNotEmpty) ...[
                                      _buildInfoCard(
                                        icon: Icons.description_outlined,
                                        label: 'Seu pedido à loja',
                                        value: msgCliente,
                                        iconColor: _roxo,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (m['itens'] is List &&
                                        (m['itens'] as List).isNotEmpty) ...[
                                      _tituloSecao(
                                        'Itens da encomenda',
                                        icone: Icons.inventory_2_outlined,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: _decorCartaoPro(),
                                        child: Column(
                                          children: (m['itens'] as List)
                                              .whereType<Map>()
                                              .map((raw) {
                                                final it =
                                                    Map<String, dynamic>.from(
                                                      raw,
                                                    );
                                                return _buildItemEncomenda(it);
                                              })
                                              .toList(),
                                        ),
                                      ),
                                    ],
                                    if (!EncomendaNegociacaoStatus
                                        .encerradaDefinitivamente(st)) ...[
                                      const SizedBox(height: 28),
                                      Builder(
                                        builder: (context) {
                                          final podeCancelar =
                                              EncomendaNegociacaoStatus
                                                  .podeCancelarNegociacaoAntesPagamentoEntrada(
                                                    st,
                                                  );
                                          return Column(
                                            children: [
                                              TextButton.icon(
                                                onPressed:
                                                    (podeCancelar &&
                                                        !_processando)
                                                    ? _confirmarCancelarNegociacao
                                                    : null,
                                                icon: Icon(
                                                  Icons.cancel_outlined,
                                                  color: podeCancelar
                                                      ? Colors.red.shade700
                                                      : Colors.grey.shade400,
                                                ),
                                                label: Text(
                                                  'Cancelar negociação',
                                                  style: TextStyle(
                                                    color: podeCancelar
                                                        ? Colors.red.shade700
                                                        : Colors.grey.shade400,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (!podeCancelar)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    'Após o pagamento da entrada o cancelamento '
                                                    'por aqui fica indisponível.',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      height: 1.35,
                                                      color: _textoMuted,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                    SizedBox(height: paddingRodape),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (painelInferior != null) painelInferior,
                  ],
                );
              },
            ),
    );
  }
}
