import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

enum LojistaEdicaoTipo { loja, cliente }

/// Modal inicial: escolher edição de loja ou de perfil pessoal (cliente).
Future<LojistaEdicaoTipo?> showLojistaEscolherEdicaoDialog(
  BuildContext context, {
  String? tituloLoja,
  String? subtituloPessoa,
}) {
  return showGeneralDialog<LojistaEdicaoTipo>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: _LojistaEscolherEdicaoBody(
            tituloLoja: tituloLoja,
            subtituloPessoa: subtituloPessoa,
          ),
        ),
      );
    },
  );
}

class _LojistaEscolherEdicaoBody extends StatelessWidget {
  const _LojistaEscolherEdicaoBody({
    this.tituloLoja,
    this.subtituloPessoa,
  });

  final String? tituloLoja;
  final String? subtituloPessoa;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final maxW = mq.width < 520 ? mq.width - 28.0 : 480.0;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: PainelAdminTheme.roxo.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 22, 16, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        PainelAdminTheme.roxo,
                        Color(0xFF8E24AA),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Como deseja editar?',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Os dados da loja e do perfil pessoal são salvos '
                              'separadamente — uma edição não altera a outra.',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  child: Column(
                    children: [
                      _OpcaoEdicaoCard(
                        icone: Icons.storefront_rounded,
                        cor: PainelAdminTheme.laranja,
                        titulo: 'Editar como Lojista',
                        subtitulo:
                            'Configurações da loja: nome, endereço, horários, '
                            'tipos de entrega e pausa.',
                        detalhe: tituloLoja?.trim().isNotEmpty == true
                            ? tituloLoja!.trim()
                            : 'Dados comerciais e operacionais',
                        onTap: () =>
                            Navigator.pop(context, LojistaEdicaoTipo.loja),
                      ),
                      const SizedBox(height: 14),
                      _OpcaoEdicaoCard(
                        icone: Icons.person_outline_rounded,
                        cor: PainelAdminTheme.roxo,
                        titulo: 'Editar como Cliente',
                        subtitulo:
                            'Perfil pessoal: nome, telefone, CPF, foto e '
                            'endereço de entrega padrão.',
                        detalhe: subtituloPessoa?.trim().isNotEmpty == true
                            ? subtituloPessoa!.trim()
                            : 'Dados da conta pessoal',
                        onTap: () =>
                            Navigator.pop(context, LojistaEdicaoTipo.cliente),
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

class _OpcaoEdicaoCard extends StatefulWidget {
  const _OpcaoEdicaoCard({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.detalhe,
    required this.onTap,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final String detalhe;
  final VoidCallback onTap;

  @override
  State<_OpcaoEdicaoCard> createState() => _OpcaoEdicaoCardState();
}

class _OpcaoEdicaoCardState extends State<_OpcaoEdicaoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover
            ? widget.cor.withValues(alpha: 0.06)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hover
                    ? widget.cor.withValues(alpha: 0.55)
                    : const Color(0xFFE2E8F0),
                width: _hover ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.cor,
                        widget.cor.withValues(alpha: 0.75),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: widget.cor.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(widget.icone, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: PainelAdminTheme.textoSecundario,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.detalhe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.cor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: widget.cor.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
