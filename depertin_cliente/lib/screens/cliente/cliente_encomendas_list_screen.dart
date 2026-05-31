import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/encomenda_negociacao_status.dart';
import 'cliente_encomenda_detalhe_screen.dart';

class _StatusVisual {
  final String rotulo;
  final String descricao;
  final Color cor;
  final Color fundo;
  final IconData icone;

  const _StatusVisual({
    required this.rotulo,
    required this.descricao,
    required this.cor,
    required this.fundo,
    required this.icone,
  });
}

/// Lista encomendas do cliente autenticado (`encomendas.cliente_id`).
class ClienteEncomendasListScreen extends StatelessWidget {
  const ClienteEncomendasListScreen({super.key});

  static final DateFormat _fmtData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  static const Color _roxo = Color(0xFF6A1B9A);
  static const Color _laranja = Color(0xFFFF8F00);
  static const Color _fundo = Color(0xFFF7F4FA);

  _StatusVisual _statusVisual(String st) {
    switch (st) {
      case EncomendaNegociacaoStatus.aguardandoNegociacao:
      case EncomendaNegociacaoStatus.negociacaoEmAndamento:
      case EncomendaNegociacaoStatus.aguardandoRespostaLojaContraproposta:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'A loja está analisando sua solicitação.',
          cor: _roxo,
          fundo: const Color(0xFFF3E5F5),
          icone: Icons.handshake_rounded,
        );
      case EncomendaNegociacaoStatus.propostaEnviada:
      case EncomendaNegociacaoStatus.propostaAceitaPendenteEntrada:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Revise a proposta e conclua a entrada.',
          cor: _laranja,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.payments_rounded,
        );
      case EncomendaNegociacaoStatus.entradaAguardandoPagamento:
        return _StatusVisual(
          rotulo: 'Entrada pendente',
          descricao: 'A entrada precisa ser paga para iniciar a produção.',
          cor: Colors.deepOrange,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.pix_rounded,
        );
      case EncomendaNegociacaoStatus.entradaPagaEmProducao:
        return _StatusVisual(
          rotulo: 'Em produção',
          descricao: 'Entrada paga. A loja está preparando sua encomenda.',
          cor: Colors.blue.shade700,
          fundo: const Color(0xFFEFF5FE),
          icone: Icons.inventory_2_rounded,
        );
      case EncomendaNegociacaoStatus.saldoFinalAguardandoPgto:
        return _StatusVisual(
          rotulo: 'Saldo liberado',
          descricao: 'A loja liberou o pagamento do saldo restante.',
          cor: Colors.deepOrange,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.account_balance_wallet_rounded,
        );
      case EncomendaNegociacaoStatus.emExecucaoLogistica:
        return _StatusVisual(
          rotulo: 'Em andamento',
          descricao: 'Saldo pago. Acompanhe a entrega em Meus pedidos.',
          cor: Colors.green.shade700,
          fundo: const Color(0xFFEAF7EF),
          icone: Icons.local_shipping_rounded,
        );
      case EncomendaNegociacaoStatus.encerradaRecusadaLoja:
      case EncomendaNegociacaoStatus.encerradaCanceladaCliente:
      case EncomendaNegociacaoStatus.encerradaCanceladaLoja:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Esta negociação foi encerrada.',
          cor: Colors.red.shade700,
          fundo: const Color(0xFFFFEBEE),
          icone: Icons.cancel_outlined,
        );
      default:
        return _StatusVisual(
          rotulo: EncomendaNegociacaoStatus.rotuloPt(st),
          descricao: 'Toque para ver os detalhes da negociação.',
          cor: Colors.grey.shade700,
          fundo: Colors.grey.shade100,
          icone: Icons.receipt_long_rounded,
        );
    }
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _textoItens(Map<String, dynamic> m) {
    final itens = m['itens'];
    if (itens is! List || itens.isEmpty) return 'Itens da encomenda';
    final nomes = itens
        .whereType<Map>()
        .map((e) => (e['nome'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    if (nomes.isEmpty) return '${itens.length} item(ns) sob encomenda';
    final extra = itens.length > nomes.length
        ? ' +${itens.length - nomes.length}'
        : '';
    return '${nomes.join(', ')}$extra';
  }

  String _dataTexto(dynamic ts) {
    if (ts is Timestamp) return _fmtData.format(ts.toDate());
    return 'Atualizado recentemente';
  }

  Widget _infoPill({
    required IconData icon,
    required String rotulo,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECE7F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _roxo),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$rotulo: $valor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3D3650),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: Color(0xFFF3E5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: _roxo,
                size: 48,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nenhuma encomenda ainda',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Quando você solicitar uma encomenda, ela aparecerá aqui com status, valores e próximos passos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    final st = (m['status_negociacao'] ?? '').toString();
    final visual = _statusVisual(st);
    final loja = (m['loja_nome'] ?? m['nome_loja'] ?? 'Loja').toString();
    final total = _num(m['valor_total_referencia']);
    final entrada = _num(m['valor_entrada_loja']);
    final restante = total > 0 && entrada > 0
        ? (total - entrada).clamp(0, total)
        : 0;
    final codigo = doc.id.length > 6
        ? doc.id.substring(doc.id.length - 6).toUpperCase()
        : doc.id.toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ClienteEncomendaDetalheScreen(encomendaId: doc.id),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE9E2F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: visual.fundo,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: visual.cor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(visual.icone, color: visual.cor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visual.rotulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visual.cor,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          visual.descricao,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _roxo),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          loja,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1F1830),
                          ),
                        ),
                      ),
                      Text(
                        '#$codigo',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _textoItens(m),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (total > 0)
                        _infoPill(
                          icon: Icons.receipt_long_rounded,
                          rotulo: 'Total',
                          valor: _moeda.format(total),
                        ),
                      if (entrada > 0)
                        _infoPill(
                          icon: Icons.payments_rounded,
                          rotulo: 'Entrada',
                          valor: _moeda.format(entrada),
                        ),
                      if (restante > 0)
                        _infoPill(
                          icon: Icons.account_balance_wallet_rounded,
                          rotulo: 'Saldo',
                          valor: _moeda.format(restante),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.update_rounded,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _dataTexto(m['atualizado_em']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'Ver detalhes',
                        style: TextStyle(
                          color: _roxo,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _roxo,
        foregroundColor: Colors.white,
        title: const Text('Minhas encomendas'),
      ),
      body: uid == null
          ? const Center(child: Text('Faça login para ver suas encomendas.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('encomendas')
                  .where('cliente_id', isEqualTo: uid)
                  .orderBy('atualizado_em', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return _buildEmpty();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    return _buildCard(context, doc);
                  },
                );
              },
            ),
    );
  }
}
