import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/login_screen.dart';
import '../../services/connectivity_service.dart';
import '../../services/conta_bloqueio_entregador_service.dart';
import '../../services/conta_bloqueio_lojista_service.dart';
import '../../services/location_service.dart';
import '../../services/sessao_timeout_service.dart';
import '../../widgets/entregador_conta_bloqueada_overlay.dart';
import '../../widgets/lojista_conta_bloqueada_overlay.dart';
import 'no_internet_screen.dart';
import 'no_gps_screen.dart';

class AppGuard extends StatefulWidget {
  final Widget child;

  const AppGuard({super.key, required this.child});

  @override
  State<AppGuard> createState() => _AppGuardState();
}

class _AppGuardState extends State<AppGuard> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSub;
  Timer? _sessaoTimer;
  bool _encerrandoSessao = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _sessaoTimer?.cancel();
      if (user == null) {
        _encerrandoSessao = false;
        return;
      }
      _encerrandoSessao = false;
      _validarSessaoAuthRemota();
      _validarSessaoExpiradaLocal();
      // Valida a cada 30s: faz `user.reload()` (conta removida/bloqueada
      // pelo servidor) e verifica expiração local (sessão > 24h).
      _sessaoTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          _validarSessaoAuthRemota();
          _validarSessaoExpiradaLocal();
        },
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _sessaoTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _validarSessaoAuthRemota();
      _validarSessaoExpiradaLocal();
    }
  }

  Future<void> _validarSessaoAuthRemota() async {
    if (!mounted || _encerrandoSessao) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.reload();
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      final contaInvalida = code == 'user-not-found' ||
          code == 'user-disabled' ||
          code == 'invalid-user-token';
      if (contaInvalida) {
        await _encerrarSessaoPorContaRemovida();
      }
    }
  }

  /// Verifica a política de expiração local de 24h (ver
  /// [SessaoTimeoutService]). Se o último login foi há mais tempo que
  /// [SessaoTimeoutService.duracaoMaximaSessao], força signOut e leva
  /// o usuário para a tela de login.
  Future<void> _validarSessaoExpiradaLocal() async {
    if (!mounted || _encerrandoSessao) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Evita falso "expirado" quando ainda não há `ultimo_login_ms` no mesmo
    // tick em que o Firebase notifica o novo login (LoginScreen ainda a
    // chamar [registrarLoginAgora]).
    await SessaoTimeoutService.garantirTimestampSessaoSeAusente();
    if (!mounted || _encerrandoSessao) return;
    final expirada = await SessaoTimeoutService.sessaoExpirada();
    if (!expirada || !mounted) return;
    await _encerrarSessaoPorExpiracaoLocal();
  }

  Future<void> _encerrarSessaoPorExpiracaoLocal() async {
    if (_encerrandoSessao || !mounted) return;
    _encerrandoSessao = true;
    _sessaoTimer?.cancel();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await SessaoTimeoutService.limparSessao();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Por segurança, sua sessão expirou. Faça login novamente para continuar.',
        ),
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _encerrarSessaoPorContaRemovida() async {
    if (_encerrandoSessao || !mounted) return;
    _encerrandoSessao = true;
    _sessaoTimer?.cancel();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await SessaoTimeoutService.limparSessao();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sua conta foi removida. Faça login novamente.'),
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final location = context.watch<LocationService>();

    if (!connectivity.initialized) {
      return widget.child;
    }

    if (!connectivity.isOnline) {
      return Stack(
        children: [
          widget.child,
          const Positioned.fill(child: NoInternetScreen()),
          _LojistaBloqueioTopLayer(),
        ],
      );
    }

    if (!location.initialized) {
      return Stack(
        children: [
          widget.child,
          _LojistaBloqueioTopLayer(),
        ],
      );
    }

    if (location.status != LocationStatus.pronto) {
      return Stack(
        children: [
          widget.child,
          const Positioned.fill(child: NoGpsScreen()),
          _LojistaBloqueioTopLayer(),
        ],
      );
    }

    return Stack(
      children: [
        widget.child,
        _LojistaBloqueioTopLayer(),
      ],
    );
  }
}

/// Cobre qualquer rota (home, /pedidos por FCM, etc.): lojista bloqueado vê a mensagem mesmo com sessão já aberta.
class _LojistaBloqueioTopLayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final u = authSnap.data;
        if (u == null) return const SizedBox.shrink();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(u.uid)
              .snapshots(),
          builder: (context, docSnap) {
            if (!docSnap.hasData || !docSnap.data!.exists) {
              return const SizedBox.shrink();
            }
            final d = docSnap.data!.data()!;
            final role =
                (d['role'] ?? d['tipoUsuario'] ?? '').toString().toLowerCase();
            unawaited(
              ContaBloqueioLojistaService.sincronizarLiberacaoSeExpirado(u.uid),
            );
            unawaited(
              ContaBloqueioEntregadorService.sincronizarLiberacaoSeExpirado(
                u.uid,
              ),
            );
            if (role == 'lojista' &&
                ContaBloqueioLojistaService.estaBloqueadoParaOperacoes(d)) {
              return Positioned.fill(
                child: LojistaContaBloqueadaOverlay(
                  dadosUsuario: d,
                  onSair: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              );
            }
            if (role == 'entregador' &&
                ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(d)) {
              return Positioned.fill(
                child: EntregadorContaBloqueadaOverlay(
                  dadosUsuario: d,
                  onSair: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
