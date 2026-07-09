import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lojista_integracao_model.dart';
import '../models/plano_emissao_nfe_model.dart';

/// Serviço para gerenciar integrações de NF-e de lojistas.
abstract final class LojistaIntegracaoService {
  static const String _colecao = 'lojista_integracao';
  static const String _colecaoPlanos = 'planos_emissao_nfe';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Planos de emissão NF-e ──────────────────────────────

  static Stream<List<PlanoEmissaoNfeModel>> streamPlanos() {
    return _db
        .collection(_colecaoPlanos)
        .orderBy('ordem', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map(PlanoEmissaoNfeModel.fromFirestore).toList());
  }

  static Future<List<PlanoEmissaoNfeModel>> listarPlanosAtivos() async {
    final snap = await _db
        .collection(_colecaoPlanos)
        .where('ativo', isEqualTo: true)
        .orderBy('ordem', descending: false)
        .get();
    return snap.docs.map(PlanoEmissaoNfeModel.fromFirestore).toList();
  }

  static Future<void> salvarPlano(PlanoEmissaoNfeModel model) async {
    final ref = _db.collection(_colecaoPlanos).doc();
    await ref.set(model.toMap());
  }

  static Future<void> atualizarPlano(
      String id, PlanoEmissaoNfeModel model) async {
    await _db.collection(_colecaoPlanos).doc(id).update(model.toUpdateMap());
  }

  // ─── Integrações de lojistas ─────────────────────────────

  static Stream<List<LojistaIntegracaoModel>> streamIntegracoes() {
    return _db
        .collection(_colecao)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(LojistaIntegracaoModel.fromFirestore).toList());
  }

  static Stream<LojistaIntegracaoModel?> streamIntegracaoPorStore(
      String storeId) {
    return _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isNotEmpty
                ? LojistaIntegracaoModel.fromFirestore(snap.docs.first)
                : null);
  }

  static Future<LojistaIntegracaoModel?> buscarIntegracaoPorStore(
      String storeId) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty
        ? LojistaIntegracaoModel.fromFirestore(snap.docs.first)
        : null;
  }

  static Future<void> criarIntegracao(LojistaIntegracaoModel model) async {
    final ref = _db.collection(_colecao).doc();
    await ref.set(model.toCreateMap());
  }

  static Future<void> atualizarIntegracao(
      String id, Map<String, dynamic> dados) async {
    dados['updated_at'] = FieldValue.serverTimestamp();
    await _db.collection(_colecao).doc(id).update(dados);
  }

  static Future<void> suspenderIntegracao(String id) async {
    await _db.collection(_colecao).doc(id).update({
      'status': 'suspensa',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> reativarIntegracao(String id) async {
    await _db.collection(_colecao).doc(id).update({
      'status': 'ativa',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> alterarPlano(
      String id, String planoId, String planoNome, int limiteMensal) async {
    await _db.collection(_colecao).doc(id).update({
      'plano_id': planoId,
      'plano_nome': planoNome,
      'limite_mensal': limiteMensal,
      'notas_restantes': limiteMensal,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> excluirIntegracao(String id) async {
    await _db.collection(_colecao).doc(id).delete();
  }

  /// Incrementa o contador de notas emitidas de um lojista.
  ///
  /// [storeId] é o ID da loja (`store_id` no documento), não o ID do documento.
  /// O método faz o lookup interno pelo campo `store_id`.
  static Future<void> registrarEmissao(String storeId) async {
    final snap = await _db
        .collection(_colecao)
        .where('store_id', isEqualTo: storeId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;
    final doc = snap.docs.first;
    final model = LojistaIntegracaoModel.fromFirestore(doc);
    final emitidas = model.notasEmitidas + 1;
    await _db.collection(_colecao).doc(doc.id).update({
      'notas_emitidas': emitidas,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
