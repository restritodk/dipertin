import 'dart:typed_data';

import 'package:depertin_web/models/comercial_credito.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF / impressão do comprovante de recebimento de parcela.
abstract final class ComercialRecebimentoComprovantePdf {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _dataHora = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  static Future<void> imprimir(ComercialRecebimentoResult r) async {
    await Printing.layoutPdf(
      name: 'Recebimento ${r.parcela.codigoVenda}',
      onLayout: (_) => _build(r),
    );
  }

  static Future<void> baixarPdf(ComercialRecebimentoResult r) async {
    final bytes = await _build(r);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'recebimento_${r.recebimentoId}.pdf',
    );
  }

  static Future<Uint8List> _build(ComercialRecebimentoResult r) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    String fmtCpf(String? cpf) {
      if (cpf == null || cpf.isEmpty) return '—';
      final d = cpf.replaceAll(RegExp(r'\D'), '');
      if (d.length != 11) return cpf;
      return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(12),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              r.lojaNome.toUpperCase(),
              style: pw.TextStyle(font: fontBold, fontSize: 12),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'COMPROVANTE DE RECEBIMENTO',
              style: pw.TextStyle(font: fontBold, fontSize: 10),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(thickness: 0.5),
            pw.Text('Cliente: ${r.clienteNome}', style: pw.TextStyle(font: font, fontSize: 9)),
            pw.Text('CPF: ${fmtCpf(r.clienteCpf)}', style: pw.TextStyle(font: font, fontSize: 9)),
            if (r.clienteTelefone != null)
              pw.Text('Tel: ${r.clienteTelefone}', style: pw.TextStyle(font: font, fontSize: 9)),
            pw.SizedBox(height: 8),
            pw.Text('Venda: ${r.parcela.codigoVenda}', style: pw.TextStyle(font: fontBold, fontSize: 9)),
            pw.Text(
              'Parcela ${r.parcela.numeroParcela}',
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Valor pago:', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.Text(_moeda.format(r.valorPago), style: pw.TextStyle(font: fontBold, fontSize: 10)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Forma:', style: pw.TextStyle(font: font, fontSize: 9)),
                pw.Text(r.formaPagamento, style: pw.TextStyle(font: font, fontSize: 9)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Restante:', style: pw.TextStyle(font: font, fontSize: 9)),
                pw.Text(_moeda.format(r.valorRestante), style: pw.TextStyle(font: font, fontSize: 9)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _dataHora.format(r.dataPagamento),
              style: pw.TextStyle(font: font, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Operador: ${r.usuarioNome}',
              style: pw.TextStyle(font: font, fontSize: 8),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              '_____________________________',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 8),
            ),
            pw.Text(
              'Assinatura / identificação',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 7),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
