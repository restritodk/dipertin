import 'package:flutter/material.dart';

/// Mesma ordem que o login do painel: `role` tem prioridade sobre `tipoUsuario`.
String perfilAdministrativo(Map<String, dynamic> dados) {
  return (dados['role'] ?? dados['tipo'] ?? dados['tipoUsuario'] ?? 'cliente')
      .toString()
      .toLowerCase();
}

bool perfilPodeGestaoLojasEntregadoresBanners(String perfil) {
  return perfil == 'master' || perfil == 'master_city';
}

bool perfilPodeMenuChefe(String perfil) {
  return perfil == 'master';
}

/// Após await, mostra SnackBar de forma mais segura no Flutter Web.
void mostrarSnackPainel(
  BuildContext context, {
  required String mensagem,
  bool erro = false,
}) {
  if (!context.mounted) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  });
}
