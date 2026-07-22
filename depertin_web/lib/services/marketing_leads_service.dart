import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_functions_config.dart';

/// CRUD dos leads de marketing (lojistas e entregadores) + histórico de contato
/// e auditoria. Escrita liberada apenas a staff pelas Firestore rules.
abstract final class MarketingLeadsService {
  static const String colecaoLojistas = 'marketing_leads_lojistas';
  static const String colecaoEntregadores = 'marketing_leads_entregadores';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream da lista (ordenada pela última atualização).
  ///
  /// Quando [cidade] é informado, aplica filtro server-side usando o índice
  /// composto `(cidade ASC, atualizado_em DESC)`. Caso contrário, carrega os
  /// últimos 2000 registros sem filtro (compatível com o índice `atualizado_em DESC`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(
    String colecao, {
    String? cidade,
  }) {
    var query = _db.collection(colecao) as Query<Map<String, dynamic>>;
    if (cidade != null && cidade.isNotEmpty) {
      query = query.where('cidade', isEqualTo: cidade);
    }
    return query
        .orderBy('atualizado_em', descending: true)
        .limit(2000)
        .snapshots();
  }

  /// Cria (id nulo) ou atualiza um lead. Retorna o id do documento.
  static Future<String> salvar({
    required String colecao,
    String? id,
    required Map<String, dynamic> dados,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final agora = FieldValue.serverTimestamp();
    final payload = <String, dynamic>{
      ...dados,
      'atualizado_em': agora,
      'atualizado_por': uid,
    };

    if (id == null || id.isEmpty) {
      payload['criado_em'] = agora;
      payload['criado_por'] = uid;
      final ref = await _db.collection(colecao).add(payload);
      await _auditar(
        evento: 'marketing_lead_criado',
        colecao: colecao,
        leadId: ref.id,
        detalhe: {'nome': dados['nome'] ?? dados['nome_fantasia'] ?? ''},
      );
      return ref.id;
    }

    await _db.collection(colecao).doc(id).set(payload, SetOptions(merge: true));
    await _auditar(
      evento: 'marketing_lead_atualizado',
      colecao: colecao,
      leadId: id,
      detalhe: {
        'status': dados['status'] ?? '',
      },
    );
    return id;
  }

  /// Exclui um lead (e os filhos diretos do histórico em lote).
  static Future<void> excluir({
    required String colecao,
    required String id,
    String? nomeParaLog,
  }) async {
    final ref = _db.collection(colecao).doc(id);
    final hist = await ref.collection('historico').limit(400).get();
    if (hist.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final d in hist.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await ref.delete();
    await _auditar(
      evento: 'marketing_lead_excluido',
      colecao: colecao,
      leadId: id,
      detalhe: {'nome': nomeParaLog ?? ''},
    );
  }

  /// Histórico de contato do lead (subcoleção `historico`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamHistorico({
    required String colecao,
    required String leadId,
  }) {
    return _db
        .collection(colecao)
        .doc(leadId)
        .collection('historico')
        .orderBy('criado_em', descending: true)
        .limit(100)
        .snapshots();
  }

  static Future<void> adicionarHistorico({
    required String colecao,
    required String leadId,
    required String texto,
    String tipo = 'nota',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = FirebaseAuth.instance.currentUser?.email;
    final ref = _db.collection(colecao).doc(leadId);
    await ref.collection('historico').add({
      'texto': texto.trim(),
      'tipo': tipo,
      'autor_uid': uid,
      'autor_email': email,
      'criado_em': FieldValue.serverTimestamp(),
    });
    await ref.set({
      'atualizado_em': FieldValue.serverTimestamp(),
      'atualizado_por': uid,
    }, SetOptions(merge: true));
  }

  static Future<void> _auditar({
    required String evento,
    required String colecao,
    required String leadId,
    Map<String, dynamic>? detalhe,
  }) async {
    try {
      await callFirebaseFunctionSafe(
        'registrarEventoAuditoriaApp',
        timeout: const Duration(seconds: 12),
        parameters: <String, dynamic>{
          'evento': evento,
          'categoria': 'marketing',
          'plataforma': 'painel_web',
          'detalhe': <String, dynamic>{
            'colecao': colecao,
            'lead_id': leadId,
            ...?detalhe,
          },
        },
      );
    } catch (_) {
      // Auditoria é best-effort; nunca bloqueia a operação principal.
    }
  }
}
