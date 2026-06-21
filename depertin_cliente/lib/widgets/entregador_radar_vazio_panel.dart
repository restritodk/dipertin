import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _diPertinRoxo = Color(0xFF6A1B9A);
const Color _diPertinLaranja = Color(0xFFFF8F00);

/// Painel visual premium para o estado vazio do radar do entregador.
/// Apenas UI — sem lógica de negócio.
class EntregadorRadarVazioPanel extends StatefulWidget {
  const EntregadorRadarVazioPanel({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.dicas = const [],
    this.mostrarSeloOnline = true,
  });

  final String titulo;
  final String subtitulo;
  final List<EntregadorRadarVazioDica> dicas;
  final bool mostrarSeloOnline;

  @override
  State<EntregadorRadarVazioPanel> createState() =>
      _EntregadorRadarVazioPanelState();
}

class EntregadorRadarVazioDica {
  const EntregadorRadarVazioDica({required this.icone, required this.texto});

  final IconData icone;
  final String texto;
}

class _EntregadorRadarVazioPanelState extends State<EntregadorRadarVazioPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulsoCtrl;

  @override
  void initState() {
    super.initState();
    _pulsoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulsoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dicas = widget.dicas.isNotEmpty
        ? widget.dicas
        : const [
            EntregadorRadarVazioDica(
              icone: Icons.volume_up_rounded,
              texto: 'Alerta sonoro',
            ),
            EntregadorRadarVazioDica(
              icone: Icons.storefront_rounded,
              texto: 'Pedido pronto',
            ),
            EntregadorRadarVazioDica(
              icone: Icons.swipe_down_rounded,
              texto: 'Puxe p/ atualizar',
            ),
          ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, entrada, child) {
        return Opacity(
          opacity: entrada,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - entrada)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              _diPertinRoxo.withValues(alpha: 0.04),
              _diPertinLaranja.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(
            color: _diPertinRoxo.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: _diPertinRoxo.withValues(alpha: 0.10),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: _diPertinLaranja.withValues(alpha: 0.06),
              blurRadius: 48,
              spreadRadius: -8,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RadarPulsoAnimado(controller: _pulsoCtrl),
            if (widget.mostrarSeloOnline) ...[
              const SizedBox(height: 20),
              _SeloOnline(),
            ],
            const SizedBox(height: 22),
            Text(
              widget.titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.15,
                color: Color(0xFF1C1C28),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: Colors.grey[700],
                letterSpacing: -0.1,
              ),
            ),
            if (dicas.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: dicas.map(_ChipDica.new).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RadarPulsoAnimado extends StatelessWidget {
  const _RadarPulsoAnimado({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _anelRadar(t, 0.00, 0.52),
              _anelRadar(t, 0.33, 0.44),
              _anelRadar(t, 0.66, 0.36),
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_diPertinLaranja, Color(0xFFFFB74D)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _diPertinLaranja.withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.radar_rounded,
                  size: 52,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              Positioned(
                top: 18,
                right: 28,
                child: _pontoVarredura(t),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _anelRadar(double t, double atraso, double opacidadeMax) {
    final fase = (t + atraso) % 1.0;
    final escala = 0.55 + fase * 0.95;
    final opacidade = (1 - fase) * opacidadeMax;
    return Transform.scale(
      scale: escala,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _diPertinLaranja.withValues(alpha: opacidade),
            width: 2.5,
          ),
        ),
      ),
    );
  }

  Widget _pontoVarredura(double t) {
    final angulo = t * 2 * math.pi;
    return Transform.rotate(
      angle: angulo,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _diPertinRoxo.withValues(alpha: 0.7),
          boxShadow: [
            BoxShadow(
              color: _diPertinRoxo.withValues(alpha: 0.35),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeloOnline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF43A047).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF43A047),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF43A047).withValues(alpha: 0.55),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Online · varredura ativa',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E7D32),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipDica extends StatelessWidget {
  const _ChipDica(this.dica);

  final EntregadorRadarVazioDica dica;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _diPertinRoxo.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(dica.icone, size: 16, color: _diPertinRoxo),
          const SizedBox(width: 6),
          Text(
            dica.texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
