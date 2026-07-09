import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/cliente_assinatura_model.dart';
import 'firebase_functions_config.dart';

/// CRUD da coleção `assinaturas_clientes` — assinaturas contratadas por lojistas.
/// Documentos são criados pelo fluxo do lojista (contratação); o painel admin
/// apenas lista, bloqueia módulos e registra cobranças/histórico.
abstract final class AssinaturasClientesService {
  static const String colecao = 'assinaturas_clientes';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stream em tempo real, mais recentes primeiro.
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream() {
    return _db
        .collection(colecao)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Usado pelo fluxo do lojista ao contratar um plano (não pelo painel admin).
  static Future<String> criarPorContratacaoLojista({
    required ClienteAssinaturaModel assinatura,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = _db.collection(colecao).doc();
    await ref.set(assinatura.toMap(createdBy: uid));
    return ref.id;
  }

  /// Suspende apenas os módulos contratados (status → suspenso).
  static Future<void> bloquearModulos({
    required String id,
    String? motivo,
    bool enviarNotificacao = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final descricao = (motivo != null && motivo.trim().isNotEmpty)
        ? motivo.trim()
        : 'Módulos bloqueados pelo administrador';

    await _db.collection(colecao).doc(id).update({
      'status': 'suspenso',
      'blocked_at': FieldValue.serverTimestamp(),
      'block_reason': descricao,
      'updated_at': FieldValue.serverTimestamp(),
      'historico': FieldValue.arrayUnion([
        {
          'tipo': 'bloqueio',
          'descricao': descricao,
          'data_em': Timestamp.now(),
          if (uid != null) 'por_uid': uid,
          if (enviarNotificacao) 'notificacao_solicitada': true,
        },
      ]),
    });
  }

  /// Reativa os módulos contratados (status → ativo).
  static Future<void> desbloquearModulos({
    required String id,
    String? observacao,
    bool enviarNotificacao = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final descricao = (observacao != null && observacao.trim().isNotEmpty)
        ? observacao.trim()
        : 'Módulos reativados pelo administrador';

    await _db.collection(colecao).doc(id).update({
      'status': 'ativo',
      'blocked_at': FieldValue.delete(),
      'block_reason': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
      'historico': FieldValue.arrayUnion([
        {
          'tipo': 'desbloqueio',
          'descricao': descricao,
          'data_em': Timestamp.now(),
          if (uid != null) 'por_uid': uid,
          if (enviarNotificacao) 'notificacao_solicitada': true,
        },
      ]),
    });
  }

  /// Cancela plano via callable admin (Firestore + e-mail ao lojista).
  static Future<CancelarPlanoAssinaturaResultado> cancelarPlano({
    required String id,
    required String motivoCodigo,
    String? motivoOutroTexto,
    String? observacaoInterna,
  }) async {
    final resp = await callFirebaseFunctionSafe(
      'adminCancelarPlanoAssinatura',
      parameters: {
        'assinaturaId': id,
        'motivoCodigo': motivoCodigo,
        if (motivoOutroTexto != null && motivoOutroTexto.trim().isNotEmpty)
          'motivoOutroTexto': motivoOutroTexto.trim(),
        if (observacaoInterna != null && observacaoInterna.trim().isNotEmpty)
          'observacaoInterna': observacaoInterna.trim(),
      },
    );

    return CancelarPlanoAssinaturaResultado(
      emailEnviado: resp['emailEnviado'] == true,
      emailErro: resp['emailErro'] as String?,
    );
  }

  /// Registra envio de cobrança no histórico (sem integração de pagamento real).
  static Future<void> registrarCobrancaEnviada({
    required String id,
    required String canal,
    String? mensagem,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final canalLabel = switch (canal) {
      'email' => 'E-mail',
      'whatsapp' => 'WhatsApp',
      'link' => 'Link de pagamento',
      _ => canal,
    };

    await _db.collection(colecao).doc(id).update({
      'updated_at': FieldValue.serverTimestamp(),
      'historico': FieldValue.arrayUnion([
        {
          'tipo': 'cobranca',
          'descricao': 'Cobrança enviada via $canalLabel',
          'data_em': Timestamp.now(),
          if (uid != null) 'por_uid': uid,
          if (mensagem != null && mensagem.trim().isNotEmpty)
            'mensagem': mensagem.trim(),
        },
      ]),
    });
  }
}

class CancelarPlanoAssinaturaResultado {
  const CancelarPlanoAssinaturaResultado({
    required this.emailEnviado,
    this.emailErro,
  });

  final bool emailEnviado;
  final String? emailErro;
}
