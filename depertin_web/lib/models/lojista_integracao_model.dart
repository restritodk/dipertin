import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Integração de NF-e de um lojista, vinculada a um plano de emissão.
///
/// Coleção Firestore: `lojista_integracao/{id}`
class LojistaIntegracaoModel {
  final String id;
  final String storeId;
  final String storeNome;
  final String? storeEmail;
  final String planoId;
  final String planoNome;
  final int limiteMensal;
  final int notasEmitidas;
  final int notasRestantes;
  final double percentualUtilizado;
  final String cicloRef; // "2026-07"
  final Timestamp? proximaRenovacao;
  final String status; // ativa | suspensa | bloqueada
  final String? observacao;
  final String? createdBy;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  LojistaIntegracaoModel({
    required this.id,
    required this.storeId,
    required this.storeNome,
    this.storeEmail,
    required this.planoId,
    required this.planoNome,
    this.limiteMensal = 0,
    this.notasEmitidas = 0,
    this.notasRestantes = 0,
    this.percentualUtilizado = 0,
    required this.cicloRef,
    this.proximaRenovacao,
    this.status = 'ativa',
    this.observacao,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get estaAtiva => status == 'ativa';
  bool get estaSuspensa => status == 'suspensa';
  bool get estaBloqueada => status == 'bloqueada';
  bool get atingiuLimite => limiteMensal > 0 && notasEmitidas >= limiteMensal;
  bool get ehIlimitado => limiteMensal == 0;

  String get limiteExibir => ehIlimitado ? 'Ilimitado' : limiteMensal.toString();
  String get emitidasExibir => notasEmitidas.toString();
  String get restantesExibir => ehIlimitado ? '∞' : (limiteMensal - notasEmitidas).toString();

  Color get statusCor => switch (status) {
        'ativa' => const Color(0xFF16A34A),
        'suspensa' => const Color(0xFFEA580C),
        'bloqueada' => const Color(0xFFDC2626),
        _ => const Color(0xFF9CA3AF),
      };

  Color get statusFundo => switch (status) {
        'ativa' => const Color(0xFFE8F5E9),
        'suspensa' => const Color(0xFFFFF8E1),
        'bloqueada' => const Color(0xFFFEF2F2),
        _ => const Color(0xFFF3F4F6),
      };

  String get statusLabel => switch (status) {
        'ativa' => 'Ativa',
        'suspensa' => 'Suspensa',
        'bloqueada' => 'Bloqueada',
        _ => '—',
      };

  static LojistaIntegracaoModel fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final limite = (d['limite_mensal'] as num?)?.toInt() ?? 0;
    final emitidas = (d['notas_emitidas'] as num?)?.toInt() ?? 0;
    return LojistaIntegracaoModel(
      id: doc.id,
      storeId: d['store_id'] as String? ?? '',
      storeNome: d['store_nome'] as String? ?? '',
      storeEmail: d['store_email'] as String?,
      planoId: d['plano_id'] as String? ?? '',
      planoNome: d['plano_nome'] as String? ?? '',
      limiteMensal: limite,
      notasEmitidas: emitidas,
      notasRestantes: limite > 0 ? (limite - emitidas).clamp(0, limite) : 0,
      percentualUtilizado: limite > 0
          ? ((emitidas / limite) * 100).clamp(0, 100)
          : 0,
      cicloRef: d['ciclo_ref'] as String? ?? '',
      proximaRenovacao: d['proxima_renovacao'] as Timestamp?,
      status: d['status'] as String? ?? 'ativa',
      observacao: d['observacao'] as String?,
      createdBy: d['created_by'] as String?,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'store_id': storeId,
        'store_nome': storeNome,
        'store_email': storeEmail,
        'plano_id': planoId,
        'plano_nome': planoNome,
        'limite_mensal': limiteMensal,
        'notas_emitidas': notasEmitidas,
        'ciclo_ref': cicloRef,
        'proxima_renovacao': proximaRenovacao,
        'status': status,
        'observacao': observacao,
        'created_by': createdBy,
        'updated_at': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
}
