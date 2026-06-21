import 'package:flutter/material.dart';

import '../screens/cliente/cart_screen.dart';

/// Evita empilhar duas [CartScreen] em toques rápidos; libera após o push
/// entrar na pilha (não espera o usuário fechar o carrinho).
bool _abrindoCarrinho = false;

Future<void> abrirCarrinho(BuildContext context) {
  if (_abrindoCarrinho || !context.mounted) return Future.value();

  _abrindoCarrinho = true;
  final future = Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const CartScreen()),
  );

  Future<void>.delayed(const Duration(milliseconds: 450), () {
    _abrindoCarrinho = false;
  });

  return future;
}
