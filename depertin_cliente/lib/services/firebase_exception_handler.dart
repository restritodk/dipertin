import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sessao_erro_interceptor.dart';

/// Extensão para tratar erros Firestore com interceptação de sessão expirada.
extension FirebaseExceptionHandler on FirebaseException {
  /// Verifica se este erro indica expiração de sessão.
  bool get indicaSessaoExpirada {
    final codigo = code.toLowerCase();
    return codigo == 'permission-denied' ||
        codigo == 'unauthenticated' ||
        codigo == 'invalid-argument' && message?.contains('permission') == true;
  }

  /// Se o erro indica sessão expirada, faz logout gracioso com modal.
  /// Retorna `true` se o erro foi processado (foi de sessão), `false` caso contrário.
  Future<bool> tratarSeSessaoExpirada(BuildContext context) async {
    if (!indicaSessaoExpirada) return false;

    await SessaoErroInterceptor.processarErroSessaoExpirada(
      context,
      mensagem: _obterMensagemErro(),
    );
    return true;
  }

  String _obterMensagemErro() {
    final codigo = code.toLowerCase();
    if (codigo == 'permission-denied') {
      return 'Sua sessão expirou por segurança. Faça login novamente para continuar.';
    }
    if (codigo == 'unauthenticated') {
      return 'Você foi desconectado. Faça login novamente para acessar.';
    }
    return 'Sua sessão expirou. Por favor, faça login novamente.';
  }
}

/// Extensão para Future<T> que trata erros Firestore automaticamente.
extension FirestoreFutureHandler<T> on Future<T> {
  /// Trata erros Firestore que indicam sessão expirada.
  /// Se o erro for de sessão, faz logout e mostra modal.
  /// Caso contrário, relança o erro.
  Future<T> tratarSessaoExpirada(BuildContext context) async {
    try {
      return await this;
    } on FirebaseException catch (e) {
      final foiProcessado = await e.tratarSeSessaoExpirada(context);
      if (foiProcessado) {
        // Erro foi processado (sessão expirada), aguarda indefinidamente
        // pois o app vai redirecionar para login
        return Future.delayed(const Duration(days: 1));
      }
      // Erro não era de sessão, relança
      rethrow;
    }
  }
}
