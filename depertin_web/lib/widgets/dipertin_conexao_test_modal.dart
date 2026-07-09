import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ══════════════════════════════════════════════════════════════════
// CORES DI PERTIN
// ══════════════════════════════════════════════════════════════════

const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _laranja = Color(0xFFFF8F00);
const Color _texto = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _sucesso = Color(0xFF16A34A);
const Color _bgSucesso = Color(0xFFE8F5E9);
const Color _erro = Color(0xFFDC2626);
const Color _bgErro = Color(0xFFFEF2F2);
const Color _bg = Color(0xFFF5F4F8);

// =====================================================================
// MODAL DE TESTE DE CONEXÃO — Animação radial / pulso
// =====================================================================

/// Abre um modal premium animado que simula o teste de conexão com a API.
///
/// Retorna `true` se a conexão foi bem-sucedida, `false` em caso de falha.
///
/// Uso:
/// ```dart
/// final sucesso = await mostrarDiPertinTesteConexaoPremium(
///   context,
///   provedor: 'Mercado Pago',
///   funcaoTeste: () async {
///     // ... chamada real à API ...
///     return ConexaoTestResult(valida: true, mensagem: 'OK');
///   },
/// );
/// ```
class ConexaoTestResult {
  const ConexaoTestResult({
    required this.valida,
    this.mensagem,
    this.detalhes = const [],
  });

  final bool valida;
  final String? mensagem;
  final List<ConexaoTestDetalhe> detalhes;
}

class ConexaoTestDetalhe {
  const ConexaoTestDetalhe({
    required this.rotulo,
    required this.valor,
    this.icone = Icons.info_outline_rounded,
  });

  final String rotulo;
  final String valor;
  final IconData icone;
}

/// Modal premium de teste de conexão — animação radial + resultado.
Future<ConexaoTestResult> mostrarDiPertinTesteConexaoPremium({
  required BuildContext context,
  required String provedor,
  required Future<ConexaoTestResult> Function() funcaoTeste,
}) {
  final completer = Completer<ConexaoTestResult>();
  showDialog<ConexaoTestResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _DiPertinTesteConexaoModal(
      provedor: provedor,
      funcaoTeste: funcaoTeste,
      completer: completer,
    ),
  );
  return completer.future;
}

class _DiPertinTesteConexaoModal extends StatefulWidget {
  const _DiPertinTesteConexaoModal({
    required this.provedor,
    required this.funcaoTeste,
    required this.completer,
  });

  final String provedor;
  final Future<ConexaoTestResult> Function() funcaoTeste;
  final Completer<ConexaoTestResult> completer;

  @override
  State<_DiPertinTesteConexaoModal> createState() =>
      _DiPertinTesteConexaoModalState();
}

class _DiPertinTesteConexaoModalState
    extends State<_DiPertinTesteConexaoModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  // Animações de entrada do modal
  late final Animation<double> _scaleFade;

  // Animações das ondas de pulso
  late final Animation<double> _pulse1;
  late final Animation<double> _pulse2;
  late final Animation<double> _pulse3;

  // Animação dos pontos do radar
  late final Animation<double> _dotRotation;

  // Estado do teste
  _TesteEstado _estado = _TesteEstado.conectando;
  ConexaoTestResult? _resultado;
  String _statusTexto = 'Iniciando conexão...';
  int _statusIndex = 0;

  final List<String> _statusEtapas = [
    'Estabelecendo conexão segura...',
    'Autenticando credenciais...',
    'Validando ambiente do provedor...',
    'Testando envio de requisição...',
    'Verificando resposta da API...',
  ];

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _scaleFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );

    _pulse1 = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _pulse2 = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    _pulse3 = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    _dotRotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.linear,
      ),
    );

    _animCtrl.repeat();

    _animarStatus();
    _executarTeste();
  }

  void _animarStatus() {
    _statusTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (_estado != _TesteEstado.conectando) {
        _statusTimer?.cancel();
        return;
      }
      setState(() {
        _statusIndex = (_statusIndex + 1) % _statusEtapas.length;
        _statusTexto = _statusEtapas[_statusIndex];
      });
    });
  }

  Future<void> _executarTeste() async {
    // Pequena pausa para a animação rodar
    await Future.delayed(const Duration(milliseconds: 600));
    try {
      final result = await widget.funcaoTeste();
      if (!mounted) return;
      setState(() {
        _resultado = result;
        _estado = result.valida ? _TesteEstado.sucesso : _TesteEstado.erro;
        _statusTexto = result.valida
            ? 'Conexão estabelecida com sucesso!'
            : (result.mensagem ?? 'Falha na conexão.');
      });
      _animCtrl.stop();
      _statusTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        widget.completer.complete(_resultado);
        Navigator.pop(context, _resultado);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultado = ConexaoTestResult(
          valida: false,
          mensagem: e.toString(),
        );
        _estado = _TesteEstado.erro;
        _statusTexto = 'Falha na conexão.';
      });
      _animCtrl.stop();
      _statusTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        widget.completer.complete(_resultado);
        Navigator.pop(context, _resultado);
      }
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _scaleFade,
      child: ScaleTransition(
        scale: _scaleFade,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header gradiente ──
                  _buildHeader(),
                  // ── Corpo ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nome do provedor
                        _buildProviderChip(),
                        const SizedBox(height: 24),
                        // Texto de status
                        _buildStatusText(),
                        // Se houver resultado, mostra detalhes
                        if (_resultado != null &&
                            _resultado!.detalhes.isNotEmpty)
                          _buildDetalhesCard(),
                        // Botão pós-resultado
                        if (_estado != _TesteEstado.conectando)
                          _buildResultButton(),
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _roxo.withValues(alpha: 0.04),
            Colors.white,
          ],
        ),
      ),
      child: Column(
        children: [
          // ── Animação central ──
          SizedBox(
            width: 140,
            height: 140,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, __) {
                return CustomPaint(
                  painter: _RadarPainter(
                    pulse1: _pulse1.value,
                    pulse2: _pulse2.value,
                    pulse3: _pulse3.value,
                    rotation: _dotRotation.value,
                    estado: _estado,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Título
          Text(
            _estado == _TesteEstado.conectando
                ? 'Testando conexão'
                : _estado == _TesteEstado.sucesso
                    ? 'Conexão realizada!'
                    : 'Falha na conexão',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _texto,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProviderChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _estado == _TesteEstado.sucesso
            ? _bgSucesso
            : _estado == _TesteEstado.erro
                ? _bgErro
                : _roxo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _estado == _TesteEstado.sucesso
              ? _sucesso.withValues(alpha: 0.3)
              : _estado == _TesteEstado.erro
                  ? _erro.withValues(alpha: 0.3)
                  : _roxo.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 16,
            color: _estado == _TesteEstado.sucesso
                ? _sucesso
                : _estado == _TesteEstado.erro
                    ? _erro
                    : _roxo,
          ),
          const SizedBox(width: 8),
          Text(
            widget.provedor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _estado == _TesteEstado.sucesso
                  ? _sucesso
                  : _estado == _TesteEstado.erro
                      ? _erro
                      : _roxo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText() {
    Color cor;
    if (_estado == _TesteEstado.sucesso) {
      cor = _sucesso;
    } else if (_estado == _TesteEstado.erro) {
      cor = _erro;
    } else {
      cor = _muted;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Text(
        _statusTexto,
        key: ValueKey(_statusTexto),
        textAlign: TextAlign.center,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          height: 1.5,
          color: cor,
          fontWeight:
              _estado != _TesteEstado.conectando ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildDetalhesCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borda),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _resultado!.detalhes.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: _borda),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_resultado!.detalhes[i].icone,
                      size: 16, color: _roxo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resultado!.detalhes[i].rotulo,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _resultado!.detalhes[i].valor,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _texto,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: () {
            // O modal já foi fechado pelo completer, mas garantimos
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            backgroundColor: _estado == _TesteEstado.sucesso
                ? _roxo
                : _erro,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            _estado == _TesteEstado.sucesso ? 'Ótimo' : 'Fechar',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

enum _TesteEstado { conectando, sucesso, erro }

// ══════════════════════════════════════════════════════════════════
// PAINTER — Animação de radar/pulso
// ══════════════════════════════════════════════════════════════════

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.pulse1,
    required this.pulse2,
    required this.pulse3,
    required this.rotation,
    required this.estado,
  });

  final double pulse1;
  final double pulse2;
  final double pulse3;
  final double rotation;
  final _TesteEstado estado;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    Color corBase;
    Color corOnda;
    if (estado == _TesteEstado.sucesso) {
      corBase = _sucesso;
      corOnda = _sucesso.withValues(alpha: 0.3);
    } else if (estado == _TesteEstado.erro) {
      corBase = _erro;
      corOnda = _erro.withValues(alpha: 0.3);
    } else {
      corBase = _roxo;
      corOnda = _roxo.withValues(alpha: 0.3);
    }

    // ── Círculo base (fundo) ──
    final basePaint = Paint()
      ..color = corBase.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, basePaint);

    // ── Borda do círculo base ──
    final borderPaint = Paint()
      ..color = corBase.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, borderPaint);

    // ── Ondas de pulso (3 concêntricas) ──
    final waveRadius = radius * 0.75;
    for (final pulse in [pulse1, pulse2, pulse3]) {
      final r = waveRadius * pulse;
      final alpha = (1.0 - pulse) * 0.5;
      final wavePaint = Paint()
        ..color = corOnda.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, r, wavePaint);
    }

    // ── Círculo central (núcleo) ──
    if (estado == _TesteEstado.conectando) {
      // Pulsando
      final coreRadius = 12.0 + (pulse1 * 4.0);
      final corePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            _roxoClaro,
            _roxo,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
      canvas.drawCircle(center, coreRadius, corePaint);

      // Brilho ao redor do núcleo
      final glowPaint = Paint()
        ..color = _roxo.withValues(alpha: 0.2 * (1 - pulse1))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, coreRadius + 6, glowPaint);

      // ── Ponto em órbita ──
      final orbitRadius = radius * 0.55;
      final dotX = center.dx + orbitRadius * math.cos(rotation);
      final dotY = center.dy + orbitRadius * math.sin(rotation);
      final dotPaint = Paint()
        ..color = _laranja
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);

      // Brilho do ponto orbital
      final dotGlowPaint = Paint()
        ..color = _laranja.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(dotX, dotY), 6, dotGlowPaint);
    } else {
      // Ícone central fixo (check ou X)
      final coreRadius = 16.0;
      final cor = estado == _TesteEstado.sucesso ? _sucesso : _erro;

      final corePaint = Paint()
        ..color = cor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, coreRadius + 6, corePaint);

      // Usamos TextPainter para desenhar check/X
      final tp = TextPainter(
        text: TextSpan(
          text: estado == _TesteEstado.sucesso ? '✓' : '✕',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
        canvas,
        center - Offset(tp.width / 2, tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.pulse1 != pulse1 ||
      oldDelegate.pulse2 != pulse2 ||
      oldDelegate.pulse3 != pulse3 ||
      oldDelegate.rotation != rotation ||
      oldDelegate.estado != estado;
}

// =====================================================================
// RESULTADO DA CONEXÃO — Modal de feedback simplificado (pós-teste)
// =====================================================================

/// Modal compacto de resultado da conexão, usado quando o teste
/// já foi concluído e queremos reexibir o resultado.
Future<void> mostrarDiPertinResultadoConexaoPremium(
  BuildContext context, {
  required bool sucesso,
  required String provedor,
  String? mensagem,
  List<ConexaoTestDetalhe> detalhes = const [],
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _DiPertinResultadoConexaoModal(
      sucesso: sucesso,
      provedor: provedor,
      mensagem: mensagem,
      detalhes: detalhes,
    ),
  );
}

class _DiPertinResultadoConexaoModal extends StatefulWidget {
  const _DiPertinResultadoConexaoModal({
    required this.sucesso,
    required this.provedor,
    this.mensagem,
    this.detalhes = const [],
  });

  final bool sucesso;
  final String provedor;
  final String? mensagem;
  final List<ConexaoTestDetalhe> detalhes;

  @override
  State<_DiPertinResultadoConexaoModal> createState() =>
      _DiPertinResultadoConexaoModalState();
}

class _DiPertinResultadoConexaoModalState
    extends State<_DiPertinResultadoConexaoModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleFade;
  late final Animation<double> _iconAnim;

  Color get _cor => widget.sucesso ? _sucesso : _erro;
  Color get _fundo => widget.sucesso ? _bgSucesso : _bgErro;
  IconData get _icone =>
      widget.sucesso ? Icons.check_circle_rounded : Icons.error_outline_rounded;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );
    _iconAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Cubic(0.34, 1.56, 0.64, 1),
      ),
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
      opacity: _scaleFade,
      child: ScaleTransition(
        scale: _scaleFade,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone
                    ScaleTransition(
                      scale: _iconAnim,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _fundo,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _cor.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(_icone, size: 42, color: _cor),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Provedor
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _fundo,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.provedor,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _cor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Título
                    Text(
                      widget.sucesso
                          ? 'Conexão validada'
                          : 'Falha na conexão',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Mensagem
                    Text(
                      widget.mensagem ??
                          (widget.sucesso
                              ? 'As credenciais foram validadas com sucesso.'
                              : 'Não foi possível validar as credenciais.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                    // Detalhes
                    if (widget.detalhes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _borda),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < widget.detalhes.length; i++) ...[
                              if (i > 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 6),
                                  child: Divider(height: 1, color: _borda),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(widget.detalhes[i].icone,
                                      size: 16, color: _roxo),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.detalhes[i].rotulo,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: _muted,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.detalhes[i].valor,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1A1A2E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Botão
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.sucesso ? _roxo : _erro,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.sucesso ? 'OK' : 'Fechar',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
