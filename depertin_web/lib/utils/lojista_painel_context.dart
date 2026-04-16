import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../navigation/painel_routes.dart';
import '../theme/painel_admin_theme.dart';

/// ID da loja nos pedidos/produtos: dono do painel = [authUid];
/// colaborador = `users.lojista_owner_uid`.
String uidLojaEfetivo(Map<String, dynamic>? dadosUsuario, String authUid) {
  if (dadosUsuario == null) return authUid;
  final o = dadosUsuario['lojista_owner_uid']?.toString().trim();
  if (o != null && o.isNotEmpty) return o;
  return authUid;
}

/// Dono (sem `lojista_owner_uid`) = nível 3 implícito.
/// Colaborador: campo `painel_colaborador_nivel` 1–3.
int nivelAcessoPainelLojista(Map<String, dynamic> dadosUsuario) {
  final o = dadosUsuario['lojista_owner_uid']?.toString().trim();
  if (o == null || o.isEmpty) return 3;
  final n = dadosUsuario['painel_colaborador_nivel'];
  if (n is int) return n.clamp(1, 3);
  if (n is num) return n.toInt().clamp(1, 3);
  if (n is String) {
    final v = int.tryParse(n.trim());
    if (v != null) return v.clamp(1, 3);
  }
  return 1;
}

bool podeCadastrarColaboradoresPainel(Map<String, dynamic> dadosUsuario) {
  return nivelAcessoPainelLojista(dadosUsuario) >= 3;
}

/// Carteira, relatórios, configuração financeira e configurações da loja.
bool painelMostrarAreaCarteiraEConfig(Map<String, dynamic> dadosUsuario) {
  return nivelAcessoPainelLojista(dadosUsuario) >= 3;
}

bool painelMostrarMeusProdutos(Map<String, dynamic> dadosUsuario) {
  return nivelAcessoPainelLojista(dadosUsuario) >= 2;
}

/// Evita abas proibidas (URL direta ou estado antigo).
String sanearRotaPainelLojista(String route, int nivel) {
  if (nivel >= 3) return PainelRoutes.normalize(route);
  const carteiras = <String>[
    '/carteira_loja',
    '/carteira_financeiro',
    '/carteira_relatorio',
    '/carteira_configuracao',
  ];
  if (nivel >= 2) {
    if (route == '/configuracoes' ||
        route == '/configuracao_cadastro_acesso' ||
        carteiras.contains(route)) {
      return '/dashboard';
    }
    return PainelRoutes.normalize(route);
  }
  if (route == '/dashboard' || route == '/meus_pedidos') {
    return PainelRoutes.normalize(route);
  }
  return '/dashboard';
}

/// Stream do documento do usuário autenticado (para obter [uidLojaEfetivo]).
Stream<DocumentSnapshot<Map<String, dynamic>>> streamUsuarioPainel(
  String authUid,
) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(authUid)
      .snapshots();
}

/// Fornece [uidLoja] (dono da loja) para queries do painel lojista.
class LojistaUidLojaBuilder extends StatelessWidget {
  const LojistaUidLojaBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(
    BuildContext context,
    String authUid,
    String uidLoja,
    Map<String, dynamic>? dadosUsuario,
  ) builder;

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) {
      return const Scaffold(
        body: Center(child: Text('Não autenticado.')),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: streamUsuarioPainel(authUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }
        final d = snap.data?.data();
        final uidLoja = uidLojaEfetivo(d, authUid);
        return builder(context, authUid, uidLoja, d);
      },
    );
  }
}

Widget painelLojistaSemPermissaoScaffold({required String mensagem}) {
  return Scaffold(
    backgroundColor: PainelAdminTheme.fundoCanvas,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            mensagem,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ),
      ),
    ),
  );
}
