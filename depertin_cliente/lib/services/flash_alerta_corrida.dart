// Arquivo: lib/services/flash_alerta_corrida.dart

import 'dart:async';

import 'package:flutter/material.dart';

/// Pisca a tela do app (overlay full-screen) quando uma nova corrida chega.
/// Usado como apoio visual para entregadores com limitação auditiva ou que
/// preferem alerta silencioso.
class FlashAlertaCorrida {
  FlashAlertaCorrida._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void disparar({
    required BuildContext context,
    int piscadas = 6,
    Duration duracao = const Duration(milliseconds: 220),
    Color cor = const Color(0xFFFF8F00),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _encerrar();
    bool visivel = true;
    final entry = OverlayEntry(
      builder: (ctx) => IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: visivel ? cor.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
    );
    overlay.insert(entry);
    _entry = entry;

    int ciclo = 0;
    _timer = Timer.periodic(duracao, (t) {
      visivel = !visivel;
      entry.markNeedsBuild();
      ciclo += 1;
      if (ciclo >= piscadas * 2) {
        _encerrar();
      }
    });
  }

  static void parar() => _encerrar();

  static void _encerrar() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
