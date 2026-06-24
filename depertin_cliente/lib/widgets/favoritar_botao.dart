// Arquivo: lib/widgets/favoritar_botao.dart

import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/favoritos_service.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);

/// Partícula individual da explosão.
class _Particula {
  final double angulo;
  final double distanciaMax;
  final double tamanhoMax;
  final Color cor;
  _Particula(this.angulo, this.distanciaMax, this.tamanhoMax, this.cor);
}

/// Pintor da explosão de partículas.
class _ExplosaoPainter extends CustomPainter {
  final double progresso;
  final List<_Particula> particulas;

  _ExplosaoPainter({required this.progresso, required this.particulas});

  @override
  void paint(Canvas canvas, Size size) {
    if (progresso <= 0 || progresso >= 1) return;

    final centro = Offset(size.width / 2, size.height / 2);
    final raioBase = size.width / 2;

    for (final p in particulas) {
      final distancia = raioBase + p.distanciaMax * progresso;
      final dx = centro.dx + distancia * math.cos(p.angulo);
      final dy = centro.dy + distancia * math.sin(p.angulo);

      final opacidade = (1 - progresso) * (1 - progresso);
      final tamanho = p.tamanhoMax * progresso.clamp(0.2, 1.0);

      canvas.drawCircle(
        Offset(dx, dy),
        tamanho,
        Paint()..color = p.cor.withValues(alpha: opacidade),
      );
    }
  }

  @override
  bool shouldRepaint(_ExplosaoPainter oldDelegate) =>
      oldDelegate.progresso != progresso;
}

/// Botão de coração para favoritar/desfavoritar um produto.
/// Gerencia autenticação — se o usuário não estiver logado, abre um diálogo.
class FavoritarBotao extends StatefulWidget {
  final Map<String, dynamic> produto;
  const FavoritarBotao({super.key, required this.produto});

  @override
  State<FavoritarBotao> createState() => _FavoritarBotaoState();
}

class _FavoritarBotaoState extends State<FavoritarBotao>
    with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _favoritosService = FavoritosService.instance;
  bool _isFavorito = false;
  bool _carregando = true;

  late final AnimationController _explosaoController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  String? get _produtoId =>
      (widget.produto['id_documento'] as String?) ??
      (widget.produto['id'] as String?) ??
      (widget.produto['produto_id'] as String?);

  @override
  void initState() {
    super.initState();
    _explosaoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticOut),
    );
    _carregarEstado();
  }

  @override
  void dispose() {
    _explosaoController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _carregarEstado() async {
    final uid = _auth.currentUser?.uid;
    final pid = _produtoId;
    if (uid == null || pid == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    try {
      final favorito = await _favoritosService.isFavorito(uid, pid);
      if (mounted) setState(() => _isFavorito = favorito);
    } catch (_) {
      // falha silenciosa na leitura inicial
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _toggle() async {
    final user = _auth.currentUser;
    final pid = _produtoId;
    if (user == null || pid == null) {
      _mostrarDialogoLogin();
      return;
    }

    setState(() => _carregando = true);
    try {
      final salvou = await _favoritosService.toggle(
        user.uid,
        pid,
        widget.produto,
      );
      if (mounted) {
        setState(() => _isFavorito = salvou);
        if (salvou) {
          _explosaoController.forward(from: 0);
          _pulseController.forward(from: 0);
        }
        _mostrarSnackBar(
          salvou
              ? 'Produto salvo nos favoritos'
              : 'Produto removido dos favoritos',
          salvou,
        );
      }
    } catch (_) {
      if (mounted) {
        _mostrarSnackBar('Erro ao salvar. Tente novamente.', false);
      }
    }
    if (mounted) setState(() => _carregando = false);
  }

  void _mostrarSnackBar(String mensagem, bool sucesso) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              sucesso ? Icons.favorite_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(mensagem, style: const TextStyle(fontSize: 14))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: sucesso ? _roxo : Colors.red.shade700,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ),
    );
  }

  void _mostrarDialogoLogin() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.favorite_rounded, color: _roxo, size: 22),
            const SizedBox(width: 10),
            const Text(
              'Favoritos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: const Text(
          'Faça login para salvar produtos nos favoritos.',
          style: TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Agora não', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _roxo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Fazer login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _carregando ? null : _toggle,
      behavior: _carregando
          ? HitTestBehavior.deferToChild
          : HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Explosão
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _explosaoController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ExplosaoPainter(
                      progresso: _explosaoController.value,
                      particulas: _particulasExplosao(),
                    ),
                  );
                },
              ),
            ),
            // Círculo + coração com pulso
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _carregando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.8),
                              ),
                            ),
                          )
                        : Icon(
                            _isFavorito
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: _isFavorito ? _roxo : const Color(0xFFE53935),
                          ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Gera as partículas da explosão (roxo, laranja, pink, dourado).
  List<_Particula> _particulasExplosao() {
    const cores = [_roxo, _laranja, Color(0xFFE040FB), Color(0xFFFFD600)];
    final random = math.Random(42);
    return List.generate(24, (i) {
      final angulo = (math.pi * 2 / 24) * i + random.nextDouble() * 0.4;
      return _Particula(
        angulo,
        18 + random.nextDouble() * 16, // distância máxima (maior)
        3.5 + random.nextDouble() * 4.0, // tamanho máximo (maior)
        cores[i % 4],
      );
    });
  }
}
