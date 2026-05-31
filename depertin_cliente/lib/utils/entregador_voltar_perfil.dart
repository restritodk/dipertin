import 'package:flutter/material.dart';

/// Volta à [MainNavigator] na aba Perfil (índice 2), fechando o painel do entregador.
void voltarMeuPerfilAposAcaoEntregador(
  BuildContext context, {
  String? mensagemSnackBar,
}) {
  if (!context.mounted) return;
  final rootNav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);

  rootNav.popUntil((route) => route.isFirst);
  if (!context.mounted) return;

  rootNav.pushReplacementNamed('/home', arguments: 2);

  if (mensagemSnackBar != null && mensagemSnackBar.trim().isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(mensagemSnackBar)),
      );
    });
  }
}
