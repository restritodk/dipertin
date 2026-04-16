import 'package:flutter/material.dart';

/// Mesma ordem que o login do painel: `role` tem prioridade sobre `tipoUsuario`.
String perfilAdministrativo(Map<String, dynamic> dados) {
  return (dados['role'] ?? dados['tipo'] ?? dados['tipoUsuario'] ?? 'cliente')
      .toString()
      .trim()
      .toLowerCase();
}

/// Escolhe o **maior privilégio** entre `role`, `tipo` e `tipoUsuario`.
/// Evita doc com `role` legado `cliente` e `tipoUsuario` `master` sem menus do painel.
String perfilAdministrativoPainel(Map<String, dynamic> dados) {
  const ordemPrivilegio = <String>[
    'master',
    'superadmin',
    'super_admin',
    'master_city',
    'lojista',
  ];
  var melhorIdx = ordemPrivilegio.length;
  String? melhor;

  void considerar(dynamic raw) {
    if (raw == null) return;
    final p = raw.toString().trim().toLowerCase();
    final i = ordemPrivilegio.indexOf(p);
    if (i < 0) return;
    if (i < melhorIdx) {
      melhorIdx = i;
      melhor = p;
    }
  }

  considerar(dados['role']);
  considerar(dados['tipo']);
  considerar(dados['tipoUsuario']);

  if (melhor != null) return melhor!;
  return perfilAdministrativo(dados);
}

bool perfilPodeGestaoLojasEntregadoresBanners(String perfil) {
  final p = perfil.trim().toLowerCase();
  return p == 'master' ||
      p == 'master_city' ||
      p == 'superadmin' ||
      p == 'super_admin';
}

bool perfilPodeMenuChefe(String perfil) {
  final p = perfil.trim().toLowerCase();
  return p == 'master' || p == 'superadmin' || p == 'super_admin';
}

/// Fila de saques PIX — mesmo critério que [perfilPodeMenuChefe] (não inclui `master_city`).
bool perfilPodeVerSolicitacoesSaque(String perfil) {
  return perfilPodeMenuChefe(perfil);
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
