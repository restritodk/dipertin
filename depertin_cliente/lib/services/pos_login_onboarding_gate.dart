import 'package:flutter/widgets.dart';

/// Enquanto o utilizador conclui o login (incl. oferta de biometria) por cima
/// da rota `/home`, o [authStateChanges] do [MainNavigator] de baixo dispara
/// e o diálogo de "cadastre o endereço" podia abrir *antes* da biometria.
/// Este módulo suprime o onboarding nesse intervalo e agenda uma nova
/// avaliação **depois** de fechar o [LoginScreen].
class PosLoginOnboardingGate {
  PosLoginOnboardingGate._();

  static bool _suprimirAvaliacaoEndereco = false;
  static void Function()? _avaliarOnboardingEndereco;

  /// O [MainNavigator] regista a função que chama
  /// [MainNavigatorState._executarOnboardingEnderecoPrimeiroAcesso].
  static void definirAvaliadorOnboardingEndereco(void Function()? fn) {
    _avaliarOnboardingEndereco = fn;
  }

  /// Deve chamar-se **sincronamente** logo após o `signIn` ter sucesso,
  /// antes de qualquer `await` (biometria, etc.).
  static void iniciouFluxoPosSignIn() {
    _suprimirAvaliacaoEndereco = true;
  }

  static bool get suprimirAvaliacaoEndereco => _suprimirAvaliacaoEndereco;

  /// Login cancelado / bloqueado **antes** de fechar a ecrã — não reabre onboarding.
  static void abortouFluxoLiberarSemOnboarding() {
    _suprimirAvaliacaoEndereco = false;
  }

  /// Chamar após fechar o login com sucesso (pode ser sem `mounted`).
  /// Agenda o onboarding após a pilha de rotas actualizar.
  static void concluiuFluxoLiberarOnboardingAposSairDoLogin() {
    _suprimirAvaliacaoEndereco = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _avaliarOnboardingEndereco?.call();
      });
    });
  }
}
