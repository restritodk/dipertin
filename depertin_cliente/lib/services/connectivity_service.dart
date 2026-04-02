import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  bool _isOnline = true;
  bool _initialized = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool get isOnline => _isOnline;
  bool get initialized => _initialized;

  ConnectivityService() {
    _inicializar();
  }

  Future<void> _inicializar() async {
    final results = await Connectivity().checkConnectivity();
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    _isOnline = hasNetwork ? await _verificarAcessoReal() : false;
    _initialized = true;
    notifyListeners();

    _subscription =
        Connectivity().onConnectivityChanged.listen(_onMudancaConectividade);
  }

  Future<void> _onMudancaConectividade(List<ConnectivityResult> results) async {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    if (!hasNetwork) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
      return;
    }

    final online = await _verificarAcessoReal();
    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }
  }

  Future<bool> _verificarAcessoReal() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> verificarConexao() async {
    final online = await _verificarAcessoReal();
    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
