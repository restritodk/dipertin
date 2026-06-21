import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);

/// Exige login antes de finalizar pedido (pronta-entrega ou encomenda).
///
/// Retorna `true` se já estava logado ou se autenticou e voltou ao carrinho.
/// O carrinho em [CartProvider] / SharedPreferences não é alterado aqui.
Future<bool> garantirClienteLogadoParaCheckout(
  BuildContext context, {
  String titulo = 'Login necessário',
  String mensagem = 'Para finalizar seu pedido, faça login na sua conta.',
}) async {
  if (FirebaseAuth.instance.currentUser != null) return true;

  final irLogin = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: _diPertinRoxo, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _diPertinRoxo,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        mensagem,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          color: Color(0xFF424242),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Cancelar',
            style: TextStyle(
              color: _diPertinRoxo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: _diPertinLaranja,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Fazer login',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  if (irLogin != true || !context.mounted) return false;

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
  );

  if (!context.mounted) return false;
  return FirebaseAuth.instance.currentUser != null;
}
