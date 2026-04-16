import 'package:flutter/foundation.dart';
import 'painel_routes.dart';

/// Estado da aba/rota ativa no painel (sem [Navigator.pushReplacement]).
class PainelNavController extends ChangeNotifier {
  PainelNavController({String? initial})
      : _route = PainelRoutes.normalize(initial ?? '/dashboard');

  String _route;
  String get currentRoute => _route;

  void navigateTo(String route) {
    final r = PainelRoutes.normalize(route);
    if (_route == r) return;
    _route = r;
    notifyListeners();
  }
}
