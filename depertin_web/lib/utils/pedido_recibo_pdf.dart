import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Geração e impressão do recibo do pedido no padrão iFood.
///
/// Gera um PDF em formato de bobina (80mm) que imprime bem em impressoras
/// térmicas 58mm/80mm e também em A4 (o navegador posiciona a tira no topo).
/// No web, [Printing.layoutPdf] abre a caixa de diálogo de impressão.
abstract final class PedidoReciboPdf {
  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _moeda(double v) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);

  static String _str(dynamic v) => (v ?? '').toString().trim();

  static String _qtd(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 1;
    return (n - n.round()).abs() < 0.001
        ? n.round().toString()
        : n.toStringAsFixed(1);
  }

  static String _formaPagamento(String forma) {
    switch (forma.toLowerCase()) {
      case 'pix':
        return 'PIX';
      case 'credito':
      case 'cartao_credito':
        return 'Cartao de Credito';
      case 'debito':
      case 'cartao_debito':
        return 'Cartao de Debito';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return forma.isEmpty ? '-' : forma;
    }
  }

  /// Imprime/baixa o recibo do pedido.
  ///
  /// [pedido] = dados do documento `pedidos/{id}`.
  /// [dadosLoja] = doc do usuário lojista (fallback de nome/endereço/telefone).
  static Future<void> imprimir({
    required String pedidoId,
    required String codigoPedido,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    String nomeClienteFallback = 'Cliente',
  }) async {
    await Printing.layoutPdf(
      name: 'Pedido $codigoPedido',
      onLayout: (_) => _construir(
        pedidoId: pedidoId,
        codigoPedido: codigoPedido,
        pedido: pedido,
        dadosLoja: dadosLoja,
        nomeClienteFallback: nomeClienteFallback,
      ),
    );
  }

  static Future<Uint8List> _construir({
    required String pedidoId,
    required String codigoPedido,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    required String nomeClienteFallback,
  }) async {
    final doc = pw.Document();

    final loja = dadosLoja ?? const {};
    final lojaNome = _str(pedido['loja_nome']).isNotEmpty
        ? _str(pedido['loja_nome'])
        : (_str(loja['nome_fantasia']).isNotEmpty
            ? _str(loja['nome_fantasia'])
            : (_str(loja['nome']).isNotEmpty ? _str(loja['nome']) : 'DiPertin'));
    final lojaEndereco = _str(pedido['loja_endereco']).isNotEmpty
        ? _str(pedido['loja_endereco'])
        : _str(loja['endereco']);
    final lojaTelefone = _str(pedido['loja_telefone']).isNotEmpty
        ? _str(pedido['loja_telefone'])
        : _str(loja['telefone']);

    final ts = pedido['data_pedido'];
    final DateTime? dataPedido = ts is Timestamp
        ? ts.toDate()
        : (ts is DateTime ? ts : null);
    final dataStr = dataPedido != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(dataPedido)
        : '-';

    final isRetirada = _str(pedido['tipo_entrega']) == 'retirada';
    final nomeCliente = _str(pedido['cliente_nome']).isNotEmpty
        ? _str(pedido['cliente_nome'])
        : nomeClienteFallback;
    final telefoneCliente = _str(pedido['cliente_telefone']).isNotEmpty
        ? _str(pedido['cliente_telefone'])
        : _str(pedido['cliente_fone']);
    final endereco = _str(pedido['endereco_entrega']);
    final obsPedido = _str(pedido['observacao']);

    final itens = pedido['itens'] as List? ?? const [];
    final subtotal = _num(pedido['subtotal']);
    final taxa = _num(pedido['taxa_entrega']);
    final desconto = _num(pedido['desconto_saldo']) +
        _num(pedido['desconto_cupom']) +
        _num(pedido['desconto']);
    final total = _num(pedido['total']);
    final forma = _formaPagamento(_str(pedido['forma_pagamento']));
    final agora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    final fonteBase = pw.Font.helvetica();
    final fonteBold = pw.Font.helveticaBold();

    pw.Widget linhaDivisoria() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Container(
            height: 0.7,
            color: PdfColors.grey600,
          ),
        );

    pw.Widget linhaValor(String label, String valor, {bool forte = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  font: forte ? fonteBold : fonteBase,
                  fontSize: forte ? 11 : 9,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              valor,
              style: pw.TextStyle(
                font: forte ? fonteBold : fonteBase,
                fontSize: forte ? 11 : 9,
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 6 * PdfPageFormat.mm,
          marginRight: 6 * PdfPageFormat.mm,
          marginTop: 8 * PdfPageFormat.mm,
          marginBottom: 8 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: fonteBase, bold: fonteBold),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho
              pw.Center(
                child: pw.Text(
                  lojaNome.toUpperCase(),
                  style: pw.TextStyle(font: fonteBold, fontSize: 14),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (lojaEndereco.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    lojaEndereco,
                    style: pw.TextStyle(font: fonteBase, fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              if (lojaTelefone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: $lojaTelefone',
                    style: pw.TextStyle(font: fonteBase, fontSize: 8),
                  ),
                ),
              linhaDivisoria(),

              // Identificação do pedido
              pw.Text(
                'PEDIDO $codigoPedido',
                style: pw.TextStyle(font: fonteBold, fontSize: 12),
              ),
              pw.Text(
                'Data: $dataStr',
                style: pw.TextStyle(font: fonteBase, fontSize: 9),
              ),
              pw.Text(
                isRetirada ? 'RETIRADA NO BALCAO' : 'ENTREGA',
                style: pw.TextStyle(font: fonteBold, fontSize: 9),
              ),
              linhaDivisoria(),

              // Cliente
              pw.Text(
                'CLIENTE',
                style: pw.TextStyle(font: fonteBold, fontSize: 9),
              ),
              pw.Text(nomeCliente,
                  style: pw.TextStyle(font: fonteBase, fontSize: 9)),
              if (telefoneCliente.isNotEmpty)
                pw.Text('Tel: $telefoneCliente',
                    style: pw.TextStyle(font: fonteBase, fontSize: 9)),
              if (!isRetirada && endereco.isNotEmpty)
                pw.Text(endereco,
                    style: pw.TextStyle(font: fonteBase, fontSize: 9)),
              linhaDivisoria(),

              // Itens
              pw.Text(
                'ITENS',
                style: pw.TextStyle(font: fonteBold, fontSize: 9),
              ),
              pw.SizedBox(height: 2),
              ...itens.map((raw) {
                if (raw is! Map) return pw.SizedBox();
                final m = Map<String, dynamic>.from(raw);
                final q = _qtd(m['quantidade'] ?? 1);
                final nome = _str(m['nome']).isNotEmpty ? _str(m['nome']) : '?';
                final pu = _num(m['preco'] ?? m['preco_unitario'] ?? m['valor']);
                final qn = m['quantidade'] is num
                    ? (m['quantidade'] as num).toDouble()
                    : double.tryParse('${m['quantidade']}') ?? 1;
                final comps = _str(m['complementos']).isNotEmpty
                    ? _str(m['complementos'])
                    : _str(m['complemento']);
                final obsItem = _str(m['observacao']).isNotEmpty
                    ? _str(m['observacao'])
                    : _str(m['obs']);
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              '${q}x $nome',
                              style: pw.TextStyle(font: fonteBase, fontSize: 9),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            _moeda(pu * qn),
                            style: pw.TextStyle(font: fonteBase, fontSize: 9),
                          ),
                        ],
                      ),
                      if (comps.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 10),
                          child: pw.Text(
                            comps,
                            style: pw.TextStyle(
                                font: fonteBase,
                                fontSize: 8,
                                color: PdfColors.grey700),
                          ),
                        ),
                      if (obsItem.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 10),
                          child: pw.Text(
                            'Obs: $obsItem',
                            style: pw.TextStyle(
                                font: fonteBase,
                                fontSize: 8,
                                color: PdfColors.grey700),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              linhaDivisoria(),

              // Resumo financeiro
              linhaValor('Subtotal', _moeda(subtotal)),
              if (!isRetirada && taxa > 0) linhaValor('Frete', _moeda(taxa)),
              if (desconto > 0) linhaValor('Desconto', '- ${_moeda(desconto)}'),
              pw.SizedBox(height: 2),
              linhaValor('TOTAL', _moeda(total), forte: true),
              pw.SizedBox(height: 2),
              linhaValor('Pagamento', forma),
              if (pedido['valor_recebido'] != null) ...[
                linhaValor('Valor Recebido', _moeda(_num(pedido['valor_recebido']))),
                linhaValor('Troco', _moeda(_num(pedido['troco']))),
              ],
              if (obsPedido.isNotEmpty) ...[
                linhaDivisoria(),
                pw.Text('OBSERVACOES',
                    style: pw.TextStyle(font: fonteBold, fontSize: 9)),
                pw.Text(obsPedido,
                    style: pw.TextStyle(font: fonteBase, fontSize: 9)),
              ],
              linhaDivisoria(),

              // Rodapé
              pw.Center(
                child: pw.Text(
                  'Pedido realizado atraves do DiPertin',
                  style: pw.TextStyle(font: fonteBase, fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Impresso em $agora',
                  style: pw.TextStyle(
                      font: fonteBase, fontSize: 7, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
