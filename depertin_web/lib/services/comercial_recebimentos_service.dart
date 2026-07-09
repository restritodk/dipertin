import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';

// -----------------------------------------------------------------------------
/// Modelo de um recebimento do Gestão Comercial.
///
/// Coleção: `gestao_comercial_recebimentos/{id}`
/// Filtro obrigatório por `lojaId`.
// -----------------------------------------------------------------------------
class ComercialRecebimento {
  ComercialRecebimento({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    required this.clienteNome,
    this.clienteDocumento,
    this.pedidoId,
    this.parcelaId,
    required this.valorOriginal,
    required this.valorRecebido,
    this.valorMulta = 0,
    this.valorJuros = 0,
    this.valorDesconto = 0,
    required this.formaPagamento,
    this.recebidoPorId,
    this.recebidoPorNome,
    required this.dataRecebimento,
    this.observacao,
    this.comprovanteUrl,
    this.status = 'confirmado',
    this.estornadoEm,
    this.estornadoPor,
    this.motivoEstorno,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String lojaId;
  final String clienteId;
  final String clienteNome;
  final String? clienteDocumento;
  final String? pedidoId;
  final String? parcelaId;
  final double valorOriginal;
  final double valorRecebido;
  final double valorMulta;
  final double valorJuros;
  final double valorDesconto;
  final String formaPagamento;
  final String? recebidoPorId;
  final String? recebidoPorNome;
  final DateTime dataRecebimento;
  final String? observacao;
  final String? comprovanteUrl;
  final String status; // confirmado | estornado
  final DateTime? estornadoEm;
  final String? estornadoPor;
  final String? motivoEstorno;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get valorTotalComEncargos =>
      valorOriginal + valorMulta + valorJuros - valorDesconto;

  factory ComercialRecebimento.fromDoc(
    String id,
    Map<String, dynamic> d,
  ) {
    return ComercialRecebimento(
      id: id,
      lojaId: (d['loja_id'] ?? '').toString(),
      clienteId: (d['cliente_id'] ?? '').toString(),
      clienteNome: (d['cliente_nome'] ?? '').toString(),
      clienteDocumento: (d['cliente_documento'] ?? '').toString(),
      pedidoId: (d['pedido_id'] ?? '').toString(),
      parcelaId: (d['parcela_id'] ?? '').toString(),
      valorOriginal: _num(d['valor_original']),
      valorRecebido: _num(d['valor_recebido']),
      valorMulta: _num(d['valor_multa']),
      valorJuros: _num(d['valor_juros']),
      valorDesconto: _num(d['valor_desconto']),
      formaPagamento: (d['forma_pagamento'] ?? '').toString(),
      recebidoPorId: (d['recebido_por_id'] ?? '').toString(),
      recebidoPorNome: (d['recebido_por_nome'] ?? '').toString(),
      dataRecebimento: _ts(d['data_recebimento']) ?? DateTime.now(),
      observacao: (d['observacao'] ?? '').toString(),
      comprovanteUrl: (d['comprovante_url'] ?? '').toString(),
      status: (d['status'] ?? 'confirmado').toString(),
      estornadoEm: _ts(d['estornado_em']),
      estornadoPor: (d['estornado_por'] ?? '').toString(),
      motivoEstorno: (d['motivo_estorno'] ?? '').toString(),
      createdAt: _ts(d['created_at']),
      updatedAt: _ts(d['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'loja_id': lojaId,
        'cliente_id': clienteId,
        'cliente_nome': clienteNome,
        'cliente_documento': clienteDocumento,
        'pedido_id': pedidoId,
        'parcela_id': parcelaId,
        'valor_original': valorOriginal,
        'valor_recebido': valorRecebido,
        'valor_multa': valorMulta,
        'valor_juros': valorJuros,
        'valor_desconto': valorDesconto,
        'forma_pagamento': formaPagamento,
        'recebido_por_id': recebidoPorId,
        'recebido_por_nome': recebidoPorNome,
        'data_recebimento': Timestamp.fromDate(dataRecebimento),
        'observacao': observacao ?? '',
        'comprovante_url': comprovanteUrl ?? '',
        'status': status,
        'estornado_em': estornadoEm != null
            ? Timestamp.fromDate(estornadoEm!)
            : null,
        'estornado_por': estornadoPor,
        'motivo_estorno': motivoEstorno,
        'created_at': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

  static double _num(dynamic v) =>
      (v as num?)?.toDouble() ?? 0.0;
  static DateTime? _ts(dynamic v) =>
      (v as Timestamp?)?.toDate();
}

/// Resumo para os cards superiores.
class ComercialRecebimentosResumo {
  const ComercialRecebimentosResumo({
    this.recebidoHoje = 0,
    this.quantidadeHoje = 0,
    this.recebidoMes = 0,
    this.variacaoMes = 0,
    this.parcelasRecebidas = 0,
    this.ticketMedio = 0,
    this.clientesPagantes = 0,
    this.porForma = const {},
    this.maioresRecebimentos = const [],
    this.totalGeral = 0,
    this.totalRecebimentos = 0,
  });

  final double recebidoHoje;
  final int quantidadeHoje;
  final double recebidoMes;
  final double variacaoMes;
  final int parcelasRecebidas;
  final double ticketMedio;
  final int clientesPagantes;
  final Map<String, Map<String, double>> porForma;
  final List<ComercialRecebimento> maioresRecebimentos;
  final double totalGeral;
  final int totalRecebimentos;
}

// -----------------------------------------------------------------------------
/// Serviço responsável por ler e escrever recebimentos do Gestão Comercial.
///
/// Coleção principal: `gestao_comercial_recebimentos`
/// Também lê da subcoleção `users/{lojaId}/recebimentos_cliente` (legado).
// -----------------------------------------------------------------------------
abstract final class ComercialRecebimentosService {
  /// Coleção principal de recebimentos (top-level).
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance.collection('gestao_comercial_recebimentos');

  /// Subcoleção legada em users/{lojaId}/recebimentos_cliente
  static CollectionReference<Map<String, dynamic>> _recebimentosLegadoCol(
    String lojaId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('recebimentos_cliente');

  // ─── CRUD ─────────────────────────────────────────────────────────────

  /// Cria um documento em `gestao_comercial_recebimentos`.
  static Future<String> criar({
    required String lojaId,
    required String clienteId,
    required String clienteNome,
    String? clienteDocumento,
    String? pedidoId,
    String? parcelaId,
    required double valorOriginal,
    required double valorRecebido,
    double valorMulta = 0,
    double valorJuros = 0,
    double valorDesconto = 0,
    required String formaPagamento,
    String? recebidoPorId,
    String? recebidoPorNome,
    String? observacao,
  }) async {
    final agora = DateTime.now();
    final ref = _col().doc();
    final data = {
      'loja_id': lojaId,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'cliente_documento': clienteDocumento ?? '',
      'pedido_id': pedidoId ?? '',
      'parcela_id': parcelaId ?? '',
      'valor_original': valorOriginal,
      'valor_recebido': valorRecebido,
      'valor_multa': valorMulta,
      'valor_juros': valorJuros,
      'valor_desconto': valorDesconto,
      'forma_pagamento': formaPagamento,
      'recebido_por_id': recebidoPorId ?? '',
      'recebido_por_nome': recebidoPorNome ?? '',
      'data_recebimento': Timestamp.fromDate(agora),
      'observacao': observacao ?? '',
      'comprovante_url': '',
      'status': 'confirmado',
      'estornado_em': null,
      'estornado_por': null,
      'motivo_estorno': null,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
    return ref.id;
  }

  /// Estorna um recebimento: atualiza status e reabre a parcela.
  static Future<void> estornar({
    required String recebimentoId,
    required String motivo,
    required String estornadoPor,
  }) async {
    final db = FirebaseFirestore.instance;
    final ref = _col().doc(recebimentoId);

    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Recebimento não encontrado.');
      final d = snap.data()!;
      if (d['status'] == 'estornado') {
        throw StateError('Recebimento já foi estornado.');
      }

      tx.update(ref, {
        'status': 'estornado',
        'estornado_em': FieldValue.serverTimestamp(),
        'estornado_por': estornadoPor,
        'motivo_estorno': motivo,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Reabrir parcela vinculada se existir
      final parcelaId = (d['parcela_id'] ?? '').toString();
      final lojaId = (d['loja_id'] ?? '').toString();
      if (parcelaId.isNotEmpty && lojaId.isNotEmpty) {
        final parcelaRef = FirebaseFirestore.instance
            .collection('users')
            .doc(lojaId)
            .collection('parcelas_cliente')
            .doc(parcelaId);
        final pSnap = await tx.get(parcelaRef);
        if (pSnap.exists) {
          final pData = safeWebDocData(pSnap);
          final valorParcela = (pData['valor_parcela'] as num?)?.toDouble() ?? 0;
          tx.update(parcelaRef, {
            'valor_pago': 0,
            'valor_em_aberto': valorParcela,
            'status': 'em_aberto',
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    });
  }

  // ─── LEITURA ──────────────────────────────────────────────────────────

  /// Stream principal de recebimentos da loja.
  static Stream<List<ComercialRecebimento>> streamRecebimentos(
    String lojaId, {
    DateTime? inicio,
    DateTime? fim,
    String? formaPagamento,
    String? recebidoPor,
    String? busca,
  }) {
    Query<Map<String, dynamic>> q = _col()
        .where('loja_id', isEqualTo: lojaId)
        .orderBy('data_recebimento', descending: true);

    if (inicio != null && fim != null) {
      q = q
          .where('data_recebimento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data_recebimento',
              isLessThanOrEqualTo: Timestamp.fromDate(fim));
    }

    return q.snapshots().map((snap) {
      var lista = snap.docs
          .map((d) => ComercialRecebimento.fromDoc(d.id, safeWebDocData(d)))
          .toList();

      if (formaPagamento != null && formaPagamento != 'Todas') {
        lista = lista.where((r) => r.formaPagamento == formaPagamento).toList();
      }
      if (recebidoPor != null && recebidoPor != 'Todos' && recebidoPor.isNotEmpty) {
        lista = lista
            .where((r) =>
                (r.recebidoPorNome ?? '').toLowerCase().contains(recebidoPor.toLowerCase()))
            .toList();
      }
      if (busca != null && busca.trim().isNotEmpty) {
        final q = busca.trim().toLowerCase();
        lista = lista
            .where((r) =>
                r.clienteNome.toLowerCase().contains(q) ||
                (r.clienteDocumento ?? '').contains(q) ||
                (r.pedidoId ?? '').toLowerCase().contains(q))
            .toList();
      }

      return lista;
    });
  }

  /// Carga única com suporte a paginação.
  static Future<List<ComercialRecebimento>> carregarRecebimentos(
    String lojaId, {
    DateTime? inicio,
    DateTime? fim,
    String? formaPagamento,
    String? recebidoPor,
    String? busca,
    int limite = 100,
  }) async {
    Query<Map<String, dynamic>> q = _col()
        .where('loja_id', isEqualTo: lojaId)
        .orderBy('data_recebimento', descending: true)
        .limit(limite);

    if (inicio != null && fim != null) {
      q = q
          .where('data_recebimento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .where('data_recebimento',
              isLessThanOrEqualTo: Timestamp.fromDate(fim));
    }

    try {
      final snap = await q.get();
      var lista = snap.docs
          .map((d) => ComercialRecebimento.fromDoc(d.id, safeWebDocData(d)))
          .toList();

      if (formaPagamento != null && formaPagamento != 'Todas') {
        lista = lista.where((r) => r.formaPagamento == formaPagamento).toList();
      }
      if (recebidoPor != null && recebidoPor != 'Todos' && recebidoPor.isNotEmpty) {
        lista = lista.where((r) =>
            (r.recebidoPorNome ?? '').toLowerCase().contains(recebidoPor.toLowerCase())).toList();
      }
      if (busca != null && busca.trim().isNotEmpty) {
        final qry = busca.trim().toLowerCase();
        lista = lista.where((r) =>
            r.clienteNome.toLowerCase().contains(qry) ||
            (r.clienteDocumento ?? '').contains(qry) ||
            (r.pedidoId ?? '').toLowerCase().contains(qry)).toList();
      }

      return lista;
    } catch (_) {
      return [];
    }
  }

  /// Calcula os resumos dos cards a partir de uma lista de recebimentos.
  static ComercialRecebimentosResumo calcularResumo(
    List<ComercialRecebimento> recebimentos,
  ) {
    final hoje = DateTime.now();
    final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
    final inicioMes = DateTime(hoje.year, hoje.month, 1);
    final mesPassadoInicio = DateTime(hoje.year, hoje.month - 1, 1);
    final mesPassadoFim =
        DateTime(hoje.year, hoje.month, 1).subtract(const Duration(days: 1));

    var recebidoHoje = 0.0;
    var qtdHoje = 0;
    var recebidoMes = 0.0;
    var recebidoMesPassado = 0.0;
    final porForma = <String, Map<String, double>>{};

    for (final r in recebimentos) {
      if (r.status == 'estornado') continue;
      final data = DateTime(
        r.dataRecebimento.year,
        r.dataRecebimento.month,
        r.dataRecebimento.day,
      );

      // Hoje
      if (data.isAtSameMomentAs(hojeClean)) {
        recebidoHoje += r.valorRecebido;
        qtdHoje++;
      }

      // Mês atual
      if (!data.isBefore(inicioMes) && !data.isAfter(hojeClean)) {
        recebidoMes += r.valorRecebido;
        porForma.update(
          r.formaPagamento,
          (v) => {
            'total': (v['total'] ?? 0) + r.valorRecebido,
            'qtd': (v['qtd'] ?? 0) + 1,
          },
          ifAbsent: () => {'total': r.valorRecebido, 'qtd': 1.0},
        );
      }

      // Mês passado
      if (!data.isBefore(mesPassadoInicio) &&
          !data.isAfter(mesPassadoFim)) {
        recebidoMesPassado += r.valorRecebido;
      }
    }

    final variacao = recebidoMesPassado > 0
        ? ((recebidoMes - recebidoMesPassado) / recebidoMesPassado) * 100
        : (recebidoMes > 0 ? 100.0 : 0.0);

    // Ticket médio
    final totalRecebimentosMes = recebimentos
        .where((r) =>
            r.status != 'estornado' &&
            !DateTime(r.dataRecebimento.year, r.dataRecebimento.month,
                    r.dataRecebimento.day)
                .isBefore(inicioMes) &&
            !DateTime(r.dataRecebimento.year, r.dataRecebimento.month,
                    r.dataRecebimento.day)
                .isAfter(hojeClean))
        .toList();
    final ticketMedio = totalRecebimentosMes.isNotEmpty
        ? recebidoMes / totalRecebimentosMes.length
        : 0.0;

    // Clientes pagantes
    final clientesSet = <String>{};
    for (final r in totalRecebimentosMes) {
      clientesSet.add(r.clienteId);
    }

    // Maiores recebimentos do período
    final sorted = List<ComercialRecebimento>.from(recebimentos)
      ..sort((a, b) => b.valorRecebido.compareTo(a.valorRecebido));
    final maiores = sorted.take(5).toList();

    return ComercialRecebimentosResumo(
      recebidoHoje: _arredondar(recebidoHoje),
      quantidadeHoje: qtdHoje,
      recebidoMes: _arredondar(recebidoMes),
      variacaoMes: _arredondar(variacao),
      parcelasRecebidas: totalRecebimentosMes.length,
      ticketMedio: _arredondar(ticketMedio),
      clientesPagantes: clientesSet.length,
      porForma: porForma,
      maioresRecebimentos: maiores,
      totalGeral: recebidoMes,
      totalRecebimentos: totalRecebimentosMes.length,
    );
  }

  /// Busca recebimentos legados (migração para nova coleção).
  static Future<List<ComercialRecebimento>> migrarLegados(
    String lojaId,
  ) async {
    final snap = await _recebimentosLegadoCol(lojaId)
        .orderBy('data_pagamento', descending: true)
        .get();

    final resultados = <ComercialRecebimento>[];
    for (final d in snap.docs) {
      final data = safeWebDocData(d);
      resultados.add(ComercialRecebimento(
        id: d.id,
        lojaId: lojaId,
        clienteId: (data['cliente_id'] ?? '').toString(),
        clienteNome: (data['cliente_nome'] ?? '').toString(),
        clienteDocumento: (data['cliente_documento'] ?? '').toString(),
        pedidoId: (data['venda_id'] ?? '').toString(),
        parcelaId: (data['parcela_id'] ?? '').toString(),
        valorOriginal:
            ((data['valor_recebido'] ?? data['valor_pago'] ?? 0) as num)
                .toDouble(),
        valorRecebido: ((data['valor_pago'] ?? 0) as num).toDouble(),
        formaPagamento: (data['forma_pagamento'] ?? 'Dinheiro').toString(),
        recebidoPorId: (data['usuario_id'] ?? '').toString(),
        recebidoPorNome: (data['usuario_nome'] ?? '').toString(),
        dataRecebimento: _ts(data['data_pagamento']) ?? DateTime.now(),
        observacao: (data['observacao'] ?? '').toString(),
        status: 'confirmado',
        createdAt: _ts(data['created_at']),
        updatedAt: _ts(data['updated_at']),
      ));
    }
    return resultados;
  }

  static double _arredondar(double v) =>
      (v * 100).roundToDouble() / 100;

  static DateTime? _ts(dynamic v) =>
      (v as Timestamp?)?.toDate();
}

/// Formata moeda no padrão brasileiro.
String formatarMoeda(double v) {
  final inteiro = v.floor();
  final centavos = ((v - inteiro) * 100).round().toString().padLeft(2, '0');
  final milhar = inteiro >= 1000
      ? inteiro.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          )
      : inteiro.toString();
  return 'R\$ $milhar,$centavos';
}

/// Formata data curta: dd/mm/aaaa.
String formatarData(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';

/// Formata hora: hh:mm.
String formatarHora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Formata data + hora.
String formatarDataHora(DateTime d) =>
    '${formatarData(d)} ${formatarHora(d)}';
