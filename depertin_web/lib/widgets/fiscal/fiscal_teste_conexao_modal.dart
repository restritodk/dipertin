import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

// ══════════════════════════════════════════════════════════════════
// CORES
// ══════════════════════════════════════════════════════════════════

const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _texto = Color(0xFF1E1B4B);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _sucesso = Color(0xFF16A34A);
const Color _bgSucesso = Color(0xFFE8F5E9);
const Color _erro = Color(0xFFDC2626);
const Color _bgErro = Color(0xFFFEF2F2);

// ══════════════════════════════════════════════════════════════════
// RESULTADO DO TESTE
// ══════════════════════════════════════════════════════════════════

class _TestStep {
  final String label;
  final bool? ok; // null = em andamento, true = ok, false = erro
  final String? detalhe;

  const _TestStep({required this.label, this.ok, this.detalhe});
}

/// Resultado do teste de conexão.
class TestConexaoResultado {
  final bool sucesso;
  final String provedor;
  final String mensagem;
  final int? latenciaMs;
  final String? ambiente;
  final String? versaoApi;
  final List<String> errosDetalhados;

  const TestConexaoResultado({
    required this.sucesso,
    required this.provedor,
    required this.mensagem,
    this.latenciaMs,
    this.ambiente,
    this.versaoApi,
    this.errosDetalhados = const [],
  });
}

// ══════════════════════════════════════════════════════════════════
// MODAL DE TESTE DE CONEXÃO PREMIUM
// ══════════════════════════════════════════════════════════════════

/// Abre o modal premium de teste de conexão.
///
/// Exibe animação de radar/pulso enquanto testa, depois mostra
/// resultado detalhado (sucesso ou falha).
/// Retorna `true` se o teste foi bem-sucedido.
Future<TestConexaoResultado?> mostrarTesteConexaoPremium(
  BuildContext context, {
  required String provedor,
  required Future<TestConexaoResultado> Function() testar,
}) {
  return showDialog<TestConexaoResultado>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _FiscalTesteConexaoModal(
      provedor: provedor,
      testar: testar,
    ),
  );
}

class _FiscalTesteConexaoModal extends StatefulWidget {
  final String provedor;
  final Future<TestConexaoResultado> Function() testar;

  const _FiscalTesteConexaoModal({
    required this.provedor,
    required this.testar,
  });

  @override
  State<_FiscalTesteConexaoModal> createState() =>
      _FiscalTesteConexaoModalState();
}

class _FiscalTesteConexaoModalState extends State<_FiscalTesteConexaoModal>
    with TickerProviderStateMixin {
  late final AnimationController _radarCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _stepsCtrl;
  late final Animation<double> _radarRotation;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  late final Animation<double> _modalAnim;

  String _status = 'iniciando';
  String _statusTexto = 'Inicializando...';
  TestConexaoResultado? _resultado;
  List<_TestStep> _steps = [];
  int _stepAtivo = -1;

  @override
  void initState() {
    super.initState();

    // Animação de rotação do radar
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _radarRotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _radarCtrl, curve: Curves.linear),
    );

    // Animação de pulso do círculo central
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _pulseOpacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Animação de entrada do modal
    _stepsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _modalAnim = CurvedAnimation(
      parent: _stepsCtrl,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );

    _stepsCtrl.forward();
    _executarTeste();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  Future<void> _executarTeste() async {
    await _simularPasso('DNS / Resolução', 400);
    await _simularPasso('Conectando ao servidor', 500);
    await _simularPasso('Handshake TLS', 600);
    await _simularPasso('Autenticando credenciais', 500);
    await _simularPasso('Testando endpoint', 500);

    setState(() {
      _status = 'testando';
      _statusTexto = 'Validando conexão com o provedor...';
    });

    try {
      _resultado = await widget.testar();
    } catch (e) {
      _resultado = TestConexaoResultado(
        sucesso: false,
        provedor: widget.provedor,
        mensagem: 'Erro inesperado durante o teste.',
        errosDetalhados: [e.toString()],
      );
    }

    if (!mounted) return;

    // Atualiza o último passo
    setState(() {
      _status = 'concluido';
      _statusTexto = _resultado!.sucesso
          ? 'Conexão estabelecida com sucesso!'
          : 'Falha na conexão';
      _steps[_stepAtivo] = _TestStep(
        label: _steps[_stepAtivo].label,
        ok: _resultado!.sucesso,
        detalhe:
            _resultado!.sucesso ? '${_resultado!.latenciaMs ?? 0}ms' : 'Falhou',
      );
    });
  }

  Future<void> _simularPasso(String label, int duracaoMs) async {
    setState(() {
      _stepAtivo++;
      _steps = [
        ..._steps,
        _TestStep(label: label, ok: null),
      ];
    });
    await Future.delayed(Duration(milliseconds: duracaoMs));
    if (!mounted) return;
    setState(() {
      _steps[_stepAtivo] = _TestStep(label: label, ok: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _modalAnim,
      child: ScaleTransition(
        scale: _modalAnim,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: _status == 'concluido'
                  ? _buildResultado()
                  : _buildTestando(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTestando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Animação principal ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
          child: Column(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ondas de radar
                    ...List.generate(3, (i) {
                      final delay = i * 400;
                      return _RadarWave(
                        index: i,
                        delay: delay,
                        color: _roxo.withValues(alpha: 0.15 - i * 0.04),
                      );
                    }),
                    // Arco giratório
                    AnimatedBuilder(
                      animation: _radarRotation,
                      builder: (_, __) => Transform.rotate(
                        angle: _radarRotation.value,
                        child: CustomPaint(
                          size: const Size(120, 120),
                          painter: _RadarArcPainter(
                            color: _roxo,
                            startAngle: -0.4,
                            sweepAngle: 0.8,
                          ),
                        ),
                      ),
                    ),
                    // Círculo central pulsante
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_roxo, _roxoClaro],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _roxo.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: AnimatedBuilder(
                            animation: _pulseOpacity,
                            builder: (_, __) => Opacity(
                              opacity: _pulseOpacity.value,
                              child: const Icon(
                                Icons.wifi_find_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Testando conexão',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _texto,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.provedor,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _roxo,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _statusTexto,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),

        // ── Steps ──
        if (_steps.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            child: Column(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _StepRow(step: _steps[i], isLast: i == _steps.length - 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildResultado() {
    if (_resultado == null) return const SizedBox.shrink();

    final r = _resultado!;
    final isSuccess = r.sucesso;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Faixa resultado ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isSuccess
                  ? [_bgSucesso, Colors.white]
                  : [_bgErro, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              _ResultIcon(
                sucesso: isSuccess,
                tamanho: 80,
                duracao: 600,
              ),
              const SizedBox(height: 20),
              Text(
                isSuccess ? 'Conexão validada!' : 'Falha na conexão',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _texto,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                r.provedor,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: isSuccess ? _sucesso : _erro,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // ── Mensagem ──
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
          child: Text(
            r.mensagem,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.5,
              color: _muted,
            ),
          ),
        ),

        // ── Detalhes técnicos ──
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borda),
            ),
            child: Column(
              children: [
                _DetalheTecnico(
                  icone: Icons.speed_rounded,
                  rotulo: 'Latência',
                  valor: r.latenciaMs != null
                      ? '${r.latenciaMs}ms'
                      : '—',
                ),
                if (r.ambiente != null) ...[
                  const SizedBox(height: 6),
                  _DetalheTecnico(
                    icone: Icons.cloud_outlined,
                    rotulo: 'Ambiente',
                    valor: r.ambiente!,
                  ),
                ],
                if (r.versaoApi != null) ...[
                  const SizedBox(height: 6),
                  _DetalheTecnico(
                    icone: Icons.code_rounded,
                    rotulo: 'Versão da API',
                    valor: r.versaoApi!,
                  ),
                ],
                if (r.errosDetalhados.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _bgErro,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalhes do erro:',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _erro,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final err in r.errosDetalhados)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              err,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: _muted,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Botão ──
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _resultado),
              style: FilledButton.styleFrom(
                backgroundColor: isSuccess ? _roxo : _erro,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isSuccess ? 'Ótimo, conexão OK' : 'Entendi',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// COMPONENTES
// ══════════════════════════════════════════════════════════════════

class _RadarWave extends StatefulWidget {
  final int index;
  final int delay;
  final Color color;

  const _RadarWave({
    required this.index,
    required this.delay,
    required this.color,
  });

  @override
  State<_RadarWave> createState() => _RadarWaveState();
}

class _RadarWaveState extends State<_RadarWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _scale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.color, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarArcPainter extends CustomPainter {
  final Color color;
  final double startAngle;
  final double sweepAngle;

  _RadarArcPainter({
    required this.color,
    required this.startAngle,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    const radius = 60.0;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _StepRow extends StatelessWidget {
  final _TestStep step;
  final bool isLast;

  const _StepRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          // Indicador
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.ok == null
                        ? _roxo.withValues(alpha: 0.3)
                        : step.ok!
                            ? _sucesso
                            : _erro,
                  ),
                  child: step.ok == null
                      ? Center(
                          child: SizedBox(
                            width: 6,
                            height: 6,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _roxo,
                            ),
                          ),
                        )
                      : Icon(
                          step.ok! ? Icons.check_rounded : Icons.close_rounded,
                          size: 8,
                          color: Colors.white,
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: step.ok == true
                          ? _sucesso.withValues(alpha: 0.3)
                          : _borda,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      step.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: step.ok == null ? _texto : _muted,
                        fontWeight:
                            step.ok == null ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (step.detalhe != null)
                    Text(
                      step.detalhe!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: step.ok == true ? _sucesso : _muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultIcon extends StatefulWidget {
  final bool sucesso;
  final double tamanho;
  final int duracao;

  const _ResultIcon({
    required this.sucesso,
    required this.tamanho,
    required this.duracao,
  });

  @override
  State<_ResultIcon> createState() => _ResultIconState();
}

class _ResultIconState extends State<_ResultIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.duracao),
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Cubic(0.34, 1.56, 0.64, 1),
      ),
    );
    _rotation = Tween<double>(begin: -0.5, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _rotation.value,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: widget.tamanho,
            height: widget.tamanho,
            decoration: BoxDecoration(
              color: widget.sucesso ? _bgSucesso : _bgErro,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.sucesso ? _sucesso : _erro)
                      .withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              widget.sucesso
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              size: widget.tamanho * 0.55,
              color: widget.sucesso ? _sucesso : _erro,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetalheTecnico extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final String valor;

  const _DetalheTecnico({
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 16, color: _roxo),
        const SizedBox(width: 8),
        Text(
          rotulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const Spacer(),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _texto,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// MODAL DE CONFIRMAÇÃO PREMIUM GENÉRICO
// ══════════════════════════════════════════════════════════════════

/// Abre um modal de confirmação premium genérico.
///
/// Retorna `true` se o usuário confirmou.
Future<bool> mostrarConfirmacaoPremium(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  String textoConfirmar = 'Confirmar',
  String textoCancelar = 'Cancelar',
  IconData icone = Icons.help_outline_rounded,
  Color cor = _roxo,
  String? subtitulo,
  List<Widget>? detalhesExtras,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _ConfirmacaoPremiumModal(
      titulo: titulo,
      mensagem: mensagem,
      textoConfirmar: textoConfirmar,
      textoCancelar: textoCancelar,
      icone: icone,
      cor: cor,
      subtitulo: subtitulo,
      detalhesExtras: detalhesExtras,
    ),
  ).then((r) => r ?? false);
}

class _ConfirmacaoPremiumModal extends StatefulWidget {
  final String titulo;
  final String mensagem;
  final String textoConfirmar;
  final String textoCancelar;
  final IconData icone;
  final Color cor;
  final String? subtitulo;
  final List<Widget>? detalhesExtras;

  const _ConfirmacaoPremiumModal({
    required this.titulo,
    required this.mensagem,
    required this.textoConfirmar,
    required this.textoCancelar,
    required this.icone,
    required this.cor,
    this.subtitulo,
    this.detalhesExtras,
  });

  @override
  State<_ConfirmacaoPremiumModal> createState() =>
      _ConfirmacaoPremiumModalState();
}

class _ConfirmacaoPremiumModalState extends State<_ConfirmacaoPremiumModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.cor.withValues(alpha: 0.07),
                          Colors.white,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: widget.cor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(widget.icone,
                              size: 34, color: widget.cor),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.titulo,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _texto,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (widget.subtitulo != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitulo!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: _muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Corpo ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      widget.mensagem,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                  ),

                  // ── Detalhes extras ──
                  if (widget.detalhesExtras != null &&
                      widget.detalhesExtras!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: widget.detalhesExtras!,
                      ),
                    ),
                  ],

                  // ── Botões ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _muted,
                              side: const BorderSide(color: _borda),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              widget.textoCancelar,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.cor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              widget.textoConfirmar,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
