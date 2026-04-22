import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Pedidos da loja — mesmos campos que o app grava em [pedidos].
class LojistaMeusPedidosScreen extends StatefulWidget {
  const LojistaMeusPedidosScreen({super.key});

  @override
  State<LojistaMeusPedidosScreen> createState() =>
      _LojistaMeusPedidosScreenState();
}

class _LojistaMeusPedidosScreenState extends State<LojistaMeusPedidosScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  final _buscaC = TextEditingController();
  String _filtro = 'ativos'; // todos | ativos | entregue | cancelado

  /// Cache `cliente_id` → nome exibido (lido de `users`).
  final Map<String, String> _nomesCliente = {};
  String _ultimaChaveNomes = '';

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  // Fase 3G.3 — lê `cliente_nome` denormalizado no próprio pedido. A rule de
  // `users` agora bloqueia leitura cruzada entre autenticados, então o
  // painel do lojista não consegue mais ler `users/{cliente_id}`. O nome é
  // gravado na criação do pedido (ver `cart_screen.dart` mobile) e mantido
  // em dia pelo trigger `sincronizarIdentidadePedidosOnUpdate`.
  Future<void> _resolverNomesCliente(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    var mudou = false;
    for (final d in docs) {
      final data = d.data();
      final id = data['cliente_id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final nomeAtual = _nomesCliente[id];
      final nomeNoPedido =
          (data['cliente_nome'] ?? '').toString().trim();
      final nomeFinal = nomeNoPedido.isNotEmpty ? nomeNoPedido : 'Cliente';
      if (nomeAtual != nomeFinal) {
        _nomesCliente[id] = nomeFinal;
        mudou = true;
      }
    }
    if (mudou && mounted) setState(() {});
  }

  static String _labelStatus(String s) {
    switch (s) {
      case 'pendente':
        return 'Pendente';
      case 'aguardando_pagamento':
        return 'Aguardando pagamento';
      case 'aceito':
        return 'Aceito';
      case 'em_preparo':
      case 'preparando':
        return 'Em preparo';
      case 'aguardando_entregador':
        return 'Buscando entregador';
      case 'entregador_indo_loja':
        return 'Entregador → loja';
      case 'a_caminho':
      case 'em_rota':
      case 'saiu_entrega':
        return 'Em rota';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  static Color _corStatus(String s) {
    switch (s) {
      case 'pendente':
      case 'aguardando_pagamento':
        return const Color(0xFFB45309);
      case 'entregue':
        return const Color(0xFF15803D);
      case 'cancelado':
        return const Color(0xFFB91C1C);
      case 'aceito':
      case 'em_preparo':
      case 'preparando':
        return const Color(0xFF1D4ED8);
      default:
        return _roxo;
    }
  }

  static bool _passaFiltro(String status, String filtro) {
    switch (filtro) {
      case 'ativos':
        return status != 'entregue' && status != 'cancelado';
      case 'entregue':
        return status == 'entregue';
      case 'cancelado':
        return status == 'cancelado';
      default:
        return true;
    }
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _previewItens(List<dynamic> itens, {int max = 3}) {
    if (itens.isEmpty) return 'Sem itens';
    final partes = <String>[];
    for (var i = 0; i < itens.length && partes.length < max; i++) {
      final it = itens[i];
      if (it is Map) {
        final q = it['quantidade'] ?? 1;
        final nome = it['nome']?.toString() ?? '?';
        partes.add('${q}x $nome');
      }
    }
    var s = partes.join(' · ');
    if (itens.length > max) s += ' +${itens.length - max}';
    return s;
  }

  void _abrirDetalhe(
    BuildContext context,
    String id,
    NumberFormat moeda,
    DateFormat fmtData,
    String nomeClienteFallback,
    String uidLoja,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _LojistaPedidoDetalheDialog(
        pedidoId: id,
        uidLoja: uidLoja,
        moeda: moeda,
        fmtData: fmtData,
        nomeClienteFallback: nomeClienteFallback,
        labelStatus: _labelStatus,
        num: _num,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final fmtData = DateFormat('dd/MM/yyyy HH:mm');

    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      floatingActionButton: const BotaoSuporteFlutuante(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Meus pedidos',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _roxo,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Os mesmos dados do aplicativo: cliente, itens, totais e forma de pagamento.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _chipFiltro('Em andamento', 'ativos'),
                      _chipFiltro('Entregues', 'entregue'),
                      _chipFiltro('Cancelados', 'cancelado'),
                      _chipFiltro('Todos', 'todos'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _buscaC,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'Buscar por ID do pedido, nome do cliente ou produto…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8F7FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .where('loja_id', isEqualTo: uidLoja)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro: ${snap.error}'),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                final ordenados = docs.toList()
                  ..sort((a, b) {
                    final ta = a.data()['data_pedido'];
                    final tb = b.data()['data_pedido'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return tb.compareTo(ta);
                    }
                    return 0;
                  });

                final chaveNomes = ordenados
                    .map((e) => '${e.id}:${e.data()['cliente_id'] ?? ''}')
                    .join('|');
                if (chaveNomes != _ultimaChaveNomes) {
                  _ultimaChaveNomes = chaveNomes;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _resolverNomesCliente(ordenados);
                  });
                }

                final filtrados = ordenados.where((doc) {
                  final d = doc.data();
                  final st = d['status']?.toString() ?? 'pendente';
                  if (!_passaFiltro(st, _filtro)) return false;
                  final q = _buscaC.text.trim().toLowerCase();
                  if (q.isEmpty) return true;
                  if (doc.id.toLowerCase().contains(q)) return true;
                  final cid = d['cliente_id']?.toString() ?? '';
                  final nome = _nomesCliente[cid]?.toLowerCase() ?? '';
                  if (nome.contains(q)) return true;
                  final preview =
                      _previewItens(d['itens'] as List? ?? [], max: 20)
                          .toLowerCase();
                  if (preview.contains(q)) return true;
                  return false;
                }).toList();

                if (filtrados.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 56, color: _roxo.withValues(alpha: 0.35)),
                        const SizedBox(height: 16),
                        Text(
                          ordenados.isEmpty
                              ? 'Nenhum pedido ainda.'
                              : 'Nenhum pedido neste filtro.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 960;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          itemCount: filtrados.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final doc = filtrados[i];
                            final d = doc.data();
                            final id = doc.id;
                            final status =
                                d['status']?.toString() ?? 'pendente';
                            final ts = d['data_pedido'];
                            final dataStr = ts is Timestamp
                                ? fmtData.format(ts.toDate())
                                : '—';
                            final total = _num(d['total']);
                            final sub = _num(d['subtotal']);
                            final recebimentoLojista = d['valor_liquido_lojista'] != null
                                ? _num(d['valor_liquido_lojista'])
                                : sub;
                            final itens = d['itens'] as List? ?? [];
                            final isRetirada =
                                d['tipo_entrega']?.toString() == 'retirada';
                            final forma =
                                d['forma_pagamento']?.toString() ?? '—';
                            final cid = d['cliente_id']?.toString() ?? '';
                            final nomeCliente =
                                _nomesCliente[cid] ?? 'Carregando…';
                            final corSt = _corStatus(status);

                            return Material(
                              color: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                onTap: () => _abrirDetalhe(
                                  context,
                                  id,
                                  moeda,
                                  fmtData,
                                  nomeCliente == 'Carregando…'
                                      ? 'Cliente'
                                      : nomeCliente,
                                  uidLoja,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: wide
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: _blocoEsquerda(
                                                id: id,
                                                dataStr: dataStr,
                                                nomeCliente: nomeCliente,
                                                forma: forma,
                                                isRetirada: isRetirada,
                                                endereco: d['endereco_entrega']
                                                        ?.toString() ??
                                                    '',
                                                previewItens:
                                                    _previewItens(itens),
                                                corSt: corSt,
                                                status: status,
                                              ),
                                            ),
                                            const SizedBox(width: 20),
                                            SizedBox(
                                              width: 200,
                                              child: _blocoDireita(
                                                moeda: moeda,
                                                total: total,
                                                sub: sub,
                                                recebimentoLojista:
                                                    recebimentoLojista,
                                                isRetirada: isRetirada,
                                                taxa: _num(d['taxa_entrega']),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _blocoEsquerda(
                                              id: id,
                                              dataStr: dataStr,
                                              nomeCliente: nomeCliente,
                                              forma: forma,
                                              isRetirada: isRetirada,
                                              endereco: d['endereco_entrega']
                                                      ?.toString() ??
                                                  '',
                                              previewItens:
                                                  _previewItens(itens),
                                              corSt: corSt,
                                              status: status,
                                            ),
                                            const SizedBox(height: 14),
                                            _blocoDireita(
                                              moeda: moeda,
                                              total: total,
                                              sub: sub,
                                              recebimentoLojista:
                                                  recebimentoLojista,
                                              isRetirada: isRetirada,
                                              taxa: _num(d['taxa_entrega']),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _chipFiltro(String label, String valor) {
    final sel = _filtro == valor;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filtro = valor),
      selectedColor: _laranja.withValues(alpha: 0.22),
      labelStyle: TextStyle(
        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
        color: sel ? _roxo : Colors.grey.shade800,
      ),
      side: BorderSide(
        color: sel ? _laranja.withValues(alpha: 0.5) : Colors.grey.shade300,
      ),
    );
  }

  Widget _blocoEsquerda({
    required String id,
    required String dataStr,
    required String nomeCliente,
    required String forma,
    required bool isRetirada,
    required String endereco,
    required String previewItens,
    required Color corSt,
    required String status,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nomeCliente,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: Color(0xFF1E1B4B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dataStr,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: corSt.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _labelStatus(status).toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: corSt,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SelectableText(
          id,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              isRetirada ? Icons.storefront_outlined : Icons.delivery_dining,
              size: 18,
              color: isRetirada ? _laranja : _roxo,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isRetirada
                    ? 'Retirada no balcão'
                    : (endereco.isNotEmpty ? endereco : 'Entrega'),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.payments_outlined, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                forma,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          previewItens,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.35,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _blocoDireita({
    required NumberFormat moeda,
    required double total,
    required double sub,
    required double recebimentoLojista,
    required bool isRetirada,
    required double taxa,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          moeda.format(total),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: _laranja,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Produtos ${moeda.format(sub)}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        if (!isRetirada && taxa > 0)
          Text(
            'Taxa entrega ${moeda.format(taxa)}',
            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
          ),
        const SizedBox(height: 4),
        Text(
          'Líquido lojista ${moeda.format(recebimentoLojista)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.green.shade800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Toque no card para detalhes',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// --- Mesmas constantes de status do app mobile (`PedidoStatus`) ---
const String _kStPendente = 'pendente';
const String _kStAceito = 'aceito';
const String _kStEmPreparo = 'em_preparo';
const String _kStPreparando = 'preparando';
const String _kStAguardandoEntregador = 'aguardando_entregador';
const String _kStPronto = 'pronto';
const String _kStEntregue = 'entregue';
const String _kStCancelado = 'cancelado';
const String _kStEntregadorIndoLoja = 'entregador_indo_loja';
const String _kStSaiuEntrega = 'saiu_entrega';
const String _kStACaminho = 'a_caminho';
const String _kStEmRota = 'em_rota';

/// Detalhe do pedido com ações iguais ao app do lojista.
class _LojistaPedidoDetalheDialog extends StatefulWidget {
  const _LojistaPedidoDetalheDialog({
    required this.pedidoId,
    required this.uidLoja,
    required this.moeda,
    required this.fmtData,
    required this.nomeClienteFallback,
    required this.labelStatus,
    required this.num,
  });

  final String pedidoId;
  final String uidLoja;
  final NumberFormat moeda;
  final DateFormat fmtData;
  final String nomeClienteFallback;
  final String Function(String) labelStatus;
  final double Function(dynamic) num;

  @override
  State<_LojistaPedidoDetalheDialog> createState() =>
      _LojistaPedidoDetalheDialogState();
}

class _LojistaPedidoDetalheDialogState extends State<_LojistaPedidoDetalheDialog> {
  bool _busy = false;
  String? _nomeCliente;

  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;

  @override
  void initState() {
    super.initState();
    _carregarNomeCliente();
  }

  // Fase 3G.3 — lê `cliente_nome` direto do pedido (denormalizado).
  // Antes: lookup em `users/{cliente_id}` que a rule fechada bloqueia.
  Future<void> _carregarNomeCliente() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .get();
      final data = doc.data();
      final nomeNoPedido =
          (data?['cliente_nome'] ?? '').toString().trim();
      if (!mounted) return;
      setState(
        () => _nomeCliente = nomeNoPedido.isNotEmpty
            ? nomeNoPedido
            : widget.nomeClienteFallback,
      );
    } catch (_) {
      if (mounted) setState(() => _nomeCliente = widget.nomeClienteFallback);
    }
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  String _msgFn(Object e) {
    if (e is CallableHttpException) return e.message;
    return e.toString();
  }

  Future<void> _atualizarStatus(String novoStatus) async {
    await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(widget.pedidoId)
        .update({'status': novoStatus});
  }

  Future<void> _acaoAceitar() async {
    await _run(() async {
      await _atualizarStatus(_kStAceito);
      _snack('Pedido aceito.');
    });
  }

  Future<void> _acaoRecusar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recusar pedido?'),
        content: const Text(
          'O pedido será marcado como cancelado. Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, recusar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await _atualizarStatus(_kStCancelado);
      _snack('Pedido recusado.');
    });
  }

  Future<void> _acaoIniciarPreparo() async {
    await _run(() async {
      await _atualizarStatus(_kStEmPreparo);
      _snack('Preparo iniciado.');
    });
  }

  Future<void> _acaoSolicitarEntregador() async {
    await _run(() async {
      await callFirebaseFunctionSafe(
        'lojistaSolicitarDespachoEntregador',
        parameters: <String, dynamic>{'pedidoId': widget.pedidoId},
      );
      _snack(
        'Buscando entregador próximo. Você será avisado quando alguém aceitar.',
      );
    });
  }

  Future<void> _acaoProntoRetirada() async {
    await _run(() async {
      await _atualizarStatus(_kStPronto);
      _snack('Pedido pronto para retirada.');
    });
  }

  Future<void> _acaoConfirmarRetirada() async {
    await _run(() async {
      await _atualizarStatus(_kStEntregue);
      _snack('Retirada confirmada.');
    });
  }

  Future<void> _cancelarChamadaViaFirestore() async {
    final ref =
        FirebaseFirestore.instance.collection('pedidos').doc(widget.pedidoId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Pedido não encontrado.');
    final d = snap.data()!;
    if (d['loja_id']?.toString() != widget.uidLoja) {
      throw Exception('Sem permissão.');
    }
    if (d['status'] != _kStAguardandoEntregador) {
      throw Exception('O pedido não está buscando entregador.');
    }
    final entId = d['entregador_id'];
    if (entId != null && entId.toString().isNotEmpty) {
      throw Exception('Já há entregador atribuído.');
    }
    if (d['despacho_job_lock'] != null) {
      await ref.update({'despacho_abort_flag': true});
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final cur = await ref.get();
        final c = cur.data();
        if (c == null || c['despacho_job_lock'] == null) break;
      }
    }
    final finalSnap = await ref.get();
    final fin = finalSnap.data();
    if (fin == null) throw Exception('Pedido não encontrado.');
    if (fin['status'] != _kStAguardandoEntregador) {
      throw Exception('O estado do pedido mudou. Atualize a tela.');
    }
    if (fin['despacho_job_lock'] != null) {
      throw Exception('Aguarde alguns segundos e tente cancelar de novo.');
    }
    await ref.update(<String, dynamic>{
      'status': _kStEmPreparo,
      'despacho_job_lock': FieldValue.delete(),
      'despacho_abort_flag': FieldValue.delete(),
      'despacho_fila_ids': <String>[],
      'despacho_indice_atual': 0,
      'despacho_recusados': <String>[],
      'despacho_bloqueados': <String>[],
      'despacho_oferta_uid': FieldValue.delete(),
      'despacho_oferta_expira_em': FieldValue.delete(),
      'despacho_oferta_seq': 0,
      'despacho_oferta_estado': FieldValue.delete(),
      'despacho_estado': FieldValue.delete(),
      'despacho_sem_entregadores': FieldValue.delete(),
      'despacho_redespacho_loja_em': FieldValue.delete(),
      'despacho_redespacho_entregador_em': FieldValue.delete(),
      'despacho_redirecionado_para_proximo': FieldValue.delete(),
      'despacho_erro_msg': FieldValue.delete(),
      'despacho_aguarda_decisao_lojista': FieldValue.delete(),
      'despacho_macro_ciclo_atual': FieldValue.delete(),
      'despacho_msg_busca_entregador': FieldValue.delete(),
      'despacho_busca_extensao_usada': FieldValue.delete(),
      'despacho_auto_encerrada_sem_entregador': FieldValue.delete(),
      'busca_entregadores_notificados': <String>[],
      'busca_raio_km': FieldValue.delete(),
      'busca_entregador_inicio': FieldValue.delete(),
    });
  }

  Future<void> _acaoCancelarChamada() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar chamada?'),
        content: const Text(
          'A busca por entregador será encerrada. O pedido volta para '
          '“Em preparo” e você poderá solicitar de novo quando quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(() async {
      try {
        await callFirebaseFunctionSafe(
          'lojistaCancelarChamadaEntregador',
          parameters: {'pedidoId': widget.pedidoId},
        );
        _snack(
          'Chamada cancelada. Use “Solicitar entregador” para buscar de novo.',
        );
      } on CallableHttpException catch (e) {
        final podeFs = e.code == 'internal' ||
            e.code == 'unavailable' ||
            e.code == 'deadline-exceeded' ||
            e.code == 'not-found';
        if (podeFs) {
          try {
            await _cancelarChamadaViaFirestore();
            _snack(
              'Chamada cancelada. Use “Solicitar entregador” para buscar de novo.',
            );
          } catch (e2) {
            _snack('${e.message} — $e2', ok: false);
          }
        } else {
          _snack(e.message, ok: false);
        }
      } catch (e) {
        _snack('Erro: $e', ok: false);
      }
    });
  }

  Future<void> _acaoContinuarBuscaEntregadores() async {
    await _run(() async {
      try {
        await callFirebaseFunctionSafe(
          'lojistaContinuarBuscaEntregadores',
          parameters: {'pedidoId': widget.pedidoId},
        );
        _snack(
          'Buscando de novo (até 3 rodadas). Aguarde as ofertas aos entregadores.',
        );
      } on CallableHttpException catch (e) {
        _snack(_msgFn(e), ok: false);
      } catch (e) {
        _snack('Erro: $e', ok: false);
      }
    });
  }

  Future<void> _acaoChamarDeNovo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chamar entregador novamente?'),
        content: const Text(
          'Reinicia a busca do zero: ofertas na ordem de proximidade.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, chamar de novo'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(() async {
      try {
        await callFirebaseFunctionSafe(
          'lojistaRedespacharEntregador',
          parameters: {'pedidoId': widget.pedidoId},
        );
        _snack('Busca reiniciada. Os entregadores serão chamados novamente.');
      } on CallableHttpException catch (e) {
        _snack(_msgFn(e), ok: false);
      } catch (e) {
        _snack('Erro: $e', ok: false);
      }
    });
  }

  bool _isEmPreparo(String s) =>
      s == _kStEmPreparo || s == _kStPreparando;

  /// Cancelamento pelo cliente (app) — motivo gravado em Firestore.
  Widget _painelClienteCancelouPedido(Map<String, dynamic> d) {
    final cod = d['cancelado_cliente_codigo']?.toString().trim() ?? '';
    final det = d['cancelado_cliente_detalhe']?.toString().trim() ?? '';
    String linha;
    switch (cod) {
      case 'desistencia':
        linha = 'Cliente desistiu do pedido.';
        break;
      case 'demora_loja':
        linha = 'Motivo: a loja está demorando para o envio.';
        break;
      case 'outro':
        linha = det.isEmpty ? 'Outro motivo informado pelo cliente.' : det;
        break;
      default:
        linha = 'Cancelamento solicitado pelo cliente.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.red.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancelado pelo cliente',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  linha,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _painelEntregador(Map<String, dynamic> pedido) {
    final nome = pedido['entregador_nome']?.toString() ?? 'Entregador';
    final tel = pedido['entregador_telefone']?.toString() ?? '';
    final veiculo = pedido['entregador_veiculo']?.toString() ?? '';
    final foto = pedido['entregador_foto_url']?.toString() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _roxo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _roxo.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Entregador parceiro',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _roxo,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade300,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty
                    ? const Icon(Icons.delivery_dining, color: _roxo)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (tel.isNotEmpty)
                      Text('Tel. $tel', style: const TextStyle(fontSize: 13)),
                    if (veiculo.isNotEmpty)
                      Text(
                        'Veículo: $veiculo',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botoesAcao(String status, bool isRetirada, Map<String, dynamic> d) {
    final entId = d['entregador_id'];
    final temEntregador =
        entId != null && entId.toString().isNotEmpty;

    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: _roxo)),
      );
    }

    if (status == _kStPendente) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              onPressed: _acaoRecusar,
              child: const Text('Recusar'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: _acaoAceitar,
              child: const Text('Aceitar pedido'),
            ),
          ),
        ],
      );
    }

    if (status == _kStAceito) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _laranja),
          onPressed: _acaoIniciarPreparo,
          child: const Text('Iniciar preparo'),
        ),
      );
    }

    if (_isEmPreparo(status)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isRetirada && d['despacho_auto_encerrada_sem_entregador'] == true) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                (d['despacho_msg_busca_entregador']?.toString() ?? '').trim().isNotEmpty
                    ? d['despacho_msg_busca_entregador'].toString()
                    : 'A busca encerrou automaticamente após várias tentativas. '
                        'Use «Solicitar entregador» para tentar de novo.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade900, height: 1.35),
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _laranja),
              onPressed:
                  isRetirada ? _acaoProntoRetirada : _acaoSolicitarEntregador,
              child: Text(
                isRetirada ? 'Pronto para retirada' : 'Solicitar entregador',
              ),
            ),
          ),
        ],
      );
    }

    if (status == _kStAguardandoEntregador) {
      if (d['despacho_aguarda_decisao_lojista'] == true) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text(
                (d['despacho_msg_busca_entregador']?.toString() ?? '').trim().isNotEmpty
                    ? d['despacho_msg_busca_entregador'].toString()
                    : 'Ainda não encontramos um entregador após 3 rodadas (3 km e 5 km). '
                        'Você pode cancelar a chamada ou continuar buscando por mais 3 rodadas.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade900, height: 1.35),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _acaoContinuarBuscaEntregadores,
                    child: const Text('Continuar buscando'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                    onPressed: _acaoCancelarChamada,
                    child: const Text('Cancelar chamada'),
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              d['despacho_busca_extensao_usada'] == true
                  ? 'Buscando de novo: até 3 rodadas (3 km, depois 5 km). '
                      'Se ninguém aceitar, a chamada encerra e o pedido volta para «Em preparo».'
                  : 'Buscando entregador: até 3 rodadas (3 km, depois 5 km). '
                      'Se ninguém aceitar, você poderá continuar ou cancelar.',
              style: TextStyle(color: Colors.blue.shade900, fontSize: 13, height: 1.35),
            ),
          ),
          if (d['despacho_macro_ciclo_atual'] != null) ...[
            const SizedBox(height: 6),
            Text(
              'Rodada atual: ${d['despacho_macro_ciclo_atual']}/3',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _acaoCancelarChamada,
            icon: const Icon(Icons.close, size: 20),
            label: const Text('Cancelar chamada'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _acaoChamarDeNovo,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Chamar de novo'),
            style: OutlinedButton.styleFrom(foregroundColor: _laranja),
          ),
        ],
      );
    }

    if (isRetirada && status == _kStPronto) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          onPressed: _acaoConfirmarRetirada,
          child: const Text('Confirmar retirada no balcão'),
        ),
      );
    }

    if (!isRetirada &&
        temEntregador &&
        (status == _kStEntregadorIndoLoja ||
            status == _kStSaiuEntrega ||
            status == _kStACaminho ||
            status == _kStEmRota)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Nenhuma ação disponível para este status.',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const AlertDialog(
            content: SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(color: _roxo),
              ),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return AlertDialog(
            title: const Text('Pedido'),
            content: const Text('Pedido não encontrado.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ],
          );
        }

        final d = snap.data!.data()!;
        final ts = d['data_pedido'];
        final dataStr =
            ts is Timestamp ? widget.fmtData.format(ts.toDate()) : '—';
        final itens = d['itens'] as List? ?? [];
        final isRetirada = d['tipo_entrega']?.toString() == 'retirada';
        final sub = widget.num(d['subtotal']);
        final taxa = widget.num(d['taxa_entrega']);
        final taxaPlataforma = widget.num(d['taxa_plataforma']);
        final recebimentoLojista = d['valor_liquido_lojista'] != null
            ? widget.num(d['valor_liquido_lojista'])
            : sub;
        final desc = widget.num(d['desconto_saldo']);
        final total = widget.num(d['total']);
        final forma = d['forma_pagamento']?.toString() ?? '—';
        final endEnt = d['endereco_entrega']?.toString() ?? '—';
        final token = d['token_entrega']?.toString() ?? '';
        final lojaNome = d['loja_nome']?.toString() ?? '';
        final status = d['status']?.toString() ?? 'pendente';
        final nomeCliente = _nomeCliente ?? widget.nomeClienteFallback;
        final entId = d['entregador_id'];
        final mostrarPainelEntregador = !isRetirada &&
            entId != null &&
            entId.toString().isNotEmpty;

        return AlertDialog(
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pedido',
                  style: TextStyle(color: _roxo, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Copiar ID',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.pedidoId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID copiado.')),
                  );
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    widget.pedidoId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _pedidoSecDet('Data', dataStr),
                  _pedidoSecDet('Status', widget.labelStatus(status)),
                  if (status == _kStCancelado &&
                      d['cancelado_motivo']?.toString() ==
                          'cliente_solicitou') ...[
                    const SizedBox(height: 12),
                    _painelClienteCancelouPedido(d),
                  ],
                  if (lojaNome.isNotEmpty)
                    _pedidoSecDet('Loja (registro)', lojaNome),
                  _pedidoSecDet('Cliente', nomeCliente),
                  _pedidoSecDet(
                    isRetirada ? 'Retirada' : 'Entrega',
                    isRetirada ? 'Retirada no balcão' : endEnt,
                  ),
                  _pedidoSecDet('Pagamento', forma),
                  if (token.isNotEmpty)
                    _pedidoSecDet('Token de entrega', token),
                  if (mostrarPainelEntregador) ...[
                    const SizedBox(height: 12),
                    _painelEntregador(d),
                  ],
                  const Divider(height: 28),
                  const Text(
                    'Itens',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  ...itens.map((raw) {
                    if (raw is! Map) return const SizedBox.shrink();
                    final m = Map<String, dynamic>.from(raw);
                    final nome = m['nome']?.toString() ?? '?';
                    final qRaw = m['quantidade'] ?? 1;
                    final qn = qRaw is num
                        ? qRaw.toDouble()
                        : double.tryParse('$qRaw') ?? 1;
                    final qDisp = (qn - qn.round()).abs() < 0.001
                        ? qn.round().toString()
                        : qn.toStringAsFixed(1);
                    final pu = widget.num(m['preco']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${qDisp}x',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(nome)),
                          Text(widget.moeda.format(pu * qn)),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 28),
                  _pedidoLinhaVal('Subtotal produtos', widget.moeda.format(sub)),
                  if (taxaPlataforma > 0)
                    _pedidoLinhaVal(
                      'Taxa da plataforma',
                      widget.moeda.format(taxaPlataforma),
                      destaque: Colors.deepPurple.shade700,
                    ),
                  if (taxa > 0 && !isRetirada)
                    _pedidoLinhaVal(
                      'Taxa de entrega',
                      widget.moeda.format(taxa),
                      destaque: Colors.red.shade700,
                    ),
                  if (desc > 0)
                    _pedidoLinhaVal(
                      'Desconto (saldo app)',
                      '- ${widget.moeda.format(desc)}',
                      destaque: Colors.green.shade800,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total do pedido',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        widget.moeda.format(total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: _laranja,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Seu recebimento líquido (carteira): '
                      '${widget.moeda.format(recebimentoLojista)}',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Ações',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _roxo,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _botoesAcao(status, isRetirada, d),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }
}

Widget _pedidoSecDet(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            k,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(v, style: const TextStyle(fontSize: 14)),
        ),
      ],
    ),
  );
}

Widget _pedidoLinhaVal(String k, String v, {Color? destaque}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: destaque,
          ),
        ),
      ],
    ),
  );
}
