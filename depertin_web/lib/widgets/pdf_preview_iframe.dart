import 'package:flutter/widgets.dart';

import 'pdf_preview_iframe_stub.dart'
    if (dart.library.html) 'pdf_preview_iframe_web.dart' as impl;

/// Pré-visualização de PDF embutida (iframe no web). Em outras plataformas, mensagem informativa.
Widget buildPdfPreview(String url, {double height = 340}) {
  return impl.buildPdfPreview(url, height: height);
}

Future<void> showPdfFullscreenDialog(
  BuildContext context,
  String url,
  String titulo,
) {
  return impl.showPdfFullscreenDialog(context, url, titulo);
}
