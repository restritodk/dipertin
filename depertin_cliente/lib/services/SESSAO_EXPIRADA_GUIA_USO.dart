/**
 * GUIA DE USO: Tratamento Elegante de Sessão Expirada
 * 
 * ARQUIVOS ENVOLVIDOS:
 * - lib/services/sessao_erro_interceptor.dart (modal elegante)
 * - lib/services/firebase_exception_handler.dart (extensões)
 * - lib/screens/guards/app_guard.dart (detecção proativa)
 * 
 * FLUXO:
 * 1. AppGuard testa Firestore a cada 15s proativamente
 * 2. Se receber permission-denied, mostra modal elegante
 * 3. User clica "Fazer Login Novamente" ou esnoba
 * 4. App redireciona para LoginScreen automaticamente
 * 
 * EXEMPLOS DE USO EM SEUS SERVIÇOS:
 */

// ─────────────────────────────────────────────────────────────────────────────
// EXEMPLO 1: Em um Serviço que faz operações Firestore
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'firebase_exception_handler.dart';

class MinhaDataService {
  /// Exemplo: buscar dados de forma elegante com tratamento de sessão
  static Future<Map<String, dynamic>?> buscarUsuario(
    BuildContext context,
    String uid,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .tratarSessaoExpirada(context); // 👈 Trata automaticamente!

      return doc.data();
    } on FirebaseException catch (e) {
      // Se não era sessão expirada, aqui você trata outros erros
      print('Erro Firestore: ${e.code}');
      rethrow;
    }
  }

  /// Exemplo 2: Com try-catch tradicional
  static Future<List<String>> buscarPedidos(
    BuildContext context,
    String userId,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('cliente_id', isEqualTo: userId)
          .get();

      return snapshot.docs.map((e) => e.id).toList();
    } on FirebaseException catch (e) {
      // Verifica se foi sessão expirada
      final foiProcessado = await e.tratarSeSessaoExpirada(context);
      if (foiProcessado) {
        // Erro foi tratado, aguarda redirecionamento para login
        return [];
      }
      // Outro erro, relança para o caller tratar
      rethrow;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXEMPLO 2: Em um Provider com atualizações periódicas
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserDataNotifier extends StateNotifier<Map<String, dynamic>?> {
  UserDataNotifier(this.ref, this.uid) : super(null);
  
  final Ref ref;
  final String uid;

  Future<void> carregar(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .tratarSessaoExpirada(context);

      state = doc.data();
    } on FirebaseException catch (e) {
      if (!await e.tratarSeSessaoExpirada(context)) {
        print('Erro ao carregar: ${e.code}');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXEMPLO 3: Em um Widget que monitora Firestore em tempo real
// ─────────────────────────────────────────────────────────────────────────────

class MeuWidgetComStream extends StatelessWidget {
  final String pedidoId;

  const MeuWidgetComStream({required this.pedidoId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('pedidos')
          .doc(pedidoId)
          .snapshots(),
      builder: (context, snapshot) {
        // Trata erro de permissão (sessão expirada)
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is FirebaseException) {
            Future.microtask(() async {
              final foiProcessado = 
                  await error.tratarSeSessaoExpirada(context);
              if (!foiProcessado) {
                // Outro erro, mostra snackbar
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro: ${error.code}')),
                );
              }
            });
          }
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        return Text('Pedido: ${snapshot.data?.id}');
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXEMPLO 4: Operação em lote com recuperação
// ─────────────────────────────────────────────────────────────────────────────

Future<void> atualizarPedidosEmLote(
  BuildContext context,
  List<String> pedidoIds,
) async {
  final batch = FirebaseFirestore.instance.batch();

  for (final id in pedidoIds) {
    batch.update(
      FirebaseFirestore.instance.collection('pedidos').doc(id),
      {'status': 'processando'},
    );
  }

  try {
    await batch.commit().tratarSessaoExpirada(context);
  } on FirebaseException catch (e) {
    if (!await e.tratarSeSessaoExpirada(context)) {
      print('Erro em lote: ${e.code}');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANTE:
// ─────────────────────────────────────────────────────────────────────────────
/*
 * 1. SEMPRE passe `context` quando usar as extensões
 * 2. O AppGuard já trata proativamente a cada 15s
 * 3. Se sessão expirou e você estiver em um StreamBuilder:
 *    - Use Future.microtask() para não causar rebuild durante error
 * 4. O modal elegante aparece automaticamente, não precisa fazer nada extra
 * 5. Depois do modal, o app redireciona para LoginScreen
 * 
 * TESTES RECOMENDADOS:
 * 1. Faça login
 * 2. Aguarde 24h (ou modifique SessaoTimeoutService para menos tempo)
 * 3. Tente fazer uma requisição (ir pra próxima tela, clicar em botão, etc)
 * 4. Verifique se aparece o modal elegante (não tela branca)
 * 5. Clique "Fazer Login Novamente"
 * 6. Verifique se vai para LoginScreen
 */
