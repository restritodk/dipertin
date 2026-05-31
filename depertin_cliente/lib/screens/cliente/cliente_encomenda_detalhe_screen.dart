import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/encomenda_negociacao_status.dart';
import '../../services/firebase_functions_config.dart';
import 'checkout_pagamento_screen.dart';
import 'chat_pedido_screen.dart';

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

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  // Cores do tema DiPertin
  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _roxoClaro = Color(0xFFF3E5F5);
  static const Color _laranjaClaro = Color(0xFFFFF3E0);

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
                const Text('Contrapropor entrada'),
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
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Text('Cancelar encomenda'),
              ],
            ),
            content: const Text(
              'Tem certeza? A negociação será encerrada. '
              'Se existir cobrança da entrada ainda não paga (PIX ou cartão), ela será cancelada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancelar negociação'),
              ),
            ],
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

  /// Widget de status com badge colorido
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor = Colors.white;
    IconData icon;

    switch (status) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
        bgColor = Colors.grey.shade600;
        icon = Icons.hourglass_empty;
        break;
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
        bgColor = Colors.blue;
        icon = Icons.swap_horiz;
        break;
      case EncomendaNegociacaoStatus.propostaEnviada:
        bgColor = _laranja;
        icon = Icons.assignment_turned_in;
        break;
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        bgColor = Colors.orange;
        icon = Icons.hourglass_top;
        break;
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        bgColor = Colors.deepOrange;
        icon = Icons.payment;
        break;
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
        bgColor = Colors.teal;
        icon = Icons.build;
        break;
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        bgColor = Colors.deepOrange;
        icon = Icons.shopping_cart_checkout;
        break;
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        bgColor = Colors.green;
        icon = Icons.local_shipping;
        break;
      default:
        bgColor = Colors.red.shade700;
        icon = Icons.block;
        textColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bgColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(
            EncomendaNegociacaoStatus.rotuloPt(status),
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Card de informação com ícone
  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (iconColor ?? _roxo).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? _roxo, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
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

  /// Resolve nome da loja e cidade/estado para exibição ao cliente.
  /// Usa os snapshots gravados na encomenda; em dados antigos faz fallback
  /// para `lojas_public` (nome) e ao próprio doc do cliente (cidade/UF).
  Future<_ResumoEncomendaCliente> _carregarResumo(Map<String, dynamic> m) async {
    final lojaId = (m['loja_id'] ?? '').toString().trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    var lojaNome = (m['loja_nome_snapshot'] ?? m['loja_nome'] ?? '')
        .toString()
        .trim();
    var cidade = (m['cidade_entrega'] ?? '').toString().trim();
    var uf = (m['uf_entrega'] ?? '').toString().trim();

    if (lojaNome.isEmpty && lojaId.isNotEmpty) {
      try {
        final s = await FirebaseFirestore.instance
            .collection('lojas_public')
            .doc(lojaId)
            .get();
        final d = s.data() ?? {};
        lojaNome =
            (d['loja_nome'] ??
                    d['nome_loja'] ??
                    d['nome_fantasia'] ??
                    d['nome'] ??
                    '')
                .toString()
                .trim();
      } catch (_) {}
    }

    if ((cidade.isEmpty || uf.isEmpty) && uid.isNotEmpty) {
      try {
        final s = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final d = s.data() ?? {};
        if (cidade.isEmpty) {
          cidade =
              (d['cidade'] ??
                      d['endereco_cidade'] ??
                      d['cidade_normalizada'] ??
                      '')
                  .toString()
                  .trim();
        }
        if (uf.isEmpty) {
          uf = (d['uf'] ?? d['estado'] ?? d['endereco_estado'] ?? '')
              .toString()
              .trim();
        }
      } catch (_) {}
    }

    return _ResumoEncomendaCliente(
      lojaNome: lojaNome.isEmpty ? 'Loja' : lojaNome,
      cidade: cidade,
      uf: uf,
    );
  }

  String _enderecoCidadeEstado(_ResumoEncomendaCliente r) {
    if (r.cidade.isNotEmpty && r.uf.isNotEmpty) return '${r.cidade} - ${r.uf}';
    if (r.cidade.isNotEmpty) return r.cidade;
    if (r.uf.isNotEmpty) return r.uf;
    return '-';
  }

  Future<_ResumoEncomendaCliente>? _futResumo;

  /// Card de valor destacado
  Widget _buildValorCard({
    required String label,
    required String value,
    required Color color,
    bool destaque = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: destaque
            ? LinearGradient(
                colors: [color, color.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [Colors.white, color.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: destaque ? Colors.transparent : color.withOpacity(0.2),
        ),
        boxShadow: destaque
            ? [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: destaque
                  ? Colors.white.withOpacity(0.9)
                  : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: destaque ? Colors.white : color,
            ),
          ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          if (imagemUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imagemUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _roxoClaro,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: _roxo),
                ),
              ),
            )
          else
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _roxoClaro,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_bag, color: _roxo),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Qtd: $q',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
              ],
            ),
          ),
          Text(
            _moeda.format(preco * q),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _roxo,
            ),
          ),
        ],
      ),
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Detalhe da Encomenda',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Login necessário.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(child: CircularProgressIndicator());
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
                    ? (totalRef - entradaRef).clamp(0, double.infinity)
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

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status Badge
                      Center(child: _buildStatusBadge(st)),
                      const SizedBox(height: 12),
                      // Informações principais: loja, endereço (cidade/UF) e pagamento
                      Builder(
                        builder: (context) {
                          _futResumo ??= _carregarResumo(m);
                          return FutureBuilder<_ResumoEncomendaCliente>(
                            future: _futResumo,
                            builder: (context, resumoSnap) {
                              final r =
                                  resumoSnap.data ??
                                  const _ResumoEncomendaCliente(
                                    lojaNome: 'Loja',
                                    cidade: '',
                                    uf: '',
                                  );
                              final larguraCard =
                                  MediaQuery.of(context).size.width < 600
                                  ? MediaQuery.of(context).size.width
                                  : (MediaQuery.of(context).size.width - 48) / 2;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: larguraCard,
                                    child: _buildInfoCard(
                                      icon: Icons.storefront,
                                      label: 'Loja',
                                      value: r.lojaNome,
                                      iconColor: Colors.blue,
                                    ),
                                  ),
                                  SizedBox(
                                    width: larguraCard,
                                    child: _buildInfoCard(
                                      icon: Icons.location_on,
                                      label: 'Endereço',
                                      value: _enderecoCidadeEstado(r),
                                      iconColor: Colors.deepOrange,
                                    ),
                                  ),
                                  SizedBox(
                                    width: larguraCard,
                                    child: _buildInfoCard(
                                      icon: Icons.payment,
                                      label: 'Pagamento',
                                      value: _textoPagamentoEntrada(m, st),
                                      iconColor: Colors.purple,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // Botão rápido para abrir chat da encomenda
                      _buildBotaoSecundario(
                        texto: 'Abrir chat da encomenda',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPedidoScreen(
                                pedidoId: widget.encomendaId,
                                lojaId: (m['loja_id'] ?? '').toString(),
                                lojaNome: (m['loja_nome'] ?? '').toString(),
                                colecaoRaiz: 'encomendas',
                                remetenteTipo: 'cliente',
                                tituloOverride: (m['loja_nome'] ?? 'Loja')
                                    .toString(),
                                subtituloOverride:
                                    'Encomenda #${widget.encomendaId.substring(0, widget.encomendaId.length >= 5 ? 5 : widget.encomendaId.length).toUpperCase()}',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      if (pagoIntegralmente) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.verified,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Pago integralmente — entrada e saldo confirmados.',
                                  style: TextStyle(
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Valores: produto, frete e pagamentos
                      if (totalRef != null && totalRef > 0) ...[
                        const Text(
                          'Valores da encomenda',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildValorCard(
                          label: 'Produto (negociado)',
                          value: _moeda.format(totalRef),
                          color: _laranja,
                          destaque: true,
                        ),
                        if (freteEnc > 0) ...[
                          const SizedBox(height: 10),
                          _buildValorCard(
                            label: 'Frete',
                            value: _moeda.format(freteEnc),
                            color: Colors.blue.shade700,
                          ),
                        ],
                        if (totalGeral != null) ...[
                          const SizedBox(height: 10),
                          _buildValorCard(
                            label: 'Total (produto + frete)',
                            value: _moeda.format(totalGeral),
                            color: Colors.deepPurple.shade700,
                          ),
                        ],
                        if (entradaRef != null && entradaRef > 0) ...[
                          const SizedBox(height: 10),
                          _buildValorCard(
                            label: _entradaJaPaga(st)
                                ? 'Entrada paga (produto)'
                                : 'Entrada combinada (produto)',
                            value: _moeda.format(entradaRef),
                            color: _roxo,
                          ),
                        ],
                        if (restanteProduto != null && restanteProduto > 0) ...[
                          const SizedBox(height: 10),
                          _buildValorCard(
                            label: 'Restante do produto',
                            value: _moeda.format(restanteProduto),
                            color: Colors.teal.shade700,
                          ),
                        ],
                        if (totalPagamentoFinal != null &&
                            totalPagamentoFinal > 0 &&
                            !_entradaJaPaga(st)) ...[
                          const SizedBox(height: 10),
                          if (freteEnc > 0)
                            _buildValorCard(
                              label: 'Frete no pagamento final',
                              value: _moeda.format(freteEnc),
                              color: Colors.blueGrey.shade700,
                            ),
                          const SizedBox(height: 10),
                          _buildValorCard(
                            label: 'Total do pagamento final',
                            value: _moeda.format(totalPagamentoFinal),
                            color: Colors.indigo.shade700,
                            destaque: true,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F5FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            'A entrada refere-se apenas ao valor do produto. '
                            'O frete é cobrado no pagamento final, junto com o '
                            'restante do produto.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          icon: Icons.payments_outlined,
                          label: 'Pagamento da entrada',
                          value: _textoPagamentoEntrada(m, st),
                          iconColor: Colors.indigo,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Mensagem do cliente
                      if (msgCliente.isNotEmpty) ...[
                        _buildInfoCard(
                          icon: Icons.description,
                          label: 'Seu pedido à loja',
                          value: msgCliente,
                          iconColor: Colors.blue,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Lista de itens
                      if (m['itens'] is List &&
                          (m['itens'] as List).isNotEmpty) ...[
                        const Text(
                          'Itens da Encomenda',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: (m['itens'] as List).whereType<Map>().map(
                              (raw) {
                                final it = Map<String, dynamic>.from(raw);
                                return _buildItemEncomenda(it);
                              },
                            ).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Botões de ação baseados no status
                      if (podeAceitarPagamento &&
                          totalRef != null &&
                          entradaRef != null)
                        _buildBotaoPrimario(
                          texto: 'Aceitar proposta e pagar entrada',
                          onPressed: () =>
                              _aceitarPropostaGerarPedido(pedidoEntrada),
                        ),

                      if (podeContrapropor) ...[
                        const SizedBox(height: 12),
                        _buildBotaoSecundario(
                          onPressed: () =>
                              _mostrarDialogContraproposta(totalRef),
                          texto: 'Enviar contraproposta',
                        ),
                      ],

                      if (st ==
                              EncomendaNegociacaoStatus
                                  .entradaAguardandoPagamento &&
                          pedidoEntrada.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildBotaoPrimario(
                          texto: 'Continuar pagamento da entrada',
                          onPressed: () => _abrirCheckoutEntrada(pedidoEntrada),
                        ),
                      ],

                      if (st ==
                          EncomendaNegociacaoStatus.entradaPagaEmProducao) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.shade50,
                                Colors.amber.shade100,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.amber.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Sua entrada foi confirmada! A loja está produzindo seu pedido. '
                                  'Quando ela gerar a cobrança do saldo, você poderá pagar aqui.',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (st ==
                              EncomendaNegociacaoStatus
                                  .saldoFinalAguardandoPgto &&
                          pedidoSaldo.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildBotaoPrimario(
                          texto: 'Pagar saldo da encomenda',
                          onPressed: () =>
                              _abrirCheckoutPedidoSaldo(pedidoSaldo),
                        ),
                      ],

                      if (st == EncomendaNegociacaoStatus.emExecucaoLogistica)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.local_shipping,
                                color: Colors.green.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Saldo pago! Acompanhe a entrega em «Meus pedidos».',
                                  style: TextStyle(
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Botão de cancelar (quando aplicável)
                      if (!EncomendaNegociacaoStatus.encerradaDefinitivamente(
                        st,
                      )) ...[
                        const SizedBox(height: 28),
                        Builder(
                          builder: (context) {
                            final podeCancelar =
                                EncomendaNegociacaoStatus.podeCancelarNegociacaoAntesPagamentoEntrada(
                                  st,
                                );
                            return Column(
                              children: [
                                TextButton.icon(
                                  onPressed: (podeCancelar && !_processando)
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
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Após o pagamento da entrada o cancelamento '
                                      'por aqui fica indisponível.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Resumo leve para exibição ao cliente (nome da loja + cidade/estado de entrega).
class _ResumoEncomendaCliente {
  const _ResumoEncomendaCliente({
    required this.lojaNome,
    required this.cidade,
    required this.uf,
  });

  final String lojaNome;
  final String cidade;
  final String uf;
}
