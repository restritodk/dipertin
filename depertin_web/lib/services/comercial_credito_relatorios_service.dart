import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_config_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';

/// Linha de parcela vencida para PDF de pendências.
class CreditoRelatorioPendenciaLinha {
  const CreditoRelatorioPendenciaLinha({
    required this.cliente,
    required this.parcela,
    required this.encargos,
  });

  final ComercialCliente cliente;
  final ComercialParcelaCliente parcela;
  final JurosMultaResultado encargos;
}

/// Agregados do relatório de clientes com crédito.
class CreditoRelatorioClientesResumo {
  const CreditoRelatorioClientesResumo({
    required this.totalClientes,
    required this.limiteTotal,
    required this.utilizado,
    required this.disponivel,
    required this.emAtraso,
  });

  final int totalClientes;
  final double limiteTotal;
  final double utilizado;
  final double disponivel;
  final double emAtraso;
}

/// Agregados do relatório de pendências.
class CreditoRelatorioPendenciasResumo {
  const CreditoRelatorioPendenciasResumo({
    required this.qtdClientes,
    required this.qtdParcelas,
    required this.valorOriginal,
    required this.jurosMultas,
    required this.valorAtualizado,
  });

  final int qtdClientes;
  final int qtdParcelas;
  final double valorOriginal;
  final double jurosMultas;
  final double valorAtualizado;
}

/// Agregados do relatório de vendas.
class CreditoRelatorioVendasResumo {
  const CreditoRelatorioVendasResumo({
    required this.qtdCompras,
    required this.qtdProdutos,
    required this.valorBruto,
    required this.descontos,
    required this.valorTotal,
  });

  double get ticketMedio => qtdCompras > 0 ? valorTotal / qtdCompras : 0;

  final int qtdCompras;
  final int qtdProdutos;
  final double valorBruto;
  final double descontos;
  final double valorTotal;
}

/// Agregados do relatório de recebimentos.
class CreditoRelatorioRecebimentosResumo {
  const CreditoRelatorioRecebimentosResumo({
    required this.quantidade,
    required this.valorPrincipal,
    required this.juros,
    required this.multas,
    required this.descontos,
    required this.liquido,
  });

  final int quantidade;
  final double valorPrincipal;
  final double juros;
  final double multas;
  final double descontos;
  final double liquido;
}

/// Coleta dados dos relatórios PDF de Crédito de Clientes (reusa regras existentes).
abstract final class ComercialCreditoRelatoriosService {
  static String mascararDocumento(String? doc) {
    if (doc == null || doc.isEmpty) return '—';
    final d = doc.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '***.${d.substring(3, 6)}.${d.substring(6, 9)}-**';
    }
    if (d.length == 14) {
      return '**.${d.substring(2, 5)}.${d.substring(5, 8)}/****-${d.substring(12)}';
    }
    return ComercialClientesService.formatarCpfExibicao(doc);
  }

  static String mascararTelefone(String? tel) {
    if (tel == null || tel.trim().isEmpty) return '—';
    final d = tel.replaceAll(RegExp(r'\D'), '');
    if (d.length < 4) return '****';
    return '*****-${d.substring(d.length - 4)}';
  }

  static Future<String> nomeLoja(String lojaId) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(lojaId).get();
    final d = snap.data() ?? {};
    return (d['loja_nome'] ??
            d['nome_loja'] ??
            d['nome_fantasia'] ??
            d['nome'] ??
            'Minha Loja')
        .toString();
  }

  /// Clientes com crédito (+ filtros da tela, se fornecidos).
  static Future<
      ({
        List<ComercialCliente> clientes,
        Map<String, int> parcelasAbertas,
        Map<String, double> atrasoPorCliente,
        CreditoRelatorioClientesResumo resumo,
      })> carregarClientesComCredito({
    required String lojaId,
    List<ComercialCliente>? clientesJaFiltrados,
  }) async {
    final todos = clientesJaFiltrados ??
        (await ComercialClientesService.listar(lojaId))
            .where(
              (c) =>
                  c.creditoHabilitado ||
                  c.limiteCredito > 0 ||
                  c.creditoUtilizado > 0,
            )
            .toList();

    final parcelas =
        await ComercialCreditoService.carregarParcelasLoja(lojaId);
    final abertas = <String, int>{};
    final atraso = <String, double>{};
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);

    for (final p in parcelas) {
      if (!p.podeReceber) continue;
      abertas[p.clienteId] = (abertas[p.clienteId] ?? 0) + 1;
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (venc.isBefore(hojeClean)) {
        atraso[p.clienteId] = (atraso[p.clienteId] ?? 0) + p.valorEmAberto;
      }
    }

    var limite = 0.0, utilizado = 0.0, emAtraso = 0.0;
    for (final c in todos) {
      limite += c.limiteCredito;
      utilizado += c.creditoUtilizado;
      emAtraso += atraso[c.id] ?? 0;
    }

    return (
      clientes: todos,
      parcelasAbertas: abertas,
      atrasoPorCliente: atraso,
      resumo: CreditoRelatorioClientesResumo(
        totalClientes: todos.length,
        limiteTotal: limite,
        utilizado: utilizado,
        disponivel: (limite - utilizado).clamp(0, double.infinity),
        emAtraso: emAtraso,
      ),
    );
  }

  /// Parcelas vencidas com encargos (mesma regra de [calcularJurosMulta]).
  static Future<
      ({
        List<CreditoRelatorioPendenciaLinha> linhas,
        CreditoRelatorioPendenciasResumo resumo,
      })> carregarPendencias({
    required String lojaId,
    DateTime? vencimentoDe,
    DateTime? vencimentoAte,
    String? clienteId,
    int? diasAtrasoMin,
    int? diasAtrasoMax,
  }) async {
    final config =
        await ComercialConfigService.carregarJurosMultaConfig(lojaId);
    final clientes = await ComercialClientesService.listar(lojaId);
    final mapa = {for (final c in clientes) c.id: c};
    final parcelas =
        await ComercialCreditoService.carregarParcelasLoja(lojaId);

    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    final de = vencimentoDe == null
        ? null
        : DateTime(vencimentoDe.year, vencimentoDe.month, vencimentoDe.day);
    final ate = vencimentoAte == null
        ? null
        : DateTime(vencimentoAte.year, vencimentoAte.month, vencimentoAte.day);

    final linhas = <CreditoRelatorioPendenciaLinha>[];
    for (final p in parcelas) {
      if (!p.podeReceber) continue;
      if (clienteId != null &&
          clienteId.isNotEmpty &&
          p.clienteId != clienteId) {
        continue;
      }
      final venc = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (!venc.isBefore(hojeClean)) continue; // só vencidas/atraso
      if (de != null && venc.isBefore(de)) continue;
      if (ate != null && venc.isAfter(ate)) continue;

      final encargos = calcularJurosMulta(p.valorEmAberto, p.dataVencimento, config);
      if (diasAtrasoMin != null && encargos.diasEmAtraso < diasAtrasoMin) {
        continue;
      }
      if (diasAtrasoMax != null && encargos.diasEmAtraso > diasAtrasoMax) {
        continue;
      }

      final cliente = mapa[p.clienteId];
      if (cliente == null) continue;
      linhas.add(CreditoRelatorioPendenciaLinha(
        cliente: cliente,
        parcela: p,
        encargos: encargos,
      ));
    }

    linhas.sort(
      (a, b) => b.encargos.diasEmAtraso.compareTo(a.encargos.diasEmAtraso),
    );

    final clientesIds = linhas.map((e) => e.cliente.id).toSet();
    var original = 0.0, jurosMultas = 0.0, atualizado = 0.0;
    for (final l in linhas) {
      original += l.parcela.valorEmAberto;
      jurosMultas += l.encargos.multa + l.encargos.juros;
      atualizado += l.encargos.valorAtualizado > 0
          ? l.encargos.valorAtualizado
          : l.parcela.valorEmAberto;
    }

    return (
      linhas: linhas,
      resumo: CreditoRelatorioPendenciasResumo(
        qtdClientes: clientesIds.length,
        qtdParcelas: linhas.length,
        valorOriginal: original,
        jurosMultas: jurosMultas,
        valorAtualizado: atualizado,
      ),
    );
  }

  static Future<
      ({
        List<ComercialClienteLancamento> vendas,
        CreditoRelatorioVendasResumo resumo,
      })> carregarVendasCliente({
    required String lojaId,
    required ComercialCliente cliente,
    DateTime? dataDe,
    DateTime? dataAte,
  }) async {
    final lanc = await ComercialClientesService.carregarLancamentosCliente(
      lojaId: lojaId,
      cliente: cliente,
      limite: 500,
    );

    final de = dataDe == null
        ? null
        : DateTime(dataDe.year, dataDe.month, dataDe.day);
    final ate = dataAte == null
        ? null
        : DateTime(dataAte.year, dataAte.month, dataAte.day, 23, 59, 59);

    final filtrados = lanc.where((l) {
      final d = l.dataHora;
      if (d == null) return de == null && ate == null;
      if (de != null && d.isBefore(de)) return false;
      if (ate != null && d.isAfter(ate)) return false;
      return true;
    }).toList();

    var qtdProd = 0;
    var bruto = 0.0;
    var desc = 0.0;
    var total = 0.0;
    for (final v in filtrados) {
      qtdProd += v.itens.fold<int>(0, (s, i) => s + i.quantidade.round().abs());
      if (v.itens.isEmpty) qtdProd += 1;
      bruto += v.subtotal > 0 ? v.subtotal : v.total + v.desconto;
      desc += v.desconto;
      total += v.total;
    }

    return (
      vendas: filtrados,
      resumo: CreditoRelatorioVendasResumo(
        qtdCompras: filtrados.length,
        qtdProdutos: qtdProd,
        valorBruto: bruto,
        descontos: desc,
        valorTotal: total,
      ),
    );
  }

  static Future<
      ({
        List<Map<String, dynamic>> recebimentos,
        Map<String, ComercialCliente> clientes,
        CreditoRelatorioRecebimentosResumo resumo,
      })> carregarRecebimentos({
    required String lojaId,
    required DateTime dataDe,
    required DateTime dataAte,
    String? clienteId,
    String? formaPagamento,
    String? status,
  }) async {
    final de = DateTime(dataDe.year, dataDe.month, dataDe.day);
    final ate = DateTime(dataAte.year, dataAte.month, dataAte.day, 23, 59, 59);
    final todos =
        await ComercialCreditoService.listarRecebimentosLoja(lojaId);
    final clientesLista = await ComercialClientesService.listar(lojaId);
    final mapa = {for (final c in clientesLista) c.id: c};

    DateTime? asDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final filtrados = <Map<String, dynamic>>[];
    for (final r in todos) {
      final dt = asDate(r['data_pagamento'] ?? r['criado_em']);
      if (dt == null) continue;
      if (dt.isBefore(de) || dt.isAfter(ate)) continue;
      final cid = (r['cliente_id'] ?? '').toString();
      if (clienteId != null && clienteId.isNotEmpty && cid != clienteId) {
        continue;
      }
      final forma = (r['forma_pagamento'] ?? '').toString();
      if (formaPagamento != null &&
          formaPagamento.isNotEmpty &&
          formaPagamento != 'Todos' &&
          forma.toLowerCase() != formaPagamento.toLowerCase()) {
        continue;
      }
      final st = (r['status'] ?? 'confirmado').toString();
      if (status != null &&
          status.isNotEmpty &&
          status != 'Todos' &&
          st.toLowerCase() != status.toLowerCase()) {
        continue;
      }
      filtrados.add(r);
    }

    filtrados.sort((a, b) {
      final da = asDate(a['data_pagamento']) ?? DateTime(1970);
      final db = asDate(b['data_pagamento']) ?? DateTime(1970);
      return db.compareTo(da);
    });

    var principal = 0.0, juros = 0.0, multas = 0.0, descontos = 0.0, liquido = 0.0;
    for (final r in filtrados) {
      final pago = (r['valor_pago'] as num?)?.toDouble() ?? 0;
      final j = (r['valor_juros'] as num?)?.toDouble() ?? 0;
      final m = (r['valor_multa'] as num?)?.toDouble() ?? 0;
      final d = (r['valor_desconto'] as num?)?.toDouble() ?? 0;
      juros += j;
      multas += m;
      descontos += d;
      liquido += pago;
      principal += (pago - j - m + d).clamp(0, double.infinity);
    }

    return (
      recebimentos: filtrados,
      clientes: mapa,
      resumo: CreditoRelatorioRecebimentosResumo(
        quantidade: filtrados.length,
        valorPrincipal: principal,
        juros: juros,
        multas: multas,
        descontos: descontos,
        liquido: liquido,
      ),
    );
  }

  /// Código do produto a partir do item bruto (quando disponível).
  static String codigoProdutoDoItem(Map<String, dynamic>? raw, String nome) {
    if (raw == null) return '—';
    final c = (raw['codigo'] ??
            raw['sku'] ??
            raw['produto_codigo'] ??
            raw['codigo_produto'] ??
            raw['produto_id'] ??
            '')
        .toString()
        .trim();
    return c.isEmpty ? '—' : c;
  }
}
