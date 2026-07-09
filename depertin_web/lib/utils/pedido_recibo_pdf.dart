import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Comprovante de venda (PDV / Gestão Comercial) — layout térmico 58 mm, 80 mm e PDF.
///
/// Apenas apresentação: não altera cálculos, pagamentos nem fluxo de impressão.
abstract final class PedidoReciboPdf {
  static const _versaoComprovante = '1.0.0';
  static const _urlValidacaoBase = 'https://www.dipertin.com.br/comprovante/';

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _hora = DateFormat('HH:mm', 'pt_BR');

  /// [larguraBobinaMm] — 58 ou 80 (padrão). Não altera o fluxo de quem já chama sem o parâmetro.
  static Future<void> imprimir({
    required String pedidoId,
    required String codigoPedido,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    String nomeClienteFallback = 'Cliente',
    double larguraBobinaMm = 80,
  }) async {
    await Printing.layoutPdf(
      name: 'Comprovante $codigoPedido',
      format: _formatoBobina(larguraBobinaMm),
      onLayout: (_) => _build(
        pedidoId: pedidoId,
        codigoPedido: codigoPedido,
        pedido: pedido,
        dadosLoja: dadosLoja,
        nomeClienteFallback: nomeClienteFallback,
        larguraBobinaMm: larguraBobinaMm,
      ),
    );
  }

  static PdfPageFormat _formatoBobina(double mm) {
    final largura = (mm <= 58 ? 58.0 : 80.0) * PdfPageFormat.mm;
    final margem = (mm <= 58 ? 3.5 : 5.0) * PdfPageFormat.mm;
    return PdfPageFormat(largura, double.infinity, marginAll: margem);
  }

  static Future<Uint8List> _build({
    required String pedidoId,
    required String codigoPedido,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    required String nomeClienteFallback,
    required double larguraBobinaMm,
  }) async {
    final ctx = _ComprovanteContext(
      pedidoId: pedidoId,
      codigoPedido: codigoPedido,
      pedido: pedido,
      dadosLoja: dadosLoja,
      nomeClienteFallback: nomeClienteFallback,
      estreito: larguraBobinaMm <= 58,
    );

    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final layout = _ComprovanteLayout(
      ctx: ctx,
      font: font,
      fontBold: fontBold,
    );

    pw.ImageProvider? logo;
    final logoUrl = ctx.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(logoUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          logo = pw.MemoryImage(resp.bodyBytes);
        }
      } catch (_) {
        // Sem logo — segue sem bloquear impressão.
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _formatoBobina(larguraBobinaMm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            ...layout.cabecalho(logo: logo),
            ...layout.dadosVenda(),
            ...layout.dadosCliente(),
            ...layout.produtos(),
            ...layout.resumoFinanceiro(),
            ...layout.pagamento(),
            ...layout.informacoesExtras(),
            ...layout.qrValidacao(),
            ...layout.rodape(),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

// ─── Contexto (leitura dos maps — sem alterar dados de origem) ───────────────

final class _ComprovanteContext {
  _ComprovanteContext({
    required this.pedidoId,
    required this.codigoPedido,
    required Map<String, dynamic> pedido,
    Map<String, dynamic>? dadosLoja,
    required this.nomeClienteFallback,
    required this.estreito,
  })  : _pedido = pedido,
        _loja = dadosLoja ?? const {};

  final String pedidoId;
  final String codigoPedido;
  final bool estreito;
  final String nomeClienteFallback;
  final Map<String, dynamic> _pedido;
  final Map<String, dynamic> _loja;

  double get fsTituloBloco => estreito ? 8.0 : 9.0;
  double get fsCorpo => estreito ? 7.0 : 8.0;
  double get fsPequeno => estreito ? 6.0 : 7.0;
  double get fsTotal => estreito ? 13.0 : 15.0;
  double get fsTituloDoc => estreito ? 9.0 : 10.0;
  double get espacoBloco => estreito ? 6.0 : 8.0;
  double get espacoLinha => estreito ? 2.0 : 3.0;

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _dbl(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? fallback;
  }

  DateTime? get _dataPedido {
    final v = _pedido['data_pedido'] ??
        _pedido['data_venda'] ??
        _pedido['created_at'] ??
        _pedido['data_pagamento'];
    if (v == null) return null;
    try {
      if (v is DateTime) return v;
      // Timestamp Firestore via dynamic
      final dynamic ts = v;
      if (ts.runtimeType.toString().contains('Timestamp')) {
        return ts.toDate() as DateTime;
      }
    } catch (_) {}
    return null;
  }

  DateTime? get _dataConfirmacaoPagamento {
    final v = _pedido['pix_pago_em'] ??
        _pedido['data_confirmacao_pagamento'] ??
        _pedido['pagamento_confirmado_em'];
    if (v == null) return _dataPedido;
    try {
      if (v is DateTime) return v;
      final dynamic ts = v;
      if (ts.runtimeType.toString().contains('Timestamp')) {
        return ts.toDate() as DateTime;
      }
    } catch (_) {}
    return null;
  }

  // ── Cabeçalho loja ──

  String? get logoUrl =>
      _str(_loja['foto_logo']) ??
      _str(_loja['logo_url']) ??
      _str(_loja['foto']) ??
      _str(_loja['foto_perfil']) ??
      _str(_loja['foto_capa']) ??
      _str(_pedido['loja_foto']) ??
      _str(_pedido['loja_logo']);

  String get nomeLoja {
    return _str(_loja['nome_fantasia']) ??
        _str(_loja['nome_loja']) ??
        _str(_loja['nome']) ??
        _str(_pedido['loja_nome']) ??
        'Loja';
  }

  String? get cnpj {
    final raw = _str(_loja['cnpj']) ?? _str(_loja['documento']) ?? _str(_loja['cpf_cnpj']);
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 14) {
      return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
    }
    return raw;
  }

  String? get enderecoLinha1 {
    final rua = _str(_loja['endereco']) ??
        _str(_loja['endereco_rua']) ??
        _str(_loja['rua']) ??
        _str(_pedido['loja_endereco']);
    if (rua == null) return null;
    final num = _str(_loja['numero']) ?? _str(_loja['endereco_numero']);
    final compl = _str(_loja['complemento']);
    final bairro = _str(_loja['bairro']) ?? _str(_loja['endereco_bairro']);
    final buf = StringBuffer(rua);
    if (num != null) buf.write(', $num');
    if (compl != null) buf.write(' — $compl');
    if (bairro != null) buf.write(' — $bairro');
    return buf.toString();
  }

  String? get cidade =>
      _str(_loja['cidade']) ??
      _str(_loja['endereco_cidade']) ??
      _str(_loja['cidade_normalizada']);

  String? get estado => _str(_loja['uf']) ?? _str(_loja['estado']);

  String? get cep {
    final raw = _str(_loja['cep']) ?? _str(_loja['endereco_cep']);
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 8) return '${d.substring(0, 5)}-${d.substring(5)}';
    return raw;
  }

  String? get telefoneLoja =>
      _str(_loja['telefone']) ??
      _str(_loja['telefone_loja']) ??
      _str(_pedido['loja_telefone']);

  String? get emailLoja => _str(_loja['email']) ?? _str(_loja['email_loja']);

  // ── Venda ──

  String? get numeroPedido => _str(codigoPedido) ?? _str(_pedido['codigo_pedido']);

  String? get numeroVenda =>
      _str(_pedido['codigo_venda']) ?? _str(_pedido['codigo_venda_gc']) ?? numeroPedido;

  String? get numeroCaixa =>
      _str(_pedido['sessao_caixa_id']) ??
      _str(_pedido['caixa_id']) ??
      _str(_pedido['numero_caixa']);

  String? get operador =>
      _str(_pedido['operador_nome']) ??
      _str(_pedido['vendedor_nome']) ??
      _str(_pedido['operador']);

  String? get tipoVenda {
    final origem = _str(_pedido['origem']);
    final mesa = _str(_pedido['mesa']);
    final comanda = _str(_pedido['comanda']);
    if (mesa != null) return 'Mesa $mesa';
    if (comanda != null) return 'Comanda $comanda';
    if (origem == 'pdv_web') return 'PDV / Balcão';
    final tipo = _str(_pedido['tipo_venda']) ?? _str(_pedido['tipo_entrega']);
    return switch (tipo) {
      'retirada' => 'Retirada',
      'entrega' => 'Entrega',
      'balcao' => 'Balcão',
      'pdv' => 'PDV',
      'mesa' => 'Mesa',
      'comanda' => 'Comanda',
      _ => tipo,
    };
  }

  String? get origemVenda {
    final o = _str(_pedido['origem']);
    return switch (o) {
      'pdv_web' => 'PDV',
      'app' => 'App',
      'site' => 'Site',
      'whatsapp' => 'WhatsApp',
      _ => o,
    };
  }

  // ── Cliente ──

  String? get clienteId => _str(_pedido['cliente_id']);

  bool get clienteIdentificado {
    final id = clienteId;
    if (id == null || id.isEmpty) return false;
    return id != 'venda_balcao' && id != 'anonimo';
  }

  String get nomeCliente {
    final n = _str(_pedido['cliente_nome']);
    if (n != null && n.isNotEmpty && n.toLowerCase() != 'cliente pdv') return n;
    if (clienteIdentificado && n != null) return n;
    return clienteIdentificado ? (n ?? nomeClienteFallback) : 'Cliente Não Identificado';
  }

  String? get clienteCpf {
    final raw = _str(_pedido['cliente_cpf']) ??
        _str(_pedido['cliente_documento']) ??
        _str(_pedido['cliente_doc']);
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
    }
    return raw;
  }

  String? get clienteTelefone =>
      _str(_pedido['cliente_telefone']) ?? _str(_pedido['cliente_fone']);

  String? get clienteEmail => _str(_pedido['cliente_email']);

  // ── Itens ──

  List<Map<String, dynamic>> get itens {
    final raw = _pedido['itens'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── Financeiro ──

  double get subtotal {
    final s = _dbl(_pedido['subtotal']);
    if (s > 0) return s;
    return itens.fold<double>(0, (acc, item) => acc + _itemSubtotal(item));
  }

  double get desconto {
    final calc = _dbl(_pedido['desconto_total_calculado']);
    if (calc > 0) return calc;
    final d = _dbl(_pedido['desconto']);
    if (d > 0) return d;
    return _dbl(_pedido['desconto_total']);
  }

  double? get descontoPercentual {
    if (_str(_pedido['desconto_tipo']) != 'porcentagem') return null;
    final v = _dbl(_pedido['desconto_valor']);
    return v > 0 ? v : null;
  }

  double get acrescimos =>
      _dbl(_pedido['acrescimos']) + _dbl(_pedido['acrescimo']) + _dbl(_pedido['juros_total']);

  double get frete => _dbl(_pedido['taxa_entrega']) + _dbl(_pedido['frete']);

  double get taxaServico =>
      _dbl(_pedido['taxa_servico']) + _dbl(_pedido['taxa_plataforma']);

  String? get cupomCodigo => _str(_pedido['cupom_codigo']);

  double get cupomDesconto =>
      _dbl(_pedido['desconto_cupom']) +
      _dbl(_pedido['desconto_cupom_produto']) +
      _dbl(_pedido['desconto_cupom_frete']);

  double get cashbackUtilizado => _dbl(_pedido['cashback_utilizado']);

  double get creditoUtilizado =>
      _dbl(_pedido['credito_utilizado']) + _dbl(_pedido['valor_credito_loja']);

  double get total =>
      _dbl(_pedido['total']) > 0
          ? _dbl(_pedido['total'])
          : (subtotal - desconto - cupomDesconto + acrescimos + frete + taxaServico);

  // ── Pagamento ──

  String? get formaPagamento => _str(_pedido['forma_pagamento']);

  String? get gateway {
    final g = _str(_pedido['gateway']) ??
        _str(_pedido['gateway_pagamento']) ??
        _str(_pedido['pix_gateway']);
    if (g != null) return g;
    final fp = formaPagamento;
    if (fp != null && fp.contains(' - ')) {
      return fp.split(' - ').last.trim();
    }
    return null;
  }

  String? get formaPagamentoRotulo {
    final fp = formaPagamento;
    if (fp == null) return null;
    if (fp.contains(' - ')) return fp.split(' - ').first.trim();
    return fp;
  }

  String get statusPagamentoRotulo {
    final st = (_str(_pedido['status_pagamento']) ?? _str(_pedido['status']) ?? '')
        .toLowerCase();
    if (st.contains('cancel')) return '✕ Pagamento Cancelado';
    if (st.contains('aguard') || st == 'pendente') return '⏳ Aguardando Pagamento';
    if (st.contains('aprov') || st == 'pago' || st == 'entregue' || st == 'confirmado') {
      return '✔ Pagamento Aprovado';
    }
    return '✔ Pagamento Aprovado';
  }

  bool get ehPix {
    final fp = (formaPagamento ?? '').toUpperCase();
    return fp.contains('PIX');
  }

  bool get ehCartao {
    final fp = (formaPagamento ?? '').toUpperCase();
    return fp.contains('CART') || fp.contains('CRÉDITO') || fp.contains('CREDITO') || fp.contains('DÉBITO') || fp.contains('DEBITO');
  }

  bool get ehDinheiro {
    final fp = (formaPagamento ?? '').toUpperCase();
    return fp.contains('DINHEIRO') || fp.contains('ESPÉCIE') || fp.contains('ESPECIE');
  }

  String? get pixTransacaoId =>
      _str(_pedido['pix_payment_id']) ??
      _str(_pedido['payment_id']) ??
      _str(_pedido['transacao_id']) ??
      _str(_pedido['transaction_id']);

  String? get pixEndToEnd =>
      _str(_pedido['pix_e2e']) ??
      _str(_pedido['end_to_end_id']) ??
      _str(_pedido['e2e_id']);

  String? get bancoRecebedor => _str(_pedido['banco_recebedor']) ?? _str(_pedido['pix_banco']);

  double get valorRecebido {
    final v = _dbl(_pedido['valor_recebido']);
    return v > 0 ? v : total;
  }

  double get troco => _dbl(_pedido['troco']);

  String? get cartaoBandeira => _str(_pedido['cartao_bandeira']) ?? _str(_pedido['bandeira']);

  String? get cartaoTipo => _str(_pedido['cartao_tipo']) ?? _str(_pedido['tipo_cartao']);

  int? get cartaoParcelas {
    final p = _pedido['parcelas'] ?? _pedido['cartao_parcelas'] ?? _pedido['quantidade_parcelas'];
    if (p is int) return p;
    return int.tryParse(p?.toString() ?? '');
  }

  String? get cartaoNsu => _str(_pedido['nsu']) ?? _str(_pedido['cartao_nsu']);

  String? get cartaoAutorizacao =>
      _str(_pedido['codigo_autorizacao']) ?? _str(_pedido['cartao_autorizacao']);

  String? get cartaoUltimos4 {
    final u = _str(_pedido['cartao_ultimos4']) ?? _str(_pedido['ultimos_digitos']);
    if (u == null) return null;
    if (u.length == 4) return '**** **** **** $u';
    return u;
  }

  // ── Extras ──

  String? get vendedor => _str(_pedido['vendedor_nome']) ?? operador;

  String? get entregador =>
      _str(_pedido['entregador_nome']) ?? _str(_pedido['nome_entregador']);

  String? get mesa => _str(_pedido['mesa']);

  String? get comanda => _str(_pedido['comanda']);

  String? get observacaoVenda =>
      _str(_pedido['observacao']) ??
      _str(_pedido['observacao_venda']) ??
      _str(_pedido['observacoes']);

  String get urlValidacao => '${PedidoReciboPdf._urlValidacaoBase}$pedidoId';

  static double _itemSubtotal(Map<String, dynamic> item) {
    final qtd = _itemQtd(item);
    final unit = _itemUnitario(item);
    final vt = item['valor_total'] ?? item['subtotal'] ?? item['total'];
    if (vt != null) {
      final v = vt is num ? vt.toDouble() : double.tryParse(vt.toString()) ?? 0;
      if (v > 0) return v;
    }
    return unit * qtd;
  }

  static int _itemQtd(Map<String, dynamic> item) {
    final q = item['quantidade'] ?? item['qtd'] ?? item['qty'] ?? 1;
    if (q is int) return q;
    return int.tryParse(q.toString()) ?? 1;
  }

  static double _itemUnitario(Map<String, dynamic> item) {
    final p = item['preco'] ??
        item['preco_unitario'] ??
        item['valor_unitario'] ??
        item['unitario'];
    if (p is num) return p.toDouble();
    return double.tryParse(p?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String _itemNome(Map<String, dynamic> item) =>
      (item['nome'] ?? item['nome_produto'] ?? item['produto_nome'] ?? 'Item')
          .toString();

  static double _itemDesconto(Map<String, dynamic> item) {
    final d = item['desconto'] ?? item['desconto_item'];
    if (d is num) return d.toDouble();
    return double.tryParse(d?.toString() ?? '') ?? 0;
  }

  static String? _itemObs(Map<String, dynamic> item) {
    final o = item['observacao'] ?? item['obs'] ?? item['observacoes'];
    if (o == null) return null;
    final s = o.toString().trim();
    return s.isEmpty ? null : s;
  }
}

// ─── Layout (blocos reutilizáveis) ───────────────────────────────────────────

final class _ComprovanteLayout {
  _ComprovanteLayout({
    required this.ctx,
    required this.font,
    required this.fontBold,
  });

  final _ComprovanteContext ctx;
  final pw.Font font;
  final pw.Font fontBold;

  pw.TextStyle _bold(double size) => pw.TextStyle(font: fontBold, fontSize: size);
  pw.TextStyle _regular(double size) => pw.TextStyle(font: font, fontSize: size);

  List<pw.Widget> cabecalho({pw.ImageProvider? logo}) {
    final children = <pw.Widget>[];

    if (logo != null) {
      children.addAll([
        pw.Center(
          child: pw.Image(logo, width: ctx.estreito ? 40 : 52, height: ctx.estreito ? 40 : 52),
        ),
        pw.SizedBox(height: ctx.espacoLinha),
      ]);
    }

    children.addAll([
      pw.Text(
        ctx.nomeLoja.toUpperCase(),
        style: _bold(ctx.estreito ? 10 : 11),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: ctx.espacoLinha),
    ]);

    for (final linha in [
      if (ctx.cnpj != null) 'CNPJ: ${ctx.cnpj}',
      if (ctx.enderecoLinha1 != null) ctx.enderecoLinha1!,
      if (ctx.cidade != null || ctx.estado != null)
        [
          if (ctx.cidade != null) ctx.cidade,
          if (ctx.estado != null) ctx.estado,
        ].join(' — '),
      if (ctx.cep != null) 'CEP: ${ctx.cep}',
      if (ctx.telefoneLoja != null) 'Tel: ${ctx.telefoneLoja}',
      if (ctx.emailLoja != null) ctx.emailLoja!,
    ]) {
      children.add(
        pw.Text(linha, style: _regular(ctx.fsPequeno), textAlign: pw.TextAlign.center),
      );
    }

    children.addAll([
      pw.SizedBox(height: ctx.espacoBloco),
      pw.Text(
        'COMPROVANTE DE VENDA',
        style: _bold(ctx.fsTituloDoc),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: ctx.espacoLinha),
      _sepDuplo(),
      pw.SizedBox(height: ctx.espacoBloco),
    ]);

    return children;
  }

  List<pw.Widget> dadosVenda() {
    final dt = ctx._dataPedido;
    final linhas = <(String, String)>[];

    void add(String rotulo, String? valor) {
      if (valor != null && valor.isNotEmpty) linhas.add((rotulo, valor));
    }

    add('Nº Pedido', ctx.numeroPedido);
    add('Nº Venda', ctx.numeroVenda);
    add('Caixa', ctx.numeroCaixa);
    add('Operador', ctx.operador);
    if (dt != null) {
      add('Data', PedidoReciboPdf._data.format(dt));
      add('Hora', PedidoReciboPdf._hora.format(dt));
    }
    add('Tipo', ctx.tipoVenda);

    if (linhas.isEmpty) return const [];

    return [
      _tituloBloco('Dados da Venda'),
      ...linhas.map((l) => _linhaRotuloValor(l.$1, l.$2)),
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ];
  }

  List<pw.Widget> dadosCliente() {
    final linhas = <(String, String)>[];

    void add(String rotulo, String? valor) {
      if (valor != null && valor.isNotEmpty) linhas.add((rotulo, valor));
    }

    add('Nome', ctx.nomeCliente);
    if (ctx.clienteIdentificado) {
      add('CPF', ctx.clienteCpf);
      add('Telefone', ctx.clienteTelefone);
      add('E-mail', ctx.clienteEmail);
      add('Código', ctx.clienteId);
    }

    return [
      _tituloBloco('Cliente'),
      ...linhas.map((l) => _linhaRotuloValor(l.$1, l.$2)),
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ];
  }

  List<pw.Widget> produtos() {
    if (ctx.itens.isEmpty) return const [];

    final bloco = <pw.Widget>[
      _tituloBloco('Produtos'),
    ];

    for (var i = 0; i < ctx.itens.length; i++) {
      final item = ctx.itens[i];
      final qtd = _ComprovanteContext._itemQtd(item);
      final nome = _ComprovanteContext._itemNome(item);
      final unit = _ComprovanteContext._itemUnitario(item);
      final sub = _ComprovanteContext._itemSubtotal(item);
      final descItem = _ComprovanteContext._itemDesconto(item);
      final obs = _ComprovanteContext._itemObs(item);

      bloco.addAll([
        pw.Text('$qtd× $nome', style: _bold(ctx.fsCorpo)),
        _linhaPontilhada('Unitário', PedidoReciboPdf._moeda.format(unit)),
        _linhaPontilhada('Subtotal', PedidoReciboPdf._moeda.format(sub)),
      ]);

      if (descItem > 0) {
        bloco.add(
          _linhaPontilhada('Desconto item', '- ${PedidoReciboPdf._moeda.format(descItem)}'),
        );
      }

      if (obs != null) {
        for (final linha in obs.split('\n')) {
          if (linha.trim().isEmpty) continue;
          bloco.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8, top: 1),
              child: pw.Text(
                linha.trim(),
                style: _regular(ctx.fsPequeno),
              ),
            ),
          );
        }
      }

      if (i < ctx.itens.length - 1) {
        bloco.add(pw.SizedBox(height: ctx.espacoLinha + 2));
      }
    }

    bloco.addAll([
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ]);

    return bloco;
  }

  List<pw.Widget> resumoFinanceiro() {
    void addValor(List<pw.Widget> list, String rotulo, double valor, {bool sempre = false}) {
      if (!sempre && valor.abs() < 0.009) return;
      list.add(_linhaRotuloValor(rotulo, PedidoReciboPdf._moeda.format(valor)));
    }

    final linhas = <pw.Widget>[
      _tituloBloco('Resumo Financeiro'),
    ];

    addValor(linhas, 'Subtotal', ctx.subtotal, sempre: true);
    addValor(linhas, 'Desconto', ctx.desconto > 0 ? -ctx.desconto : ctx.desconto);
    if (ctx.descontoPercentual != null) {
      linhas.add(
        _linhaRotuloValor('Desconto (%)', '${ctx.descontoPercentual!.toStringAsFixed(1)}%'),
      );
    }
    addValor(linhas, 'Acréscimos', ctx.acrescimos);
    addValor(linhas, 'Frete', ctx.frete);
    addValor(linhas, 'Taxa de serviço', ctx.taxaServico);
    if (ctx.cupomCodigo != null) {
      linhas.add(_linhaRotuloValor('Cupom', ctx.cupomCodigo!));
    }
    addValor(linhas, 'Cupom (valor)', ctx.cupomDesconto > 0 ? -ctx.cupomDesconto : ctx.cupomDesconto);
    addValor(linhas, 'Cashback utilizado', ctx.cashbackUtilizado > 0 ? -ctx.cashbackUtilizado : ctx.cashbackUtilizado);
    addValor(linhas, 'Crédito utilizado', ctx.creditoUtilizado > 0 ? -ctx.creditoUtilizado : ctx.creditoUtilizado);

    linhas.addAll([
      pw.SizedBox(height: ctx.espacoLinha),
      _sepDuplo(),
      pw.SizedBox(height: ctx.espacoLinha),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text('TOTAL', style: _bold(ctx.fsTotal)),
          pw.Text(
            PedidoReciboPdf._moeda.format(ctx.total),
            style: _bold(ctx.fsTotal),
          ),
        ],
      ),
      pw.SizedBox(height: ctx.espacoLinha),
      _sepDuplo(),
      pw.SizedBox(height: ctx.espacoBloco),
    ]);

    return linhas;
  }

  List<pw.Widget> pagamento() {
    if (ctx.formaPagamento == null) return const [];

    final bloco = <pw.Widget>[
      _tituloBloco('Pagamento'),
    ];

    void add(String rotulo, String? valor) {
      if (valor != null && valor.isNotEmpty) {
        bloco.add(_linhaRotuloValor(rotulo, valor));
      }
    }

    add('Forma', ctx.formaPagamentoRotulo ?? ctx.formaPagamento);
    add('Gateway', ctx.gateway);
    bloco.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
        child: pw.Text(ctx.statusPagamentoRotulo, style: _bold(ctx.fsCorpo)),
      ),
    );

    if (ctx.ehPix) {
      add('ID Transação', ctx.pixTransacaoId);
      add('Transaction ID', ctx.pixTransacaoId);
      add('EndToEnd (E2E)', ctx.pixEndToEnd);
      final conf = ctx._dataConfirmacaoPagamento;
      if (conf != null) {
        add('Confirmação', PedidoReciboPdf._data.format(conf));
        add('Hora confirmação', PedidoReciboPdf._hora.format(conf));
      }
      add('Banco recebedor', ctx.bancoRecebedor);
      bloco.add(_linhaRotuloValor('Valor recebido', PedidoReciboPdf._moeda.format(ctx.valorRecebido)));
    } else if (ctx.ehCartao) {
      add('Bandeira', ctx.cartaoBandeira);
      add('Tipo', ctx.cartaoTipo);
      final parc = ctx.cartaoParcelas;
      if (parc != null && parc > 1) {
        add('Parcelas', '$parc×');
        final vp = ctx.total / parc;
        add('Valor parcela', PedidoReciboPdf._moeda.format(vp));
      }
      add('NSU', ctx.cartaoNsu);
      add('Autorização', ctx.cartaoAutorizacao);
      add('Cartão', ctx.cartaoUltimos4);
    } else if (ctx.ehDinheiro) {
      bloco.add(_linhaRotuloValor('Valor recebido', PedidoReciboPdf._moeda.format(ctx.valorRecebido)));
      bloco.add(_linhaRotuloValor('Troco', PedidoReciboPdf._moeda.format(ctx.troco)));
    } else {
      bloco.add(_linhaRotuloValor('Valor recebido', PedidoReciboPdf._moeda.format(ctx.valorRecebido)));
    }

    bloco.addAll([
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ]);

    return bloco;
  }

  List<pw.Widget> informacoesExtras() {
    final linhas = <(String, String)>[];

    void add(String rotulo, String? valor) {
      if (valor != null && valor.isNotEmpty) linhas.add((rotulo, valor));
    }

    add('Vendedor', ctx.vendedor);
    add('Entregador', ctx.entregador);
    if (ctx.mesa != null) add('Mesa', ctx.mesa);
    if (ctx.comanda != null) add('Comanda', ctx.comanda);
    add('Observação', ctx.observacaoVenda);
    add('Origem', ctx.origemVenda);

    if (linhas.isEmpty) return const [];

    return [
      _tituloBloco('Informações Extras'),
      ...linhas.map((l) => _linhaRotuloValor(l.$1, l.$2)),
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ];
  }

  List<pw.Widget> qrValidacao() {
    final size = ctx.estreito ? 72.0 : 88.0;
    return [
      pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: ctx.urlValidacao,
          width: size,
          height: size,
          drawText: false,
        ),
      ),
      pw.SizedBox(height: ctx.espacoLinha),
      pw.Text(
        'Escaneie para validar este comprovante.',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: ctx.espacoBloco),
      _sepSimples(),
      pw.SizedBox(height: ctx.espacoBloco),
    ];
  }

  List<pw.Widget> rodape() {
    final agora = DateTime.now();
    return [
      pw.Text(
        'Obrigado pela preferência!',
        style: _bold(ctx.fsCorpo),
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'Volte sempre!',
        style: _regular(ctx.fsCorpo),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: ctx.espacoLinha),
      pw.Text(
        'Pedido realizado através do',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'DiPertin Gestão Comercial',
        style: _bold(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'www.dipertin.com.br',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: ctx.espacoLinha),
      pw.Text(
        'Impresso em ${PedidoReciboPdf._dataHora.format(agora)}',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'Versão ${PedidoReciboPdf._versaoComprovante}',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      ),
    ];
  }

  pw.Widget _tituloBloco(String titulo) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: ctx.espacoLinha),
        child: pw.Text(titulo, style: _bold(ctx.fsTituloBloco)),
      );

  pw.Widget _sepDuplo() => pw.Text(
        '══════════════════════════════',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      );

  pw.Widget _sepSimples() => pw.Text(
        '──────────────────────────────',
        style: _regular(ctx.fsPequeno),
        textAlign: pw.TextAlign.center,
      );

  pw.Widget _linhaRotuloValor(String rotulo, String valor) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Text(rotulo, style: _regular(ctx.fsCorpo)),
            ),
            pw.SizedBox(width: 4),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                valor,
                style: _regular(ctx.fsCorpo),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );

  pw.Widget _linhaPontilhada(String rotulo, String valor) => pw.Padding(
        padding: pw.EdgeInsets.only(left: 6, bottom: 1),
        child: pw.Row(
          children: [
            pw.Text(rotulo, style: _regular(ctx.fsPequeno)),
            pw.Spacer(),
            pw.Text(valor, style: _regular(ctx.fsPequeno)),
          ],
        ),
      );
}
