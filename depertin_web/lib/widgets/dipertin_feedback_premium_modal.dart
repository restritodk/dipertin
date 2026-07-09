import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _roxo = Color(0xFF6A1B9A);
const Color _texto = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _sucesso = Color(0xFF16A34A);
const Color _bgSucesso = Color(0xFFE8F5E9);
const Color _erro = Color(0xFFDC2626);
const Color _bgErro = Color(0xFFFEF2F2);

/// Linha de detalhe exibida no modal (ex.: ambiente, chave PIX, conta MP).
class DiPertinFeedbackDetalhe {
  const DiPertinFeedbackDetalhe({
    required this.rotulo,
    required this.valor,
    this.icone = Icons.info_outline_rounded,
  });

  final String rotulo;
  final String valor;
  final IconData icone;
}

/// Modal premium de feedback (sucesso ou erro) — substitui SnackBar no rodapé.
Future<void> mostrarDiPertinFeedbackPremium(
  BuildContext context, {
  required bool sucesso,
  required String titulo,
  required String mensagem,
  List<DiPertinFeedbackDetalhe> detalhes = const [],
  String botaoTexto = 'Entendi',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _DiPertinFeedbackPremiumModal(
      sucesso: sucesso,
      titulo: titulo,
      mensagem: mensagem,
      detalhes: detalhes,
      botaoTexto: botaoTexto,
    ),
  );
}

/// Loading premium durante validação de API / salvamento.
Future<void> mostrarDiPertinLoadingPremium(
  BuildContext context, {
  required String titulo,
  String subtitulo = 'Aguarde um momento...',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _DiPertinLoadingPremiumModal(
      titulo: titulo,
      subtitulo: subtitulo,
    ),
  );
}

class _DiPertinFeedbackPremiumModal extends StatefulWidget {
  const _DiPertinFeedbackPremiumModal({
    required this.sucesso,
    required this.titulo,
    required this.mensagem,
    required this.detalhes,
    required this.botaoTexto,
  });

  final bool sucesso;
  final String titulo;
  final String mensagem;
  final List<DiPertinFeedbackDetalhe> detalhes;
  final String botaoTexto;

  @override
  State<_DiPertinFeedbackPremiumModal> createState() =>
      _DiPertinFeedbackPremiumModalState();
}

class _DiPertinFeedbackPremiumModalState extends State<_DiPertinFeedbackPremiumModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleFade;
  late final Animation<double> _iconScale;

  Color get _corPrincipal => widget.sucesso ? _sucesso : _erro;
  Color get _corFundo => widget.sucesso ? _bgSucesso : _bgErro;
  IconData get _icone => widget.sucesso
      ? Icons.check_circle_rounded
      : Icons.error_outline_rounded;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scaleFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Cubic(0.16, 1, 0.3, 1),
    );
    _iconScale = Tween<double>(begin: 0, end: 1).animate(
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Faixa superior gradiente
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: widget.sucesso
                            ? [
                                _bgSucesso,
                                Colors.white,
                              ]
                            : [
                                _bgErro,
                                Colors.white,
                              ],
                      ),
                    ),
                    child: Column(
                      children: [
                        ScaleTransition(
                          scale: _iconScale,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _corFundo,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _corPrincipal.withValues(alpha: 0.2),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(_icone, size: 40, color: _corPrincipal),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.titulo,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _texto,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                    child: Text(
                      widget.mensagem,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.55,
                        color: _muted,
                      ),
                    ),
                  ),

                  if (widget.detalhes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
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
                            for (var i = 0; i < widget.detalhes.length; i++) ...[
                              if (i > 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Divider(height: 1, color: _borda),
                                ),
                              _DetalheRow(item: widget.detalhes[i]),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              widget.sucesso ? _roxo : _erro,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.botaoTexto,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
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
    );
  }
}

class _DetalheRow extends StatelessWidget {
  const _DetalheRow({required this.item});

  final DiPertinFeedbackDetalhe item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(item.icone, size: 18, color: _roxo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.rotulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.valor,
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
    );
  }
}

class _DiPertinLoadingPremiumModal extends StatelessWidget {
  const _DiPertinLoadingPremiumModal({
    required this.titulo,
    required this.subtitulo,
  });

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _roxo,
                    backgroundColor: _roxo.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _texto,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
