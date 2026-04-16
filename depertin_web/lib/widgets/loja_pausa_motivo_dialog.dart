import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/loja_pausa.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LojaPausaMotivoResult {
  const LojaPausaMotivoResult({required this.motivo, this.pausaVoltaAt});

  final String motivo;
  final Timestamp? pausaVoltaAt;
}

Future<LojaPausaMotivoResult?> showLojaPausaMotivoDialog(
  BuildContext context, {
  Color accent = PainelAdminTheme.roxo,
  Color surface = const Color(0xFFFDFCFE),
}) {
  final messenger = ScaffoldMessenger.of(context);

  return showDialog<LojaPausaMotivoResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => _LojaPausaMotivoDialog(
      accent: accent,
      surface: surface,
      messenger: messenger,
    ),
  );
}

class _LojaPausaMotivoDialog extends StatefulWidget {
  const _LojaPausaMotivoDialog({
    required this.accent,
    required this.surface,
    required this.messenger,
  });

  final Color accent;
  final Color surface;
  final ScaffoldMessengerState messenger;

  @override
  State<_LojaPausaMotivoDialog> createState() => _LojaPausaMotivoDialogState();
}

class _LojaPausaMotivoDialogState extends State<_LojaPausaMotivoDialog> {
  String _motivoSel = PausaMotivoLoja.almoco;
  TimeOfDay? _volta;

  static const _radius = 28.0;

  Future<void> _escolherHora() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _volta ?? const TimeOfDay(hour: 13, minute: 0),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: widget.accent,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (t != null) setState(() => _volta = t);
  }

  void _confirmar() {
    if (_motivoSel == PausaMotivoLoja.almoco && _volta == null) {
      widget.messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Para pausa de almoço, defina o horário em que a loja volta a atender.',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          backgroundColor: const Color(0xFFE65100),
        ),
      );
      return;
    }

    Timestamp? ts;
    if (_motivoSel == PausaMotivoLoja.almoco && _volta != null) {
      final agora = DateTime.now();
      ts = Timestamp.fromDate(
        LojaPausa.proximaDataHoraVoltaAlmoco(
          _volta!.hour,
          _volta!.minute,
          agora,
        ),
      );
    }

    Navigator.of(context).pop(
      LojaPausaMotivoResult(motivo: _motivoSel, pausaVoltaAt: ts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final soft = Color.lerp(accent, Colors.white, 0.92)!;
    final border = Colors.grey.shade300;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Material(
        color: widget.surface,
        elevation: 12,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      soft,
                      widget.surface,
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(color: border.withValues(alpha: 0.35)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAUSAR PEDIDOS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: accent.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Motivo da pausa',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.grey.shade900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O cliente verá este motivo na vitrine. Para almoço, '
                      'a loja reabre automaticamente no horário indicado.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        height: 1.45,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OpcaoCard(
                      accent: accent,
                      selecionado: _motivoSel == PausaMotivoLoja.almoco,
                      icone: Icons.restaurant_rounded,
                      titulo: PausaMotivoLoja.labelPt(PausaMotivoLoja.almoco),
                      subtitulo:
                          'Defina quando volta a atender; a vitrine atualiza sozinha.',
                      onTap: () =>
                          setState(() => _motivoSel = PausaMotivoLoja.almoco),
                    ),
                    const SizedBox(height: 10),
                    _OpcaoCard(
                      accent: accent,
                      selecionado: _motivoSel == PausaMotivoLoja.temporario,
                      icone: Icons.pause_circle_outline_rounded,
                      titulo:
                          PausaMotivoLoja.labelPt(PausaMotivoLoja.temporario),
                      subtitulo:
                          'Pausa sem horário automático; reabra quando puder.',
                      onTap: () =>
                          setState(() => _motivoSel = PausaMotivoLoja.temporario),
                    ),
                    const SizedBox(height: 10),
                    _OpcaoCard(
                      accent: accent,
                      selecionado: _motivoSel == PausaMotivoLoja.manutencao,
                      icone: Icons.build_circle_outlined,
                      titulo:
                          PausaMotivoLoja.labelPt(PausaMotivoLoja.manutencao),
                      subtitulo: 'Informe que a loja voltará após a manutenção.',
                      onTap: () => setState(
                        () => _motivoSel = PausaMotivoLoja.manutencao,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _motivoSel == PausaMotivoLoja.almoco
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _BlocoHorario(
                                accent: accent,
                                soft: soft,
                                volta: _volta,
                                onTap: _escolherHora,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _confirmar,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Confirmar pausa',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.2,
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
    );
  }
}

class _OpcaoCard extends StatelessWidget {
  const _OpcaoCard({
    required this.accent,
    required this.selecionado,
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final Color accent;
  final bool selecionado;
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selecionado ? accent : Colors.grey.shade300,
              width: selecionado ? 2 : 1,
            ),
            color: selecionado
                ? accent.withValues(alpha: 0.07)
                : Colors.white,
            boxShadow: selecionado
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selecionado
                      ? accent.withValues(alpha: 0.14)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icone,
                  size: 22,
                  color: selecionado ? accent : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Colors.grey.shade900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.35,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selecionado
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('on'),
                        color: accent,
                        size: 26,
                      )
                    : const SizedBox(
                        key: ValueKey('off'),
                        width: 26,
                        height: 26,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlocoHorario extends StatelessWidget {
  const _BlocoHorario({
    required this.accent,
    required this.soft,
    required this.volta,
    required this.onTap,
  });

  final Color accent;
  final Color soft;
  final TimeOfDay? volta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final definido = volta != null;

    return Material(
      color: soft.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.schedule_rounded, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RETORNO PREVISTO',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: accent.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      definido
                          ? volta!.format(context)
                          : 'Toque para escolher o horário',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: definido ? 22 : 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: definido ? accent : Colors.grey.shade600,
                        height: 1.1,
                      ),
                    ),
                    if (!definido) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Ex.: 13:00 — a vitrine reabre nesse horário.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
