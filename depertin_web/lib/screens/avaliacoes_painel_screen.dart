import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/painel_admin_theme.dart';
import '../utils/codigo_pedido.dart';
class AvaliacoesPainelScreen extends StatefulWidget {
  const AvaliacoesPainelScreen({super.key});

  @override
  State<AvaliacoesPainelScreen> createState() => _AvaliacoesPainelScreenState();
}

class _AvaliacoesPainelScreenState extends State<AvaliacoesPainelScreen> {
  static const _ink = Color(0xFF1E1B4B);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _bg = Color(0xFFF8FAFC);
  static const _amber = Color(0xFFF59E0B);
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);

  String _janela = 'hoje';
  int _estrelas = 0;
  String _ordenacao = 'recentes';
  final _buscaC = TextEditingController();

  final _cacheNomesLojas = <String, String>{};

  @override
  void dispose() {
    _buscaC.dispose();
    super.dispose();
  }

  Future<String> _resolverNomeLoja(String? lojaId) async {
    if (lojaId == null || lojaId.isEmpty) return 'Loja';
    if (_cacheNomesLojas.containsKey(lojaId)) return _cacheNomesLojas[lojaId]!;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .get();
      final d = doc.data() ?? {};
      final nome = (d['loja_nome'] ?? d['nome_fantasia'] ?? d['nomeFantasia'] ??
              d['nome_loja'] ?? d['nome'] ?? 'Loja')
          .toString();
      _cacheNomesLojas[lojaId] = nome;
      return nome;
    } catch (_) {
      return 'Loja';
    }
  }

  int _notaDoc(Map<String, dynamic> d) {
    final v = d['nota'] ?? d['estrelas'];
    if (v is int) return v.clamp(1, 5);
    if (v is num) return v.toInt().clamp(1, 5);
    return 0;
  }

  Timestamp? _dataDoc(Map<String, dynamic> d) {
    return (d['data'] ?? d['data_criacao']) as Timestamp?;
  }

  String _clienteDoc(Map<String, dynamic> d) {
    return (d['cliente_nome_exibicao'] ?? d['cliente_nome'] ?? '')
        .toString();
  }

  bool _passaJanela(Timestamp? ts) {
    if (_janela == 'todos') return true;
    if (ts == null) return false;
    final dt = ts.toDate();
    final agora = DateTime.now();
    if (_janela == 'hoje') {
      return dt.year == agora.year &&
          dt.month == agora.month &&
          dt.day == agora.day;
    }
    final diff = agora.difference(dt);
    if (_janela == '7d') return diff.inDays <= 7;
    if (_janela == '30d') return diff.inDays <= 30;
    return true;
  }

  bool _passaBusca(Map<String, dynamic> d) {
    final q = _buscaC.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      _clienteDoc(d),
      d['comentario'],
      d['resposta_loja'],
      d['pedido_id'],
      d['loja_id'],
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ').contains(q);
  }

  Color _corNota(int n) {
    if (n <= 2) return _red;
    if (n == 3) return _amber;
    return _green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('avaliacoes')
            .orderBy('data', descending: true)
            .limit(500)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            );
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Erro ao carregar avaliações:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _red),
                ),
              ),
            );
          }

          var docs = (snap.data?.docs ?? []).where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return _passaJanela(_dataDoc(d));
          }).toList();

          final todosNaJanela = List<QueryDocumentSnapshot>.from(docs);

          if (_estrelas > 0) {
            docs = docs.where((d) {
              return _notaDoc(d.data() as Map<String, dynamic>) == _estrelas;
            }).toList();
          }

          if (_buscaC.text.trim().isNotEmpty) {
            docs = docs
                .where(
                    (d) => _passaBusca(d.data() as Map<String, dynamic>))
                .toList();
          }

          if (_ordenacao == 'piores') {
            docs.sort((a, b) {
              final na = _notaDoc(a.data() as Map<String, dynamic>);
              final nb = _notaDoc(b.data() as Map<String, dynamic>);
              return na.compareTo(nb);
            });
          } else if (_ordenacao == 'melhores') {
            docs.sort((a, b) {
              final na = _notaDoc(a.data() as Map<String, dynamic>);
              final nb = _notaDoc(b.data() as Map<String, dynamic>);
              return nb.compareTo(na);
            });
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _kpis(todosNaJanela)),
              if (docs.isEmpty)
                SliverFillRemaining(child: _vazio())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  sliver: SliverList.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(docs[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avaliações',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Acompanhe o que os clientes dizem sobre as lojas',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: DropdownButton<String>(
                  value: _ordenacao,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  borderRadius: BorderRadius.circular(12),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                  items: const [
                    DropdownMenuItem(
                        value: 'recentes', child: Text('Mais recentes')),
                    DropdownMenuItem(
                        value: 'piores', child: Text('Piores notas')),
                    DropdownMenuItem(
                        value: 'melhores', child: Text('Melhores notas')),
                  ],
                  onChanged: (v) => setState(() => _ordenacao = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscaC,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por loja, cliente ou comentário...',
                    hintStyle:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: _bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: PainelAdminTheme.roxo, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _janelaBtn('hoje', 'Hoje'),
              const SizedBox(width: 6),
              _janelaBtn('7d', '7 dias'),
              const SizedBox(width: 6),
              _janelaBtn('30d', '30 dias'),
              const SizedBox(width: 6),
              _janelaBtn('todos', 'Tudo'),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipEstrela(0, 'Todas'),
                _chipEstrela(1, '★ 1'),
                _chipEstrela(2, '★★ 2'),
                _chipEstrela(3, '★★★ 3'),
                _chipEstrela(4, '★★★★ 4'),
                _chipEstrela(5, '★★★★★ 5'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _janelaBtn(String val, String label) {
    final ativo = _janela == val;
    return Material(
      color: ativo ? const Color(0xFFEEF2FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ativo ? const Color(0xFFC7D2FE) : _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _janela = val),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ativo ? const Color(0xFF4338CA) : _muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipEstrela(int valor, String label) {
    final ativo = _estrelas == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: ativo ? _amber : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side:
              BorderSide(color: ativo ? _amber : const Color(0xFFCBD5E1)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _estrelas = valor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ativo ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpis(List<QueryDocumentSnapshot> docs) {
    final total = docs.length;
    final soma = docs.fold<double>(
        0, (acc, d) => acc + _notaDoc(d.data() as Map<String, dynamic>));
    final media = total > 0 ? soma / total : 0.0;

    int contar(int e) => docs
        .where((d) => _notaDoc(d.data() as Map<String, dynamic>) == e)
        .length;
    final c5 = contar(5);
    final c4 = contar(4);
    final c3 = contar(3);
    final c2 = contar(2);
    final c1 = contar(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _kpi('Total', '$total', Icons.rate_review_outlined,
              PainelAdminTheme.roxo),
          _kpi('Média', media.toStringAsFixed(1), Icons.star_rounded, _amber),
          _kpi('5 estrelas', '$c5', Icons.sentiment_very_satisfied_rounded,
              _green),
          _kpi('4 estrelas', '$c4', Icons.sentiment_satisfied_rounded,
              const Color(0xFF059669)),
          _kpi('3 estrelas', '$c3', Icons.sentiment_neutral_rounded, _amber),
          _kpi('2 estrelas', '$c2', Icons.sentiment_dissatisfied_rounded,
              const Color(0xFFEA580C)),
          _kpi('1 estrela', '$c1', Icons.sentiment_very_dissatisfied_rounded,
              _red),
        ],
      ),
    );
  }

  Widget _kpi(String label, String valor, IconData icon, Color cor) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: cor),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cor,
                    height: 1,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: _muted, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border_rounded,
              size: 56, color: _amber.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          const Text(
            'Nenhuma avaliação encontrada',
            style: TextStyle(
                fontSize: 16, color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ajuste os filtros, período ou busca.',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _card(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final nota = _notaDoc(d);
    final cor = _corNota(nota);
    final comentario = d['comentario']?.toString() ?? '';
    final resposta = d['resposta_loja']?.toString() ?? '';
    final cliente = _clienteDoc(d);
    final ts = _dataDoc(d);
    final data = ts != null
        ? DateFormat('dd/MM/yyyy  HH:mm').format(ts.toDate())
        : '—';
    final pedidoId = d['pedido_id']?.toString() ?? '';
    final lojaId = d['loja_id']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$nota',
                        style: TextStyle(
                          color: cor,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.star_rounded, color: cor, size: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _resolverNomeLoja(lojaId),
                        builder: (context, snap) {
                          final nome = snap.data ?? 'Carregando...';
                          return Row(
                            children: [
                              Icon(Icons.storefront_rounded,
                                  size: 15, color: PainelAdminTheme.roxo),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  nome,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: PainelAdminTheme.roxo,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          if (cliente.isNotEmpty)
                            _tag(Icons.person_outline_rounded, cliente),
                          _tag(Icons.calendar_today_rounded, data),
                          if (pedidoId.isNotEmpty)
                            _tag(
                                Icons.receipt_long_outlined,
                                CodigoPedido.gerar(pedidoId)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _estrelasVisuais(nota),
              ],
            ),
            if (comentario.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  '"$comentario"',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF334155),
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (resposta.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: PainelAdminTheme.roxo.withValues(alpha: 0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_rounded,
                        size: 16,
                        color: PainelAdminTheme.roxo.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        resposta,
                        style: TextStyle(
                          fontSize: 13,
                          color: PainelAdminTheme.roxo.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmarExclusao(doc.id),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: _red),
                label: const Text(
                  'Remover',
                  style: TextStyle(
                      color: _red, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estrelasVisuais(int qtd) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < qtd ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: i < qtd ? _amber : const Color(0xFFCBD5E1),
        );
      }),
    );
  }

  Widget _tag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
      ],
    );
  }

  Future<void> _confirmarExclusao(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _amber),
          SizedBox(width: 12),
          Expanded(
            child: Text('Remover avaliação',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ),
        ]),
        content: const Text(
            'Esta avaliação será removida permanentemente. Deseja continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await FirebaseFirestore.instance
          .collection('avaliacoes')
          .doc(docId)
          .delete();
    }
  }
}
