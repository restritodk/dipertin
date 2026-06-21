import 'csv_download_stub.dart'
    if (dart.library.html) 'csv_download_web.dart' as impl;

/// Monta uma linha CSV escapando aspas/; conforme RFC 4180.
String _csvCampo(Object? valor) {
  final s = (valor ?? '').toString();
  final precisaAspas =
      s.contains('"') || s.contains(',') || s.contains('\n') || s.contains(';');
  final escapado = s.replaceAll('"', '""');
  return precisaAspas ? '"$escapado"' : escapado;
}

/// Gera o conteúdo CSV a partir do cabeçalho e das linhas.
String montarCsv(List<String> cabecalho, List<List<Object?>> linhas) {
  final buffer = StringBuffer();
  buffer.writeln(cabecalho.map(_csvCampo).join(','));
  for (final linha in linhas) {
    buffer.writeln(linha.map(_csvCampo).join(','));
  }
  return buffer.toString();
}

/// Faz o download de um arquivo `.csv` no browser; no-op em outras plataformas.
void downloadCsvFile(String conteudo, String filename) {
  impl.downloadCsvFile(conteudo, filename);
}

/// Conveniência: monta o CSV e dispara o download.
void exportarCsv({
  required List<String> cabecalho,
  required List<List<Object?>> linhas,
  required String filename,
}) {
  downloadCsvFile(montarCsv(cabecalho, linhas), filename);
}
