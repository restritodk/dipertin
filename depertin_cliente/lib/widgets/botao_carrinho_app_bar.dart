import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../utils/abrir_carrinho.dart';

const Color _diPertinLaranja = Color(0xFFFF8F00);

/// Ícone de sacola com contador — área de toque única (sem badge bloqueando o tap).
class BotaoCarrinhoAppBar extends StatelessWidget {
  const BotaoCarrinhoAppBar({
    super.key,
    this.iconColor = Colors.white,
    this.buttonStyle,
    this.tooltip = 'Abrir carrinho',
  });

  final Color iconColor;
  final ButtonStyle? buttonStyle;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CartProvider>().itemCount;
    final label = count > 99 ? '99+' : '$count';

    return IconButton(
      tooltip: tooltip,
      style: buttonStyle,
      onPressed: () => abrirCarrinho(context),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: _diPertinLaranja,
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Icon(Icons.shopping_cart, color: iconColor),
      ),
    );
  }
}
