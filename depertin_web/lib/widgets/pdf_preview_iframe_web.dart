import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/painel_admin_theme.dart';

Widget buildPdfPreview(String url, {double height = 340}) {
  return _PdfIframeEmbed(url: url, height: height);
}

Future<void> showPdfFullscreenDialog(
  BuildContext context,
  String url,
  String titulo,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog.fullscreen(
        backgroundColor: const Color(0xFF0F172A),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 48),
                child: _PdfIframeEmbed(url: url, height: null),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.72),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded,
                              color: Colors.white),
                          tooltip: 'Abrir em nova aba',
                          onPressed: () => launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PdfIframeEmbed extends StatefulWidget {
  const _PdfIframeEmbed({required this.url, this.height = 340});

  final String url;
  final double? height;

  @override
  State<_PdfIframeEmbed> createState() => _PdfIframeEmbedState();
}

class _PdfIframeEmbedState extends State<_PdfIframeEmbed> {
  late final String _viewType;
  html.IFrameElement? _iframe;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _viewType =
        'pdf-embed-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final initialUrl = _pdfUrlForIframe(widget.url);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) {
        final iframe = html.IFrameElement()
          ..src = initialUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.display = 'block'
          ..allowFullscreen = true;

        iframe.onLoad.listen((_) {
          if (mounted) setState(() => _loaded = true);
        });

        _iframe = iframe;
        return iframe;
      },
    );
  }

  @override
  void didUpdateWidget(covariant _PdfIframeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _iframe != null) {
      setState(() => _loaded = false);
      _iframe!.src = _pdfUrlForIframe(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.height != null
        ? SizedBox(
            height: widget.height,
            width: double.infinity,
            child: HtmlElementView(viewType: _viewType),
          )
        : SizedBox.expand(
            child: HtmlElementView(viewType: _viewType),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          if (!_loaded)
            Positioned.fill(
              child: Container(
                color: const Color(0xFFF1F5F9),
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: PainelAdminTheme.roxo,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// URL direta ao PDF. Opcional: visualizador Google para URLs públicas com bloqueio de iframe.
String _pdfUrlForIframe(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null) return raw;
  if (u.hasScheme && (u.scheme == 'http' || u.scheme == 'https')) {
    return raw;
  }
  return raw;
}
