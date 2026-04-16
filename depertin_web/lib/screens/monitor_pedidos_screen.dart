import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonitorPedidosScreen extends StatefulWidget {
  const MonitorPedidosScreen({super.key});

  @override
  State<MonitorPedidosScreen> createState() => _MonitorPedidosScreenState();
}

class _MonitorPedidosScreenState extends State<MonitorPedidosScreen> {
  static const _roxo = PainelAdminTheme.roxo;
  static const _laranja = PainelAdminTheme.laranja;
  static const _statusAtivos = [
    'pendente',
    'aceito',
    'preparando',
    'a_caminho',
    'em_rota',
  ];

  String _filtroStatus = 'todos';

  final _statusLabel = <String, String>{
    'pendente': 'Pendente',
    'aceito': 'Aceito',
    'preparando': 'Preparando',
    'a_caminho': 'Pronto p/ coleta',
    'em_rota': 'Em rota',
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
  };

  Color _corStatus(String s) {
    switch (s) {
      case 'pendente':
        return const Color(0xFFB45309);
      case 'aceito':
        return const Color(0xFF1D4ED8);
      case 'preparando':
        return _roxo;
      case 'a_caminho':
        return const Color(0xFF0369A1);
      case 'em_rota':
        return const Color(0xFF15803D);
      case 'entregue':
        return const Color(0xFF15803D);
      case 'cancelado':
        return const Color(0xFFB91C1C);
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _iconeStatus(String s) {
    switch (s) {
      case 'pendente':
        return Icons.schedule_rounded;
      case 'aceito':
        return Icons.check_circle_outline_rounded;
      case 'preparando':
        return Icons.restaurant_rounded;
      case 'a_caminho':
        return Icons.store_rounded;
      case 'em_rota':
        return Icons.delivery_dining_rounded;
      case 'entregue':
        return Icons.task_alt_rounded;
      case 'cancelado':
        return Icons.cancel_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(child: _buildCorpo()),
        ],
      ),
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  Widget _buildHeader() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monitor de Pedidos',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _roxo,
                            letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Acompanhe pedidos ativos em tempo real em todas as cidades.',
                        style: TextStyle(
                            color: PainelAdminTheme.textoSecundario,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF15803D),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Ao vivo',
                    style: TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _filtroChip('todos', 'Todos'),
                ..._statusAtivos.map(
                    (s) => _filtroChip(s, _statusLabel[s] ?? s)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtroChip(String valor, String label) {
    final sel = _filtroStatus == valor;
    return InkWell(
      onTap: () => setState(() => _filtroStatus = valor),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _roxo : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? _roxo : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCorpo() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .where('status', whereIn: _statusAtivos)
          .orderBy('data_pedido', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snap.data?.docs ?? [];

        if (_filtroStatus != 'todos') {
          docs = docs.where((d) {
            final s = (d.data() as Map<String, dynamic>)['status'] ?? '';
            return s == _filtroStatus;
          }).toList();
        }

        final totalAtivos = docs.length;

        if (docs.isEmpty) {
          return Column(
            children: [
              _buildStats(totalAtivos),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 56, color: const Color(0xFF15803D).withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        _filtroStatus == 'todos'
                            ? 'Nenhum pedido ativo agora.'
                            : 'Nenhum pedido com status "${_statusLabel[_filtroStatus]}".',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildStats(totalAtivos),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCard(docs[i]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStats(int totalAtivos) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'entregador')
          .where('online', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final onlineCount = snap.data?.docs.length ?? 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                children: [
                  Expanded(
                    child: _statCard(
                      Icons.receipt_long_outlined,
                      'Pedidos ativos',
                      '$totalAtivos',
                      _roxo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statCard(
                      Icons.delivery_dining_rounded,
                      'Entregadores online',
                      '$onlineCount',
                      const Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statCard(
                      Icons.radar_rounded,
                      'Pedidos p/ coletar',
                      '${_contarStatus(snap.data?.docs ?? [], 'a_caminho')}',
                      _laranja,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _contarStatus(List<QueryDocumentSnapshot> docs, String status) {
    return docs
        .where((d) =>
            (d.data() as Map<String, dynamic>)['status'] == status)
        .length;
  }

  Widget _statCard(IconData icon, String label, String valor, Color cor) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cor, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: cor)),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status']?.toString() ?? 'pendente';
    final cor = _corStatus(status);
    final total = (d['total'] as num?)?.toDouble() ?? 0;
    final taxa = (d['taxa_entrega'] as num?)?.toDouble() ?? 0;
    final forma = d['forma_pagamento']?.toString() ?? '—';
    final ts = d['data_pedido'] as Timestamp?;
    final hora =
        ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '—';
    final cliente = d['cliente_nome']?.toString() ?? 'Cliente';
    final loja = d['loja_nome']?.toString() ?? 'Loja';
    final cidade = d['cidade']?.toString() ?? '';
    final itens = (d['items'] as List?)?.length ?? 0;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconeStatus(status), color: cor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#${doc.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel[status] ?? status,
                          style: TextStyle(
                              color: cor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _info(Icons.storefront_rounded, loja),
                      _info(Icons.person_outline_rounded, cliente),
                      if (cidade.isNotEmpty)
                        _info(Icons.place_outlined, cidade.toUpperCase()),
                      _info(Icons.schedule_rounded, hora),
                      _info(Icons.shopping_bag_outlined, '$itens item(s)'),
                      _info(Icons.payments_outlined,
                          'R\$ ${total.toStringAsFixed(2)} + R\$ ${taxa.toStringAsFixed(2)} entrega'),
                      _info(Icons.credit_card_outlined, forma),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700)),
        ],
      );
}
