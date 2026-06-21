import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/cliente/product_details_screen.dart';

const Color _roxo = Color(0xFF6A1B9A);

/// Busca um produto por ID, valida se existe/está ativo e abre a tela de
/// detalhes. Caso contrário, exibe uma mensagem amigável.
///
/// Usado pelos deep links (link compartilhado do produto).
Future<void> abrirProdutoPorId(
  BuildContext context,
  String produtoId, {
  bool mostrarCarregando = true,
}) async {
  final id = produtoId.trim();
  if (id.isEmpty) {
    _avisarIndisponivel(context);
    return;
  }

  if (mostrarCarregando) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _roxo),
      ),
    );
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection('produtos')
        .doc(id)
        .get();

    if (mostrarCarregando && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    final dados = doc.data();
    final ativo = dados?['ativo'];
    final indisponivel = !doc.exists || dados == null || ativo == false;
    if (indisponivel) {
      _avisarIndisponivel(context);
      return;
    }

    final produto = Map<String, dynamic>.from(dados);
    produto['id_documento'] = doc.id;

    // Enriquece com o nome público da loja (best-effort).
    final lojaId =
        (produto['lojista_id'] ?? produto['loja_id'] ?? '').toString().trim();
    if (lojaId.isNotEmpty &&
        (produto['loja_nome_vitrine'] == null ||
            produto['loja_nome_vitrine'].toString().trim().isEmpty)) {
      try {
        final loja = await FirebaseFirestore.instance
            .collection('lojas_public')
            .doc(lojaId)
            .get();
        final ld = loja.data();
        if (ld != null) {
          produto['loja_nome_vitrine'] =
              ld['nome_fantasia'] ?? ld['nome'] ?? ld['loja_nome'] ?? '';
        }
      } catch (_) {
        // segue sem o nome da loja
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(produto: produto),
      ),
    );
  } catch (_) {
    if (mostrarCarregando && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) _avisarIndisponivel(context);
  }
}

void _avisarIndisponivel(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.shopping_bag_outlined, color: _roxo, size: 36),
      title: const Text(
        'Produto indisponível',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: const Text(
        'Este produto não está mais disponível.',
        textAlign: TextAlign.center,
      ),
      actions: [
        Center(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _roxo),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ),
      ],
    ),
  );
}
