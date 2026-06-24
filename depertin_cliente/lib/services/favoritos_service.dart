// Arquivo: lib/services/favoritos_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Gerencia os favoritos do usuário em `users/{uid}/favoritos/{produtoId}`.
class FavoritosService {
  FavoritosService._();
  static final FavoritosService instance = FavoritosService._();

  CollectionReference _ref(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('favoritos');

  /// Adiciona ou remove um produto dos favoritos.
  /// Retorna `true` se passou a ser favorito, `false` se foi removido.
  Future<bool> toggle(String uid, String produtoId, Map<String, dynamic> produtoData) async {
    final ref = _ref(uid).doc(produtoId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    } else {
      await ref.set({
        ...produtoData,
        'favoritado_em': FieldValue.serverTimestamp(),
      });
      return true;
    }
  }

  /// Verifica se um produto é favorito.
  Future<bool> isFavorito(String uid, String produtoId) async {
    final snap = await _ref(uid).doc(produtoId).get();
    return snap.exists;
  }

  /// Retorna a lista de favoritos como uma Future (get único).
  Future<QuerySnapshot> listar(String uid) {
    return _ref(uid).get();
  }

  /// Remove um produto dos favoritos.
  Future<void> remover(String uid, String produtoId) async {
    await _ref(uid).doc(produtoId).delete();
  }
}
