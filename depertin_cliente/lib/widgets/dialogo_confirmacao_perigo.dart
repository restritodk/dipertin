import 'package:flutter/material.dart';

const Color _roxo = Color(0xFF6A1B9A);

/// Modal Sim/Não — bloqueio ou exclusão do perfil de entregador.
Future<bool> mostrarDialogoConfirmacaoPerigo(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  required String rotuloConfirmar,
  bool destrutivo = false,
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        titulo,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      content: Text(
        mensagem,
        style: const TextStyle(height: 1.5, fontSize: 15),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Não, cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: destrutivo ? const Color(0xFFB91C1C) : _roxo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(rotuloConfirmar),
        ),
      ],
    ),
  );
  return resultado == true;
}
