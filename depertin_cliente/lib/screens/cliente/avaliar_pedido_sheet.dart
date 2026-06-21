import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:depertin_cliente/utils/codigo_pedido.dart';
import 'package:flutter/material.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Bottom sheet para avaliar pedido entregue.
///
/// Grava 1 avaliação da loja em `avaliacoes/{pedidoId}` e, para cada produto
/// que o cliente avaliar, um doc em `avaliacoes_produto/{pedidoId}_{produtoId}`.
Future<void> mostrarAvaliarPedidoSheet(
  BuildContext context, {
  required String pedidoId,
  required String lojaId,
  required String lojaNome,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
      ),
      child: _AvaliarPedidoForm(
        pedidoId: pedidoId,
        lojaId: lojaId,
        lojaNome: lojaNome,
      ),
    ),
  );
}

/// Estado editável da avaliação de um produto dentro do sheet.
class _ItemProdutoAvaliacao {
  _ItemProdutoAvaliacao({
    required this.produtoId,
    required this.nome,
    required this.imagem,
  });

  final String produtoId;
  final String nome;
  final String imagem;
  int nota = 0; // 0 = não avaliado
  final TextEditingController comentario = TextEditingController();

  void dispose() => comentario.dispose();
}

class _AvaliarPedidoForm extends StatefulWidget {
  const _AvaliarPedidoForm({
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
  });

  final String pedidoId;
  final String lojaId;
  final String lojaNome;

  @override
  State<_AvaliarPedidoForm> createState() => _AvaliarPedidoFormState();
}

class _AvaliarPedidoFormState extends State<_AvaliarPedidoForm> {
  int _notaLoja = 5;
  final TextEditingController _comentarioLoja = TextEditingController();
  bool _enviando = false;

  bool _carregandoItens = true;
  final List<_ItemProdutoAvaliacao> _produtos = [];

  @override
  void initState() {
    super.initState();
    _carregarItensPedido();
  }

  @override
  void dispose() {
    _comentarioLoja.dispose();
    for (final p in _produtos) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarItensPedido() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pedidos')
          .doc(widget.pedidoId)
          .get();
      final itens = (doc.data()?['itens'] as List?) ?? const [];
      final vistos = <String>{};
      for (final raw in itens) {
        if (raw is! Map) continue;
        final tipoVenda = (raw['tipo_venda'] ?? 'pronta_entrega').toString();
        if (tipoVenda == 'encomenda') continue;
        final id = (raw['id_produto'] ?? '').toString().trim();
        if (id.isEmpty || vistos.contains(id)) continue;
        vistos.add(id);
        _produtos.add(
          _ItemProdutoAvaliacao(
            produtoId: id,
            nome: (raw['nome'] ?? 'Produto').toString(),
            imagem: (raw['imagem'] ?? '').toString(),
          ),
        );
      }
    } catch (_) {
      // Sem itens: o sheet ainda permite avaliar a loja.
    } finally {
      if (mounted) setState(() => _carregandoItens = false);
    }
  }

  Future<void> _enviar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _enviando = true);
    try {
      String nomeCliente = user.displayName ?? '';
      if (nomeCliente.isEmpty) {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        nomeCliente = u.data()?['nome']?.toString() ?? '';
      }

      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      final comentarioLoja = _comentarioLoja.text.trim();
      batch.set(db.collection('avaliacoes').doc(widget.pedidoId), {
        'pedido_id': widget.pedidoId,
        'cliente_id': user.uid,
        'loja_id': widget.lojaId,
        'nota': _notaLoja,
        'data': FieldValue.serverTimestamp(),
        if (comentarioLoja.isNotEmpty) 'comentario': comentarioLoja,
        if (nomeCliente.isNotEmpty) 'cliente_nome_exibicao': nomeCliente,
      });

      for (final p in _produtos) {
        if (p.nota < 1) continue;
        final comentarioProduto = p.comentario.text.trim();
        final docId = '${widget.pedidoId}_${p.produtoId}';
        batch.set(db.collection('avaliacoes_produto').doc(docId), {
          'pedido_id': widget.pedidoId,
          'produto_id': p.produtoId,
          'produto_nome': p.nome,
          'loja_id': widget.lojaId,
          'cliente_id': user.uid,
          'nota': p.nota,
          'data': FieldValue.serverTimestamp(),
          if (comentarioProduto.isNotEmpty) 'comentario': comentarioProduto,
          if (nomeCliente.isNotEmpty) 'cliente_nome_exibicao': nomeCliente,
        });
      }

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obrigado pela avaliação!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _estrelas({
    required int nota,
    required ValueChanged<int> onSelecionar,
    double size = 40,
    bool permiteZero = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final n = i + 1;
        final ativo = n <= nota;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          onPressed: _enviando
              ? null
              : () {
                  // Toque na mesma estrela "1" zera (opcional, p/ produtos).
                  if (permiteZero && nota == n && n == 1) {
                    onSelecionar(0);
                  } else {
                    onSelecionar(n);
                  }
                },
          icon: Icon(
            ativo ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: ativo ? Colors.amber.shade700 : Colors.grey.shade400,
          ),
        );
      }),
    );
  }

  Widget _cardProduto(_ItemProdutoAvaliacao p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: p.imagem.isNotEmpty
                    ? Image.network(
                        p.imagem,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholderProduto(),
                      )
                    : _placeholderProduto(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _estrelas(
            nota: p.nota,
            size: 30,
            permiteZero: true,
            onSelecionar: (n) => setState(() => p.nota = n),
          ),
          if (p.nota > 0) ...[
            const SizedBox(height: 6),
            TextField(
              controller: p.comentario,
              enabled: !_enviando,
              maxLines: 2,
              maxLength: 300,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: 'Comentário sobre este produto (opcional)',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeholderProduto() {
    return Container(
      width: 46,
      height: 46,
      color: const Color(0xFFEDEAF5),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Avaliar ${widget.lojaNome}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _roxo,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pedido ${CodigoPedido.gerar(widget.pedidoId)}',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nota para a loja',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _estrelas(
            nota: _notaLoja,
            onSelecionar: (n) => setState(() => _notaLoja = n),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentarioLoja,
            enabled: !_enviando,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Comentário sobre a loja (opcional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_carregandoItens)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _laranja,
                  ),
                ),
              ),
            )
          else if (_produtos.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Avaliar os produtos',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Toque nas estrelas dos produtos que você quer avaliar.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 12),
            ..._produtos.map(_cardProduto),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _enviando ? null : _enviar,
            style: FilledButton.styleFrom(
              backgroundColor: _laranja,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _enviando
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enviar avaliação'),
          ),
        ],
      ),
    );
  }
}
