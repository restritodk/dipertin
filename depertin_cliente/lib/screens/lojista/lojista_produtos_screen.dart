import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/location_service.dart';
import '../../services/permissoes_app_service.dart';
import '../../utils/safe_area_insets.dart';
import '../../widgets/dipertin_safe_bottom_panel.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const Color _fundoModal = Color(0xFFF5F4F8);
const Color _textoPrimario = Color(0xFF1A1A2E);
const Color _textoMuted = Color(0xFF64748B);
const Color _bordaCampo = Color(0xFFE0DEE8);
const Color _roxoEscuro = Color(0xFF4A148C);

enum _FiltroEstoqueChip { todos, prontaEntrega, encomenda, semEstoque, inativos }

enum _OrdenacaoEstoque { nome, precoAsc, estoqueDesc }

class _KpisEstoque {
  const _KpisEstoque({
    required this.total,
    required this.ativos,
    required this.semEstoque,
    required this.encomendas,
  });

  final int total;
  final int ativos;
  final int semEstoque;
  final int encomendas;
}

class LojistaProdutosScreen extends StatefulWidget {
  const LojistaProdutosScreen({super.key, this.uidLoja});

  final String? uidLoja;

  @override
  State<LojistaProdutosScreen> createState() => _LojistaProdutosScreenState();
}

class _LojistaProdutosScreenState extends State<LojistaProdutosScreen> {
  late final String _uid =
      widget.uidLoja ?? FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _buscaController = TextEditingController();

  late final Stream<QuerySnapshot> _streamProdutos = FirebaseFirestore.instance
      .collection('produtos')
      .where('lojista_id', isEqualTo: _uid)
      .snapshots();

  _FiltroEstoqueChip _filtroChip = _FiltroEstoqueChip.todos;
  _OrdenacaoEstoque _ordenacao = _OrdenacaoEstoque.nome;
  bool _entradaAnimada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _abrirFormularioProduto({DocumentSnapshot? produtoExistente}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FormularioProdutoModal(
          lojistaId: _uid,
          produtoExistente: produtoExistente,
        ),
      ),
    );
  }

  Future<bool?> _confirmarExclusaoProduto(String nomeProduto) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade700,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Excluir produto?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                nomeProduto.isNotEmpty
                    ? '“$nomeProduto” será removido da vitrine.'
                    : 'Este produto será removido da vitrine.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: _textoMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'As fotos no armazenamento também serão apagadas. Esta ação não pode ser desfeita.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textoMuted,
                        side: const BorderSide(color: _bordaCampo),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Excluir',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _excluirProduto(
    String id,
    String nomeProduto,
    List<dynamic>? urlsImagens,
  ) async {
    final bool? confirmar = await _confirmarExclusaoProduto(nomeProduto);
    if (confirmar != true) return;

    try {
      if (urlsImagens != null) {
        for (final url in urlsImagens) {
          if (url.toString().contains('firebasestorage')) {
            await FirebaseStorage.instance.refFromURL(url.toString()).delete();
          }
        }
      }
      await FirebaseFirestore.instance.collection('produtos').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto removido.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao excluir: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _dadosProduto(QueryDocumentSnapshot doc) =>
      doc.data() as Map<String, dynamic>;

  bool _produtoAtivo(Map<String, dynamic> m) => m['ativo'] != false;

  String _tipoVendaDe(Map<String, dynamic> m) =>
      (m['tipo_venda'] ?? 'pronta_entrega').toString();

  int _estoqueDe(Map<String, dynamic> m) {
    final raw = m['estoque_qtd'] ?? 0;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  _KpisEstoque _calcularKpis(List<QueryDocumentSnapshot> docs) {
    var ativos = 0;
    var semEstoque = 0;
    var encomendas = 0;
    for (final doc in docs) {
      final m = _dadosProduto(doc);
      if (_produtoAtivo(m)) ativos++;
      if (_tipoVendaDe(m) == 'encomenda') {
        encomendas++;
      } else if (_estoqueDe(m) <= 0) {
        semEstoque++;
      }
    }
    return _KpisEstoque(
      total: docs.length,
      ativos: ativos,
      semEstoque: semEstoque,
      encomendas: encomendas,
    );
  }

  List<QueryDocumentSnapshot> _filtrarEOrdenar(
    List<QueryDocumentSnapshot> docs,
    String busca,
  ) {
    var lista = docs.toList();
    if (busca.trim().isNotEmpty) {
      final q = busca.trim().toLowerCase();
      lista = lista.where((d) {
        final m = _dadosProduto(d);
        final nome = (m['nome'] ?? '').toString().toLowerCase();
        final cat = (m['categoria_nome'] ?? m['categoria'] ?? '')
            .toString()
            .toLowerCase();
        return nome.contains(q) || cat.contains(q);
      }).toList();
    }

    switch (_filtroChip) {
      case _FiltroEstoqueChip.prontaEntrega:
        lista = lista
            .where((d) => _tipoVendaDe(_dadosProduto(d)) != 'encomenda')
            .toList();
      case _FiltroEstoqueChip.encomenda:
        lista = lista
            .where((d) => _tipoVendaDe(_dadosProduto(d)) == 'encomenda')
            .toList();
      case _FiltroEstoqueChip.semEstoque:
        lista = lista.where((d) {
          final m = _dadosProduto(d);
          return _tipoVendaDe(m) != 'encomenda' && _estoqueDe(m) <= 0;
        }).toList();
      case _FiltroEstoqueChip.inativos:
        lista = lista
            .where((d) => !_produtoAtivo(_dadosProduto(d)))
            .toList();
      case _FiltroEstoqueChip.todos:
        break;
    }

    lista.sort((a, b) {
      final ma = _dadosProduto(a);
      final mb = _dadosProduto(b);
      switch (_ordenacao) {
        case _OrdenacaoEstoque.precoAsc:
          final pa = (ma['preco'] ?? 0.0) is num
              ? (ma['preco'] as num).toDouble()
              : 0.0;
          final pb = (mb['preco'] ?? 0.0) is num
              ? (mb['preco'] as num).toDouble()
              : 0.0;
          return pa.compareTo(pb);
        case _OrdenacaoEstoque.estoqueDesc:
          return _estoqueDe(mb).compareTo(_estoqueDe(ma));
        case _OrdenacaoEstoque.nome:
          final na = (ma['nome'] ?? '').toString().toLowerCase();
          final nb = (mb['nome'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);
      }
    });
    return lista;
  }

  Future<void> _alternarAtivoProduto(String id, bool ativoAtual) async {
    try {
      await FirebaseFirestore.instance.collection('produtos').doc(id).update({
        'ativo': !ativoAtual,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ativoAtual
                ? 'Produto pausado — não aparece na vitrine.'
                : 'Produto ativado na vitrine.',
          ),
          backgroundColor: ativoAtual ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao alternar ativo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _aoAtualizarLista() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  Widget _decorRadial(double size, Color cor) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [cor, cor.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _buildHeroKpis(_KpisEstoque kpis) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_roxoEscuro, diPertinRoxo, Color(0xFF8E24AA)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -30,
            child: _decorRadial(120, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -40,
            left: -40,
            child: _decorRadial(
              140,
              diPertinLaranja.withValues(alpha: 0.16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produtos visíveis na vitrine da sua cidade.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _KpiChipEstoque(
                      label: 'Total',
                      valor: '${kpis.total}',
                      icone: Icons.inventory_2_outlined,
                    ),
                    _KpiChipEstoque(
                      label: 'Ativos',
                      valor: '${kpis.ativos}',
                      icone: Icons.check_circle_outline,
                    ),
                    _KpiChipEstoque(
                      label: 'Sem estoque',
                      valor: '${kpis.semEstoque}',
                      icone: Icons.warning_amber_outlined,
                      destaque: kpis.semEstoque > 0,
                    ),
                    _KpiChipEstoque(
                      label: 'Encomendas',
                      valor: '${kpis.encomendas}',
                      icone: Icons.schedule,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoBusca() {
    return Transform.translate(
      offset: const Offset(0, -14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Material(
          color: Colors.white,
          elevation: 0,
          shadowColor: diPertinRoxo.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: diPertinRoxo.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: _buscaController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: _textoPrimario),
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou categoria…',
                hintStyle: const TextStyle(color: _textoMuted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _textoMuted,
                ),
                suffixIcon: _buscaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        color: _textoMuted,
                        onPressed: () {
                          _buscaController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _bordaCampo),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _bordaCampo),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: diPertinLaranja, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltrosChips() {
    const opcoes = <_FiltroEstoqueChip, String>{
      _FiltroEstoqueChip.todos: 'Todos',
      _FiltroEstoqueChip.prontaEntrega: 'Pronta entrega',
      _FiltroEstoqueChip.encomenda: 'Encomenda',
      _FiltroEstoqueChip.semEstoque: 'Sem estoque',
      _FiltroEstoqueChip.inativos: 'Inativos',
    };

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: opcoes.entries.map((e) {
          final selecionado = _filtroChip == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(e.value),
              selected: selecionado,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selecionado ? Colors.white : diPertinRoxo,
              ),
              selectedColor: diPertinLaranja,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selecionado ? diPertinLaranja : _bordaCampo,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (_) => setState(() => _filtroChip = e.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBarraContagemOrdenacao(
    List<QueryDocumentSnapshot> todos,
    List<QueryDocumentSnapshot> filtrados,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${filtrados.length} ${filtrados.length == 1 ? 'produto' : 'produtos'}'
              '${todos.length != filtrados.length ? ' · de ${todos.length}' : ''}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoMuted,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<_OrdenacaoEstoque>(
              value: _ordenacao,
              isDense: true,
              icon: const Icon(Icons.sort_rounded, size: 20, color: diPertinRoxo),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: diPertinRoxo,
              ),
              borderRadius: BorderRadius.circular(12),
              items: const [
                DropdownMenuItem(
                  value: _OrdenacaoEstoque.nome,
                  child: Text('Nome A–Z'),
                ),
                DropdownMenuItem(
                  value: _OrdenacaoEstoque.precoAsc,
                  child: Text('Menor preço'),
                ),
                DropdownMenuItem(
                  value: _OrdenacaoEstoque.estoqueDesc,
                  child: Text('Mais estoque'),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _ordenacao = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLista() {
    Widget cardSkeleton() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [for (var i = 0; i < 5; i++) cardSkeleton()],
    );
  }

  Widget _buildErroCarregamento(Object erro) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: diPertinRoxo.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 14),
              const Text(
                'Não foi possível carregar',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _textoPrimario,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$erro',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _textoMuted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(
                  backgroundColor: diPertinRoxo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemResultados() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Nenhum produto encontrado',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tente outro termo, limpe a busca ou mude o filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textoMuted, height: 1.4),
            ),
            if (_buscaController.text.isNotEmpty ||
                _filtroChip != _FiltroEstoqueChip.todos) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _buscaController.clear();
                  setState(() => _filtroChip = _FiltroEstoqueChip.todos);
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpar busca e filtros'),
                style: TextButton.styleFrom(foregroundColor: diPertinRoxo),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardProduto(
    QueryDocumentSnapshot doc,
    NumberFormat fmt,
  ) {
    final p = _dadosProduto(doc);
    final imagens = p['imagens'];
    final urlImg = imagens is List && imagens.isNotEmpty
        ? imagens.first.toString()
        : '';
    final ativo = _produtoAtivo(p);
    final preco = (p['preco'] ?? 0.0) is num
        ? (p['preco'] as num).toDouble()
        : 0.0;
    final tipoVenda = _tipoVendaDe(p);
    final estoque = _estoqueDe(p);
    final categoria =
        p['categoria_nome']?.toString() ?? p['categoria']?.toString();
    final requerVeiculoGrande = p['requer_veiculo_grande'] == true;
    final usaVariacoes = p['usa_variacoes'] == true;
    final nome = (p['nome'] ?? 'Sem nome').toString();

    return Opacity(
      opacity: ativo ? 1 : 0.72,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: ativo
              ? null
              : Border.all(color: Colors.grey.shade300, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: diPertinRoxo.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _abrirFormularioProduto(produtoExistente: doc),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: urlImg.isNotEmpty
                        ? Image.network(
                            urlImg,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _thumbPlaceholder(),
                          )
                        : SizedBox(
                            width: 72,
                            height: 72,
                            child: _thumbPlaceholder(semFoto: true),
                          ),
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
                                nome,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  height: 1.2,
                                  color: ativo ? _textoPrimario : _textoMuted,
                                ),
                              ),
                            ),
                            if (!ativo)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Inativo',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (categoria != null && categoria.isNotEmpty)
                              _MiniChip(
                                label: categoria,
                                icon: Icons.label_outline,
                              ),
                            if (tipoVenda == 'encomenda')
                              const _MiniChip(
                                label: 'Encomenda',
                                icon: Icons.schedule,
                                corFundo: Color(0xFFFFF3E0),
                                corTexto: diPertinLaranja,
                              )
                            else if (estoque <= 0)
                              const _MiniChip(
                                label: 'Sem estoque',
                                icon: Icons.inventory_2_outlined,
                                corFundo: Color(0xFFFFEBEE),
                                corTexto: Colors.red,
                              )
                            else
                              _MiniChip(
                                label: 'Estoque: $estoque',
                                icon: Icons.inventory_2_outlined,
                                corFundo: const Color(0xFFE8F5E9),
                                corTexto: Colors.green.shade800,
                              ),
                            if (requerVeiculoGrande)
                              const _MiniChip(
                                label: 'Carro',
                                icon: Icons.local_shipping_outlined,
                                corFundo: Color(0xFFE3F2FD),
                                corTexto: Color(0xFF1565C0),
                              ),
                            if (usaVariacoes)
                              const _MiniChip(
                                label: 'Variações',
                                icon: Icons.style_outlined,
                              ),
                            if (urlImg.isEmpty)
                              _MiniChip(
                                label: 'Sem foto',
                                icon: Icons.hide_image_outlined,
                                corFundo: Colors.orange.shade50,
                                corTexto: Colors.orange.shade800,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fmt.format(preco),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: diPertinLaranja,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: diPertinRoxo.withValues(alpha: 0.85),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (acao) async {
                      switch (acao) {
                        case 'editar':
                          _abrirFormularioProduto(produtoExistente: doc);
                        case 'toggle':
                          await _alternarAtivoProduto(doc.id, ativo);
                        case 'excluir':
                          await _excluirProduto(
                            doc.id,
                            nome,
                            imagens is List
                                ? List<dynamic>.from(imagens)
                                : null,
                          );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, color: diPertinRoxo),
                          title: Text('Editar'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            ativo
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            color: ativo ? Colors.orange : Colors.green,
                          ),
                          title: Text(ativo ? 'Pausar na vitrine' : 'Ativar na vitrine'),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'excluir',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Excluir'),
                          dense: true,
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
    );
  }

  Widget _buildListaProdutos(
    List<QueryDocumentSnapshot> todos,
    List<QueryDocumentSnapshot> filtrados,
    NumberFormat fmt,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBarraContagemOrdenacao(todos, filtrados),
        Expanded(
          child: AnimatedOpacity(
            opacity: _entradaAnimada ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: RefreshIndicator(
              color: diPertinLaranja,
              onRefresh: _aoAtualizarLista,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: filtrados.length,
                itemBuilder: (context, index) =>
                    _buildCardProduto(filtrados[index], fmt),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConteudoStream(AsyncSnapshot<QuerySnapshot> snapshot) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return _buildSkeletonLista();
    }
    if (snapshot.hasError) {
      return _buildErroCarregamento(snapshot.error!);
    }

    final todos = snapshot.data?.docs ?? [];
    final filtrados = _filtrarEOrdenar(todos, _buscaController.text);

    if (todos.isEmpty) {
      return AnimatedOpacity(
        opacity: _entradaAnimada ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: const _EstadoVazioEstoque(),
      );
    }
    if (filtrados.isEmpty) {
      return AnimatedOpacity(
        opacity: _entradaAnimada ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: _buildSemResultados(),
      );
    }

    return _buildListaProdutos(todos, filtrados, fmt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoModal,
      appBar: AppBar(
        title: const Text(
          'Meu estoque',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: diPertinRoxo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBar: DiPertinSafeBottomPanel(
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _abrirFormularioProduto,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Novo produto',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: diPertinLaranja,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _streamProdutos,
        builder: (context, snapshot) {
          final todos = snapshot.data?.docs ?? [];
          final kpis = _calcularKpis(todos);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroKpis(kpis),
              _buildCampoBusca(),
              _buildFiltrosChips(),
              Expanded(child: _buildConteudoStream(snapshot)),
            ],
          );
        },
      ),
    );
  }

  Widget _thumbPlaceholder({bool semFoto = false}) {
    return Container(
      color: const Color(0xFFEDEAF2),
      alignment: Alignment.center,
      child: Icon(
        semFoto ? Icons.add_a_photo_outlined : Icons.image_not_supported_outlined,
        color: semFoto ? diPertinRoxo.withValues(alpha: 0.5) : Colors.grey.shade400,
        size: 28,
      ),
    );
  }
}

class _KpiChipEstoque extends StatelessWidget {
  const _KpiChipEstoque({
    required this.label,
    required this.valor,
    required this.icone,
    this.destaque = false,
  });

  final String label;
  final String valor;
  final IconData icone;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: destaque
            ? Colors.orange.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destaque
              ? diPertinLaranja.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.icon,
    this.corFundo = const Color(0xFFF0EBF5),
    this.corTexto = diPertinRoxo,
  });

  final String label;
  final IconData icon;
  final Color corFundo;
  final Color corTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: corTexto),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: corTexto,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazioEstoque extends StatelessWidget {
  const _EstadoVazioEstoque();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: diPertinRoxo.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: diPertinLaranja.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Seu estoque está vazio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _textoPrimario,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Cadastre produtos com fotos, preço e categoria para aparecerem na vitrine do app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: _textoMuted,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _bordaCampo),
                boxShadow: [
                  BoxShadow(
                    color: diPertinRoxo.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: diPertinLaranja.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: diPertinLaranja,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toque em Novo produto',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'O botão fixo no rodapé abre o cadastro.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _textoMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_downward_rounded,
                    color: diPertinRoxo.withValues(alpha: 0.55),
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormularioProdutoModal extends StatefulWidget {
  const FormularioProdutoModal({
    super.key,
    required this.lojistaId,
    this.produtoExistente,
  });

  final String lojistaId;
  final DocumentSnapshot? produtoExistente;

  @override
  State<FormularioProdutoModal> createState() => _FormularioProdutoModalState();
}

class _FormularioProdutoModalState extends State<FormularioProdutoModal> {
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoController = TextEditingController();
  final _estoqueController = TextEditingController(text: '1');
  final _prazoController = TextEditingController();
  final _corController = TextEditingController();
  final _tamanhoController = TextEditingController();

  String? _categoriaSelecionada;
  final List<File> _novasImagens = [];
  List<dynamic> _imagensAtuais = [];
  bool _salvando = false;
  String _tipoVenda = 'pronta_entrega';
  bool _usaVariacoes = false;
  List<String> _cores = [];
  List<String> _tamanhos = [];
  bool _entradaAnimada = false;

  String _cidadeLoja = '';
  String _ufLoja = '';
  String _nomeLoja = '';

  int get _totalFotos => _imagensAtuais.length + _novasImagens.length;

  bool get _formularioMinimoOk =>
      _nomeController.text.trim().isNotEmpty &&
      _precoController.text.trim().isNotEmpty &&
      _categoriaSelecionada != null;

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF9F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: diPertinRoxo,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _bordaCampo),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: diPertinLaranja, width: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _carregarDadosLojista();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entradaAnimada = true);
    });
    if (widget.produtoExistente != null) {
      final p = widget.produtoExistente!.data() as Map<String, dynamic>;
      _nomeController.text = p['nome'] ?? '';
      _descricaoController.text = p['descricao'] ?? '';
      _precoController.text = (p['preco'] ?? 0.0).toStringAsFixed(2);
      _categoriaSelecionada = p['categoria_nome']?.toString();
      _imagensAtuais = List<dynamic>.from(p['imagens'] ?? []);
      _tipoVenda = p['tipo_venda'] ?? 'pronta_entrega';
      _estoqueController.text = (p['estoque_qtd'] ?? 1).toString();
      _prazoController.text = p['prazo_encomenda'] ?? '';
      _usaVariacoes = p['usa_variacoes'] == true;
      _cores = _listaStrings(p['variacoes_cores']);
      _tamanhos = _listaStrings(p['variacoes_tamanhos']);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _estoqueController.dispose();
    _prazoController.dispose();
    _corController.dispose();
    _tamanhoController.dispose();
    super.dispose();
  }

  List<String> _listaStrings(dynamic raw) {
    final lista = raw is List ? raw : const [];
    return lista
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  void _adicionarVariacao({
    required TextEditingController controller,
    required List<String> destino,
  }) {
    final texto = controller.text.trim();
    if (texto.isEmpty) return;
    if (!destino.any((e) => e.toLowerCase() == texto.toLowerCase())) {
      setState(() => destino.add(texto));
    }
    controller.clear();
  }

  Future<void> _carregarDadosLojista() async {
    try {
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojistaId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _cidadeLoja = (data['cidade'] ?? '').toString();
        _ufLoja = (data['uf'] ?? data['estado'] ?? '').toString();
        _nomeLoja =
            data['loja_nome'] ?? data['nome_loja'] ?? data['nome'] ?? 'Loja';
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao carregar dados do lojista: $e');
      }
    }
  }

  Future<void> _sugerirCategoria() async {
    final String? nomeSugestao = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SugerirCategoriaDialog(),
    );
    if (nomeSugestao == null || nomeSugestao.isEmpty) return;

    await FirebaseFirestore.instance.collection('sugestoes_categorias').add({
      'nome': nomeSugestao,
      'lojista_id': widget.lojistaId,
      'status': 'pendente',
      'origem': 'app_lojista_produto',
      'data': FieldValue.serverTimestamp(),
      'criada_em': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text('Sugestão enviada')),
            ],
          ),
          content: Text(
            'A categoria "$nomeSugestao" foi enviada para análise. '
            'Assim que for aprovada, ela ficará disponível no cadastro de produtos.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pegarImagem() async {
    final ResultadoPermissao pr =
        await PermissoesAppService.garantirGaleriaFotos();
    if (!mounted) return;
    if (pr != ResultadoPermissao.concedida) {
      PermissoesFeedback.galeria(context, pr);
      return;
    }
    final pickedFiles = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (final file in pickedFiles) {
          if (_novasImagens.length + _imagensAtuais.length < 5) {
            _novasImagens.add(File(file.path));
          }
        }
      });
    }
  }

  Future<void> _salvar() async {
    if (_nomeController.text.isEmpty ||
        _precoController.text.isEmpty ||
        _categoriaSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha nome, preço e categoria.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_usaVariacoes && _cores.isEmpty && _tamanhos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione ao menos uma cor ou tamanho/numeração.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final List<String> urlsFinais = List<String>.from(
        _imagensAtuais.map((e) => e.toString()),
      );
      for (final file in _novasImagens) {
        final String path =
            'produtos/${widget.lojistaId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final TaskSnapshot task = await FirebaseStorage.instance
            .ref()
            .child(path)
            .putFile(file);
        urlsFinais.add(await task.ref.getDownloadURL());
      }

      final dados = <String, dynamic>{
        'lojista_id': widget.lojistaId,
        'loja_id': widget.lojistaId,
        'loja_nome': _nomeLoja,
        'nome': _nomeController.text.trim(),
        'descricao': _descricaoController.text.trim(),
        'preco':
            double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0,
        'categoria': _categoriaSelecionada,
        'categoria_nome': _categoriaSelecionada,
        'imagens': urlsFinais,
        'tipo_venda': _tipoVenda,
        'estoque_qtd': int.tryParse(_estoqueController.text) ?? 0,
        'prazo_encomenda': _prazoController.text.trim(),
        'usa_variacoes': _usaVariacoes,
        'variacoes_cores': _usaVariacoes ? _cores : <String>[],
        'variacoes_tamanhos': _usaVariacoes ? _tamanhos : <String>[],
        'variacoes': {
          'cores': _usaVariacoes ? _cores : <String>[],
          'tamanhos': _usaVariacoes ? _tamanhos : <String>[],
        },
        'ativo': true,
        'cidade': _cidadeLoja,
        'uf': _ufLoja,
        'cidade_normalizada': LocationService.normalizar(_cidadeLoja),
        'uf_normalizado':
            LocationService.extrairUf(_ufLoja) ??
            LocationService.normalizar(_ufLoja),
      };

      if (widget.produtoExistente != null) {
        await FirebaseFirestore.instance
            .collection('produtos')
            .doc(widget.produtoExistente!.id)
            .update(dados);
      } else {
        dados['data_criacao'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('produtos').add(dados);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao salvar: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _cabecalhoModal() {
    final editando = widget.produtoExistente != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editando ? 'Editar produto' : 'Novo produto',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _textoPrimario,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Fotos nítidas e dados corretos vendem mais na vitrine.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textoMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _salvando ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                color: _textoMuted,
                tooltip: 'Fechar',
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _caixaSecaoModal({
    required String titulo,
    required IconData icone,
    required Widget child,
    String? subtitulo,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: diPertinRoxo.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _secaoTitulo(titulo, icone)),
              if (trailing != null) trailing,
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: const TextStyle(
                fontSize: 12.5,
                color: _textoMuted,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildGaleriaFotos() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._imagensAtuais.asMap().entries.map(
            (e) => _imgCard(
              url: e.value.toString(),
              capa: e.key == 0,
              onDel: () => setState(() => _imagensAtuais.removeAt(e.key)),
            ),
          ),
          ..._novasImagens.asMap().entries.map(
            (e) => _imgCard(
              file: e.value,
              capa: _imagensAtuais.isEmpty && e.key == 0,
              onDel: () => setState(() => _novasImagens.removeAt(e.key)),
            ),
          ),
          if (_totalFotos < 5)
            Material(
              color: diPertinRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _pegarImagem,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: diPertinRoxo,
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adicionar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: diPertinRoxo.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBotaoSalvar() {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        onPressed: (_salvando || !_formularioMinimoOk) ? null : _salvar,
        style: FilledButton.styleFrom(
          backgroundColor: diPertinLaranja,
          disabledBackgroundColor: diPertinLaranja.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _salvando
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Salvar produto',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = diPertinSafeAreaBottom(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: _fundoModal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _cabecalhoModal(),
          Expanded(
            child: AnimatedOpacity(
              opacity: _entradaAnimada ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _caixaSecaoModal(
                      titulo: 'Fotos',
                      icone: Icons.photo_library_outlined,
                      subtitulo:
                          'Até 5 fotos — a primeira é a capa na vitrine.',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: diPertinRoxo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_totalFotos/5',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: diPertinRoxo,
                          ),
                        ),
                      ),
                      child: _buildGaleriaFotos(),
                    ),
                    _caixaSecaoModal(
                      titulo: 'Informações',
                      icone: Icons.edit_note_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _nomeController,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                            decoration: _fieldDecoration('Nome do produto *'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descricaoController,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: 3,
                            decoration: _fieldDecoration(
                              'Descrição',
                              hint: 'Opcional — ingredientes, tamanho…',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _precoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.,]'),
                              ),
                            ],
                            decoration: _fieldDecoration('Preço *').copyWith(
                              prefixText: 'R\$ ',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _caixaSecaoModal(
                      titulo: 'Tipo de venda',
                      icone: Icons.local_shipping_outlined,
                      subtitulo: _tipoVenda == 'pronta_entrega'
                          ? 'Pronta entrega com quantidade em estoque.'
                          : 'Sob encomenda — informe o prazo de produção.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'pronta_entrega',
                                label: Text('Estoque'),
                                icon: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 18,
                                ),
                              ),
                              ButtonSegment(
                                value: 'encomenda',
                                label: Text('Encomenda'),
                                icon: Icon(Icons.schedule, size: 18),
                              ),
                            ],
                            selected: {_tipoVenda},
                            onSelectionChanged: (s) =>
                                setState(() => _tipoVenda = s.first),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              foregroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return diPertinRoxo;
                              }),
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return diPertinLaranja;
                                }
                                return _fundoModal;
                              }),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_tipoVenda == 'pronta_entrega')
                            TextField(
                              controller: _estoqueController,
                              keyboardType: TextInputType.number,
                              decoration:
                                  _fieldDecoration('Quantidade em estoque'),
                            ),
                          if (_tipoVenda == 'encomenda')
                            TextField(
                              controller: _prazoController,
                              decoration: _fieldDecoration(
                                'Prazo de produção',
                                hint: 'Ex.: 2 dias úteis',
                              ),
                            ),
                        ],
                      ),
                    ),
                    _caixaSecaoModal(
                      titulo: 'Variações',
                      icone: Icons.style_outlined,
                      child: _buildSecaoVariacoes(),
                    ),
                    _caixaSecaoModal(
                      titulo: 'Categoria',
                      icone: Icons.category_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('categorias')
                                .where('ativo', isEqualTo: true)
                                .snapshots(),
                            builder: (context, snap) {
                              if (!snap.hasData) {
                                return const LinearProgressIndicator(
                                  color: diPertinLaranja,
                                );
                              }
                              final categorias = snap.data!.docs.toList()
                                ..sort((a, b) {
                                  final ma = a.data() as Map<String, dynamic>;
                                  final mb = b.data() as Map<String, dynamic>;
                                  final oa =
                                      (ma['ordem'] as num?)?.toInt() ?? 999;
                                  final ob =
                                      (mb['ordem'] as num?)?.toInt() ?? 999;
                                  if (oa != ob) return oa.compareTo(ob);
                                  return (ma['nome'] ?? '')
                                      .toString()
                                      .compareTo(
                                        (mb['nome'] ?? '').toString(),
                                      );
                                });
                              final valores = categorias
                                  .map(
                                    (d) =>
                                        ((d.data()
                                                as Map<String, dynamic>)['nome'] ??
                                            '')
                                        .toString(),
                                  )
                                  .where((nome) => nome.isNotEmpty)
                                  .toSet()
                                  .toList();
                              final valorAtual =
                                  valores.contains(_categoriaSelecionada)
                                  ? _categoriaSelecionada
                                  : null;
                              return DropdownButtonFormField<String>(
                                key: ValueKey(valorAtual),
                                initialValue: valorAtual,
                                isExpanded: true,
                                decoration: _fieldDecoration('Selecione *'),
                                items: valores
                                    .map(
                                      (nome) => DropdownMenuItem(
                                        value: nome,
                                        child: Text(nome),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(
                                  () => _categoriaSelecionada = v,
                                ),
                              );
                            },
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _sugerirCategoria,
                              icon: const Icon(
                                Icons.lightbulb_outline,
                                size: 18,
                              ),
                              label: const Text('Sugerir nova categoria'),
                              style: TextButton.styleFrom(
                                foregroundColor: diPertinRoxo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_formularioMinimoOk)
                      Padding(
                        padding: EdgeInsets.only(bottom: bottomInset > 0 ? 4 : 8),
                        child: Text(
                          'Preencha nome, preço e categoria para salvar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: _buildBotaoSalvar(),
          ),
        ],
      ),
    );
  }

  Widget _secaoTitulo(String titulo, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 20, color: diPertinRoxo),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _textoPrimario,
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoVariacoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          value: _usaVariacoes,
          contentPadding: EdgeInsets.zero,
          activeThumbColor: diPertinLaranja,
          title: const Text(
            'Produto com variações',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Use para roupas, calçados e produtos com cor, tamanho ou numeração.',
          ),
          onChanged: (v) => setState(() => _usaVariacoes = v),
        ),
        if (_usaVariacoes) ...[
          const SizedBox(height: 10),
          _campoListaVariacao(
              titulo: 'Cores disponíveis',
              hint: 'Ex.: Azul, Preto, Vermelho',
              controller: _corController,
              valores: _cores,
              icon: Icons.palette_outlined,
              onAdd: () => _adicionarVariacao(
                controller: _corController,
                destino: _cores,
              ),
              onRemove: (valor) => setState(() => _cores.remove(valor)),
            ),
            const SizedBox(height: 14),
            _campoListaVariacao(
              titulo: 'Tamanhos ou numerações',
              hint: 'Ex.: PP, P, M, G, GG ou 38, 39, 40',
              controller: _tamanhoController,
              valores: _tamanhos,
              icon: Icons.straighten,
              onAdd: () => _adicionarVariacao(
                controller: _tamanhoController,
                destino: _tamanhos,
              ),
              onRemove: (valor) => setState(() => _tamanhos.remove(valor)),
            ),
        ],
      ],
    );
  }

  Widget _campoListaVariacao({
    required String titulo,
    required String hint,
    required TextEditingController controller,
    required List<String> valores,
    required IconData icon,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(
                  hint,
                ).copyWith(prefixIcon: Icon(icon, color: diPertinRoxo)),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: diPertinRoxo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        ),
        if (valores.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: valores
                .map(
                  (valor) => Chip(
                    label: Text(valor),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => onRemove(valor),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: diPertinRoxo.withValues(alpha: 0.22),
                    ),
                    labelStyle: const TextStyle(
                      color: diPertinRoxo,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _imgCard({
    String? url,
    File? file,
    required VoidCallback onDel,
    bool capa = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 92,
              height: 92,
              child: url != null
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
          if (capa)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: diPertinLaranja,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Capa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Colors.red,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onDel,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog interno com ciclo de vida próprio para o TextEditingController,
// evitando o `_dependents.isEmpty` assertion que acontecia ao dar dispose
// no controller logo após Navigator.pop.
class _SugerirCategoriaDialog extends StatefulWidget {
  const _SugerirCategoriaDialog();

  @override
  State<_SugerirCategoriaDialog> createState() =>
      _SugerirCategoriaDialogState();
}

class _SugerirCategoriaDialogState extends State<_SugerirCategoriaDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    Navigator.pop(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Sugerir categoria',
        style: TextStyle(color: diPertinLaranja),
      ),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        onSubmitted: (_) => _enviar(),
        decoration: const InputDecoration(
          hintText: 'Ex.: Veganos, doces…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _enviar, child: const Text('Enviar')),
      ],
    );
  }
}
