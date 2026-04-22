// Arquivo: lib/screens/cliente/orders_screen.dart

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/screens/cliente/avaliar_pedido_sheet.dart';
import 'package:depertin_cliente/widgets/badge_entregador_acessibilidade.dart';
import 'package:depertin_cliente/widgets/chat_pedido_botao.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

enum _FiltroPedidos { andamento, todos }

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  _FiltroPedidos _filtro = _FiltroPedidos.andamento;
  String? _cancelandoPedidoId;
  bool _filtroInicializadoPorRota = false;
  bool _mostrarVoltarVitrine = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  /// Garante comparação com [PedidoStatus] mesmo se o Firestore vier com espaços/caso diferente.
  static String _normalizarStatus(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (s.isEmpty) return 'pendente';
    return s;
  }

  /// Últimos caracteres do ID para identificação rápida em suporte.
  static String _idCurto(String pedidoId) {
    if (pedidoId.length <= 8) return pedidoId.toUpperCase();
    return pedidoId.substring(pedidoId.length - 8).toUpperCase();
  }

  /// Retorna etapas da timeline e se o preparo na cozinha já começou (`em_preparo`).
  /// [preparoIniciado] distingue **aceito** (loja aceitou, preparo ainda não) de **em_preparo**.
  static ({int concluidas, int ativa, bool aguardandoPix, bool preparoIniciado})
      _estadoTimeline(String status) {
    switch (status) {
      case PedidoStatus.cancelado:
        return (
          concluidas: 0,
          ativa: -1,
          aguardandoPix: false,
          preparoIniciado: false,
        );
      case PedidoStatus.entregue:
        return (
          concluidas: 4,
          ativa: -1,
          aguardandoPix: false,
          preparoIniciado: false,
        );
      case PedidoStatus.aguardandoPagamento:
        return (
          concluidas: 0,
          ativa: 0,
          aguardandoPix: true,
          preparoIniciado: false,
        );
      case PedidoStatus.pendente:
      case PedidoStatus.aceito:
        return (
          concluidas: 1,
          ativa: 1,
          aguardandoPix: false,
          preparoIniciado: false,
        );
      case PedidoStatus.emPreparo:
      case PedidoStatus.pronto:
        return (
          concluidas: 1,
          ativa: 1,
          aguardandoPix: false,
          preparoIniciado: true,
        );
      case PedidoStatus.aguardandoEntregador:
      case PedidoStatus.entregadorIndoLoja:
        return (
          concluidas: 2,
          ativa: 2,
          aguardandoPix: false,
          preparoIniciado: true,
        );
      case PedidoStatus.saiuEntrega:
      case PedidoStatus.aCaminho:
      case PedidoStatus.emRota:
        return (
          concluidas: 3,
          ativa: 3,
          aguardandoPix: false,
          preparoIniciado: true,
        );
      default:
        return (
          concluidas: 0,
          ativa: 0,
          aguardandoPix: false,
          preparoIniciado: false,
        );
    }
  }

  static String? _dicaProximoPasso(String status) {
    switch (status) {
      case PedidoStatus.aguardandoPagamento:
        return 'Conclua o pagamento para enviar o pedido à loja.';
      case PedidoStatus.pendente:
        return 'Aguarde a loja aceitar seu pedido.';
      case PedidoStatus.aceito:
        return 'Pedido aceito pela loja. Aguarde o início do preparo.';
      case PedidoStatus.emPreparo:
      case PedidoStatus.pronto:
        return 'Seu pedido está sendo preparado neste momento.';
      case PedidoStatus.aguardandoEntregador:
        return 'Estamos encontrando um entregador próximo.';
      case PedidoStatus.entregadorIndoLoja:
        return 'O entregador está indo até a loja.';
      case PedidoStatus.saiuEntrega:
      case PedidoStatus.aCaminho:
      case PedidoStatus.emRota:
        return 'Tenha o código de confirmação em mãos na entrega.';
      case PedidoStatus.entregue:
        return null;
      case PedidoStatus.cancelado:
        return null;
      default:
        return null;
    }
  }

  Future<void> _cancelarPedidoAguardandoPix(
    BuildContext context,
    String pedidoId,
  ) async {
    final snapPedido = await FirebaseFirestore.instance
        .collection('pedidos')
        .doc(pedidoId)
        .get();
    final pd = snapPedido.data() ?? {};
    final rawGrupo = pd['checkout_grupo_pedido_ids'];
    final idsGrupo = <String>{pedidoId};
    if (rawGrupo is List) {
      for (final e in rawGrupo) {
        final s = e.toString().trim();
        if (s.isNotEmpty) idsGrupo.add(s);
      }
    }
    final multiLoja = idsGrupo.length > 1;

    if (!context.mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido?'),
        content: Text(
          multiLoja
              ? 'O PIX deste pagamento vale para ${idsGrupo.length} pedidos (várias lojas). '
                  'Todos serão cancelados e o PIX deixará de ser válido. Esta ação não pode ser desfeita.'
              : 'O PIX deste pedido deixará de ser válido e o pedido será cancelado. '
                  'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    setState(() => _cancelandoPedidoId = pedidoId);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in idsGrupo) {
        final r = FirebaseFirestore.instance.collection('pedidos').doc(id);
        final s = await r.get();
        if (!s.exists) continue;
        final st = (s.data()?['status'] ?? '').toString();
        if (st != PedidoStatus.aguardandoPagamento) continue;
        batch.update(r, {
          'status': PedidoStatus.cancelado,
          'cancelado_motivo': 'cliente_cancelou_pix',
          'cancelado_em': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              multiLoja ? 'Pedidos cancelados.' : 'Pedido cancelado.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível cancelar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelandoPedidoId = null);
    }
  }

  Future<void> _cancelarPedidoEmAndamentoComMotivo(
    BuildContext context,
    String pedidoId, {
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) async {
    final formaPagLower =
        (pedido['forma_pagamento'] ?? '').toString().toLowerCase();
    final pagamentoDinheiro = formaPagLower.contains('dinheiro');

    if (PedidoStatus.clienteCancelamentoParcialFreteRetido.contains(
          statusAtual,
        ) &&
        !pagamentoDinheiro &&
        context.mounted) {
      final taxa = _toDouble(pedido['taxa_entrega']);
      final total = _toDouble(pedido['total']);
      final reembolso = (total - taxa).clamp(0.0, total);
      final lojaNome = (pedido['loja_nome'] ?? 'Loja').toString().trim();
      final aceitaPolitica = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cancelar após saída para entrega',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'O entregador já está a caminho do seu endereço. Se você cancelar agora:',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '• O pedido será cancelado.\n'
                  '• O valor da entrega (taxa do entregador) não será reembolsado.\n'
                  '• Será solicitado o reembolso pelo app apenas do valor dos produtos (e descontos já aplicados no total).',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Resumo (referência)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: diPertinRoxo,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Loja: $lojaNome\n'
                  'Total pago: ${_moeda.format(total)}\n'
                  'Taxa de entrega: ${_moeda.format(taxa)}\n'
                  'Estorno estimado ao pagador: ${_moeda.format(reembolso)}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Os valores finais seguem o processamento do pagamento (ex.: Mercado Pago).',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Li e quero cancelar'),
            ),
          ],
        ),
      );
      if (aceitaPolitica != true || !context.mounted) return;
    }

    final idsGrupoPedido = <String>{pedidoId};
    final rawGrupoPedido = pedido['checkout_grupo_pedido_ids'];
    if (rawGrupoPedido is List) {
      for (final e in rawGrupoPedido) {
        final s = e.toString().trim();
        if (s.isNotEmpty) idsGrupoPedido.add(s);
      }
    }
    final checkoutVariasLojas =
        idsGrupoPedido.length > 1 && !pagamentoDinheiro;

    final escolha = await showModalBottomSheet<_MotivoCancelCliente>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SheetMotivoCancelamentoCliente(
        avisoCheckoutVariasLojas: checkoutVariasLojas,
      ),
    );
    if (escolha == null || !context.mounted) return;

    setState(() => _cancelandoPedidoId = pedidoId);
    try {
      final patch = <String, dynamic>{
        'status': PedidoStatus.cancelado,
        'cancelado_motivo': PedidoStatus.canceladoMotivoClienteSolicitou,
        'cancelado_em': FieldValue.serverTimestamp(),
        'cancelado_cliente_codigo': escolha.codigo,
      };
      if (escolha.codigo == PedidoStatus.cancelClienteCodOutro) {
        patch['cancelado_cliente_detalhe'] = escolha.detalhe.trim();
      }
      await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .update(patch);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              checkoutVariasLojas
                  ? 'Pedido cancelado. Os demais pedidos do mesmo pagamento permanecem ativos; o estorno no Mercado Pago será proporcional a este pedido. A loja foi notificada.'
                  : 'Pedido cancelado. A loja foi notificada.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível cancelar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelandoPedidoId = null);
    }
  }

  void _mostrarComoFunciona(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Como acompanhar seu pedido',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: diPertinRoxo,
              ),
            ),
            const SizedBox(height: 16),
            _bulletComoFunciona(
              'A linha acima do card mostra em que etapa você está.',
            ),
            _bulletComoFunciona(
              'Use o chat para falar com a loja sobre o pedido.',
            ),
            _bulletComoFunciona(
              'Quando o entregador sair, aparecerá o código para você '
              'informar na entrega.',
            ),
            _bulletComoFunciona(
              'Em "Todos" você vê o histórico completo.',
            ),
          ],
        ),
      ),
    );
  }

  static Widget _bulletComoFunciona(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: diPertinRoxo, fontSize: 16)),
          Expanded(
            child: Text(texto, style: const TextStyle(height: 1.45)),
          ),
        ],
      ),
    );
  }

  /// Linhas finais do bloco "Valores" no resumo: total pago ou reembolso (parcial/total).
  static List<Widget> _linhasValorResumoPedido(Map<String, dynamic> pedido) {
    final status = _normalizarStatus(pedido['status']);
    final refundOk =
        (pedido['mp_refund_status']?.toString() ?? '') == 'succeeded';
    final parcial = pedido['mp_refund_parcial_frete_retido'] == true;
    final total = _toDouble(pedido['total']);
    final taxa = _toDouble(pedido['taxa_entrega']);
    final valorCalcMp = pedido['mp_refund_valor_calculado'];

    if (status == PedidoStatus.cancelado && refundOk && parcial) {
      final vReembolso = valorCalcMp != null
          ? _toDouble(valorCalcMp)
          : (total - taxa).clamp(0.0, total);
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Text(
            'Reembolso parcial: devolvemos apenas o valor dos produtos. '
            'A taxa de entrega não entra nesse reembolso.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.grey[900],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Valor reembolsado (produtos)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              _moeda.format(vReembolso),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: diPertinLaranja,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total pago no pedido',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            Text(
              _moeda.format(total),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ];
    }

    if (status == PedidoStatus.cancelado && refundOk) {
      final vTot = _toDouble(pedido['mp_refund_total'] ?? valorCalcMp ?? total);
      return [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Valor reembolsado',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _moeda.format(vTot > 0 ? vTot : total),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: diPertinLaranja,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Reembolso referente ao valor pago no pedido.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ];
    }

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Text(
            _moeda.format(total),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: diPertinLaranja,
            ),
          ),
        ],
      ),
    ];
  }

  void _mostrarDetalhesPedido(
    BuildContext context,
    Map<String, dynamic> pedido,
  ) {
    final itens = pedido['itens'] as List<dynamic>? ?? [];
    final formaPag = pedido['forma_pagamento']?.toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Resumo do pedido',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: diPertinRoxo,
                ),
              ),
              const SizedBox(height: 16),
              _tituloSecaoSheet('Itens'),
              const Divider(height: 20),
              ...itens.map((item) {
                if (item is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(item);
                final qtd = _toDouble(m['quantidade'], 1);
                final preco = _toDouble(m['preco']);
                final nome = m['nome']?.toString() ?? 'Item';
                final sub = qtd * preco;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${qtd.toStringAsFixed(qtd == qtd.roundToDouble() ? 0 : 1)}x $nome',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(_moeda.format(sub)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              _tituloSecaoSheet('Valores'),
              const Divider(height: 20),
              _rowFinanceira('Subtotal', pedido['subtotal']),
              _rowFinanceira('Taxa de entrega', pedido['taxa_entrega']),
              const SizedBox(height: 12),
              ..._linhasValorResumoPedido(pedido),
              if (formaPag != null && formaPag.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Pagamento: $formaPag',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 22),
              _tituloSecaoSheet('Entrega'),
              const Divider(height: 16),
              Text(
                pedido['endereco_entrega']?.toString() ?? 'Não informado',
                style: TextStyle(color: Colors.grey[800], height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _tituloSecaoSheet(String titulo) {
    return Text(
      titulo,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: Colors.grey[700],
      ),
    );
  }

  Widget _rowFinanceira(String rotulo, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: TextStyle(color: Colors.grey[600])),
          Text(_moeda.format(_toDouble(valor))),
        ],
      ),
    );
  }

  Widget _construirStatus(String statusDb, Map<String, dynamic> pedido) {
    var texto = 'Processando';
    Color cor = Colors.grey;
    switch (statusDb) {
      case 'aguardando_pagamento':
        final forma = (pedido['forma_pagamento'] ?? '').toString().toLowerCase();
        final subtipo = (pedido['pagamento_cartao_tipo_solicitado'] ?? '')
            .toString()
            .toLowerCase();
        if (forma.contains('cart')) {
          texto = subtipo == 'debito'
              ? 'Aguardando cartão (débito)'
              : 'Aguardando cartão (crédito)';
        } else {
          texto = 'Aguardando PIX';
        }
        cor = Colors.deepOrange;
        break;
      case 'pendente':
        texto = 'Aguardando loja';
        cor = diPertinLaranja;
        break;
      case 'aceito':
        texto = 'Pedido aceito';
        cor = Colors.green.shade700;
        break;
      case 'em_preparo':
        texto = 'Em preparo';
        cor = Colors.blue;
        break;
      case 'aguardando_entregador':
        texto = 'Buscando entregador';
        cor = Colors.indigo;
        break;
      case 'entregador_indo_loja':
        texto = 'Entregador a caminho da loja';
        cor = Colors.deepPurple;
        break;
      case 'saiu_entrega':
        texto = 'Saiu para entrega';
        cor = Colors.teal;
        break;
      case 'pronto':
        texto = 'Pronto para retirada';
        cor = Colors.brown;
        break;
      case 'a_caminho':
      case 'em_rota':
        texto = 'Em entrega';
        cor = Colors.teal;
        break;
      case 'entregue':
        texto = 'Entregue';
        cor = Colors.green;
        break;
      case 'cancelado':
        texto = 'Cancelado';
        cor = Colors.red;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.6)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  static bool _emAndamento(String status) {
    return status != 'entregue' && status != 'cancelado';
  }

  static String _formatarDataPedido(Map<String, dynamic> pedido) {
    final t = pedido['data_pedido'];
    if (t is! Timestamp) return '—';
    return DateFormat("dd/MM/yyyy 'às' HH:mm").format(t.toDate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filtroInicializadoPorRota) return;
    _filtroInicializadoPorRota = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final filtroArg = (args['filtro'] ?? '').toString().toLowerCase().trim();
      final mostrarTodos = args['mostrarTodos'] == true;
      _mostrarVoltarVitrine = args['mostrarVoltarVitrine'] == true;
      if (filtroArg == 'todos' || mostrarTodos) {
        _filtro = _FiltroPedidos.todos;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F7),
      appBar: AppBar(
        leading: _mostrarVoltarVitrine
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Voltar para vitrine',
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/home', (route) => false);
                },
              )
            : null,
        title: const Text('Meus pedidos'),
        backgroundColor: diPertinRoxo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: user == null
          ? const Center(child: Text('Faça login para ver seus pedidos.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pedidos')
                  .where('cliente_id', isEqualTo: user.uid)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: diPertinRoxo),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar os pedidos. '
                        'Verifique a conexão e tente novamente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[800]),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = List<QueryDocumentSnapshot>.from(
                  snapshot.data!.docs,
                );

                docs.sort((a, b) {
                  final dataA =
                      (a.data() as Map<String, dynamic>)['data_pedido']
                          as Timestamp?;
                  final dataB =
                      (b.data() as Map<String, dynamic>)['data_pedido']
                          as Timestamp?;
                  if (dataA == null) return 1;
                  if (dataB == null) return -1;
                  return dataB.compareTo(dataA);
                });

                final filtrados = _filtro == _FiltroPedidos.todos
                    ? docs
                    : docs
                          .where(
                            (d) => _emAndamento(
                              _normalizarStatus(
                                (d.data() as Map<String, dynamic>)['status'],
                              ),
                            ),
                          )
                          .toList();

                return RefreshIndicator(
                  color: diPertinLaranja,
                  onRefresh: () async {
                    await FirebaseFirestore.instance
                        .collection('pedidos')
                        .where('cliente_id', isEqualTo: user.uid)
                        .get(const GetOptions(source: Source.server));
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Acompanhe cada etapa abaixo. Toque em '
                                  '"Como funciona" para ver dicas.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _mostrarComoFunciona(context),
                                child: const Text('Como funciona'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SegmentedButton<_FiltroPedidos>(
                            segments: const [
                              ButtonSegment(
                                value: _FiltroPedidos.andamento,
                                label: Text('Em andamento'),
                                icon: Icon(Icons.schedule, size: 18),
                              ),
                              ButtonSegment(
                                value: _FiltroPedidos.todos,
                                label: Text('Todos'),
                                icon: Icon(Icons.list_alt, size: 18),
                              ),
                            ],
                            selected: {_filtro},
                            onSelectionChanged: (s) {
                              setState(() => _filtro = s.first);
                            },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.selected)) {
                                  return diPertinRoxo;
                                }
                                return Colors.black87;
                              }),
                            ),
                          ),
                        ),
                      ),
                      if (docs.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyNuncaPediu(context),
                        )
                      else if (filtrados.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyFiltro(context),
                        )
                      else
                        ..._buildSliversAgrupados(filtrados),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Agrupa pedidos por `checkout_grupo_id` (multi-loja). Pedidos sem grupo
  /// são tratados como grupo de 1 (single-store, comportamento legado).
  /// Retorna a lista de slivers já com headers de grupo + cards.
  List<Widget> _buildSliversAgrupados(
    List<QueryDocumentSnapshot> docs,
  ) {
    final ordemGrupos = <String>[];
    final grupos = <String, List<QueryDocumentSnapshot>>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final grupoId = (data['checkout_grupo_id'] ?? '').toString().trim();
      final chave = grupoId.isNotEmpty ? 'g:$grupoId' : 'p:${doc.id}';
      if (!grupos.containsKey(chave)) {
        grupos[chave] = [];
        ordemGrupos.add(chave);
      }
      grupos[chave]!.add(doc);
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final chave = ordemGrupos[index];
              final docsGrupo = grupos[chave]!;
              final ehMultiLoja = docsGrupo.length > 1;

              if (!ehMultiLoja) {
                final doc = docsGrupo.first;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _streamCardPedido(doc),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _construirEnvelopeMultiLoja(
                  docsGrupo: docsGrupo,
                ),
              );
            },
            childCount: ordemGrupos.length,
          ),
        ),
      ),
    ];
  }

  /// Card individual com stream realtime do documento. Reutilizado por
  /// pedidos single-store e por cada loja dentro do envelope multi-loja.
  Widget _streamCardPedido(QueryDocumentSnapshot doc) {
    final pedidoId = doc.id;
    final pedidoFallback = doc.data() as Map<String, dynamic>;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .snapshots(includeMetadataChanges: true),
      builder: (context, docSnap) {
        final pedido = (docSnap.hasData &&
                docSnap.data!.exists &&
                docSnap.data!.data() != null)
            ? docSnap.data!.data()!
            : pedidoFallback;
        final statusAtual = _normalizarStatus(pedido['status']);
        return _construirCardPedido(
          context: context,
          pedidoId: pedidoId,
          pedido: pedido,
          statusAtual: statusAtual,
        );
      },
    );
  }

  /// Envelope visual para checkout multi-loja. Mostra cabeçalho com
  /// resumo do pagamento único + cards de cada loja agrupados.
  Widget _construirEnvelopeMultiLoja({
    required List<QueryDocumentSnapshot> docsGrupo,
  }) {
    var totalGrupo = 0.0;
    var qtdAtivos = 0;
    var qtdCancelados = 0;
    var qtdEntregues = 0;
    String? formaPag;
    DateTime? dataMaisRecente;

    for (final d in docsGrupo) {
      final data = d.data() as Map<String, dynamic>;
      final st = _normalizarStatus(data['status']);
      totalGrupo += _toDouble(data['total']);
      if (st == 'cancelado') {
        qtdCancelados++;
      } else if (st == 'entregue') {
        qtdEntregues++;
      } else {
        qtdAtivos++;
      }
      formaPag ??= data['forma_pagamento']?.toString();
      final ts = data['data_pedido'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (dataMaisRecente == null || dt.isAfter(dataMaisRecente)) {
          dataMaisRecente = dt;
        }
      }
    }

    final qtdLojas = docsGrupo.length;
    final dataStr = dataMaisRecente != null
        ? DateFormat("dd/MM/yyyy 'às' HH:mm").format(dataMaisRecente)
        : '—';

    String statusResumo;
    Color corStatus;
    if (qtdCancelados == qtdLojas) {
      statusResumo = 'Todas canceladas';
      corStatus = Colors.red.shade700;
    } else if (qtdEntregues == qtdLojas) {
      statusResumo = 'Todas entregues';
      corStatus = Colors.green.shade700;
    } else if (qtdAtivos > 0) {
      statusResumo = '$qtdAtivos em andamento';
      corStatus = diPertinLaranja;
    } else {
      statusResumo = 'Concluído';
      corStatus = Colors.green.shade700;
    }

    return Container(
      decoration: BoxDecoration(
        color: diPertinRoxo.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: diPertinRoxo.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: diPertinRoxo.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: diPertinRoxo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_bag,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Compra de $qtdLojas lojas',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: diPertinRoxo,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pagamento único · $dataStr',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: corStatus.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: corStatus.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        statusResumo,
                        style: TextStyle(
                          color: corStatus,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total pago',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _moeda.format(totalGrupo),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: diPertinLaranja,
                          ),
                        ),
                      ],
                    ),
                    if (formaPag != null && formaPag.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            formaPag,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Cada loja prepara e entrega seu pedido separadamente. '
                          'Acompanhe abaixo.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[800],
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < docsGrupo.length; i++) ...[
            _streamCardPedido(docsGrupo[i]),
            if (i < docsGrupo.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _construirCardPedido({
    required BuildContext context,
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final total = _toDouble(pedido['total']);
    final dataStr = _formatarDataPedido(pedido);
    final idCurto = _idCurto(pedidoId);
    final dica = _dicaProximoPasso(statusAtual);

    var tokenReal = pedido['token_entrega']?.toString() ?? '';
    if (tokenReal.isEmpty && pedidoId.length >= 6) {
      tokenReal = pedidoId.substring(pedidoId.length - 6).toUpperCase();
    }

    return Card(
      key: ValueKey('$pedidoId-$statusAtual'),
      elevation: 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                        pedido['loja_nome'] ?? 'Loja',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pedido · $idCurto',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dataStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _construirStatus(statusAtual, pedido),
              ],
            ),
            const SizedBox(height: 14),
            _LinhaTempoPedido(
              status: statusAtual,
              estado: _estadoTimeline(statusAtual),
              pedido: pedido,
            ),
                                        if (dica != null) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.lightbulb_outline,
                                                size: 18,
                                                color: diPertinLaranja
                                                    .withValues(alpha: 0.9),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  dica,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.35,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (statusAtual ==
                                            PedidoStatus.aguardandoPagamento) ...[
                                          const SizedBox(height: 14),
                                          SizedBox(
                                            height: 46,
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed:
                                                  _cancelandoPedidoId == pedidoId
                                                  ? null
                                                  : () =>
                                                        _cancelarPedidoAguardandoPix(
                                                          context,
                                                          pedidoId,
                                                        ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                                side: const BorderSide(
                                                  color: Colors.red,
                                                ),
                                              ),
                                              icon: _cancelandoPedidoId ==
                                                      pedidoId
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.red,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 20,
                                                    ),
                                              label: Text(
                                                _cancelandoPedidoId == pedidoId
                                                    ? 'Cancelando…'
                                                    : 'Cancelar pedido',
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (PedidoStatus
                                            .clientePodeCancelarAposPagamento
                                            .contains(statusAtual)) ...[
                                          const SizedBox(height: 14),
                                          SizedBox(
                                            height: 46,
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed:
                                                  _cancelandoPedidoId == pedidoId
                                                  ? null
                                                  : () =>
                                                        _cancelarPedidoEmAndamentoComMotivo(
                                                          context,
                                                          pedidoId,
                                                          pedido: pedido,
                                                          statusAtual:
                                                              statusAtual,
                                                        ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                                side: const BorderSide(
                                                  color: Colors.red,
                                                ),
                                              ),
                                              icon: _cancelandoPedidoId ==
                                                      pedidoId
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.red,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 20,
                                                    ),
                                              label: Text(
                                                _cancelandoPedidoId == pedidoId
                                                    ? 'Cancelando…'
                                                    : 'Cancelar pedido',
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (total > 0) ...[
                                          const SizedBox(height: 14),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey[200]!,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Total do pedido',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _moeda.format(total),
                                                  style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w800,
                                                    color: diPertinLaranja,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (statusAtual == PedidoStatus.aCaminho ||
                                            statusAtual == PedidoStatus.emRota ||
                                            statusAtual ==
                                                PedidoStatus
                                                    .aguardandoEntregador ||
                                            statusAtual ==
                                                PedidoStatus
                                                    .entregadorIndoLoja ||
                                            statusAtual ==
                                                PedidoStatus.saiuEntrega) ...[
                                          const SizedBox(height: 14),
                                          BadgeEntregadorAcessibilidade(
                                            audicao: pedido[
                                                    'entregador_acessibilidade_audicao']
                                                ?.toString(),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.green.withValues(
                                                  alpha: 0.45,
                                                ),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                const Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.delivery_dining,
                                                      color: Colors.green,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        'Entrega em andamento',
                                                        style: TextStyle(
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Informe este código ao entregador '
                                                  'para concluir a entrega. '
                                                  'Não publique em redes sociais.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.grey[800],
                                                    fontSize: 13,
                                                    height: 1.35,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.06,
                                                            ),
                                                        blurRadius: 4,
                                                      ),
                                                    ],
                                                  ),
                                                  child: SelectableText(
                                                    tokenReal,
                                                    style: const TextStyle(
                                                      fontSize: 26,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 6,
                                                      color: diPertinRoxo,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                OutlinedButton.icon(
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                      ClipboardData(
                                                        text: tokenReal,
                                                      ),
                                                    );
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Código copiado.',
                                                          ),
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.copy,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    'Copiar código',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const Divider(height: 22),
                                        SizedBox(
                                          height: 48,
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed: () =>
                                                _mostrarDetalhesPedido(
                                                  context,
                                                  pedido,
                                                ),
                                            child: const Text('Ver detalhes'),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildAcaoChatOuAvaliacao(
                                          context: context,
                                          pedidoId: pedidoId,
                                          pedido: pedido,
                                          statusAtual: statusAtual,
                                        ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyNuncaPediu(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 80,
            color: diPertinRoxo.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhum pedido ainda',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Explore a vitrine ou a busca e monte seu primeiro pedido. '
            'Tudo o que você comprar aparecerá aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/home');
            },
            style: FilledButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Ir para a vitrine'),
          ),
        ],
      ),
    );
  }

  /// Ações na base do card do pedido:
  /// - **Em andamento**: botão de chat com a loja (badge de mensagens novas).
  /// - **Entregue**: avaliar/mostrar avaliação + "Ver conversa" (histórico).
  /// - **Cancelado**: apenas "Ver conversa" (histórico), se houver.
  Widget _buildAcaoChatOuAvaliacao({
    required BuildContext context,
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final lojaId = pedido['loja_id']?.toString() ?? '';
    final lojaNome = pedido['loja_nome']?.toString() ?? 'Loja';

    final botaoHistorico = ChatPedidoBotao(
      pedidoId: pedidoId,
      lojaId: lojaId,
      lojaNome: lojaNome,
      rotuloAtivo: 'Ver conversa',
      rotuloEncerrado: 'Ver conversa',
      encerrado: true,
    );

    if (statusAtual == PedidoStatus.cancelado) {
      return botaoHistorico;
    }

    if (statusAtual != PedidoStatus.entregue) {
      return ChatPedidoBotao(
        pedidoId: pedidoId,
        lojaId: lojaId,
        lojaNome: lojaNome,
        rotuloAtivo: 'Chat com a loja',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('avaliacoes')
          .doc(pedidoId)
          .snapshots(),
      builder: (context, snap) {
        final jaAvaliou = snap.hasData && snap.data!.exists;
        if (!jaAvaliou) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => mostrarAvaliarPedidoSheet(
                    context,
                    pedidoId: pedidoId,
                    lojaId: lojaId,
                    lojaNome: lojaNome,
                  ),
                  icon: const Icon(Icons.star_rate_rounded),
                  label: const Text('Avaliar pedido'),
                ),
              ),
              const SizedBox(height: 8),
              botaoHistorico,
            ],
          );
        }

        final map = snap.data!.data();
        final nota = (map != null && map['nota'] is num)
            ? (map['nota'] as num).toInt().clamp(1, 5)
            : 5;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sua avaliação',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ...List.generate(5, (i) {
                        final preenchida = i < nota;
                        return Icon(
                          preenchida
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: preenchida
                              ? Colors.amber.shade700
                              : Colors.grey.shade400,
                          size: 22,
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            botaoHistorico,
            const SizedBox(height: 6),
            Text(
              'O chat foi encerrado após a entrega.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyFiltro(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 72,
            color: diPertinRoxo.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum pedido em andamento',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Seus pedidos ativos foram concluídos ou cancelados. '
            'Veja o histórico completo em "Todos".',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => setState(() => _filtro = _FiltroPedidos.todos),
            style: FilledButton.styleFrom(
              backgroundColor: diPertinRoxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: const Text('Ver todos os pedidos'),
          ),
        ],
      ),
    );
  }
}

class _MotivoCancelCliente {
  _MotivoCancelCliente({required this.codigo, this.detalhe = ''});

  final String codigo;
  final String detalhe;
}

class _SheetMotivoCancelamentoCliente extends StatefulWidget {
  const _SheetMotivoCancelamentoCliente({this.avisoCheckoutVariasLojas = false});

  /// Checkout com mais de um pedido (várias lojas) e pagamento online.
  final bool avisoCheckoutVariasLojas;

  @override
  State<_SheetMotivoCancelamentoCliente> createState() =>
      _SheetMotivoCancelamentoClienteState();
}

class _SheetMotivoCancelamentoClienteState
    extends State<_SheetMotivoCancelamentoCliente> {
  String? _codigo;
  final _detalheCtrl = TextEditingController();

  @override
  void dispose() {
    _detalheCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cancelar pedido',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Informe o motivo. A loja receberá esta mensagem.',
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.35),
          ),
          if (widget.avisoCheckoutVariasLojas) ...[
            const SizedBox(height: 12),
            Text(
              'Este pagamento inclui pedidos de outras lojas. Será cancelado apenas este pedido; os outros seguem ativos e pagos. O estorno no cartão ou PIX será só do valor deste pedido (taxa de entrega segue a regra do app).',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.blueGrey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: PedidoStatus.cancelClienteCodDesistencia,
            groupValue: _codigo,
            onChanged: (v) => setState(() => _codigo = v),
            title: const Text('Desisti do pedido'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: PedidoStatus.cancelClienteCodDemoraLoja,
            groupValue: _codigo,
            onChanged: (v) => setState(() => _codigo = v),
            title: const Text('A loja está demorando para o envio'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: PedidoStatus.cancelClienteCodOutro,
            groupValue: _codigo,
            onChanged: (v) => setState(() => _codigo = v),
            title: const Text('Outro'),
          ),
          if (_codigo == PedidoStatus.cancelClienteCodOutro) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _detalheCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Descreva o motivo',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              if (_codigo == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione um motivo.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (_codigo == PedidoStatus.cancelClienteCodOutro &&
                  _detalheCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Escreva o motivo em "Outro".'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(
                context,
                _MotivoCancelCliente(
                  codigo: _codigo!,
                  detalhe: _detalheCtrl.text,
                ),
              );
            },
            child: const Text('Confirmar cancelamento'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }
}

/// Linha do tempo em 4 etapas: Confirmado → Preparando → A caminho → Entregue
class _LinhaTempoPedido extends StatelessWidget {
  const _LinhaTempoPedido({
    required this.status,
    required this.estado,
    this.pedido,
  });

  final String status;
  final ({
    int concluidas,
    int ativa,
    bool aguardandoPix,
    bool preparoIniciado,
  }) estado;
  final Map<String, dynamic>? pedido;

  static String? _subtituloCancelamentoCliente(Map<String, dynamic>? pedido) {
    if (pedido == null) return null;
    if (pedido['cancelado_motivo']?.toString() !=
        PedidoStatus.canceladoMotivoClienteSolicitou) {
      return null;
    }
    final cod = pedido['cancelado_cliente_codigo']?.toString().trim() ?? '';
    final det = pedido['cancelado_cliente_detalhe']?.toString().trim() ?? '';
    switch (cod) {
      case PedidoStatus.cancelClienteCodDesistencia:
        return 'Motivo: desistência do pedido.';
      case PedidoStatus.cancelClienteCodDemoraLoja:
        return 'Motivo: demora no envio da loja.';
      case PedidoStatus.cancelClienteCodOutro:
        return det.isEmpty ? 'Motivo: outro.' : 'Motivo: $det';
      default:
        return null;
    }
  }

  static const _labels = [
    'Confirmado',
    'Preparando',
    'A caminho',
    'Entregue',
  ];

  static bool _emUltimaMilha(String s) {
    return s == PedidoStatus.saiuEntrega ||
        s == PedidoStatus.aCaminho ||
        s == PedidoStatus.emRota;
  }

  String _textoEtapa(int i) {
    if (i != 3) return _labels[i];
    if (status == PedidoStatus.entregue) return 'Entregue';
    if (_emUltimaMilha(status)) return 'Em entrega';
    return _labels[i];
  }

  @override
  Widget build(BuildContext context) {
    if (status == PedidoStatus.cancelado) {
      final sub = _subtituloCancelamentoCliente(pedido);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este pedido foi cancelado.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (sub != null) ...[
              const SizedBox(height: 8),
              Text(
                sub,
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final c = estado.concluidas;
    final a = estado.ativa;
    final agPix = estado.aguardandoPix;
    final prep = estado.preparoIniciado;
    final entregue = status == PedidoStatus.entregue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: entregue || c >= i
                            ? diPertinRoxo.withValues(alpha: 0.45)
                            : Colors.grey[300],
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    _bolinha(
                      index: i,
                      status: status,
                      concluidas: c,
                      ativa: a,
                      aguardandoPix: agPix,
                      entregue: entregue,
                      preparoIniciado: prep,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _textoEtapa(i),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.15,
                        fontWeight: _labelWeight(i, c, a, entregue),
                        color: _labelColor(i, c, a, entregue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  FontWeight _labelWeight(int i, int c, int a, bool entregue) {
    if (entregue) return FontWeight.w700;
    if (a >= 0 && i == a) return FontWeight.w800;
    if (i < c) return FontWeight.w600;
    return FontWeight.w500;
  }

  Color _labelColor(int i, int c, int a, bool entregue) {
    if (entregue) return diPertinRoxo;
    if (a >= 0 && i == a) return diPertinRoxo;
    if (i < c) return diPertinRoxo.withValues(alpha: 0.85);
    return Colors.grey[500]!;
  }

  Widget _bolinha({
    required int index,
    required String status,
    required int concluidas,
    required int ativa,
    required bool aguardandoPix,
    required bool entregue,
    required bool preparoIniciado,
  }) {
    final feito = entregue || index < concluidas;
    final atual = !entregue && ativa >= 0 && index == ativa;

    // Última milha (saiu / em rota): etapa final em andamento, ainda não entregue.
    if (atual && index == 3 && !entregue && _emUltimaMilha(status)) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.teal, width: 2.5),
        ),
        child: const Icon(Icons.delivery_dining, size: 13, color: Colors.teal),
      );
    }

    // Etapa "Preparando" (índice 1): antes do lojista iniciar = relógio; em preparo = fogão.
    if (atual && index == 1 && !preparoIniciado) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: diPertinLaranja.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: diPertinLaranja, width: 2),
        ),
        child: Icon(Icons.schedule, size: 13, color: diPertinLaranja),
      );
    }
    if (atual && index == 1 && preparoIniciado) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blue, width: 2.5),
        ),
        // Pacote/caixa em vez de talheres — DiPertin é marketplace de
        // lojas (vestuário, acessórios etc.), não delivery de comida.
        child: const Icon(
          Icons.inventory_2_rounded,
          size: 13,
          color: Colors.blue,
        ),
      );
    }

    if (feito && !(aguardandoPix && index == 0)) {
      return Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: diPertinRoxo,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: atual
            ? diPertinLaranja.withValues(alpha: 0.2)
            : Colors.grey[200],
        shape: BoxShape.circle,
        border: Border.all(
          color: atual ? diPertinLaranja : Colors.grey[400]!,
          width: atual ? 2.5 : 1.5,
        ),
      ),
      child: aguardandoPix && atual && index == 0
          ? Icon(Icons.schedule, size: 13, color: diPertinLaranja)
          : null,
    );
  }
}
