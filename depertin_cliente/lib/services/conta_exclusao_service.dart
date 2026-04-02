import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/google_auth_helper.dart';
import '../providers/cart_provider.dart';

/// Estados de conta relacionados à exclusão (Firestore `status_conta`).
abstract class StatusConta {
  static const String ativa = 'ativa';
  static const String exclusaoPendente = 'exclusao_pendente';
  static const String elegivelExclusaoDefinitiva = 'elegivel_exclusao_definitiva';
  static const String excluidaDefinitiva = 'excluida_definitiva';
}

/// Campos em `users/{uid}` para soft delete com retenção de 30 dias.
abstract class CamposExclusaoConta {
  static const String statusConta = 'status_conta';
  static const String exclusaoSolicitada = 'exclusao_solicitada';
  static const String exclusaoSolicitadaEm = 'exclusao_solicitada_em';
  static const String exclusaoDefinitivaPrevistaEm = 'exclusao_definitiva_prevista_em';
  static const String exclusaoCanceladaPorReativacao = 'exclusao_cancelada_por_reativacao';
  static const String exclusaoUltimaReativacaoEm = 'exclusao_ultima_reativacao_em';
  static const String exclusaoElegivelDefinitivaEm = 'exclusao_elegivel_definitiva_em';
}

class ContaExclusaoService {
  ContaExclusaoService._();

  /// Mesma região do deploy (`firebase deploy`). Callable HTTP (1st gen) — evita o plugin
  /// `cloud_functions`, que em alguns Android falha no canal Pigeon.
  static const String _callableUrl =
      'https://us-central1-depertin-f940f.cloudfunctions.net/solicitarExclusaoConta';

  /// Solicita exclusão lógica com datas definidas no servidor (30 dias).
  static Future<void> solicitarExclusaoConta() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Usuário não autenticado.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Não foi possível obter o token de sessão.');
    }

    final response = await http
        .post(
          Uri.parse(_callableUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'data': {}}),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw StateError(
        'Servidor respondeu ${response.statusCode}. Tente novamente.',
      );
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Resposta inválida do servidor.');
    }

    if (map.containsKey('error')) {
      final err = map['error'];
      var msg = 'Não foi possível concluir o pedido.';
      if (err is Map && err['message'] != null) {
        msg = err['message'].toString();
      }
      throw StateError(msg);
    }

    final result = map['result'];
    if (result is Map && result['ok'] == true) {
      return;
    }
    throw StateError('Resposta inválida do servidor.');
  }

  static const List<String> _mesesPtBr = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  static String _formatarDataLimitePtBr(DateTime d) {
    final mes = _mesesPtBr[d.month - 1];
    return '${d.day} de $mes de ${d.year}';
  }

  /// Lê [exclusao_definitiva_prevista_em] no servidor (após a Cloud Function gravar).
  static Future<String?> obterDataLimiteExclusaoFormatadaPtBr() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    for (var i = 0; i < 6; i++) {
      final snap = await ref.get(const GetOptions(source: Source.server));
      if (!snap.exists) return null;
      final raw = snap.data()![CamposExclusaoConta.exclusaoDefinitivaPrevistaEm];
      if (raw is Timestamp) {
        return _formatarDataLimitePtBr(raw.toDate());
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  /// Ao entrar de novo dentro do prazo de retenção, cancela o pedido de exclusão.
  static Future<void> cancelarExclusaoPendenteSeNecessario(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final d = snap.data()!;
    final status = d[CamposExclusaoConta.statusConta]?.toString();
    if (status != StatusConta.exclusaoPendente) return;

    await ref.update({
      CamposExclusaoConta.statusConta: StatusConta.ativa,
      CamposExclusaoConta.exclusaoSolicitada: false,
      CamposExclusaoConta.exclusaoSolicitadaEm: FieldValue.delete(),
      CamposExclusaoConta.exclusaoDefinitivaPrevistaEm: FieldValue.delete(),
      CamposExclusaoConta.exclusaoCanceladaPorReativacao: true,
      CamposExclusaoConta.exclusaoUltimaReativacaoEm: FieldValue.serverTimestamp(),
    });
  }

  /// Encerra sessão, limpa dados locais relevantes e envia para a Vitrine (`/home`).
  static Future<void> encerrarSessaoERedirecionarParaVitrine(
    BuildContext context,
  ) async {
    try {
      if (context.mounted) {
        context.read<CartProvider>().clearCart();
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fcm_token');
      await prefs.remove('fcm_uid');
    } catch (_) {}

    await signOutGoogle();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
    );
  }
}
