import 'package:firebase_auth/firebase_auth.dart';

/// UID efetivo da loja: dono = auth UID; colaborador = `lojista_owner_uid`.
String uidLojaEfetivo(Map<String, dynamic>? dadosUsuario) {
  final authUid = FirebaseAuth.instance.currentUser!.uid;
  if (dadosUsuario == null) return authUid;
  final o = dadosUsuario['lojista_owner_uid']?.toString().trim();
  if (o != null && o.isNotEmpty) return o;
  return authUid;
}

/// Dono (sem `lojista_owner_uid`) = nível 3 implícito.
/// Colaborador: campo `painel_colaborador_nivel` 1–3.
int nivelAcessoLojista(Map<String, dynamic> dadosUsuario) {
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

bool podeCadastrarProdutos(Map<String, dynamic> d) =>
    nivelAcessoLojista(d) >= 2;

bool podeAcessarConfigECarteira(Map<String, dynamic> d) =>
    nivelAcessoLojista(d) >= 3;
