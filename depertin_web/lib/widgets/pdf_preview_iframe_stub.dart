import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/painel_admin_theme.dart';

/// Fora do web: mensagem + abrir no navegador ao usar tela cheia.
Widget buildPdfPreview(String url, {double height = 340}) {
  return Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(18),
    child: Text(
      'Pré-visualização de PDF integrada está disponível apenas no painel web.',
      textAlign: TextAlign.center,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        height: 1.45,
        color: PainelAdminTheme.textoSecundario,
      ),
    ),
  );
}

Future<void> showPdfFullscreenDialog(
  BuildContext context,
  String url,
  String titulo,
) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
