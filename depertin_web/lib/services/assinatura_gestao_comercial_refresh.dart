import 'package:flutter/foundation.dart';

/// Sinaliza telas/sidebar/gates do Gestão Comercial para recarregar o acesso
/// após contratação ou renovação de plano (Firestore já gravado pelo backend).
class AssinaturaGestaoComercialRefresh extends ChangeNotifier {
  AssinaturaGestaoComercialRefresh._();

  static final AssinaturaGestaoComercialRefresh instance =
      AssinaturaGestaoComercialRefresh._();

  int _versao = 0;

  int get versao => _versao;

  void notificarPagamentoAprovado() {
    _versao++;
    notifyListeners();
  }
}
