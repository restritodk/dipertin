// Arquivo: lib/screens/entregador/configuracoes/informacoes_fiscais_screen.dart
//
// Agrega em tempo real os pedidos entregues pelo entregador (campo
// `entregador_id`) e resume por ano/mês, sem depender do doc agregado em
// `fiscal/{uid}` (que só é preenchido a partir do deploy da CF). Dessa forma
// o histórico antigo também aparece.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

class InformacoesFiscaisScreen extends StatefulWidget {
  const InformacoesFiscaisScreen({super.key});

  @override
  State<InformacoesFiscaisScreen> createState() =>
      _InformacoesFiscaisScreenState();
}

class _InformacoesFiscaisScreenState extends State<InformacoesFiscaisScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _anoSelecionado = DateTime.now().year;
  int _mesSelecionado = DateTime.now().month;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _streamPedidos() {
    final uid = _uid;
    if (uid == null) return null;
    // Apenas filtro por entregador_id para não depender de índice composto.
    // O status=entregue é filtrado localmente.
    return FirebaseFirestore.instance
        .collection('pedidos')
        .where('entregador_id', isEqualTo: uid)
        .snapshots();
  }

  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  /// Extrai a melhor data possível do pedido (entregue_em > data_entrega > atualizado_em > criado_em).
  DateTime? _dataDoPedido(Map<String, dynamic> p) {
    for (final k in const [
      'entregue_em',
      'data_entrega',
      'atualizado_em',
      'criado_em',
    ]) {
      final v = p[k];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
    }
    return null;
  }

  /// Calcula o resumo financeiro a partir da lista de pedidos entregues.
  _ResumoCalculado _calcular(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool Function(DateTime) filtroData,
  }) {
    double bruto = 0;
    double taxa = 0;
    double liquido = 0;
    int corridas = 0;

    for (final d in docs) {
      final p = d.data();
      final status = (p['status'] ?? '').toString();
      if (status != 'entregue') continue;
      final dt = _dataDoPedido(p);
      if (dt == null || !filtroData(dt)) continue;

      // Ganho bruto = frete total (taxa_entrega / valor_frete).
      final brutoPedido = _n(p['valor_frete']) > 0
          ? _n(p['valor_frete'])
          : _n(p['taxa_entrega']);
      final taxaPedido = _n(p['taxa_entregador']);
      double liquidoPedido = _n(p['valor_liquido_entregador']);
      if (liquidoPedido == 0 && brutoPedido > 0) {
        // Fallback: calcula na mão se o campo ainda não foi populado.
        liquidoPedido = (brutoPedido - taxaPedido).clamp(0, double.infinity);
      }

      bruto += brutoPedido;
      taxa += taxaPedido;
      liquido += liquidoPedido;
      corridas += 1;
    }

    return _ResumoCalculado(
      brutos: bruto,
      taxas: taxa,
      liquido: liquido,
      corridas: corridas,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Informações fiscais',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _roxo,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _laranja,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Anualmente'),
            Tab(text: 'Mensalmente'),
          ],
        ),
      ),
      body: _uid == null
          ? const Center(child: Text('Você precisa estar autenticado.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamPedidos(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Erro ao carregar corridas: ${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _laranja),
                  );
                }
                final docs = snap.data!.docs;
                return TabBarView(
                  controller: _tabs,
                  children: [
                    _tabAnual(docs),
                    _tabMensal(docs),
                  ],
                );
              },
            ),
    );
  }

  Widget _tabAnual(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final resumoTotal = _calcular(docs, filtroData: (_) => true);
    final resumoAno = _calcular(
      docs,
      filtroData: (dt) => dt.year == _anoSelecionado,
    );
    return Column(
      children: [
        _SeletorAno(
          ano: _anoSelecionado,
          onChange: (a) => setState(() => _anoSelecionado = a),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _ResumoFiscal(
                resumo: resumoAno,
                periodo: 'Ano $_anoSelecionado',
              ),
              const SizedBox(height: 10),
              _BlocoTotalHistorico(resumo: resumoTotal),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabMensal(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final resumo = _calcular(
      docs,
      filtroData: (dt) =>
          dt.year == _anoSelecionado && dt.month == _mesSelecionado,
    );
    final nomeMes = DateFormat.MMMM('pt_BR').format(
      DateTime(_anoSelecionado, _mesSelecionado),
    );
    return Column(
      children: [
        _SeletorMesAno(
          ano: _anoSelecionado,
          mes: _mesSelecionado,
          onChange: (ano, mes) {
            setState(() {
              _anoSelecionado = ano;
              _mesSelecionado = mes;
            });
          },
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _ResumoFiscal(
                resumo: resumo,
                periodo: '$nomeMes/$_anoSelecionado',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResumoCalculado {
  final double brutos;
  final double taxas;
  final double liquido;
  final int corridas;
  const _ResumoCalculado({
    required this.brutos,
    required this.taxas,
    required this.liquido,
    required this.corridas,
  });
}

class _SeletorAno extends StatelessWidget {
  final int ano;
  final ValueChanged<int> onChange;
  const _SeletorAno({required this.ano, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => onChange(ano - 1),
          ),
          Expanded(
            child: Center(
              child: Text(
                ano.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _roxo,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: ano >= DateTime.now().year
                ? null
                : () => onChange(ano + 1),
          ),
        ],
      ),
    );
  }
}

class _SeletorMesAno extends StatelessWidget {
  final int ano;
  final int mes;
  final void Function(int ano, int mes) onChange;
  const _SeletorMesAno({
    required this.ano,
    required this.mes,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final atual = DateTime(ano, mes);
    final fim = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              final anterior = DateTime(ano, mes - 1);
              onChange(anterior.year, anterior.month);
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat("MMMM 'de' yyyy", 'pt_BR').format(atual),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _roxo,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: (atual.year == fim.year && atual.month >= fim.month)
                ? null
                : () {
                    final proximo = DateTime(ano, mes + 1);
                    onChange(proximo.year, proximo.month);
                  },
          ),
        ],
      ),
    );
  }
}

class _ResumoFiscal extends StatelessWidget {
  final _ResumoCalculado resumo;
  final String periodo;

  const _ResumoFiscal({required this.resumo, required this.periodo});

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(
          periodo,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        _Kpi(
          icone: Icons.trending_up_rounded,
          rotulo: 'Ganhos brutos',
          valor: moeda.format(resumo.brutos),
          cor: Colors.green,
        ),
        _Kpi(
          icone: Icons.remove_circle_outline,
          rotulo: 'Taxas da plataforma',
          valor: moeda.format(resumo.taxas),
          cor: Colors.red,
        ),
        _Kpi(
          icone: Icons.payments_rounded,
          rotulo: 'Ganhos líquidos',
          valor: moeda.format(resumo.liquido),
          cor: _laranja,
        ),
        _Kpi(
          icone: Icons.pedal_bike_rounded,
          rotulo: 'Total de corridas',
          valor: resumo.corridas.toString(),
          cor: _roxo,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _roxo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: _roxo, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Os valores são atualizados em tempo real a cada entrega. '
                  'A exportação em PDF e o envio automático por e-mail chegarão em breve.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlocoTotalHistorico extends StatelessWidget {
  final _ResumoCalculado resumo;
  const _BlocoTotalHistorico({required this.resumo});

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _laranja.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acumulado total do entregador',
            style: TextStyle(fontWeight: FontWeight.bold, color: _roxo),
          ),
          const SizedBox(height: 10),
          _LinhaTotal(
              rotulo: 'Ganhos brutos', valor: moeda.format(resumo.brutos)),
          _LinhaTotal(
              rotulo: 'Taxas da plataforma',
              valor: moeda.format(resumo.taxas)),
          _LinhaTotal(
              rotulo: 'Ganhos líquidos',
              valor: moeda.format(resumo.liquido)),
          _LinhaTotal(
              rotulo: 'Total de corridas',
              valor: resumo.corridas.toString()),
        ],
      ),
    );
  }
}

class _LinhaTotal extends StatelessWidget {
  final String rotulo;
  final String valor;
  const _LinhaTotal({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            rotulo,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final String valor;
  final Color cor;

  const _Kpi({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
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
