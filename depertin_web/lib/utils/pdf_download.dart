import 'dart:typed_data';

import 'pdf_download_stub.dart'
    if (dart.library.html) 'pdf_download_web.dart' as impl;

/// Download do PDF no browser; em outras plataformas é no-op (use [Printing]).
void downloadPdfFile(Uint8List bytes, String filename) {
  impl.downloadPdfFile(bytes, filename);
}
