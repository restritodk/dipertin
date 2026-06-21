import 'dart:convert';
import 'dart:html' as html;

void downloadCsvFile(String conteudo, String filename) {
  // BOM UTF-8 para o Excel reconhecer acentos corretamente.
  final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(conteudo)];
  final blob = html.Blob(<dynamic>[bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
