import 'dart:typed_data';

import 'package:depertin_web/services/carteira_lojista_extrato.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;

/// Cores da marca (alinhadas ao painel) — [PdfColor] para o pacote `pdf`.
final PdfColor _brand = PdfColor.fromInt(0xFF6A1B9A);
final PdfColor _brandSoft = PdfColor.fromInt(0xFFF3E8F8);
final PdfColor _ink = PdfColor.fromInt(0xFF111827);
final PdfColor _muted = PdfColor.fromInt(0xFF6B7280);

/// Gera PDF do relatório financeiro (mesmos dados da tela).
/// Usa Noto Sans (via [PdfGoogleFonts]) para suportar pt-BR e traços Unicode.
Future<Uint8List> gerarCarteiraFinanceiroPdf({
  required String nomeLoja,
  required String periodoLabel,
  required double saldoAtual,
  required CarteiraFinanceiroResumo resumo,
  required List<CarteiraLancamento> lancamentos,
  required DateTime geradoEm,
}) async {
  final fontBase = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final theme = pw.ThemeData.withFont(
    base: fontBase,
    bold: fontBold,
  );

  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dfH = DateFormat('dd/MM/yyyy HH:mm');
  final dfD = DateFormat('dd/MM/yyyy');

  String trunc(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      header: (ctx) => pw.Container(
        width: double.infinity,
        height: 3,
        margin: const pw.EdgeInsets.only(bottom: 14),
        decoration: pw.BoxDecoration(
          color: _brand,
          borderRadius: pw.BorderRadius.circular(1.5),
        ),
      ),
      footer: (ctx) => _pdfFooter(ctx),
      build: (ctx) => [
        _pdfHero(
          nomeLoja: nomeLoja,
          periodoLabel: periodoLabel,
          saldoAtual: moeda.format(saldoAtual),
          emitidoEm: dfH.format(geradoEm),
        ),
        pw.SizedBox(height: 22),
        pw.Text(
          'Totais do período',
          style: pw.TextStyle(
            fontSize: 11.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey50,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _linhaResumo('Entradas', moeda.format(resumo.entradas)),
              _linhaResumo('Saídas', moeda.format(resumo.saidas)),
              _linhaResumo('Líquido (entradas − saídas)', moeda.format(resumo.liquido)),
              _linhaResumo('Lançamentos', '${resumo.qLancamentos}'),
              _linhaResumo('Vendas creditadas (quantidade)', '${resumo.qVendasCreditadas}'),
              if (resumo.ticketMedioVendas != null)
                _linhaResumo(
                  'Ticket médio (vendas creditadas)',
                  moeda.format(resumo.ticketMedioVendas!),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 22),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Movimentações',
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.Text(
              '${lancamentos.length} registro(s)',
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.35),
            verticalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.35),
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.75),
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.75),
            left: pw.BorderSide(color: PdfColors.grey400, width: 0.75),
            right: pw.BorderSide(color: PdfColors.grey400, width: 0.75),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.15),
            1: const pw.FlexColumnWidth(0.75),
            2: const pw.FlexColumnWidth(3.1),
            3: const pw.FlexColumnWidth(1.05),
            4: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: _brandSoft,
                border: pw.Border(
                  bottom: pw.BorderSide(color: _brand, width: 1),
                ),
              ),
              children: [
                _cellH('Data'),
                _cellH('Tipo'),
                _cellH('Descrição'),
                _cellH('Valor', align: pw.TextAlign.right),
                _cellH('Status'),
              ],
            ),
            for (var i = 0; i < lancamentos.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? PdfColors.white : PdfColors.grey100,
                ),
                children: [
                  _cell(dfD.format(lancamentos[i].data)),
                  _cell(lancamentos[i].entrada ? 'Entrada' : 'Saída'),
                  _cell(trunc('${lancamentos[i].titulo} — ${lancamentos[i].subtitulo}', 72)),
                  _cell(
                    moeda.format(lancamentos[i].valor),
                    align: pw.TextAlign.right,
                    bold: true,
                  ),
                  _cell(trunc(_statusLabelPt(lancamentos[i].status), 22)),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _pdfFooter(pw.Context ctx) {
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Divider(color: PdfColors.grey300, thickness: 0.5),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.UrlLink(
            destination: 'https://www.dipertin.com.br',
            child: pw.Text(
              'www.dipertin.com.br',
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromInt(0xFF1D4ED8),
                decoration: pw.TextDecoration.underline,
                decorationColor: PdfColor.fromInt(0xFF1D4ED8),
              ),
            ),
          ),
          pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _pdfHero({
  required String nomeLoja,
  required String periodoLabel,
  required String saldoAtual,
  required String emitidoEm,
}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(
        colors: [_brandSoft, PdfColors.white],
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
      ),
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: PdfColor.fromInt(0xFFE9D5FF), width: 0.75),
      boxShadow: [
        pw.BoxShadow(
          color: PdfColors.grey400,
          blurRadius: 6,
          offset: const PdfPoint(0, 2),
        ),
      ],
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DiPertin',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _brand,
            letterSpacing: 0.8,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Relatório financeiro da sua loja',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Extrato consolidado e totais do período selecionado.',
          style: pw.TextStyle(fontSize: 9.5, color: _muted, height: 1.35),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.only(top: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _metaLinha('Loja', nomeLoja),
              pw.SizedBox(height: 6),
              _metaLinha('Período', periodoLabel),
              pw.SizedBox(height: 6),
              _metaLinha('Saldo atual na carteira', saldoAtual, destaque: true),
              pw.SizedBox(height: 6),
              _metaLinha('Documento emitido em', emitidoEm),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _metaLinha(String rotulo, String valor, {bool destaque = false}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 148,
        child: pw.Text(
          rotulo,
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: destaque ? 11 : 9.5,
            fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: destaque ? _brand : _ink,
          ),
        ),
      ),
    ],
  );
}

String _statusLabelPt(String status) {
  switch (status) {
    case 'pago':
      return 'Pago';
    case 'recusado':
      return 'Recusado';
    case 'pendente':
      return 'Pendente';
    case 'concluido':
      return 'Creditado';
    case 'estornado':
      return 'Estornado';
    case 'estorno_pix_credito':
      return 'Crédito estorno';
    default:
      return status;
  }
}

pw.Widget _linhaResumo(String rotulo, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            rotulo,
            style: pw.TextStyle(fontSize: 9.5, color: _ink),
          ),
        ),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: 9.5,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _cellH(String t, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        t,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    );

pw.Widget _cell(
  String t, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        t,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: _ink,
        ),
      ),
    );
