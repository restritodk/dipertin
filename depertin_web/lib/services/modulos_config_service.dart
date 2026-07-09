import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/modulo_config_model.dart';

/// CRUD da coleção `assinaturas_modulos` — módulos configuráveis.
abstract final class ModulosConfigService {
  static const String _colecao = 'assinaturas_modulos';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> stream() {
    return _db
        .collection(_colecao)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  static Future<String> criar({
    required String nome,
    required String codigo,
    String descricao = '',
    bool ativo = true,
    bool contratavel = true,
    String icone = 'widgets',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = _db.collection(_colecao).doc();
    final model = ModuloConfigModel(
      id: ref.id,
      nome: nome,
      codigo: codigo,
      descricao: descricao,
      ativo: ativo,
      contratavel: contratavel,
      icone: icone,
      createdBy: uid,
    );
    await ref.set(model.toMap());
    return ref.id;
  }

  static Future<void> atualizar({
    required String id,
    String? nome,
    String? codigo,
    String? descricao,
    bool? ativo,
    bool? contratavel,
    String? icone,
  }) async {
    final data = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (nome != null) data['nome'] = nome;
    if (codigo != null) data['codigo'] = codigo;
    if (descricao != null) data['descricao'] = descricao;
    if (ativo != null) data['ativo'] = ativo;
    if (contratavel != null) data['contratavel'] = contratavel;
    if (icone != null) data['icone'] = icone;
    await _db.collection(_colecao).doc(id).update(data);
  }

  static Future<void> toggleAtivo(String id, bool ativo) async {
    await _db.collection(_colecao).doc(id).update({
      'ativo': ativo,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> excluir(String id) async {
    await _db.collection(_colecao).doc(id).delete();
  }

  static Future<int> contarAtivos() async {
    final snap = await _db
        .collection(_colecao)
        .where('ativo', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
