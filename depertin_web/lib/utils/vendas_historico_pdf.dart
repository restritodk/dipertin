import 'dart:typed_data';

import 'package:depertin_web/models/venda_historico_model.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;

final PdfColor _brand = PdfColor.fromInt(0xFF6A1B9A);
final PdfColor _brandDark = PdfColor.fromInt(0xFF4A0072);
final PdfColor _ink = PdfColor.fromInt(0xFF111827);
final PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
final PdfColor _bgCard = PdfColor.fromInt(0xFFF9FAFB);
final PdfColor _zebra = PdfColor.fromInt(0xFFF3F4F6);
final PdfColor _green = PdfColor.fromInt(0xFF16A34A);
final PdfColor _lightGreen = PdfColor.fromInt(0xFFE8F5E9);
final PdfColor _orange = PdfColor.fromInt(0xFFFF8F00);
final PdfColor _lightOrange = PdfColor.fromInt(0xFFFFF3E0);
final PdfColor _red = PdfColor.fromInt(0xFFDC2626);
final PdfColor _lightRed = PdfColor.fromInt(0xFFFEE2E2);
final PdfColor _gray = PdfColor.fromInt(0xFF6B7280);
final PdfColor _lightGray = PdfColor.fromInt(0xFFF3F4F6);

/// Gera PDF premium do relatório de histórico de vendas.
Future<Uint8List> gerarVendasHistoricoPdf({
  required String nomeLoja,
  required String cnpjCpf,
  required String endereco,
  required String telefone,
  required String email,
  required String responsavel,
  required DateTime dataInicio,
  required DateTime dataFim,
  required List<VendaHistorico> vendas,
  required VendasHistoricoResumo resumo,
  required DateTime geradoEm,
}) async {
  final fontBase = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();
  final theme = pw.ThemeData.withFont(
    base: fontBase,
    bold: fontBold,
  );

  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dfD = DateFormat('dd/MM/yyyy');
  final dfH = DateFormat("dd/MM/yyyy 'às' HH:mm");
  final geradoEmStr = dfH.format(geradoEm);
  final periodoStr =
      '${dfD.format(dataInicio)} até ${dfD.format(dataFim)}';

  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      header: (ctx) => _buildHeader(ctx),
      footer: (ctx) => _buildFooter(ctx, geradoEmStr),
      build: (ctx) => [
        // Faixa roxa superior
        pw.Container(
          width: double.infinity,
          height: 18,
          decoration: pw.BoxDecoration(
            color: _brand,
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(4),
              topRight: pw.Radius.circular(4),
            ),
          ),
        ),
        pw.SizedBox(height: 16),

        // Header da loja + badge relatório
        _buildLojaHeader(
          nomeLoja: nomeLoja,
          cnpjCpf: cnpjCpf,
          endereco: endereco,
          telefone: telefone,
          email: email,
          responsavel: responsavel,
        ),
        pw.SizedBox(height: 16),

        // Divider sutil
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 12),

        // Título do relatório
        pw.Text(
          'Relatório de Histórico de Vendas',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _brandDark,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Período: $periodoStr',
          style: pw.TextStyle(fontSize: 10, color: _muted),
        ),
        pw.Text(
          'Gerado em: $geradoEmStr',
          style: pw.TextStyle(fontSize: 10, color: _muted),
        ),
        pw.SizedBox(height: 20),

        // Cards de resumo premium
        _buildResumoCards(resumo: resumo, moeda: moeda),
        pw.SizedBox(height: 22),

        // Tabela de vendas
        if (vendas.isNotEmpty) ...[
          pw.Text(
            'Vendas do Período',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 10),
          _buildTabelaVendas(vendas, moeda, dfD),
        ] else ...[
          pw.Center(
            child: pw.Text(
              'Nenhuma venda encontrada no período.',
              style: pw.TextStyle(fontSize: 11, color: _muted),
            ),
          ),
        ],
      ],
    ),
  );

  return pdf.save();
}

// ─── HEADER (faixa roxa) ─────────────────────────────────────────────
pw.Widget _buildHeader(pw.Context ctx) {
  return pw.Container(
    width: double.infinity,
    height: 3,
    margin: const pw.EdgeInsets.only(bottom: 10),
    decoration: pw.BoxDecoration(
      color: _brand,
      borderRadius: pw.BorderRadius.circular(1.5),
    ),
  );
}

// ─── LOJA HEADER + BADGE ─────────────────────────────────────────────
pw.Widget _buildLojaHeader({
  required String nomeLoja,
  required String cnpjCpf,
  required String endereco,
  required String telefone,
  required String email,
  required String responsavel,
}) {
  // Dados da loja (lado esquerdo)
  final lojaInfo = <pw.Widget>[
    pw.Text(
      nomeLoja.isNotEmpty ? nomeLoja : 'Minha Loja',
      style: pw.TextStyle(
        fontSize: 20,
        fontWeight: pw.FontWeight.bold,
        color: _brand,
      ),
    ),
  ];

  void addInfo(String label, String value) {
    if (value.isNotEmpty) {
      lojaInfo.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            '$label: $value',
            style: pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ),
      );
    }
  }

  addInfo('CNPJ/CPF', cnpjCpf);
  if (endereco.isNotEmpty) {
    lojaInfo.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(
          endereco,
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
    );
  }
  addInfo('E-mail', email);
  addInfo('Telefone', telefone);
  addInfo('Responsável', responsavel);

  // Badge "Relatório" (lado direito)
  final badge = pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: pw.BoxDecoration(
      color: _bgCard,
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          'Relatório',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _muted,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Histórico de Vendas',
          style: pw.TextStyle(
            fontSize: 8,
            color: _brand,
          ),
        ),
      ],
    ),
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: lojaInfo,
        ),
      ),
      pw.SizedBox(width: 20),
      badge,
    ],
  );
}

// ─── CARDS DE RESUMO PREMIUM ─────────────────────────────────────────
pw.Widget _buildResumoCards({
  required VendasHistoricoResumo resumo,
  required NumberFormat moeda,
}) {
  final cards = [
    _resumoCard('Total vendido', moeda.format(resumo.totalVendido), _brand),
    _resumoCard('Total pago', moeda.format(resumo.vendasPagas), _green),
    _resumoCard(
        'Total pendente', moeda.format(resumo.vendasPendentes), _orange),
    _resumoCard('Qtd. vendas', '${resumo.quantidadeVendas}', _brand),
    _resumoCard('Ticket médio', moeda.format(resumo.ticketMedio), _brand),
  ];

  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: cards
        .map((card) => pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 6),
                child: card,
              ),
            ))
        .toList(),
  );
}

pw.Widget _resumoCard(String label, String valor, PdfColor cor) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _bgCard,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: _muted,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: cor,
          ),
        ),
      ],
    ),
  );
}

// ─── TABELA PROFISSIONAL ─────────────────────────────────────────────
pw.Widget _buildTabelaVendas(
  List<VendaHistorico> vendas,
  NumberFormat moeda,
  DateFormat dfD,
) {
  // Cabeçalhos
  final headers = [
    _cellHeader('Código'),
    _cellHeader('Cliente'),
    _cellHeader('Data'),
    _cellHeader('Forma pag.'),
    _cellHeader('Valor total', align: pw.Alignment.centerRight),
    _cellHeader('Valor pago', align: pw.Alignment.centerRight),
    _cellHeader('Valor pend.', align: pw.Alignment.centerRight),
    _cellHeader('Status', align: pw.Alignment.center),
  ];

  // Linhas
  final rows = vendas.asMap().entries.map((entry) {
    final i = entry.key;
    final v = entry.value;
    final isOdd = i % 2 == 1;

    return [
      _cellData(v.codigoExibicao, isOdd: isOdd, fontWeight: pw.FontWeight.bold),
      _cellData(_nomeCliente(v), isOdd: isOdd, fontSize: 8),
      _cellData(v.dataVenda != null ? dfD.format(v.dataVenda!) : '—',
          isOdd: isOdd),
      _cellData(v.formaPagamentoExibicao, isOdd: isOdd),
      _cellData(moeda.format(v.valorTotal),
          isOdd: isOdd, align: pw.Alignment.centerRight),
      _cellData(moeda.format(v.valorPago),
          isOdd: isOdd,
          align: pw.Alignment.centerRight,
          color: v.valorPago > 0 ? _green : null),
      _cellData(moeda.format(v.valorPendente),
          isOdd: isOdd,
          align: pw.Alignment.centerRight,
          color: v.valorPendente > 0 ? _red : null),
      _statusCell(v.statusExibicao, v.status, isOdd: isOdd),
    ];
  }).toList();

  return pw.Table(
    border: pw.TableBorder(
      horizontalInside:
          pw.BorderSide(color: PdfColors.grey200, width: 0.3),
      bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.3),
    ),
    columnWidths: {
      0: const pw.FixedColumnWidth(56),
      1: const pw.FlexColumnWidth(),
      2: const pw.FixedColumnWidth(52),
      3: const pw.FixedColumnWidth(58),
      4: const pw.FixedColumnWidth(52),
      5: const pw.FixedColumnWidth(48),
      6: const pw.FixedColumnWidth(48),
      7: const pw.FixedColumnWidth(44),
    },
    children: [
      // Cabeçalho
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _brand),
        children: headers,
      ),
      // Dados
      ...rows.map((cells) => pw.TableRow(children: cells)),
    ],
  );
}

pw.Widget _cellHeader(String text,
    {pw.Alignment align = pw.Alignment.centerLeft}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    alignment: align,
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
    ),
  );
}

pw.Widget _cellData(
  String text, {
  bool isOdd = false,
  pw.Alignment align = pw.Alignment.centerLeft,
  PdfColor? color,
  double fontSize = 7.5,
  pw.FontWeight? fontWeight,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    alignment: align,
    decoration: pw.BoxDecoration(
      color: isOdd ? _zebra : PdfColors.white,
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: fontSize,
        color: color ?? _ink,
        fontWeight: fontWeight,
      ),
    ),
  );
}

pw.Widget _statusCell(String label, String? status,
    {bool isOdd = false}) {
  PdfColor cor;
  PdfColor bgCor;
    switch (status) {
      case 'pago':
        cor = _green;
        bgCor = _lightGreen;
        break;
      case 'parcial':
        cor = _orange;
        bgCor = _lightOrange;
        break;
      case 'pendente':
        cor = _red;
        bgCor = _lightRed;
        break;
      case 'cancelado':
        cor = _gray;
        bgCor = _lightGray;
        break;
      default:
        cor = _gray;
        bgCor = _lightGray;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: isOdd ? _zebra : PdfColors.white,
      ),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(
          color: bgCor,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: cor,
        ),
      ),
    ),
  );
}

/// Nome do cliente para exibição, quebrando se necessário.
String _nomeCliente(VendaHistorico v) {
  if (v.clienteNome == null || v.clienteNome!.isEmpty) return '—';
  return v.clienteNome!;
}

// ─── FOOTER (todas as páginas) ───────────────────────────────────────
pw.Widget _buildFooter(pw.Context ctx, String geradoEmStr) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 2,
              child: pw.UrlLink(
                destination: 'https://www.dipertin.com.br',
                child: pw.Text(
                  'Sistema: https://www.dipertin.com.br',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColor.fromInt(0xFF1D4ED8),
                    decoration: pw.TextDecoration.underline,
                    decorationColor: PdfColor.fromInt(0xFF1D4ED8),
                  ),
                ),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                'Relatório gerado automaticamente pelo DiPertin Gestão Comercial.',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: _muted,
                  fontStyle: pw.FontStyle.italic,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                'Gerado em: $geradoEmStr',
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 7.5, color: _muted),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ),
  );
}
