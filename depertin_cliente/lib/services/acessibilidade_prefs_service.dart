// Arquivo: lib/services/acessibilidade_prefs_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status auditivo persistido em `users/{uid}.acessibilidade.audicao`.
enum StatusAuditivo { surdo, deficiencia, normal }

extension StatusAuditivoX on StatusAuditivo {
  String get codigo {
    switch (this) {
      case StatusAuditivo.surdo:
        return 'surdo';
      case StatusAuditivo.deficiencia:
        return 'deficiencia';
      case StatusAuditivo.normal:
        return 'normal';
    }
  }

  String get rotulo {
    switch (this) {
      case StatusAuditivo.surdo:
        return 'Eu sou surdo';
      case StatusAuditivo.deficiencia:
        return 'Tenho deficiência auditiva';
      case StatusAuditivo.normal:
        return 'Não sou surdo ou deficiente auditivo';
    }
  }

  static StatusAuditivo fromCodigo(String? codigo) {
    switch ((codigo ?? '').toLowerCase().trim()) {
      case 'surdo':
        return StatusAuditivo.surdo;
      case 'deficiencia':
      case 'deficiência':
        return StatusAuditivo.deficiencia;
      default:
        return StatusAuditivo.normal;
    }
  }

  /// Se true, exibimos badge "Entregador com limitação auditiva" nos pedidos
  /// do cliente e do lojista e orientamos a priorizar chat.
  bool get temLimitacao =>
      this == StatusAuditivo.surdo || this == StatusAuditivo.deficiencia;
}

/// Leitura/escrita das preferências de acessibilidade do entregador.
///
/// Estratégia:
/// - Persistência canônica: Firestore (`users/{uid}` campos `acessibilidade.*` e `config.*`).
/// - Cache local em SharedPreferences para leitura rápida em lugares "quentes"
///   (ex.: alerta de nova corrida) sem depender da rede.
class AcessibilidadePrefsService {
  static const _kAudicao = 'acessibilidade_audicao';
  static const _kVibracao = 'config_vibracao';
  static const _kFlash = 'config_flash';

  AcessibilidadePrefsService._();

  static final AcessibilidadePrefsService instance =
      AcessibilidadePrefsService._();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? _docUser() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Lê o Firestore, atualiza o cache local e retorna os valores atuais.
  Future<AcessibilidadeSnapshot> carregarESincronizar() async {
    final doc = _docUser();
    if (doc == null) return _lerCacheLocal();
    try {
      final snap = await doc.get();
      final d = snap.data() ?? <String, dynamic>{};
      final ac = d['acessibilidade'] is Map ? d['acessibilidade'] as Map : {};
      final cfg = d['config'] is Map ? d['config'] as Map : {};
      final audicao = StatusAuditivoX.fromCodigo(ac['audicao']?.toString());
      final vibracao = (cfg['vibracao'] == true);
      final flash = (cfg['flash'] == true);
      await _salvarCacheLocal(
        audicao: audicao,
        vibracao: vibracao,
        flash: flash,
      );
      return AcessibilidadeSnapshot(
        audicao: audicao,
        vibracao: vibracao,
        flash: flash,
      );
    } catch (e) {
      debugPrint('[AcessibilidadePrefs] erro carregar: $e');
      return _lerCacheLocal();
    }
  }

  /// Leitura rápida, somente cache local. Use em caminhos quentes.
  Future<AcessibilidadeSnapshot> lerCacheLocal() => _lerCacheLocal();

  Future<AcessibilidadeSnapshot> _lerCacheLocal() async {
    final sp = await SharedPreferences.getInstance();
    return AcessibilidadeSnapshot(
      audicao: StatusAuditivoX.fromCodigo(sp.getString(_kAudicao)),
      vibracao: sp.getBool(_kVibracao) ?? false,
      flash: sp.getBool(_kFlash) ?? false,
    );
  }

  Future<void> _salvarCacheLocal({
    required StatusAuditivo audicao,
    required bool vibracao,
    required bool flash,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAudicao, audicao.codigo);
    await sp.setBool(_kVibracao, vibracao);
    await sp.setBool(_kFlash, flash);
  }

  Future<void> definirAudicao(StatusAuditivo status) async {
    final doc = _docUser();
    if (doc == null) return;
    await doc.set({
      'acessibilidade': {'audicao': status.codigo},
    }, SetOptions(merge: true));
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAudicao, status.codigo);
  }

  Future<void> definirVibracao(bool ativa) async {
    final doc = _docUser();
    if (doc == null) return;
    await doc.set({
      'config': {'vibracao': ativa},
    }, SetOptions(merge: true));
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kVibracao, ativa);
  }

  Future<void> definirFlash(bool ativo) async {
    final doc = _docUser();
    if (doc == null) return;
    await doc.set({
      'config': {'flash': ativo},
    }, SetOptions(merge: true));
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kFlash, ativo);
  }
}

class AcessibilidadeSnapshot {
  final StatusAuditivo audicao;
  final bool vibracao;
  final bool flash;

  const AcessibilidadeSnapshot({
    required this.audicao,
    required this.vibracao,
    required this.flash,
  });
}
