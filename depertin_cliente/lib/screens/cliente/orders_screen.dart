// Arquivo: lib/screens/cliente/orders_screen.dart

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/screens/cliente/avaliar_pedido_sheet.dart';
import 'package:depertin_cliente/screens/cliente/checkout_pagamento_screen.dart';
import 'package:depertin_cliente/screens/cliente/cliente_encomenda_detalhe_screen.dart';
import 'package:depertin_cliente/utils/codigo_pedido.dart';
import 'package:depertin_cliente/utils/safe_area_insets.dart';
import 'package:depertin_cliente/widgets/badge_entregador_acessibilidade.dart';
import 'package:depertin_cliente/widgets/chat_pedido_botao.dart';
import 'package:depertin_cliente/widgets/dipertin_safe_bottom_panel.dart';
import 'package:depertin_cliente/widgets/pedido_estorno_detalhe_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoTela = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _bordaCampo = Color(0xFFE0DEE8);
const Color _verdeStatus = Color(0xFF2E7D32);
const Color _vermelhoStatus = Color(0xFFC62828);

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
  bool _entradaAnimada = false;
  // Grupos multi-loja expandidos pelo usuário. Chave: `checkout_grupo_id`.
  // Vazio = colapsado (só o card-pai). Usuário toca para abrir e ver cada
  // loja com seu próprio código de entrega.
  final Set<String> _gruposExpandidos = <String>{};

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
      case PedidoStatus.encomendaEntradaPaga:
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

  static String? _dicaProximoPasso(
    String status, [
    Map<String, dynamic>? pedido,
  ]) {
    final tipoCompra = (pedido?['tipo_compra'] ?? '').toString();
    final fase = (pedido?['encomenda_fase_financeira'] ?? '').toString();
    if (tipoCompra == 'encomenda') {
      if (fase == 'entrada' && status == PedidoStatus.encomendaEntradaPaga) {
        return 'Entrada paga. A loja está produzindo sua encomenda e vai liberar a cobrança do saldo quando estiver pronta.';
      }
      if (fase == 'saldo_final' && status == PedidoStatus.aguardandoPagamento) {
        return 'A loja liberou o saldo restante. Conclua o pagamento para seguir para a entrega.';
      }
      if (fase == 'saldo_final' && status == PedidoStatus.emPreparo) {
        return 'Saldo pago. A loja vai solicitar o entregador para finalizar sua encomenda.';
      }
    }
    switch (status) {
      case PedidoStatus.aguardandoPagamento:
        return 'Conclua o pagamento para enviar o pedido à loja.';
      case PedidoStatus.pendente:
        return 'Aguarde a loja aceitar seu pedido.';
      case PedidoStatus.encomendaEntradaPaga:
        return 'Entrada paga — a loja está produzindo. Aguarde a cobrança do saldo.';
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
    final lojaNome = (pd['loja_nome'] ?? 'esta loja').toString().trim();
    final rawGrupo = pd['checkout_grupo_pedido_ids'];
    var multiLoja = false;
    if (rawGrupo is List) {
      final ids = rawGrupo
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      multiLoja = ids.length > 1;
    }
    final pagamentoUnificadoLegado =
        _toDouble(pd['checkout_valor_mp_total_cobranca']) > 0 &&
        pd['checkout_grupo_lider'] == true;

    if (!context.mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido?'),
        content: Text(
          multiLoja
              ? pagamentoUnificadoLegado
                    ? 'Este pedido faz parte de uma compra com pagamento único '
                          '(${rawGrupo is List ? rawGrupo.length : 1} lojas). '
                          'Cancelar apenas $lojaNome pode exigir novo pagamento '
                          'para as demais lojas. Deseja cancelar só este pedido?'
                    : 'Cancelar apenas o pedido de $lojaNome. '
                          'Os pedidos das outras lojas permanecem ativos. '
                          'Esta ação não pode ser desfeita.'
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
      final r = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);
      final s = await r.get();
      if (!s.exists) return;
      final st = (s.data()?['status'] ?? '').toString();
      if (st != PedidoStatus.aguardandoPagamento) return;
      await r.update({
        'status': PedidoStatus.cancelado,
        'cancelado_motivo': 'cliente_cancelou_pix',
        'cancelado_em': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              multiLoja
                  ? 'Pedido de $lojaNome cancelado. As demais lojas não foram alteradas.'
                  : 'Pedido cancelado.',
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

  /// Resolve pedido e valor para checkout (compatível com pagamento unificado
  /// legado e pagamento independente por loja).
  Future<({String pedidoIdPagamento, double valorPagamento})?>
  _resolverPagamentoCheckoutPedido(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final valorMpLider = _toDouble(pedido['checkout_valor_mp_total_cobranca']);
    if (valorMpLider > 0 && pedido['checkout_grupo_lider'] == true) {
      return (pedidoIdPagamento: pedidoId, valorPagamento: valorMpLider);
    }

    final cobrancaLiderId =
        (pedido['checkout_cobranca_pedido_mp_id'] ?? '').toString().trim();
    if (cobrancaLiderId.isNotEmpty && cobrancaLiderId != pedidoId) {
      final liderSnap = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(cobrancaLiderId)
          .get();
      if (liderSnap.exists) {
        final ld = liderSnap.data() ?? {};
        final valorGrupo = _toDouble(ld['checkout_valor_mp_total_cobranca']);
        if (valorGrupo > 0 &&
            (ld['status'] ?? '').toString() ==
                PedidoStatus.aguardandoPagamento) {
          return (
            pedidoIdPagamento: cobrancaLiderId,
            valorPagamento: valorGrupo,
          );
        }
      }
    }

    final total = _toDouble(pedido['total']);
    if (total <= 0) return null;
    return (pedidoIdPagamento: pedidoId, valorPagamento: total);
  }

  Future<void> _continuarPagamentoPedido(
    BuildContext context,
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final resolvido = await _resolverPagamentoCheckoutPedido(pedidoId, pedido);
    if (resolvido == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valor do pedido inválido para pagamento.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pagamentoUnificado =
        resolvido.pedidoIdPagamento != pedidoId ||
        _toDouble(pedido['checkout_valor_mp_total_cobranca']) > 0;
    if (pagamentoUnificado && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pagamento único da compra: ${_moeda.format(resolvido.valorPagamento)} '
            '(inclui todas as lojas deste checkout).',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    final forma = (pedido['forma_pagamento'] ?? 'PIX').toString().toLowerCase();
    final metodoPre = forma.contains('cart') ? 'Cartão' : 'PIX';

    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPagamentoScreen(
          valorTotal: resolvido.valorPagamento,
          metodoPreSelecionado: metodoPre,
          pedidoFirestoreId: resolvido.pedidoIdPagamento,
          onPagamentoAprovado: () {
            if (!context.mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/meus-pedidos',
              (route) => route.isFirst,
              arguments: {
                'filtro': 'todos',
                'mostrarVoltarVitrine': true,
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _cancelarPedidoEmAndamentoComMotivo(
    BuildContext context,
    String pedidoId, {
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) async {
    final formaPagLower = (pedido['forma_pagamento'] ?? '')
        .toString()
        .toLowerCase();
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
    final checkoutVariasLojas = idsGrupoPedido.length > 1 && !pagamentoDinheiro;

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
            _bulletComoFunciona('Em "Todos" você vê o histórico completo.'),
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
          Expanded(child: Text(texto, style: const TextStyle(height: 1.45))),
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

    final extras = <Widget>[];
    if ((pedido['tipo_compra'] ?? '').toString() == 'encomenda' &&
        (pedido['encomenda_fase_financeira'] ?? '').toString() ==
            'saldo_final') {
      final entrada = _toDouble(
        pedido['valor_entrada_acordado'] ?? pedido['valor_entrada_produto'],
      );
      final restante = _toDouble(
        pedido['valor_restante_produto'] ?? pedido['subtotal'],
      );
      if (entrada > 0) {
        extras.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Entrada já paga (produto)',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Text(_moeda.format(entrada)),
              ],
            ),
          ),
        );
      }
      if (restante > 0) {
        extras.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Restante do produto',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Text(_moeda.format(restante)),
              ],
            ),
          ),
        );
      }
    }

    return [
      ...extras,
      if (extras.isNotEmpty) const SizedBox(height: 8),
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

  Widget _chipDetalheSheet(String texto, {Color? cor}) {
    final c = cor ?? diPertinRoxo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: c,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _itemDetalheSheet(Map<String, dynamic> m) {
    final qtd = _toDouble(m['quantidade'], 1);
    final preco = _toDouble(m['preco']);
    final nome = m['nome']?.toString() ?? 'Item';
    final sub = qtd * preco;
    final imagemUrl = (m['imagem'] ?? '').toString();
    final variacoes = m['variacoes'] is Map
        ? Map<String, dynamic>.from(m['variacoes'] as Map)
        : <String, dynamic>{};
    final cor = (variacoes['cor'] ?? '').toString().trim();
    final tamanho = (variacoes['tamanho'] ?? '').toString().trim();
    final resumo = (m['variacoes_resumo'] ?? '').toString().trim();
    final qtdTxt = qtd.toStringAsFixed(
      qtd == qtd.roundToDouble() ? 0 : 1,
    );

    Widget thumb() {
      if (imagemUrl.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            imagemUrl,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _thumbItemDetalhePlaceholder(),
          ),
        );
      }
      return _thumbItemDetalhePlaceholder();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _fundoTela.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bordaCampo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          thumb(),
          const SizedBox(width: 10),
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
                const SizedBox(height: 3),
                Text(
                  'Qtd: $qtdTxt',
                  style: const TextStyle(fontSize: 12, color: _textoMuted),
                ),
                if (cor.isNotEmpty ||
                    tamanho.isNotEmpty ||
                    resumo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (cor.isNotEmpty) 'Cor: $cor',
                      if (tamanho.isNotEmpty) 'Tamanho: $tamanho',
                      if (cor.isEmpty && tamanho.isEmpty && resumo.isNotEmpty)
                        resumo,
                    ].join(' • '),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _textoMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            preco > 0 ? _moeda.format(sub) : 'A combinar',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: preco > 0 ? diPertinRoxo : _textoMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbItemDetalhePlaceholder() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.shopping_bag_outlined,
        color: diPertinRoxo,
        size: 24,
      ),
    );
  }

  Widget _heroSheetDetalhe({
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final ehEnc = _ehPedidoEncomenda(pedido);
    final fase = (pedido['encomenda_fase_financeira'] ?? '').toString();
    final lojaNome = (pedido['loja_nome'] ?? 'Loja').toString();
    final codigo = CodigoPedido.exibir(pedidoId, pedido);
    final tituloCodigo = ehEnc ? 'Encomenda · $codigo' : 'Pedido · $codigo';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), diPertinRoxo, Color(0xFF8E24AA)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tituloCodigo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lojaNome,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatarDataPedido(pedido),
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _construirStatus(statusAtual, pedido),
              if (ehEnc)
                _chipDetalheSheet(
                  fase == 'saldo_final'
                      ? 'Pagamento: saldo final'
                      : 'Pagamento: entrada',
                  cor: diPertinLaranja,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowFinanceira(String rotulo, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rotulo,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoMuted,
              ),
            ),
          ),
          Text(
            _moeda.format(_toDouble(valor)),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: diPertinRoxo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFinanceiroDetalhe(Map<String, dynamic> pedido) {
    final formaPag = pedido['forma_pagamento']?.toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _decorCartaoPro(destacado: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloSecaoPedido(
            'Resumo financeiro',
            icone: Icons.receipt_long_outlined,
          ),
          _rowFinanceira('Subtotal', pedido['subtotal']),
          _rowFinanceira('Taxa de entrega', pedido['taxa_entrega']),
          const SizedBox(height: 4),
          ..._linhasValorResumoPedido(pedido),
          if (formaPag != null && formaPag.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: _bordaCampo),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Forma de pagamento',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textoMuted,
                    ),
                  ),
                ),
                Text(
                  formaPag,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRodapeSheetDetalhe({
    required BuildContext sheetContext,
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final ehEnc = _ehPedidoEncomenda(pedido);
    final encId = (pedido['encomenda_id'] ?? '').toString().trim();
    final filhos = <Widget>[];

    if (statusAtual == PedidoStatus.aguardandoPagamento) {
      filhos.add(
        SizedBox(
          height: 50,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              _continuarPagamentoPedido(context, pedidoId, pedido);
            },
            style: FilledButton.styleFrom(
              backgroundColor: diPertinLaranja,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.payment_outlined),
            label: const Text(
              'Continuar pagamento',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      );
    } else if (statusAtual == PedidoStatus.entregue) {
      filhos.add(
        SizedBox(
          height: 50,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              mostrarAvaliarPedidoSheet(
                context,
                pedidoId: pedidoId,
                lojaId: pedido['loja_id']?.toString() ?? '',
                lojaNome: pedido['loja_nome']?.toString() ?? 'Loja',
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: diPertinLaranja,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.star_rate_rounded),
            label: const Text(
              'Avaliar pedido',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      );
    } else if (statusAtual != PedidoStatus.cancelado) {
      filhos.add(
        ChatPedidoBotao(
          pedidoId: pedidoId,
          lojaId: pedido['loja_id']?.toString() ?? '',
          lojaNome: pedido['loja_nome']?.toString() ?? 'Loja',
          rotuloAtivo: 'Chat com a loja',
          rotuloEncerrado: 'Ver conversa',
          encerrado: false,
        ),
      );
    } else {
      filhos.add(
        ChatPedidoBotao(
          pedidoId: pedidoId,
          lojaId: pedido['loja_id']?.toString() ?? '',
          lojaNome: pedido['loja_nome']?.toString() ?? 'Loja',
          rotuloAtivo: 'Ver conversa',
          rotuloEncerrado: 'Ver conversa',
          encerrado: true,
        ),
      );
    }

    if (ehEnc && encId.isNotEmpty) {
      filhos.add(const SizedBox(height: 8));
      filhos.add(
        SizedBox(
          height: 46,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ClienteEncomendaDetalheScreen(encomendaId: encId),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: diPertinRoxo,
              side: BorderSide(color: diPertinRoxo.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.handshake_outlined, size: 20),
            label: const Text(
              'Ver negociação completa',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    if (statusAtual == PedidoStatus.aguardandoPagamento) {
      filhos.add(const SizedBox(height: 8));
      filhos.add(
        SizedBox(
          height: 44,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _cancelandoPedidoId == pedidoId
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    _cancelarPedidoAguardandoPix(context, pedidoId);
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: _vermelhoStatus,
              side: BorderSide(color: _vermelhoStatus.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _cancelandoPedidoId == pedidoId
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _vermelhoStatus,
                    ),
                  )
                : const Icon(Icons.cancel_outlined, size: 18),
            label: Text(
              _cancelandoPedidoId == pedidoId
                  ? 'Cancelando…'
                  : 'Cancelar pedido',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    } else if (PedidoStatus.clientePodeCancelarAposPagamento.contains(
      statusAtual,
    )) {
      filhos.add(const SizedBox(height: 8));
      filhos.add(
        SizedBox(
          height: 44,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _cancelandoPedidoId == pedidoId
                ? null
                : () {
                    Navigator.pop(sheetContext);
                    _cancelarPedidoEmAndamentoComMotivo(
                      context,
                      pedidoId,
                      pedido: pedido,
                      statusAtual: statusAtual,
                    );
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: _vermelhoStatus,
              side: BorderSide(color: _vermelhoStatus.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _cancelandoPedidoId == pedidoId
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _vermelhoStatus,
                    ),
                  )
                : const Icon(Icons.cancel_outlined, size: 18),
            label: Text(
              _cancelandoPedidoId == pedidoId
                  ? 'Cancelando…'
                  : 'Cancelar pedido',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return DiPertinSafeBottomPanel(child: Column(children: filhos));
  }

  void _mostrarDetalhesPedido(
    BuildContext context, {
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final itens = pedido['itens'] as List<dynamic>? ?? [];
    final endereco = pedido['endereco_entrega']?.toString() ?? 'Não informado';
    final tipoEntrega = (pedido['tipo_entrega'] ?? 'entrega').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _fundoTela,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _bordaCampo,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  _heroSheetDetalhe(
                    pedidoId: pedidoId,
                    pedido: pedido,
                    statusAtual: statusAtual,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: _decorCartaoPro(),
                          child: _LinhaTempoPedido(
                            status: statusAtual,
                            estado: _estadoTimeline(statusAtual),
                            pedido: pedido,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (itens.isNotEmpty) ...[
                          _tituloSecaoPedido(
                            'Itens do pedido',
                            icone: Icons.shopping_basket_outlined,
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: _decorCartaoPro(),
                            child: Column(
                              children: itens
                                  .whereType<Map>()
                                  .map(
                                    (raw) => _itemDetalheSheet(
                                      Map<String, dynamic>.from(raw),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildCardFinanceiroDetalhe(pedido),
                        if (PedidoEstornoUiData.fromPedido(pedido)
                            .deveExibirCliente) ...[
                          const SizedBox(height: 16),
                          _tituloSecaoPedido(
                            'Estorno',
                            icone: Icons.undo_rounded,
                          ),
                          PedidoEstornoClienteCard(pedido: pedido),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: _decorCartaoPro(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _tituloSecaoPedido(
                                tipoEntrega == 'retirada'
                                    ? 'Retirada na loja'
                                    : 'Endereço de entrega',
                                icone: tipoEntrega == 'retirada'
                                    ? Icons.storefront_outlined
                                    : Icons.location_on_outlined,
                              ),
                              Text(
                                endereco,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: _textoPrimario,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_statusExibeCodigoEntrega(statusAtual)) ...[
                          const SizedBox(height: 16),
                          _buildBlocoCodigoEntrega(
                            context: sheetContext,
                            pedidoId: pedidoId,
                            pedido: pedido,
                          ),
                        ],
                        SizedBox(
                          height: 12 + diPertinSafeAreaBottom(sheetContext),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildRodapeSheetDetalhe(
              sheetContext: sheetContext,
              pedidoId: pedidoId,
              pedido: pedido,
              statusAtual: statusAtual,
            ),
          ],
        ),
      ),
    );
  }

  String _textoStatusPedido(String statusDb, Map<String, dynamic> pedido) {
    final tipoCompra = (pedido['tipo_compra'] ?? '').toString();
    final fase = (pedido['encomenda_fase_financeira'] ?? '').toString();
    switch (statusDb) {
      case 'aguardando_pagamento':
        if (tipoCompra == 'encomenda' && fase == 'saldo_final') {
          return 'Saldo pendente';
        }
        final forma = (pedido['forma_pagamento'] ?? '')
            .toString()
            .toLowerCase();
        final subtipo = (pedido['pagamento_cartao_tipo_solicitado'] ?? '')
            .toString()
            .toLowerCase();
        if (forma.contains('cart')) {
          return subtipo == 'debito'
              ? 'Aguardando cartão (débito)'
              : 'Aguardando cartão (crédito)';
        }
        return 'Aguardando PIX';
      case 'pendente':
        return 'Aguardando loja';
      case PedidoStatus.encomendaEntradaPaga:
        return 'Encomenda — produção';
      case 'aceito':
        return 'Pedido aceito';
      case 'em_preparo':
        return tipoCompra == 'encomenda' && fase == 'saldo_final'
            ? 'Saldo pago'
            : 'Em preparo';
      case 'aguardando_entregador':
        return 'Buscando entregador';
      case 'entregador_indo_loja':
        return 'Entregador a caminho da loja';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'pronto':
        return 'Pronto para retirada';
      case 'a_caminho':
      case 'em_rota':
        return 'Em entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Processando';
    }
  }

  Widget _construirStatus(String statusDb, Map<String, dynamic> pedido) {
    final cor = _corStatusUnificada(statusDb, pedido);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.45)),
      ),
      child: Text(
        _textoStatusPedido(statusDb, pedido),
        style: TextStyle(
          color: cor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static bool _emAndamento(String status) {
    return status != 'entregue' && status != 'cancelado';
  }

  static bool _ehPedidoEncomenda(Map<String, dynamic> data) {
    return (data['tipo_compra'] ?? '').toString() == 'encomenda' &&
        (data['encomenda_id'] ?? '').toString().trim().isNotEmpty;
  }

  static int _prioridadePedidoEncomenda(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final fase = (data['encomenda_fase_financeira'] ?? '').toString();
    final status = _normalizarStatus(data['status']);
    if (fase == 'saldo_final') return 100;
    if (status == PedidoStatus.entregue || status == PedidoStatus.cancelado) {
      return 90;
    }
    if (fase == 'entrada') return 10;
    return 0;
  }

  static List<QueryDocumentSnapshot> _consolidarCardsEncomenda(
    List<QueryDocumentSnapshot> docs,
  ) {
    final resultado = <QueryDocumentSnapshot>[];
    final porEncomenda = <String, QueryDocumentSnapshot>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_ehPedidoEncomenda(data)) {
        resultado.add(doc);
        continue;
      }

      final encId = (data['encomenda_id'] ?? '').toString().trim();
      final atual = porEncomenda[encId];
      if (atual == null ||
          _prioridadePedidoEncomenda(doc) > _prioridadePedidoEncomenda(atual)) {
        porEncomenda[encId] = doc;
      }
    }

    resultado.addAll(porEncomenda.values);
    resultado.sort((a, b) {
      final dataA =
          (a.data() as Map<String, dynamic>)['data_pedido'] as Timestamp?;
      final dataB =
          (b.data() as Map<String, dynamic>)['data_pedido'] as Timestamp?;
      if (dataA == null) return 1;
      if (dataB == null) return -1;
      return dataB.compareTo(dataA);
    });
    return resultado;
  }

  static String _formatarDataPedido(Map<String, dynamic> pedido) {
    final t = pedido['data_pedido'];
    if (t is! Timestamp) return '—';
    return DateFormat("dd/MM/yyyy 'às' HH:mm").format(t.toDate());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  BoxDecoration _decorCartaoPro({bool destacado = false}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: diPertinRoxo.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
      border: Border.all(
        color: destacado
            ? diPertinRoxo.withValues(alpha: 0.15)
            : _bordaCampo,
      ),
    );
  }

  static ({int andamento, int aguardandoPagamento, int entregues}) _calcularKpis(
    List<QueryDocumentSnapshot> docs,
  ) {
    var andamento = 0;
    var aguardandoPag = 0;
    var entregues = 0;
    for (final d in docs) {
      final st = _normalizarStatus(
        (d.data() as Map<String, dynamic>)['status'],
      );
      if (st == PedidoStatus.entregue) {
        entregues++;
      } else if (st != PedidoStatus.cancelado) {
        andamento++;
      }
      if (st == PedidoStatus.aguardandoPagamento) {
        aguardandoPag++;
      }
    }
    return (
      andamento: andamento,
      aguardandoPagamento: aguardandoPag,
      entregues: entregues,
    );
  }

  String _urlFotoLoja(Map<String, dynamic> pedido) {
    for (final chave in ['loja_foto', 'loja_foto_url', 'loja_foto_perfil']) {
      final url = (pedido[chave] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  String _tokenEntrega(String pedidoId, Map<String, dynamic> pedido) {
    var token = pedido['token_entrega']?.toString() ?? '';
    if (token.isEmpty && pedidoId.length >= 6) {
      token = pedidoId.substring(pedidoId.length - 6).toUpperCase();
    }
    return token;
  }

  Widget _avatarLojaPedido(Map<String, dynamic> pedido, {double tamanho = 44}) {
    final url = _urlFotoLoja(pedido);
    final nome = (pedido['loja_nome'] ?? 'L').toString().trim();
    final inicial = nome.isNotEmpty ? nome[0].toUpperCase() : 'L';

    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: tamanho,
          height: tamanho,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarLojaFallback(inicial, tamanho),
        ),
      );
    }
    return _avatarLojaFallback(inicial, tamanho);
  }

  Widget _avatarLojaFallback(String inicial, double tamanho) {
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: diPertinRoxo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: diPertinRoxo.withValues(alpha: 0.2)),
      ),
      child: Text(
        inicial,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: diPertinRoxo,
          fontSize: tamanho * 0.38,
        ),
      ),
    );
  }

  Widget _buildMiniHeroKpis({
    required int andamento,
    required int aguardandoPagamento,
    required int entregues,
  }) {
    Widget kpi(String rotulo, int valor, {Color? corValor}) {
      return Expanded(
        child: Column(
          children: [
            Text(
              '$valor',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: corValor ?? Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), diPertinRoxo, Color(0xFF8E24AA)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: diPertinRoxo.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Resumo dos pedidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _mostrarComoFunciona(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Como funciona',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              kpi('Em andamento', andamento),
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              kpi(
                'Aguard. pagamento',
                aguardandoPagamento,
                corValor: aguardandoPagamento > 0
                    ? diPertinLaranja
                    : Colors.white,
              ),
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withValues(alpha: 0.22),
              ),
              kpi('Entregues', entregues, corValor: const Color(0xFFA5D6A7)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipFiltroPedidos({
    required String rotulo,
    required int contagem,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selecionado
          ? diPertinLaranja.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selecionado
                  ? diPertinLaranja.withValues(alpha: 0.55)
                  : diPertinRoxo.withValues(alpha: 0.2),
              width: selecionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selecionado ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: selecionado ? diPertinLaranja : _textoMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$rotulo ($contagem)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selecionado ? diPertinLaranja : _textoPrimario,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFiltrosChips({
    required int qtdAndamento,
    required int qtdTodos,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _decorCartaoPro(),
        child: Row(
          children: [
            Expanded(
              child: _chipFiltroPedidos(
                rotulo: 'Em andamento',
                contagem: qtdAndamento,
                selecionado: _filtro == _FiltroPedidos.andamento,
                onTap: () => setState(() => _filtro = _FiltroPedidos.andamento),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _chipFiltroPedidos(
                rotulo: 'Todos',
                contagem: qtdTodos,
                selecionado: _filtro == _FiltroPedidos.todos,
                onTap: () => setState(() => _filtro = _FiltroPedidos.todos),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCarregamento() {
    Widget cardSkeleton() {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: _decorCartaoPro(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _bordaCampo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _bordaCampo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 11,
                        width: 120,
                        decoration: BoxDecoration(
                          color: _bordaCampo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: _bordaCampo,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: _bordaCampo,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [for (var i = 0; i < 3; i++) cardSkeleton()],
    );
  }

  Widget _buildAlertaContextualCard({
    String? dica,
    String? mensagemPagamentoRecusado,
  }) {
    if (mensagemPagamentoRecusado != null &&
        mensagemPagamentoRecusado.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _vermelhoStatus.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _vermelhoStatus.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: _vermelhoStatus, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensagemPagamentoRecusado,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: _textoPrimario,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (dica == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: diPertinLaranja.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: diPertinLaranja.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: diPertinLaranja.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dica,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: _textoPrimario,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlocoCodigoEntrega({
    required BuildContext context,
    required String pedidoId,
    required Map<String, dynamic> pedido,
  }) {
    final tokenReal = _tokenEntrega(pedidoId, pedido);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BadgeEntregadorAcessibilidade(
          audicao: pedido['entregador_acessibilidade_audicao']?.toString(),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _verdeStatus.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _verdeStatus.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delivery_dining, color: _verdeStatus),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Entrega em andamento',
                      style: TextStyle(
                        color: _verdeStatus,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Informe este código ao entregador para concluir a entrega.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: _textoMuted,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: diPertinRoxo.withValues(alpha: 0.2),
                  ),
                ),
                child: SelectableText(
                  tokenReal,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: diPertinRoxo,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: tokenReal));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Código copiado.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: diPertinLaranja,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text(
                    'Copiar código',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _statusExibeCodigoEntrega(String status) {
    return status == PedidoStatus.aCaminho ||
        status == PedidoStatus.emRota ||
        status == PedidoStatus.saiuEntrega;
  }

  Widget? _buildCtaPrimarioCard({
    required BuildContext context,
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    void abrirDetalhes() => _mostrarDetalhesPedido(
      context,
      pedidoId: pedidoId,
      pedido: pedido,
      statusAtual: statusAtual,
    );

    if (statusAtual == PedidoStatus.aguardandoPagamento) {
      return SizedBox(
        height: 46,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () =>
              _continuarPagamentoPedido(context, pedidoId, pedido),
          style: FilledButton.styleFrom(
            backgroundColor: diPertinLaranja,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.payment, size: 20),
          label: const Text(
            'Continuar pagamento',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    if (_statusExibeCodigoEntrega(statusAtual)) {
      return SizedBox(
        height: 46,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: abrirDetalhes,
          style: FilledButton.styleFrom(
            backgroundColor: _verdeStatus,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.pin_outlined, size: 20),
          label: const Text(
            'Ver código de entrega',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    if (statusAtual == PedidoStatus.entregue) {
      final lojaId = pedido['loja_id']?.toString() ?? '';
      final lojaNome = pedido['loja_nome']?.toString() ?? 'Loja';
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('avaliacoes')
            .doc(pedidoId)
            .snapshots(),
        builder: (context, snap) {
          final jaAvaliou = snap.hasData && snap.data!.exists;
          if (jaAvaliou) return const SizedBox.shrink();
          return SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => mostrarAvaliarPedidoSheet(
                context,
                pedidoId: pedidoId,
                lojaId: lojaId,
                lojaNome: lojaNome,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.star_rate_rounded),
              label: const Text(
                'Avaliar pedido',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          );
        },
      );
    }

    return null;
  }

  Widget _passoOrientacaoPedidos({
    required int numero,
    required String titulo,
    required String subtitulo,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: diPertinRoxo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                color: diPertinRoxo,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _textoMuted,
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

  Widget _tituloSecaoPedido(String titulo, {IconData? icone}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icone != null) ...[
            Icon(icone, size: 20, color: diPertinRoxo),
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

  /// Paleta Pro Max: laranja = ação pendente; roxo = andamento; verde = ok; vermelho = cancelado.
  Color _corStatusUnificada(String statusDb, Map<String, dynamic> pedido) {
    switch (statusDb) {
      case PedidoStatus.aguardandoPagamento:
      case PedidoStatus.encomendaEntradaPaga:
        return diPertinLaranja;
      case PedidoStatus.entregue:
        return _verdeStatus;
      case PedidoStatus.cancelado:
        return _vermelhoStatus;
      default:
        return diPertinRoxo;
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          nav.pushNamedAndRemoveUntil('/home', (route) => false);
        }
      },
      child: Scaffold(
      backgroundColor: _fundoTela,
      appBar: AppBar(
        // Sempre permite sair de Meus Pedidos: volta para a tela anterior
        // quando houver, ou direto para a vitrine quando a tela foi aberta
        // isolada (ex.: cold start por notificação de status do pedido).
        leading: Builder(
          builder: (context) {
            final nav = Navigator.of(context);
            final podeVoltar = nav.canPop();
            final irParaVitrine = _mostrarVoltarVitrine || !podeVoltar;
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: irParaVitrine ? 'Voltar para vitrine' : 'Voltar',
              onPressed: () {
                if (irParaVitrine) {
                  nav.pushNamedAndRemoveUntil('/home', (route) => false);
                } else {
                  nav.pop();
                }
              },
            );
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Meus pedidos',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Pronta-entrega e encomendas',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
                height: 1.2,
              ),
            ),
          ],
        ),
        backgroundColor: diPertinRoxo,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
                  return _buildSkeletonCarregamento();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: _decorCartaoPro(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 48,
                              color: _vermelhoStatus.withValues(alpha: 0.85),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Não foi possível carregar',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Verifique a conexão e tente novamente.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: _textoMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return _buildSkeletonCarregamento();
                }

                final docsBrutos = List<QueryDocumentSnapshot>.from(
                  snapshot.data!.docs,
                );

                docsBrutos.sort((a, b) {
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
                final docs = _consolidarCardsEncomenda(docsBrutos);

                final kpis = _calcularKpis(docs);
                final qtdAndamento = kpis.andamento;
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

                return AnimatedOpacity(
                  opacity: _entradaAnimada ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: RefreshIndicator(
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
                        child: _buildMiniHeroKpis(
                          andamento: qtdAndamento,
                          aguardandoPagamento: kpis.aguardandoPagamento,
                          entregues: kpis.entregues,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _buildFiltrosChips(
                          qtdAndamento: qtdAndamento,
                          qtdTodos: docs.length,
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
                          child: _buildEmptyFiltro(context, qtdTodos: docs.length),
                        )
                      else
                        ..._buildSliversAgrupados(filtrados),
                    ],
                  ),
                ),
                );
              },
            ),
      ),
    );
  }

  /// Agrupa pedidos por `checkout_grupo_id` (multi-loja). Pedidos sem grupo
  /// são tratados como grupo de 1 (single-store, comportamento legado).
  /// Retorna a lista de slivers já com headers de grupo + cards.
  List<Widget> _buildSliversAgrupados(List<QueryDocumentSnapshot> docs) {
    final ordemGrupos = <String>[];
    final grupos = <String, List<QueryDocumentSnapshot>>{};
    final grupoIdPorChave = <String, String>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final grupoId = (data['checkout_grupo_id'] ?? '').toString().trim();
      final chave = grupoId.isNotEmpty ? 'g:$grupoId' : 'p:${doc.id}';
      if (!grupos.containsKey(chave)) {
        grupos[chave] = [];
        ordemGrupos.add(chave);
        grupoIdPorChave[chave] = grupoId;
      }
      grupos[chave]!.add(doc);
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
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
                grupoId: grupoIdPorChave[chave] ?? '',
                docsGrupo: docsGrupo,
              ),
            );
          }, childCount: ordemGrupos.length),
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
        final pedido =
            (docSnap.hasData &&
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
    required String grupoId,
    required List<QueryDocumentSnapshot> docsGrupo,
  }) {
    var totalGrupo = 0.0;
    var qtdAtivos = 0;
    var qtdCancelados = 0;
    var qtdEntregues = 0;
    var pagamentoUnificadoLegado = false;
    String? formaPag;
    DateTime? dataMaisRecente;

    for (final d in docsGrupo) {
      final data = d.data() as Map<String, dynamic>;
      final st = _normalizarStatus(data['status']);
      if (_toDouble(data['checkout_valor_mp_total_cobranca']) > 0 &&
          data['checkout_grupo_lider'] == true) {
        pagamentoUnificadoLegado = true;
      }
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

    final chaveExpansao = grupoId.isNotEmpty ? grupoId : docsGrupo.first.id;
    final expandido = _gruposExpandidos.contains(chaveExpansao);

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
                            pagamentoUnificadoLegado
                                ? 'Pagamento único · $dataStr'
                                : 'Pagamento por loja · $dataStr',
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
                          'O código de confirmação é exclusivo por loja.',
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
                const SizedBox(height: 10),
                if (!expandido) _resumoLojasDoGrupo(docsGrupo),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      if (expandido) {
                        _gruposExpandidos.remove(chaveExpansao);
                      } else {
                        _gruposExpandidos.add(chaveExpansao);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          expandido
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: diPertinRoxo,
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expandido
                              ? 'Ocultar detalhes de cada loja'
                              : 'Ver pedido de cada loja (com código de entrega)',
                          style: const TextStyle(
                            color: diPertinRoxo,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expandido) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < docsGrupo.length; i++) ...[
              _streamCardPedido(docsGrupo[i]),
              if (i < docsGrupo.length - 1) const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  /// Lista compacta das lojas no estado colapsado do envelope multi-loja.
  /// Mostra logo/inicial + nome da loja + status rápido. Serve como preview
  /// enquanto o card pai está fechado.
  Widget _resumoLojasDoGrupo(List<QueryDocumentSnapshot> docsGrupo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final d in docsGrupo) _linhaResumoLoja(d)],
    );
  }

  Widget _linhaResumoLoja(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final nomeLoja = (data['loja_nome'] ?? 'Loja').toString();
    final status = _normalizarStatus(data['status']);
    final rotuloStatus = _rotuloCurtoStatus(status);
    final corStatus = _corRotuloStatus(status);

    final inicial = nomeLoja.isNotEmpty ? nomeLoja[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: diPertinRoxo.withValues(alpha: 0.1),
            child: Text(
              inicial,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: diPertinRoxo,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nomeLoja,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: corStatus.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: corStatus.withValues(alpha: 0.4)),
            ),
            child: Text(
              rotuloStatus,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: corStatus,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _rotuloCurtoStatus(String status) {
    switch (status) {
      case PedidoStatus.pendente:
        return 'Aguardando loja';
      case PedidoStatus.encomendaEntradaPaga:
        return 'Encomenda (produção)';
      case PedidoStatus.aguardandoPagamento:
        return 'Aguarda pagamento';
      case PedidoStatus.aceito:
        return 'Aceito';
      case PedidoStatus.emPreparo:
        return 'Em preparo';
      case PedidoStatus.pronto:
        return 'Pronto';
      case PedidoStatus.aguardandoEntregador:
        return 'Buscando entregador';
      case PedidoStatus.entregadorIndoLoja:
        return 'Entregador na loja';
      case PedidoStatus.saiuEntrega:
      case PedidoStatus.aCaminho:
      case PedidoStatus.emRota:
        return 'A caminho';
      case PedidoStatus.entregue:
        return 'Entregue';
      case PedidoStatus.cancelado:
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _corRotuloStatus(String status, [Map<String, dynamic>? pedido]) {
    return _corStatusUnificada(status, pedido ?? const {});
  }

  Widget _construirCardPedido({
    required BuildContext context,
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required String statusAtual,
  }) {
    final total = _toDouble(pedido['total']);
    final dataStr = _formatarDataPedido(pedido);
    final codigo = CodigoPedido.exibir(pedidoId, pedido);
    final dica = _dicaProximoPasso(statusAtual, pedido);
    final tipoCompra = (pedido['tipo_compra'] ?? '').toString();
    final ehEncomenda = tipoCompra == 'encomenda';
    final tituloCodigo = ehEncomenda
        ? 'Encomenda · $codigo'
        : 'Pedido · $codigo';
    final faseEnc = (pedido['encomenda_fase_financeira'] ?? '').toString();

    final msgRecusado = (pedido['pagamento_recusado_mensagem'] ?? '')
        .toString()
        .trim();
    final ctaPrimario = _buildCtaPrimarioCard(
      context: context,
      pedidoId: pedidoId,
      pedido: pedido,
      statusAtual: statusAtual,
    );

    void abrirDetalhes() => _mostrarDetalhesPedido(
      context,
      pedidoId: pedidoId,
      pedido: pedido,
      statusAtual: statusAtual,
    );

    return Container(
      key: ValueKey('$pedidoId-$statusAtual'),
      decoration: _decorCartaoPro(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: abrirDetalhes,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _avatarLojaPedido(pedido),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pedido['loja_nome'] ?? 'Loja',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: _textoPrimario,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tituloCodigo,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textoMuted,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dataStr,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: _textoMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _construirStatus(statusAtual, pedido),
                      ],
                    ),
                    if (ehEncomenda && faseEnc.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _chipDetalheSheet(
                          faseEnc == 'saldo_final'
                              ? 'Fase: pagamento do saldo'
                              : 'Fase: entrada / produção',
                          cor: diPertinLaranja,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _LinhaTempoPedido(
                      status: statusAtual,
                      estado: _estadoTimeline(statusAtual),
                      pedido: pedido,
                    ),
                    if (dica != null ||
                        (statusAtual == PedidoStatus.aguardandoPagamento &&
                            msgRecusado.isNotEmpty)) ...[
                      const SizedBox(height: 10),
                      _buildAlertaContextualCard(
                        dica: dica,
                        mensagemPagamentoRecusado:
                            statusAtual == PedidoStatus.aguardandoPagamento
                            ? msgRecusado
                            : null,
                      ),
                    ],
                    if (total > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total do pedido',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textoMuted,
                              ),
                            ),
                          ),
                          Text(
                            _moeda.format(total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: diPertinLaranja,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ctaPrimario != null) ...[
                  ctaPrimario,
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  onPressed: abrirDetalhes,
                  style: TextButton.styleFrom(
                    foregroundColor: diPertinRoxo,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text(
                    'Ver detalhes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroVazioPedidos() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), diPertinRoxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      diPertinLaranja.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 52,
                  color: diPertinLaranja.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNuncaPediu(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroVazioPedidos(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    children: [
                      const Text(
                        'Nenhum pedido ainda',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _textoPrimario,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Compre na vitrine e acompanhe cada etapa aqui — '
                        'do pagamento até a entrega.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: _textoMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        decoration: _decorCartaoPro(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Como funciona',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _textoPrimario,
                              ),
                            ),
                            _passoOrientacaoPedidos(
                              numero: 1,
                              titulo: 'Compre na vitrine',
                              subtitulo: 'Escolha produtos de lojas da sua cidade.',
                            ),
                            _passoOrientacaoPedidos(
                              numero: 2,
                              titulo: 'Acompanhe aqui',
                              subtitulo:
                                  'Veja status, pagamento e chat com a loja.',
                            ),
                            _passoOrientacaoPedidos(
                              numero: 3,
                              titulo: 'Código na entrega',
                              subtitulo:
                                  'Informe o código ao entregador para concluir.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DiPertinSafeBottomPanel(
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/home');
              },
              icon: const Icon(Icons.storefront_outlined),
              label: const Text(
                'Explorar vitrine',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: diPertinLaranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyFiltro(BuildContext context, {required int qtdTodos}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: _decorCartaoPro(),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: _verdeStatus.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum pedido em andamento',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textoPrimario,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Seus pedidos ativos foram concluídos ou cancelados. '
                  'O histórico completo está em Todos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: _textoMuted,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: _chipFiltroPedidos(
                    rotulo: 'Todos',
                    contagem: qtdTodos,
                    selecionado: false,
                    onTap: () => setState(() => _filtro = _FiltroPedidos.todos),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        setState(() => _filtro = _FiltroPedidos.todos),
                    style: FilledButton.styleFrom(
                      backgroundColor: diPertinRoxo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Ver todos os pedidos',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
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
  const _SheetMotivoCancelamentoCliente({
    this.avisoCheckoutVariasLojas = false,
  });

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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Informe o motivo. A loja receberá esta mensagem.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.35,
            ),
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
  final ({int concluidas, int ativa, bool aguardandoPix, bool preparoIniciado})
  estado;
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

  static const _labels = ['Confirmado', 'Preparando', 'A caminho', 'Entregue'];

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
