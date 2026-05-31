// Entrada do painel: modal de escolha + formulários separados (loja × cliente).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'lojista_editar_cliente_admin_dialog.dart';
import 'lojista_editar_loja_admin_dialog.dart';
import 'lojista_escolher_edicao_dialog.dart';

export 'lojista_editar_cliente_admin_dialog.dart' show updateClientePerfilAdmin;
export 'lojista_editar_loja_admin_dialog.dart' show updateLojaConfiguracoesAdmin;
export 'lojista_escolher_edicao_dialog.dart' show LojistaEdicaoTipo;

/// Abre o modal de escolha e, em seguida, o formulário correto (loja ou cliente).
/// Retorna `true` se algum formulário salvou com sucesso.
Future<bool?> showLojistaEditarDialog(
  BuildContext context, {
  required String lojistaId,
}) async {
  String? tituloLoja;
  String? nomePessoa;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(lojistaId)
        .get();
    if (snap.exists) {
      final d = snap.data() ?? {};
      final ln = (d['loja_nome'] ?? d['nome_loja'] ?? '').toString().trim();
      if (ln.isNotEmpty) tituloLoja = ln;
      final np = (d['nome'] ?? d['nome_completo'] ?? '').toString().trim();
      if (np.isNotEmpty) nomePessoa = np;
    }
  } catch (_) {}

  if (!context.mounted) return null;

  final escolha = await showLojistaEscolherEdicaoDialog(
    context,
    tituloLoja: tituloLoja,
    subtituloPessoa: nomePessoa,
  );
  if (escolha == null || !context.mounted) return null;

  switch (escolha) {
    case LojistaEdicaoTipo.loja:
      return showLojistaEditarLojaAdminDialog(context, lojistaId: lojistaId);
    case LojistaEdicaoTipo.cliente:
      return showLojistaEditarClienteAdminDialog(context, lojistaId: lojistaId);
  }
}
