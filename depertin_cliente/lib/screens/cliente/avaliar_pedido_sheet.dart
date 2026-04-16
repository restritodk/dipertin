import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Bottom sheet para avaliar pedido entregue (1 doc por pedido: avaliacoes/{pedidoId}).
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
  int _nota = 5;
  final TextEditingController _comentario = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
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

      final comentario = _comentario.text.trim();
      await FirebaseFirestore.instance
          .collection('avaliacoes')
          .doc(widget.pedidoId)
          .set({
            'pedido_id': widget.pedidoId,
            'cliente_id': user.uid,
            'loja_id': widget.lojaId,
            'nota': _nota,
            'data': FieldValue.serverTimestamp(),
            if (comentario.isNotEmpty) 'comentario': comentario,
            if (nomeCliente.isNotEmpty) 'cliente_nome_exibicao': nomeCliente,
          });

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
            'Pedido #${widget.pedidoId.length > 8 ? widget.pedidoId.substring(widget.pedidoId.length - 8).toUpperCase() : widget.pedidoId.toUpperCase()}',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sua nota',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final n = i + 1;
              final ativo = n <= _nota;
              return IconButton(
                onPressed: _enviando ? null : () => setState(() => _nota = n),
                icon: Icon(
                  ativo ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 40,
                  color: ativo ? Colors.amber.shade700 : Colors.grey.shade400,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentario,
            enabled: !_enviando,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Comentário (opcional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
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
