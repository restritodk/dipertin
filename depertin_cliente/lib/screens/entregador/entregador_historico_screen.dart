// Arquivo: lib/screens/entregador/entregador_historico_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

enum _PeriodoFiltro { todos, hoje, dias7, dias30 }

class EntregadorHistoricoScreen extends StatefulWidget {
  const EntregadorHistoricoScreen({super.key});

  @override
  State<EntregadorHistoricoScreen> createState() =>
      _EntregadorHistoricoScreenState();
}

class _EntregadorHistoricoScreenState extends State<EntregadorHistoricoScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  _PeriodoFiltro _periodo = _PeriodoFiltro.hoje;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  static double _ganhoEntregador(Map<String, dynamic> pedido) {
    final liquido = _toDouble(pedido['valor_liquido_entregador']);
    if (liquido > 0) return liquido;
    final frete = _toDouble(pedido['taxa_entrega']);
    final taxaPlataforma = _toDouble(pedido['taxa_entregador']);
    return math.max(0, frete - taxaPlataforma);
  }

  /// Data da conclusão (preferência) ou do pedido — usada para ordenar e filtrar.
  static DateTime? _dataReferencia(Map<String, dynamic> p) {
    final ent = p['data_entregue'];
    final ped = p['data_pedido'];
    if (ent is Timestamp) return ent.toDate();
    if (ped is Timestamp) return ped.toDate();
    return null;
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _dentroPeriodo(DateTime? d, _PeriodoFiltro f) {
    switch (f) {
      case _PeriodoFiltro.todos:
        return true;
      case _PeriodoFiltro.hoje:
        if (d == null) return false;
        return _mesmoDia(d, DateTime.now());
      case _PeriodoFiltro.dias7:
        if (d == null) return false;
        return d.isAfter(DateTime.now().subtract(const Duration(days: 7)));
      case _PeriodoFiltro.dias30:
        if (d == null) return false;
        return d.isAfter(DateTime.now().subtract(const Duration(days: 30)));
    }
  }

  static String _rotuloPeriodo(_PeriodoFiltro f) {
    switch (f) {
      case _PeriodoFiltro.todos:
        return 'Todos';
      case _PeriodoFiltro.hoje:
        return 'Hoje';
      case _PeriodoFiltro.dias7:
        return '7 dias';
      case _PeriodoFiltro.dias30:
        return '30 dias';
    }
  }

  void _mostrarDetalhes({
    required String docId,
    required Map<String, dynamic> pedido,
  }) {
    final loja = pedido['loja_nome'] ?? 'Loja parceira';
    final endereco =
        pedido['endereco_entrega']?.toString() ?? 'Endereço não informado';
    final taxa = _ganhoEntregador(pedido);
    final totalPedido = (pedido['total'] ?? 0.0).toDouble();

    int qtdItens = 0;
    final items = pedido['items'];
    if (items is List) qtdItens = items.length;

    String fmt(Timestamp? t) {
      if (t == null) return '—';
      return DateFormat("dd/MM/yyyy 'às' HH:mm").format(t.toDate());
    }

    final tsEntrega = pedido['data_entregue'] is Timestamp
        ? pedido['data_entregue'] as Timestamp
        : null;
    final tsPedido = pedido['data_pedido'] is Timestamp
        ? pedido['data_pedido'] as Timestamp
        : null;

    final idCurto = docId.length > 8
        ? '…${docId.substring(docId.length - 8)}'
        : docId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Detalhes da corrida',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: diPertinRoxo,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pedido $idCurto',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                _linhaDetalhe(Icons.store, 'Loja', loja),
                const SizedBox(height: 12),
                _linhaDetalhe(Icons.event, 'Entrega concluída', fmt(tsEntrega)),
                if (tsPedido != null) ...[
                  const SizedBox(height: 8),
                  _linhaDetalhe(
                    Icons.shopping_bag_outlined,
                    'Pedido criado',
                    fmt(tsPedido),
                  ),
                ],
                if (qtdItens > 0) ...[
                  const SizedBox(height: 12),
                  _linhaDetalhe(
                    Icons.inventory_2_outlined,
                    'Itens',
                    '$qtdItens ${qtdItens == 1 ? 'item' : 'itens'}',
                  ),
                ],
                if (totalPedido > 0) ...[
                  const SizedBox(height: 8),
                  _linhaDetalhe(
                    Icons.receipt_long,
                    'Valor do pedido',
                    _moeda.format(totalPedido),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on, color: Colors.red[700], size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        endereco,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: endereco));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Endereço copiado.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar endereço'),
                ),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Seu ganho líquido',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _moeda.format(taxa),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: diPertinLaranja,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _linhaDetalhe(IconData icon, String titulo, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: diPertinRoxo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Usuário não autenticado.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Histórico de corridas',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: diPertinRoxo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('pedidos')
            .where('entregador_id', isEqualTo: uid)
            .where('status', isEqualTo: 'entregue')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: diPertinLaranja),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return RefreshIndicator(
              color: diPertinLaranja,
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 400));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                  Icon(
                    Icons.delivery_dining,
                    size: 72,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Nenhuma corrida finalizada ainda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Quando você concluir uma entrega com o token no mapa, '
                    'a corrida aparece aqui com data e valor da taxa.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          var pedidos = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);

          pedidos.sort((a, b) {
            final da = _dataReferencia(a.data() as Map<String, dynamic>);
            final db = _dataReferencia(b.data() as Map<String, dynamic>);
            final ta = da?.millisecondsSinceEpoch ?? 0;
            final tb = db?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
          });

          final filtrados = pedidos.where((doc) {
            final d = _dataReferencia(doc.data() as Map<String, dynamic>);
            return _dentroPeriodo(d, _periodo);
          }).toList();

          final totalGanho = filtrados.fold<double>(
            0,
            (s, doc) =>
                s +
                _ganhoEntregador(doc.data() as Map<String, dynamic>),
          );

          Widget cardCorrida(int index) {
            final doc = filtrados[index];
            final pedido = doc.data() as Map<String, dynamic>;

            final loja = pedido['loja_nome'] ?? 'Loja parceira';
            final endereco =
                pedido['endereco_entrega'] ?? 'Endereço não informado';
            final valor = _ganhoEntregador(pedido);

            final dRef = _dataReferencia(pedido);
            var dataEntregaFmt = '—';
            if (dRef != null) {
              dataEntregaFmt = DateFormat("dd/MM/yyyy '·' HH:mm").format(dRef);
            }

            final temDataEntrega = pedido['data_entregue'] is Timestamp;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _mostrarDetalhes(docId: doc.id, pedido: pedido),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
                                      _moeda.format(valor),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: diPertinLaranja,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      temDataEntrega
                                          ? 'Concluída em $dataEntregaFmt'
                                          : 'Registrada em $dataEntregaFmt',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Concluída',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(
                                Icons.store,
                                color: diPertinRoxo,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loja,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Colors.red[400],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  endereco.toString(),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toque para ver detalhes e copiar o endereço',
                            style: TextStyle(
                              fontSize: 12,
                              color: diPertinRoxo.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: diPertinLaranja,
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 450));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      'Entregas concluídas e quanto entrou líquido para você em cada corrida.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _rotuloPeriodo(_periodo),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${filtrados.length} ${filtrados.length == 1 ? 'corrida' : 'corridas'}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Total no período',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _moeda.format(totalGanho),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: diPertinLaranja,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: _PeriodoFiltro.values.map((p) {
                        final sel = _periodo == p;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(_rotuloPeriodo(p)),
                            selected: sel,
                            onSelected: (_) {
                              setState(() => _periodo = p);
                            },
                            selectedColor: diPertinRoxo.withValues(alpha: 0.15),
                            checkmarkColor: diPertinRoxo,
                            labelStyle: TextStyle(
                              color: sel ? diPertinRoxo : Colors.black87,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (filtrados.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.filter_alt_off,
                            size: 56,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma corrida neste período',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tente outro filtro ou aguarde novas entregas concluídas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => cardCorrida(index),
                        childCount: filtrados.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
