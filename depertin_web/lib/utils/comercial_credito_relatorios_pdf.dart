import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/services/comercial_credito_relatorios_service.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;

final PdfColor _roxo = PdfColor.fromInt(0xFF6A1B9A);
final PdfColor _roxoEscuro = PdfColor.fromInt(0xFF4A148C);
final PdfColor _laranja = PdfColor.fromInt(0xFFFF8F00);
final PdfColor _texto = PdfColor.fromInt(0xFF1A1A2E);
final PdfColor _muted = PdfColor.fromInt(0xFF64748B);
final PdfColor _fundoCard = PdfColor.fromInt(0xFFF8F6FF);
final PdfColor _zebra = PdfColor.fromInt(0xFFF5F4F8);
final PdfColor _borda = PdfColor.fromInt(0xFFE2E8F0);

/// Gera PDFs premium dos relatórios de Crédito de Clientes (DiPertin).
abstract final class ComercialCreditoRelatoriosPdf {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _df = DateFormat('dd/MM/yyyy');
  static final _dfH = DateFormat('dd/MM/yyyy HH:mm');
  static final _dfRodape = DateFormat("dd/MM/yyyy 'às' HH:mm");

  static Future<Uint8List> clientes({
    required String nomeLoja,
    required List<ComercialCliente> clientes,
    required Map<String, int> parcelasAbertas,
    required Map<String, double> atrasoPorCliente,
    required CreditoRelatorioClientesResumo resumo,
    required DateTime geradoEm,
    String? periodoAplicado,
  }) async {
    final theme = await _theme();
    final geradoStr = _dfRodape.format(geradoEm);
    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (ctx) => _cabecalho(
          nomeLoja: nomeLoja,
          titulo: 'Relatório de Clientes com Crédito',
          periodo: periodoAplicado,
          geradoEm: geradoEm,
        ),
        footer: (ctx) => _rodape(ctx, geradoStr),
        build: (ctx) => [
          _cardsResumo([
            ('Clientes com crédito', '${resumo.totalClientes}', false),
            ('Limite total', _moeda.format(resumo.limiteTotal), false),
            ('Utilizado', _moeda.format(resumo.utilizado), false),
            ('Disponível', _moeda.format(resumo.disponivel), true),
            ('Em atraso', _moeda.format(resumo.emAtraso), false),
          ]),
          pw.SizedBox(height: 16),
          _tituloSecao('Lista de clientes'),
          pw.SizedBox(height: 8),
          _tabela(
            headers: const [
              'Cliente',
              'CPF/CNPJ',
              'Telefone',
              'Limite',
              'Utilizado',
              'Disponível',
              'Em atraso',
              'Parc. abertas',
              'Status',
              'Última compra',
            ],
            rows: clientes.map((c) {
              final st = c.statusExibicao.replaceAll('_', ' ');
              return [
                c.nome,
                ComercialCreditoRelatoriosService.mascararDocumento(c.cpf),
                ComercialCreditoRelatoriosService.mascararTelefone(c.telefone),
                _moeda.format(c.limiteCredito),
                _moeda.format(c.creditoUtilizado),
                _moeda.format(c.creditoDisponivel.clamp(0, double.infinity)),
                _moeda.format(atrasoPorCliente[c.id] ?? 0),
                '${parcelasAbertas[c.id] ?? 0}',
                st.isEmpty ? '—' : '${st[0].toUpperCase()}${st.substring(1)}',
                c.ultimaCompra != null ? _df.format(c.ultimaCompra!) : '—',
              ];
            }).toList(),
            colFlex: const [3, 2, 1.5, 1.4, 1.4, 1.4, 1.4, 1.1, 1.4, 1.4],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Gerado em ${_dfH.format(geradoEm)}',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> pendencias({
    required String nomeLoja,
    required List<CreditoRelatorioPendenciaLinha> linhas,
    required CreditoRelatorioPendenciasResumo resumo,
    required DateTime geradoEm,
    String? periodoAplicado,
  }) async {
    final theme = await _theme();
    final geradoStr = _dfRodape.format(geradoEm);
    final pdf = pw.Document(theme: theme);

    final totalPorCliente = <String, double>{};
    for (final l in linhas) {
      final v = l.encargos.valorAtualizado > 0
          ? l.encargos.valorAtualizado
          : l.parcela.valorEmAberto;
      totalPorCliente[l.cliente.id] = (totalPorCliente[l.cliente.id] ?? 0) + v;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (ctx) => _cabecalho(
          nomeLoja: nomeLoja,
          titulo: 'Relatório de Pendências / Inadimplência',
          periodo: periodoAplicado,
          geradoEm: geradoEm,
        ),
        footer: (ctx) => _rodape(ctx, geradoStr),
        build: (ctx) => [
          _cardsResumo([
            ('Clientes inadimplentes', '${resumo.qtdClientes}', false),
            ('Parcelas vencidas', '${resumo.qtdParcelas}', false),
            ('Valor original', _moeda.format(resumo.valorOriginal), false),
            ('Juros e multas', _moeda.format(resumo.jurosMultas), false),
            ('Total atualizado', _moeda.format(resumo.valorAtualizado), true),
          ]),
          pw.SizedBox(height: 16),
          _tituloSecao('Parcelas em atraso'),
          pw.SizedBox(height: 8),
          _tabela(
            headers: const [
              'Cliente',
              'CPF/CNPJ',
              'Telefone',
              'Parcela',
              'Vencimento',
              'Original',
              'Dias atraso',
              'Juros',
              'Multa',
              'Atualizado',
              'Total dívida',
            ],
            rows: linhas.map((l) {
              final atual = l.encargos.valorAtualizado > 0
                  ? l.encargos.valorAtualizado
                  : l.parcela.valorEmAberto;
              return [
                l.cliente.nome,
                ComercialCreditoRelatoriosService.mascararDocumento(
                  l.cliente.cpf,
                ),
                ComercialCreditoRelatoriosService.mascararTelefone(
                  l.cliente.telefone,
                ),
                '${l.parcela.numeroParcela}/${l.parcela.codigoVenda}',
                _df.format(l.parcela.dataVencimento),
                _moeda.format(l.parcela.valorEmAberto),
                '${l.encargos.diasEmAtraso}',
                _moeda.format(l.encargos.juros),
                _moeda.format(l.encargos.multa),
                _moeda.format(atual),
                _moeda.format(totalPorCliente[l.cliente.id] ?? atual),
              ];
            }).toList(),
            colFlex: const [2.4, 1.6, 1.2, 1.4, 1.2, 1.2, 1, 1.1, 1.1, 1.2, 1.3],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> vendas({
    required String nomeLoja,
    required ComercialCliente cliente,
    required List<ComercialClienteLancamento> vendas,
    required CreditoRelatorioVendasResumo resumo,
    required DateTime geradoEm,
    String? periodoAplicado,
  }) async {
    final theme = await _theme();
    final geradoStr = _dfRodape.format(geradoEm);
    final pdf = pw.Document(theme: theme);

    final rows = <List<String>>[];
    for (final v in vendas) {
      final data = v.dataHora != null ? _df.format(v.dataHora!) : '—';
      final hora = v.dataHora != null
          ? DateFormat('HH:mm').format(v.dataHora!)
          : '—';
      final itensRaw = v.dadosBrutos['itens'];
      final rawList = itensRaw is List ? itensRaw : const [];

      if (v.itens.isEmpty) {
        rows.add([
          v.codigoExibicao,
          data,
          hora,
          '—',
          '—',
          '1',
          _moeda.format(v.total),
          _moeda.format(v.desconto),
          _moeda.format(v.total),
          v.formaPagamento,
          _moeda.format(v.total),
          v.statusRotulo,
        ]);
        continue;
      }

      for (var i = 0; i < v.itens.length; i++) {
        final item = v.itens[i];
        Map<String, dynamic>? raw;
        if (i < rawList.length && rawList[i] is Map) {
          raw = Map<String, dynamic>.from(rawList[i] as Map);
        }
        final descItem = i == 0 ? v.desconto : 0.0;
        rows.add([
          i == 0 ? v.codigoExibicao : '',
          i == 0 ? data : '',
          i == 0 ? hora : '',
          item.nome,
          ComercialCreditoRelatoriosService.codigoProdutoDoItem(raw, item.nome),
          item.quantidade.toStringAsFixed(
            item.quantidade == item.quantidade.roundToDouble() ? 0 : 2,
          ),
          _moeda.format(item.precoUnitario),
          _moeda.format(descItem),
          _moeda.format(item.subtotal),
          i == 0 ? v.formaPagamento : '',
          i == 0 ? _moeda.format(v.total) : '',
          i == 0 ? v.statusRotulo : '',
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (ctx) => _cabecalho(
          nomeLoja: nomeLoja,
          titulo: 'Histórico de Compras do Cliente',
          periodo: periodoAplicado,
          geradoEm: geradoEm,
        ),
        footer: (ctx) => _rodape(ctx, geradoStr),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _fundoCard,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: _borda, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  cliente.nome,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _roxoEscuro,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CPF/CNPJ: ${ComercialCreditoRelatoriosService.mascararDocumento(cliente.cpf)}  ·  '
                  'Tel: ${ComercialCreditoRelatoriosService.mascararTelefone(cliente.telefone)}',
                  style: pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _cardsResumo([
            ('Compras', '${resumo.qtdCompras}', false),
            ('Produtos', '${resumo.qtdProdutos}', false),
            ('Valor bruto', _moeda.format(resumo.valorBruto), false),
            ('Descontos', _moeda.format(resumo.descontos), false),
            ('Total comprado', _moeda.format(resumo.valorTotal), true),
            ('Ticket médio', _moeda.format(resumo.ticketMedio), false),
          ]),
          pw.SizedBox(height: 16),
          _tituloSecao('Itens por venda'),
          pw.SizedBox(height: 8),
          _tabela(
            headers: const [
              'Venda',
              'Data',
              'Hora',
              'Produto',
              'Código',
              'Qtd',
              'Unitário',
              'Desconto',
              'Total item',
              'Pagamento',
              'Total venda',
              'Situação',
            ],
            rows: rows,
            colFlex: const [
              1.3, 1.1, 0.8, 2.2, 1.1, 0.7, 1.1, 1.0, 1.1, 1.2, 1.1, 1.1,
            ],
            fontSize: 7.5,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> recebimentos({
    required String nomeLoja,
    required List<Map<String, dynamic>> recebimentos,
    required Map<String, ComercialCliente> clientes,
    required CreditoRelatorioRecebimentosResumo resumo,
    required DateTime geradoEm,
    required DateTime dataDe,
    required DateTime dataAte,
  }) async {
    final theme = await _theme();
    final geradoStr = _dfRodape.format(geradoEm);
    final pdf = pw.Document(theme: theme);
    final periodo = '${_df.format(dataDe)} até ${_df.format(dataAte)}';

    DateTime? asDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final r in recebimentos) {
      final dt = asDate(r['data_pagamento'] ?? r['criado_em']);
      final key = dt != null ? _df.format(dt) : 'Sem data';
      porDia.putIfAbsent(key, () => []).add(r);
    }

    final widgets = <pw.Widget>[
      _cardsResumo([
        ('Recebimentos', '${resumo.quantidade}', false),
        ('Valor principal', _moeda.format(resumo.valorPrincipal), false),
        ('Juros', _moeda.format(resumo.juros), false),
        ('Multas', _moeda.format(resumo.multas), false),
        ('Descontos', _moeda.format(resumo.descontos), false),
        ('Total líquido', _moeda.format(resumo.liquido), true),
      ]),
      pw.SizedBox(height: 14),
    ];

    for (final entry in porDia.entries) {
      widgets.add(_tituloSecao(entry.key));
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        _tabela(
          headers: const [
            'Hora',
            'Cliente',
            'CPF/CNPJ',
            'Referência',
            'Recebido',
            'Juros',
            'Multa',
            'Desconto',
            'Líquido',
            'Forma',
            'Responsável',
            'Observação',
          ],
          rows: entry.value.map((r) {
            final dt = asDate(r['data_pagamento'] ?? r['criado_em']);
            final cid = (r['cliente_id'] ?? '').toString();
            final c = clientes[cid];
            final nome = c?.nome ??
                (r['cliente_nome'] ?? 'Cliente').toString();
            final doc = c?.cpf ?? (r['cliente_documento'] ?? '').toString();
            final pago = (r['valor_pago'] as num?)?.toDouble() ??
                (r['valor_recebido'] as num?)?.toDouble() ??
                0;
            final j = (r['valor_juros'] as num?)?.toDouble() ?? 0;
            final m = (r['valor_multa'] as num?)?.toDouble() ?? 0;
            final d = (r['valor_desconto'] as num?)?.toDouble() ?? 0;
            final ref =
                'Parc. ${r['numero_parcela'] ?? '—'} · ${r['codigo_venda'] ?? r['pedido_id'] ?? '—'}';
            final resp = (r['usuario_nome'] ??
                    r['recebido_por_nome'] ??
                    '—')
                .toString();
            final obs = (r['observacao'] ?? '').toString().trim();
            return [
              dt != null ? DateFormat('HH:mm').format(dt) : '—',
              nome,
              ComercialCreditoRelatoriosService.mascararDocumento(doc),
              ref,
              _moeda.format(pago),
              _moeda.format(j),
              _moeda.format(m),
              _moeda.format(d),
              _moeda.format(pago),
              (r['forma_pagamento'] ?? '—').toString(),
              resp,
              obs.isEmpty ? '—' : obs,
            ];
          }).toList(),
          colFlex: const [
            0.7, 2.0, 1.4, 1.6, 1.1, 0.9, 0.9, 0.9, 1.1, 1.1, 1.3, 1.4,
          ],
          fontSize: 7.5,
        ),
      );
      widgets.add(pw.SizedBox(height: 12));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (ctx) => _cabecalho(
          nomeLoja: nomeLoja,
          titulo: 'Relatório de Recebimentos',
          periodo: periodo,
          geradoEm: geradoEm,
        ),
        footer: (ctx) => _rodape(ctx, geradoStr),
        build: (ctx) => widgets,
      ),
    );

    return pdf.save();
  }

  // ── helpers visuais ──

  static Future<pw.ThemeData> _theme() async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return pw.ThemeData.withFont(base: base, bold: bold);
  }

  static pw.Widget _cabecalho({
    required String nomeLoja,
    required String titulo,
    required DateTime geradoEm,
    String? periodo,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [_roxoEscuro, _roxo],
              ),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 28,
                  height: 28,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'D',
                      style: pw.TextStyle(
                        color: _roxo,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DiPertin',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        nomeLoja,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    color: _laranja,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'PDF',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            titulo,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _texto,
            ),
          ),
          if (periodo != null && periodo.trim().isNotEmpty)
            pw.Text(
              'Período: $periodo',
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
          pw.Text(
            'Gerado em: ${_dfH.format(geradoEm)}',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: _borda, thickness: 0.6),
        ],
      ),
    );
  }

  static pw.Widget _rodape(pw.Context ctx, String geradoStr) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borda, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'DiPertin — Gestão Comercial',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Relatório gerado em $geradoStr',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tituloSecao(String t) {
    return pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _roxoEscuro,
      ),
    );
  }

  static pw.Widget _cardsResumo(List<(String, String, bool)> items) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) {
        final destaque = e.$3;
        return pw.Container(
          width: 120,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: destaque ? PdfColor.fromInt(0xFFFFF3E0) : _fundoCard,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(
              color: destaque ? _laranja : _borda,
              width: 0.7,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                e.$1,
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                e.$2,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: destaque ? _laranja : _roxo,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _tabela({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> colFlex,
    double fontSize = 8,
  }) {
    assert(headers.length == colFlex.length);
    pw.Widget cell(String text, {bool header = false, bool zebra = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        color: header ? _roxo : (zebra ? _zebra : null),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? PdfColors.white : _texto,
          ),
          maxLines: 3,
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _borda, width: 0.4),
      columnWidths: {
        for (var i = 0; i < colFlex.length; i++)
          i: pw.FlexColumnWidth(colFlex[i]),
      },
      children: [
        pw.TableRow(
          children: [
            for (final h in headers) cell(h, header: true),
          ],
        ),
        for (var r = 0; r < rows.length; r++)
          pw.TableRow(
            children: [
              for (final c in rows[r]) cell(c, zebra: r.isOdd),
            ],
          ),
      ],
    );
  }
}
