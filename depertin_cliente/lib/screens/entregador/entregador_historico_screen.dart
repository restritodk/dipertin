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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => _DetalhesCorridaSheet(
        docId: docId,
        pedido: pedido,
      ),
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

/// Modal "Detalhes da corrida" — visual premium usado na listagem do
/// histórico do entregador.
///
/// Arquitetura visual (top → bottom):
///   - `_DetalhesCorridaHeader`: faixa com gradiente DiPertin, ganho
///     líquido em destaque, selo "Concluída" e ID resumido.
///   - Card com dados da loja, itens, datas.
///   - Card com endereço de entrega + botão "Copiar".
///   - Resumo financeiro (valor do pedido, taxa do app, ganho).
class _DetalhesCorridaSheet extends StatelessWidget {
  const _DetalhesCorridaSheet({
    required this.docId,
    required this.pedido,
  });

  final String docId;
  final Map<String, dynamic> pedido;

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

  static double _ganho(Map<String, dynamic> pedido) {
    final liquido = _toDouble(pedido['valor_liquido_entregador']);
    if (liquido > 0) return liquido;
    final frete = _toDouble(pedido['taxa_entrega']);
    final taxaPlataforma = _toDouble(pedido['taxa_entregador']);
    return math.max(0, frete - taxaPlataforma);
  }

  @override
  Widget build(BuildContext context) {
    final loja = (pedido['loja_nome'] ?? 'Loja parceira').toString();
    final endereco =
        (pedido['endereco_entrega']?.toString() ?? '').trim().isEmpty
            ? 'Endereço não informado'
            : pedido['endereco_entrega'].toString();
    final ganho = _ganho(pedido);
    final totalPedido = _toDouble(pedido['total']);
    final freteBruto = _toDouble(pedido['taxa_entrega']);
    final taxaPlataforma = _toDouble(pedido['taxa_entregador']);

    int qtdItens = 0;
    final items = pedido['items'];
    if (items is List) qtdItens = items.length;

    final tsEntrega = pedido['data_entregue'] is Timestamp
        ? (pedido['data_entregue'] as Timestamp).toDate()
        : null;
    final tsPedido = pedido['data_pedido'] is Timestamp
        ? (pedido['data_pedido'] as Timestamp).toDate()
        : null;

    final idCurto = docId.length > 8
        ? docId.substring(docId.length - 8).toUpperCase()
        : docId.toUpperCase();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F6FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: _DetalhesCorridaHeader(
                  ganho: ganho,
                  idCurto: idCurto,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _CardSecao(
                      icone: Icons.storefront_outlined,
                      titulo: 'Loja',
                      children: [
                        _LinhaInfo(
                          icone: Icons.store,
                          rotulo: 'Nome',
                          valor: loja,
                          cor: diPertinRoxo,
                        ),
                        if (qtdItens > 0) ...[
                          _LinhaInfo(
                            icone: Icons.inventory_2_outlined,
                            rotulo: 'Itens transportados',
                            valor:
                                '$qtdItens ${qtdItens == 1 ? 'item' : 'itens'}',
                            cor: diPertinRoxo,
                          ),
                        ],
                        if (totalPedido > 0)
                          _LinhaInfo(
                            icone: Icons.receipt_long_outlined,
                            rotulo: 'Valor do pedido',
                            valor: _moeda.format(totalPedido),
                            cor: diPertinRoxo,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CardSecao(
                      icone: Icons.schedule,
                      titulo: 'Linha do tempo',
                      children: [
                        if (tsPedido != null)
                          _LinhaInfo(
                            icone: Icons.shopping_bag_outlined,
                            rotulo: 'Pedido criado',
                            valor: _formatarData(tsPedido),
                            cor: diPertinRoxo,
                          ),
                        if (tsEntrega != null)
                          _LinhaInfo(
                            icone: Icons.task_alt_rounded,
                            rotulo: 'Entrega concluída',
                            valor: _formatarData(tsEntrega),
                            cor: Colors.green.shade700,
                          ),
                        if (tsPedido != null && tsEntrega != null)
                          _LinhaInfo(
                            icone: Icons.timer_outlined,
                            rotulo: 'Duração total',
                            valor: _formatarDuracao(
                              tsEntrega.difference(tsPedido),
                            ),
                            cor: diPertinRoxo,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CardSecao(
                      icone: Icons.location_on_outlined,
                      titulo: 'Endereço de entrega',
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Text(
                            endereco,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFEDEAF3)),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: endereco));
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Endereço copiado.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded,
                                    size: 18, color: diPertinRoxo),
                                const SizedBox(width: 8),
                                Text(
                                  'Copiar endereço',
                                  style: TextStyle(
                                    color: diPertinRoxo,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CardSecao(
                      icone: Icons.account_balance_wallet_outlined,
                      titulo: 'Resumo financeiro',
                      children: [
                        if (freteBruto > 0)
                          _LinhaInfoValor(
                            rotulo: 'Frete bruto',
                            valor: _moeda.format(freteBruto),
                          ),
                        if (taxaPlataforma > 0)
                          _LinhaInfoValor(
                            rotulo: 'Taxa do app',
                            valor: '- ${_moeda.format(taxaPlataforma)}',
                            corValor: Colors.red.shade600,
                          ),
                        const Divider(height: 1, color: Color(0xFFEDEAF3)),
                        _LinhaInfoValor(
                          rotulo: 'Seu ganho líquido',
                          valor: _moeda.format(ganho),
                          corValor: diPertinLaranja,
                          destaque: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).maybePop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: diPertinRoxo.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Fechar',
                        style: TextStyle(
                          color: diPertinRoxo,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatarData(DateTime d) {
    return DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(d);
  }

  static String _formatarDuracao(Duration d) {
    if (d.isNegative || d == Duration.zero) return '—';
    final horas = d.inHours;
    final minutos = d.inMinutes.remainder(60);
    if (horas > 0) {
      return '${horas}h ${minutos.toString().padLeft(2, '0')}min';
    }
    return '${minutos}min';
  }
}

class _DetalhesCorridaHeader extends StatelessWidget {
  const _DetalhesCorridaHeader({
    required this.ganho,
    required this.idCurto,
  });

  final double ganho;
  final String idCurto;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [diPertinRoxo, Color(0xFF8E24AA), Color(0xFF7B1FA2)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade400.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.green.shade300.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.green.shade200, size: 15),
                    const SizedBox(width: 6),
                    const Text(
                      'Concluída',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Pedido · $idCurto',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Ganho desta corrida',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _moeda.format(ganho),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Valor líquido creditado na sua carteira',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSecao extends StatelessWidget {
  const _CardSecao({
    required this.icone,
    required this.titulo,
    required this.children,
  });

  final IconData icone;
  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEAF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: diPertinRoxo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icone, color: diPertinRoxo, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: diPertinRoxo,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEAF3)),
          ...children,
        ],
      ),
    );
  }
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.cor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
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
}

class _LinhaInfoValor extends StatelessWidget {
  const _LinhaInfoValor({
    required this.rotulo,
    required this.valor,
    this.corValor,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final Color? corValor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            rotulo,
            style: TextStyle(
              fontSize: destaque ? 14.5 : 13,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
              color: destaque ? Colors.black87 : Colors.grey.shade700,
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: destaque ? 18 : 14,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w700,
              color: corValor ?? Colors.black87,
              letterSpacing: destaque ? -0.3 : 0,
            ),
          ),
        ],
      ),
    );
  }
}
