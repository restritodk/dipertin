import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ══════════════════════════════════════════════════════════════════
// CORES DI PERTIN
// ══════════════════════════════════════════════════════════════════

const Color _roxo = Color(0xFF6A1B9A);
const Color _laranja = Color(0xFFFF8F00);
const Color _texto = Color(0xFF1E1B4B);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _vermelho = Color(0xFFEF4444);
const Color _sucesso = Color(0xFF10B981);
const Color _bgSucesso = Color(0xFFD1FAE5);

/// Ação disponível para confirmação.
enum AcaoClienteComercial {
  bloquear,
  desbloquear,
  excluir,
}

/// Modal premium de confirmação (bloquear/desbloquear/excluir).
///
/// Retorna `true` se o usuário confirmou a ação.
Future<bool> mostrarConfirmacaoCliente(
  BuildContext context, {
  required AcaoClienteComercial acao,
  required String nomeCliente,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PremiumConfirmModal(
      acao: acao,
      nomeCliente: nomeCliente,
    ),
  ).then((r) => r ?? false);
}

/// Modal premium de sucesso (após bloquear/desbloquear/excluir).
Future<void> mostrarSucessoCliente(
  BuildContext context, {
  required AcaoClienteComercial acao,
  required String nomeCliente,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _PremiumSucessoModal(
      acao: acao,
      nomeCliente: nomeCliente,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// CONFIRMAÇÃO
// ══════════════════════════════════════════════════════════════════

class _PremiumConfirmModal extends StatefulWidget {
  const _PremiumConfirmModal({
    required this.acao,
    required this.nomeCliente,
  });

  final AcaoClienteComercial acao;
  final String nomeCliente;

  @override
  State<_PremiumConfirmModal> createState() => _PremiumConfirmModalState();
}

class _PremiumConfirmModalState extends State<_PremiumConfirmModal>
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

  String get _titulo {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return 'Bloquear cliente';
      case AcaoClienteComercial.desbloquear:
        return 'Desbloquear cliente';
      case AcaoClienteComercial.excluir:
        return 'Excluir cliente';
    }
  }

  String get _mensagem {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return 'O cliente "${widget.nomeCliente}" não poderá realizar novas compras no crediário. O histórico financeiro será preservado.';
      case AcaoClienteComercial.desbloquear:
        return 'O cliente "${widget.nomeCliente}" voltará a ter acesso ao crediário e poderá realizar novas compras normalmente.';
      case AcaoClienteComercial.excluir:
        return 'Tem certeza que deseja remover "${widget.nomeCliente}" da base comercial? Esta ação não pode ser desfeita. Todos os dados do cliente serão permanentemente removidos.';
    }
  }

  String get _botaoConfirmar {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return 'Sim, bloquear';
      case AcaoClienteComercial.desbloquear:
        return 'Sim, desbloquear';
      case AcaoClienteComercial.excluir:
        return 'Sim, excluir';
    }
  }

  Color get _corAcao {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return _laranja;
      case AcaoClienteComercial.desbloquear:
        return _sucesso;
      case AcaoClienteComercial.excluir:
        return _vermelho;
    }
  }

  IconData get _icone {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return Icons.block_rounded;
      case AcaoClienteComercial.desbloquear:
        return Icons.lock_open_rounded;
      case AcaoClienteComercial.excluir:
        return Icons.delete_outline_rounded;
    }
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
                  // ── Header com gradiente ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _corAcao.withValues(alpha: 0.07),
                          Colors.white,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Ícone grande pulsante
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: _corAcao.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icone, size: 34, color: _corAcao),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _titulo,
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

                  // ── Corpo ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      _mensagem,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                  ),

                  // ── Card de resumo do cliente ──
                  if (widget.acao != AcaoClienteComercial.excluir)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _corAcao.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _corAcao.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_rounded,
                                size: 16, color: _corAcao),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.nomeCliente,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _texto,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Botões ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _muted,
                              side: BorderSide(color: _borda),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancelar',
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
                              backgroundColor: _corAcao,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _botaoConfirmar,
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

// ══════════════════════════════════════════════════════════════════
// SUCESSO
// ══════════════════════════════════════════════════════════════════

class _PremiumSucessoModal extends StatefulWidget {
  const _PremiumSucessoModal({
    required this.acao,
    required this.nomeCliente,
  });

  final AcaoClienteComercial acao;
  final String nomeCliente;

  @override
  State<_PremiumSucessoModal> createState() => _PremiumSucessoModalState();
}

class _PremiumSucessoModalState extends State<_PremiumSucessoModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleFade;
  late final Animation<double> _checkScale;

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

    _checkScale = Tween<double>(begin: 0, end: 1).animate(
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

  String get _titulo {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return 'Cliente bloqueado';
      case AcaoClienteComercial.desbloquear:
        return 'Cliente desbloqueado';
      case AcaoClienteComercial.excluir:
        return 'Cliente excluído';
    }
  }

  String get _mensagem {
    switch (widget.acao) {
      case AcaoClienteComercial.bloquear:
        return '${widget.nomeCliente} foi bloqueado com sucesso. O cliente não poderá realizar compras no crediário.';
      case AcaoClienteComercial.desbloquear:
        return '${widget.nomeCliente} foi desbloqueado com sucesso. O cliente já pode realizar compras no crediário.';
      case AcaoClienteComercial.excluir:
        return '${widget.nomeCliente} foi removido da base comercial com sucesso.';
    }
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
                    // ── Check animado ──
                    ScaleTransition(
                      scale: _checkScale,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _bgSucesso,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          size: 42,
                          color: _sucesso,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _texto,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _mensagem,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'OK',
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
