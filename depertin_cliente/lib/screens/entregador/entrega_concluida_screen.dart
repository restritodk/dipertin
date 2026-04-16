import 'dart:math' as math;

import 'package:depertin_cliente/app_navigator_key.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color _kRoxo = Color(0xFF6A1B9A);
const Color _kLaranja = Color(0xFFFF8F00);

class EntregaConcluidaScreen extends StatefulWidget {
  const EntregaConcluidaScreen({
    super.key,
    required this.pedidoId,
    required this.valorTotalCorrida,
    required this.taxaPlataforma,
    required this.valorLiquidoEntregador,
    required this.tipoCorrida,
    required this.temProximaCorrida,
    this.proximaCorridaId,
  });

  final String pedidoId;
  final double valorTotalCorrida;
  final double taxaPlataforma;
  final double valorLiquidoEntregador;
  final String tipoCorrida;
  final bool temProximaCorrida;
  final String? proximaCorridaId;

  @override
  State<EntregaConcluidaScreen> createState() => _EntregaConcluidaScreenState();
}

class _EntregaConcluidaScreenState extends State<EntregaConcluidaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _escalaCheck;
  late final Animation<double> _fadeConteudo;
  bool _navegandoFluxo = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  String get _codigoCurto {
    final id = widget.pedidoId;
    if (id.length <= 6) return '#${id.toUpperCase()}';
    return '#${id.substring(0, 6).toUpperCase()}';
  }

  String get _tipoFormatado {
    final b = widget.tipoCorrida.trim().toLowerCase();
    if (b.isEmpty || b == 'entrega') return 'Entrega';
    if (b == 'retirada') return 'Retirada';
    return b[0].toUpperCase() + b.substring(1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    });
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _escalaCheck = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    );
    _fadeConteudo = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _seguirFluxo() {
    if (!mounted || _navegandoFluxo) return;
    setState(() => _navegandoFluxo = true);
    // Após conclusão, volta ao shell do entregador com menu (Radar/Histórico/Ganhos).
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/entregador',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = math.max(mq.padding.bottom, 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 36),

                    ScaleTransition(
                      scale: _escalaCheck,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF43A047,
                              ).withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 52,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    FadeTransition(
                      opacity: _fadeConteudo,
                      child: Column(
                        children: [
                          const Text(
                            'Entrega concluída!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1B1B2F),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Corrida $_codigoCurto finalizada com sucesso',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 28),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 22,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_kRoxo, _kLaranja],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: _kRoxo.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Você ganhou',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _moeda.format(widget.valorLiquidoEntregador),
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'valor líquido',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _LinhaDetalhe(
                                  rotulo: 'Valor total da corrida',
                                  valor: _moeda.format(
                                    widget.valorTotalCorrida,
                                  ),
                                ),
                                const _DividerSutil(),
                                _LinhaDetalhe(
                                  rotulo: 'Taxa da plataforma',
                                  valor: _moeda.format(widget.taxaPlataforma),
                                  corValor: Colors.red.shade400,
                                ),
                                const _DividerSutil(),
                                _LinhaDetalhe(
                                  rotulo: 'Tipo',
                                  valor: _tipoFormatado,
                                ),
                                const _DividerSutil(),
                                _LinhaDetalhe(
                                  rotulo: 'Pedido',
                                  valor: _codigoCurto,
                                ),
                              ],
                            ),
                          ),

                          if (widget.temProximaCorrida &&
                              (widget.proximaCorridaId ?? '').isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _kLaranja.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _kLaranja.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delivery_dining_outlined,
                                    color: _kLaranja,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Próxima corrida aguardando',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _navegandoFluxo ? null : _seguirFluxo,
                  icon: Icon(
                    _navegandoFluxo
                        ? Icons.hourglass_top_rounded
                        : widget.temProximaCorrida
                        ? Icons.arrow_forward_rounded
                        : Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: Text(
                    _navegandoFluxo
                        ? 'Abrindo radar...'
                        : widget.temProximaCorrida
                        ? 'Ir para próxima'
                        : 'Fechar',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kRoxo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDetalhe extends StatelessWidget {
  const _LinhaDetalhe({
    required this.rotulo,
    required this.valor,
    this.corValor,
  });

  final String rotulo;
  final String valor;
  final Color? corValor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            rotulo,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: corValor ?? const Color(0xFF1B1B2F),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerSutil extends StatelessWidget {
  const _DividerSutil();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 0.5, color: Colors.grey.shade200);
  }
}
