import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Histórico local das notificações push recebidas pelo usuário.
///
/// Este serviço funciona **paralelamente** ao pipeline de FCM atual:
/// o app continua recebendo/rotando push exatamente como antes. Este
/// serviço apenas grava uma cópia do payload em
/// `notificacoes_usuario/{uid}/items/{autoId}` para alimentar a tela
/// "Minhas notificações" (badge + lista + marcar como lida).
class NotificacoesHistoricoService {
  NotificacoesHistoricoService._();

  static const String _rootCollection = 'notificacoes_usuario';
  static const String _itemsSub = 'items';

  /// Fontes de origem do push (para idempotência).
  static const String origemOnMessage = 'on_message';
  static const String origemOnOpen = 'on_opened';
  static const String origemInitial = 'initial';
  static const String origemLocal = 'local';

  static CollectionReference<Map<String, dynamic>> _itemsRef(String uid) =>
      FirebaseFirestore.instance
          .collection(_rootCollection)
          .doc(uid)
          .collection(_itemsSub);

  /// Persiste uma notificação recebida via FCM para o usuário logado.
  ///
  /// [origem] identifica o pipeline que disparou (apenas para logs).
  /// Falhas são silenciadas — esta gravação nunca deve quebrar o fluxo de push.
  static Future<void> salvarDePush(
    RemoteMessage message, {
    String origem = origemOnMessage,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;

      final dados = <String, dynamic>{};
      message.data.forEach((k, v) {
        if (v == null) return;
        dados[k] = v.toString();
      });

      final titulo = (message.notification?.title ?? dados['title'] ?? '')
          .toString()
          .trim();
      final corpo = (message.notification?.body ?? dados['body'] ?? '')
          .toString()
          .trim();

      // Evita gravar payloads vazios (keepalive/topics sem mensagem visual).
      if (titulo.isEmpty && corpo.isEmpty) return;

      final tipoNotificacao = (dados['tipoNotificacao'] ?? dados['type'] ?? '')
          .toString()
          .trim();
      final segmento = (dados['segmento'] ?? '').toString().trim();

      // Idempotência best-effort: deduplica pelo id técnico do FCM, se houver.
      final fcmId = (message.messageId ?? '').trim();
      if (fcmId.isNotEmpty) {
        final jaExiste = await _itemsRef(uid)
            .where('fcm_message_id', isEqualTo: fcmId)
            .limit(1)
            .get();
        if (jaExiste.docs.isNotEmpty) return;
      }

      await _itemsRef(uid).add({
        'titulo': titulo,
        'corpo': corpo,
        'tipo_notificacao': tipoNotificacao,
        'segmento': segmento,
        'dados': dados,
        'fcm_message_id': fcmId,
        'origem': origem,
        'lida': false,
        'criado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NotificacoesHistoricoService] Falha ao salvar: $e');
      }
    }
  }

  /// Stream de quantidade de notificações **não lidas** do usuário atual.
  ///
  /// Se [segmentoFiltro] for informado, considera apenas as notificações com
  /// `segmento` vazio (genéricas/institucionais) ou igual ao segmento. Isso
  /// alinha o contador do sino ao filtro aplicado na tela "Minhas notificações"
  /// (que esconde, por exemplo, notificações de loja para um usuário cliente).
  static Stream<int> streamContagemNaoLidas({String? segmentoFiltro}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return Stream<int>.value(0);
    }
    final filtro = (segmentoFiltro ?? '').trim().toLowerCase();
    return _itemsRef(uid)
        .where('lida', isEqualTo: false)
        .snapshots()
        .map((s) {
      if (filtro.isEmpty) return s.docs.length;
      var total = 0;
      for (final d in s.docs) {
        final seg = (d.data()['segmento'] ?? '').toString().trim().toLowerCase();
        if (seg.isEmpty || seg == filtro) total++;
      }
      return total;
    });
  }

  /// Stream ordenada por data, do mais recente para o mais antigo.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamLista({
    int limite = 200,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const Stream.empty();
    }
    return _itemsRef(uid)
        .orderBy('criado_em', descending: true)
        .limit(limite)
        .snapshots();
  }

  /// Marca os IDs indicados como lidos.
  static Future<void> marcarComoLidas(Iterable<String> ids) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || ids.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final col = _itemsRef(uid);
    for (final id in ids) {
      batch.update(col.doc(id), {
        'lida': true,
        'lida_em': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NotificacoesHistoricoService] marcarComoLidas: $e');
      }
    }
  }

  /// Marca TODAS as notificações do usuário como lidas.
  static Future<void> marcarTodasComoLidas() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final naoLidas = await _itemsRef(uid)
        .where('lida', isEqualTo: false)
        .limit(500)
        .get();
    if (naoLidas.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in naoLidas.docs) {
      batch.update(d.reference, {
        'lida': true,
        'lida_em': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NotificacoesHistoricoService] marcarTodasComoLidas: $e');
      }
    }
  }

  /// Remove as notificações indicadas.
  ///
  /// Processa em lotes de até 400 operações por batch (Firestore aceita até
  /// 500, deixamos uma folga para operações implícitas). Retorna `true` se
  /// todas as operações foram confirmadas, `false` se houve qualquer erro.
  static Future<bool> deletar(Iterable<String> ids) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    final lista = ids.toSet().toList();
    if (lista.isEmpty) return true;

    final col = _itemsRef(uid);
    const tamanhoLote = 400;
    var sucessoTotal = true;
    for (var i = 0; i < lista.length; i += tamanhoLote) {
      final fim = (i + tamanhoLote < lista.length) ? i + tamanhoLote : lista.length;
      final chunk = lista.sublist(i, fim);
      final batch = FirebaseFirestore.instance.batch();
      for (final id in chunk) {
        batch.delete(col.doc(id));
      }
      try {
        await batch.commit();
      } catch (e) {
        sucessoTotal = false;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[NotificacoesHistoricoService] deletar chunk $i..$fim: $e');
        }
      }
    }
    return sucessoTotal;
  }
}
