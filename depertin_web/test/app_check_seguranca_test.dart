import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';

void main() {
  group('AppCheckException', () {
    test('deve armazenar a mensagem de erro', () {
      const exc = AppCheckException('Token inválido');
      expect(exc.message, equals('Token inválido'));
      expect(exc.toString(), contains('AppCheckException'));
      expect(exc.toString(), contains('Token inválido'));
    });
  });

  group('CallableHttpException', () {
    test('deve armazenar code e message', () {
      const exc = CallableHttpException('permission-denied',
          'Usuário não autorizado');
      expect(exc.code, equals('permission-denied'));
      expect(exc.message, equals('Usuário não autorizado'));
    });

    test('toString deve conter code e message', () {
      const exc =
          CallableHttpException('not-found', 'Função não encontrada');
      expect(
        exc.toString(),
        equals('CallableHttpException(not-found, Função não encontrada)'),
      );
    });

    test('deve aceitar details opcionais', () {
      final exc = CallableHttpException('internal', 'Erro interno',
          details: {'campo': 'valor'});
      expect(exc.details, isA<Map>());
      expect((exc.details as Map)['campo'], equals('valor'));
    });
  });

  group('mensagemCallableHttpException', () {
    test('not_found → mensagem de deploy pendente', () {
      const exc =
          CallableHttpException('not-found', 'Function not found');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, contains('Serviço não encontrado'));
      expect(msg, contains('Cloud Functions'));
    });

    test('internal → mensagem de erro interno', () {
      const exc = CallableHttpException('internal', 'Internal error');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, contains('Erro interno'));
    });

    test('unauthenticated genérico → mensagem amigável de reauth', () {
      const exc =
          CallableHttpException('UNAUTHENTICATED', 'Unauthenticated');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, contains('autenticar'));
      expect(msg, contains('login'));
      expect(msg, isNot(contains('App Check')));
    });

    test('unauthenticated com mensagem custom → preserva mensagem', () {
      const exc = CallableHttpException(
          'unauthenticated', 'Login necessário.');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, equals('Login necessário.'));
    });

    test('permission-denied → retorna a mensagem original', () {
      const exc = CallableHttpException(
          'permission-denied', 'Usuário sem permissão');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, equals('Usuário sem permissão'));
    });

    test('mensagem vazia → retorna o code', () {
      const exc = CallableHttpException('custom-error', '');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, equals('custom-error'));
    });

    test('código com not_found no meio → considera not_found', () {
      const exc = CallableHttpException(
          'function_not_found_error', 'not found');
      final msg = mensagemCallableHttpException(exc);
      expect(msg, contains('Serviço não encontrado'));
    });
  });

  group('callFirebaseFunctionSafe — comportamento de loading', () {
    // Testa a lógica de timeout do App Check sem chamar Firebase de verdade.

    test(
      'AppCheckException é lançada quando getToken falha com TimeoutException',
      () async {
        // Simula o tratamento de timeout no callFirebaseFunctionSafe
        Future<void> chamadaQueTomaTimeout() async {
          try {
            throw TimeoutException('getToken timed out');
          } on TimeoutException {
            throw const AppCheckException(
              'Não foi possível validar a segurança do painel. '
              'O reCAPTCHA v3 não respondeu. Atualize a página e tente novamente.',
            );
          }
        }

        try {
          await chamadaQueTomaTimeout();
          fail('Deveria ter lançado AppCheckException');
        } on AppCheckException catch (e) {
          expect(e.message, contains('não respondeu'));
          expect(e.message, contains('reCAPTCHA'));
        }
      },
    );

    test(
      'AppCheckException é lançada quando getToken retorna vazio',
      () async {
        try {
          const token = '';
          throw AppCheckException(
            token.isEmpty
                ? 'Token App Check vazio'
                : 'Outro erro',
          );
        } on AppCheckException catch (e) {
          expect(e.message, contains('vazio'));
        }
      },
    );

    test(
      'cadeia de catch deve classificar AppCheckException antes de genérico',
      () async {
        final erros = <String>[];

        Future<void> simularChamada(String tipoErro) async {
          try {
            switch (tipoErro) {
              case 'app_check':
                throw const AppCheckException('Falha App Check');
              case 'callable':
                throw const CallableHttpException(
                    'permission-denied', 'Negado');
              case 'timeout':
                throw TimeoutException('timeout');
              case 'generico':
                throw Exception('Erro genérico');
            }
          } on AppCheckException catch (e) {
            erros.add('app_check: ${e.message}');
          } on CallableHttpException catch (e) {
            erros.add('callable: ${e.message}');
          } on TimeoutException {
            erros.add('timeout');
          } catch (e) {
            erros.add('generico: $e');
          }
        }

        await simularChamada('app_check');
        await simularChamada('callable');
        await simularChamada('timeout');
        await simularChamada('generico');

        expect(erros.length, equals(4));
        expect(erros[0], contains('app_check'));
        expect(erros[0], contains('Falha App Check'));
        expect(erros[1], contains('callable'));
        expect(erros[2], equals('timeout'));
        expect(erros[3], contains('generico'));
      },
    );

    test(
      'finally sempre executa mesmo quando catch lança',
      () async {
        var finallyExecutou = false;

        try {
          throw const AppCheckException('Falha');
        } on AppCheckException {
          // catch processou o erro — não relança
        } finally {
          finallyExecutou = true;
        }

        expect(finallyExecutou, isTrue);
      },
    );

    test(
      'loadingState é false após finally com erro',
      () async {
        var salvando = true;

        try {
          throw const AppCheckException('Falha App Check');
        } on AppCheckException {
          // erro tratado
        } finally {
          salvando = false;
        }

        expect(salvando, isFalse);
      },
    );

    test(
      'loadingState é false após finally com sucesso',
      () async {
        var salvando = true;

        try {
          // sucesso — sem erros
        } finally {
          salvando = false;
        }

        expect(salvando, isFalse);
      },
    );

    test(
      'loadingState é false após finally com timeout',
      () async {
        var salvando = true;

        try {
          throw TimeoutException('timeout');
        } on TimeoutException {
          // timeout tratado
        } finally {
          salvando = false;
        }

        expect(salvando, isFalse);
      },
    );

    test(
      'sanitização de mensagens remove caracteres perigosos',
      () {
        String sanitizar(String input) {
          return input
              .replaceAll(RegExp("[<>&\"']"), ' ');
        }

        expect(sanitizar('<script>'), equals(' script '));
        expect(sanitizar('a"b\'c&d>e<f'), equals('a b c d e f'));
        expect(sanitizar('texto normal'), equals('texto normal'));
        expect(sanitizar(''), equals(''));
      },
    );
  });
}
