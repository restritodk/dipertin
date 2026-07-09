import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/firebase_functions_config.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Crediário: vendas, parcelas e recebimentos em `users/{lojaId}/…`.
abstract final class ComercialCreditoService {
  static CollectionReference<Map<String, dynamic>> _vendasCol(String lojaId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('vendas_credito');

  static CollectionReference<Map<String, dynamic>> _parcelasCol(String lojaId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('parcelas_cliente');

  static CollectionReference<Map<String, dynamic>> _recebimentosCol(
    String lojaId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('recebimentos_cliente');

  static DocumentReference<Map<String, dynamic>> _clienteDoc(
    String lojaId,
    String clienteId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('clientes_comercial')
          .doc(clienteId);

  static double _roundMoney(double v) =>
      (v * 100).roundToDouble() / 100;

  static Stream<List<ComercialParcelaCliente>> streamParcelasCliente(
    String lojaId,
    String clienteId,
  ) {
    return _parcelasCol(lojaId)
        .where('cliente_id', isEqualTo: clienteId)
        .orderBy('data_vencimento', descending: false)
        .snapshots()
        .map((snap) => _ordenarParcelas(_mapParcelasDocs(snap.docs)));
  }

  /// Carga única de parcelas (perfil / lançamentos).
  static Future<List<ComercialParcelaCliente>> carregarParcelasCliente(
    String lojaId,
    String clienteId,
  ) async {
    final snap = await _parcelasCol(lojaId)
        .where('cliente_id', isEqualTo: clienteId)
        .get();
    return _ordenarParcelas(_mapParcelasDocs(snap.docs));
  }

  /// Vendas a crédito do cliente (carga única).
  static Future<List<ComercialVendaCredito>> carregarVendasCreditoCliente(
    String lojaId,
    String clienteId,
  ) async {
    final snap = await _vendasCol(lojaId)
        .where('cliente_id', isEqualTo: clienteId)
        .get();
    final lista = snap.docs
        .map((d) => ComercialVendaCredito.fromDoc(d.id, safeWebDocData(d)))
        .toList();
    lista.sort((a, b) {
      final da = a.dataCompra ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.dataCompra ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return lista;
  }

  static List<ComercialParcelaCliente> _mapParcelasDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .map((d) => ComercialParcelaCliente.fromDoc(d.id, safeWebDocData(d)))
          .toList();

  static List<ComercialParcelaCliente> _ordenarParcelas(
    List<ComercialParcelaCliente> lista,
  ) {
    lista.sort((a, b) {
      final cmpVenc = a.dataVencimento.compareTo(b.dataVencimento);
      if (cmpVenc != 0) return cmpVenc;
      return a.numeroParcela.compareTo(b.numeroParcela);
    });
    return lista;
  }

  static ComercialResumoParcelas calcularResumo(
    List<ComercialParcelaCliente> parcelas,
  ) {
    if (parcelas.isEmpty) return ComercialResumoParcelas.vazio;

    double aberto = 0;
    double pago = 0;
    var vencidas = 0;
    ComercialParcelaCliente? proxima;

    for (final p in parcelas) {
      pago += p.valorPago;
      aberto += p.valorEmAberto;
      if (p.status == ComercialParcelaStatus.vencido) vencidas++;
      if (p.podeReceber && proxima == null) proxima = p;
    }

    return ComercialResumoParcelas(
      totalEmAberto: _roundMoney(aberto),
      totalPago: _roundMoney(pago),
      parcelasVencidas: vencidas,
      proximaParcela: proxima,
    );
  }

  /// Cria venda a crédito + parcelas e consome limite do cliente (PDV).
  static Future<void> criarVendaCreditoDoPdv({
    required String lojaId,
    required String clienteId,
    required String pedidoId,
    required String codigoPedido,
    required double valorTotal,
    required int quantidadeParcelas,
    double valorEntrada = 0,
    int? diaVencimentoCredito,
    DateTime? dataCompra,
  }) async {
    if (quantidadeParcelas < 1) quantidadeParcelas = 1;
    valorEntrada = _roundMoney(valorEntrada.clamp(0, valorTotal));
    final financiado = _roundMoney(valorTotal - valorEntrada);
    if (financiado <= 0) return;

    final clienteSnap = await _clienteDoc(lojaId, clienteId).get();
    if (!clienteSnap.exists) {
      throw StateError('Cliente comercial não encontrado.');
    }
    final clienteData = safeWebDocData(clienteSnap);
    final limite = _num(clienteData['limite_credito']);
    final usado = _num(clienteData['credito_utilizado']);
    final disponivel = limite - usado;
    if (financiado > disponivel + 0.009) {
      throw StateError(
        'Limite insuficiente. Disponível: R\$ ${disponivel.toStringAsFixed(2)}',
      );
    }

    final compra = dataCompra ?? DateTime.now();
    final parcelas = _gerarParcelas(
      quantidade: quantidadeParcelas,
      valorFinanciado: financiado,
      dataCompra: compra,
      diaVencimento: diaVencimentoCredito ?? compra.day,
    );

    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      final clienteRef = _clienteDoc(lojaId, clienteId);
      final clienteTx = await tx.get(clienteRef);
      if (!clienteTx.exists) throw StateError('Cliente não encontrado.');

      final cData = clienteTx.data() ?? {};
      final lim = _num(cData['limite_credito']);
      var util = _num(cData['credito_utilizado']);
      final disp = lim - util;
      if (financiado > disp + 0.009) {
        throw StateError('Limite de crédito insuficiente.');
      }

      util = _roundMoney((util + financiado).clamp(0, lim));

      final vendaRef = _vendasCol(lojaId).doc();
      tx.set(vendaRef, {
        'loja_id': lojaId,
        'cliente_id': clienteId,
        'venda_id': pedidoId,
        'codigo_venda': codigoPedido,
        'valor_total': valorTotal,
        'quantidade_parcelas': quantidadeParcelas,
        'valor_entrada': valorEntrada,
        'valor_financiado': financiado,
        'status': 'ativo',
        'data_compra': Timestamp.fromDate(compra),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      for (var i = 0; i < parcelas.length; i++) {
        final p = parcelas[i];
        final parcelaRef = _parcelasCol(lojaId).doc();
        tx.set(parcelaRef, {
          'loja_id': lojaId,
          'cliente_id': clienteId,
          'venda_credito_id': vendaRef.id,
          'venda_id': pedidoId,
          'codigo_venda': codigoPedido,
          'numero_parcela': p.numero,
          'valor_parcela': p.valor,
          'valor_pago': 0,
          'valor_em_aberto': p.valor,
          'data_compra': Timestamp.fromDate(compra),
          'data_vencimento': Timestamp.fromDate(p.vencimento),
          'status': ComercialParcelaStatus.emAberto,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      tx.update(clienteRef, {
        'credito_utilizado': util,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<ComercialRecebimentoResult> registrarPagamentoParcela({
    required String lojaId,
    required ComercialCliente cliente,
    required ComercialParcelaCliente parcela,
    required double valorPago,
    required String formaPagamento,
    String? observacao,
    String? lojaNome,
    double valorMulta = 0,
    double valorJuros = 0,
    double valorDesconto = 0,
  }) async {
    valorPago = _roundMoney(valorPago);
    if (valorPago <= 0) throw ArgumentError('Informe um valor válido.');
    if (valorPago > parcela.valorEmAberto + 0.009) {
      throw ArgumentError('Valor maior que o saldo em aberto da parcela.');
    }

    final user = FirebaseAuth.instance.currentUser;
    final usuarioId = user?.uid ?? '';
    final usuarioNome =
        user?.displayName ?? user?.email?.split('@').first ?? 'Lojista';

    final db = FirebaseFirestore.instance;
    late String recebimentoId;
    late ComercialParcelaCliente parcelaAtualizada;
    final agora = DateTime.now();
    final vendaCreditoId = parcela.vendaCreditoId;

    await db.runTransaction((tx) async {
      final parcelaRef = _parcelasCol(lojaId).doc(parcela.id);
      final clienteRef = _clienteDoc(lojaId, cliente.id);

      final pSnap = await tx.get(parcelaRef);
      final cSnap = await tx.get(clienteRef);
      if (!pSnap.exists) throw StateError('Parcela não encontrada.');
      if (!cSnap.exists) throw StateError('Cliente não encontrado.');

      final pAtual = ComercialParcelaCliente.fromDoc(
        pSnap.id,
        pSnap.data() ?? {},
      );
      final aberto = pAtual.valorEmAberto;
      if (valorPago > aberto + 0.009) {
        throw ArgumentError('Valor excede o saldo em aberto.');
      }

      final novoPago = _roundMoney(pAtual.valorPago + valorPago);
      final novoAberto =
          _roundMoney((pAtual.valorParcela - novoPago).clamp(0, double.infinity));
      final novoStatus = ComercialParcelaStatus.calcular(
        valorParcela: pAtual.valorParcela,
        valorPago: novoPago,
        dataVencimento: pAtual.dataVencimento,
      );

      tx.update(parcelaRef, {
        'valor_pago': novoPago,
        'valor_em_aberto': novoAberto,
        'status': novoStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });

      final cData = cSnap.data() ?? {};
      final limite = _num(cData['limite_credito']);
      var utilizado = _num(cData['credito_utilizado']);
      utilizado = _roundMoney((utilizado - valorPago).clamp(0, limite));

      tx.update(clienteRef, {
        'credito_utilizado': utilizado,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // ── Legado: users/{lojaId}/recebimentos_cliente ──
      final recRef = _recebimentosCol(lojaId).doc();
      recebimentoId = recRef.id;
      tx.set(recRef, {
        'loja_id': lojaId,
        'cliente_id': cliente.id,
        'parcela_id': parcela.id,
        'venda_id': pAtual.vendaId,
        'codigo_venda': pAtual.codigoVenda,
        'numero_parcela': pAtual.numeroParcela,
        'valor_pago': valorPago,
        'forma_pagamento': formaPagamento,
        if (observacao != null && observacao.trim().isNotEmpty)
          'observacao': observacao.trim(),
        'usuario_id': usuarioId,
        'usuario_nome': usuarioNome,
        'data_pagamento': Timestamp.fromDate(agora),
        'valor_restante_apos': novoAberto,
        'created_at': FieldValue.serverTimestamp(),
      });

      // ── Nova coleção: gestao_comercial_recebimentos (atômico) ──
      final novaRef = db.collection('gestao_comercial_recebimentos').doc();
      tx.set(novaRef, {
        'loja_id': lojaId,
        'cliente_id': cliente.id,
        'cliente_nome': cliente.nome,
        'cliente_documento': cliente.cpf ?? '',
        'pedido_id': pAtual.vendaId,
        'parcela_id': parcela.id,
        'valor_original': pAtual.valorParcela,
        'valor_recebido': valorPago,
        'valor_multa': valorMulta,
        'valor_juros': valorJuros,
        'valor_desconto': valorDesconto,
        'forma_pagamento': formaPagamento,
        'recebido_por_id': usuarioId,
        'recebido_por_nome': lojaNome,
        'data_recebimento': Timestamp.fromDate(agora),
        'observacao': (observacao ?? '').trim(),
        'comprovante_url': '',
        'status': 'confirmado',
        'estornado_em': null,
        'estornado_por': null,
        'motivo_estorno': null,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      parcelaAtualizada = pAtual.copyWith(
        valorPago: novoPago,
        status: novoStatus,
      );
    });

    await _atualizarStatusVendaSeQuitada(lojaId, vendaCreditoId);

    // Atualizar gestao_comercial_vendas (histórico) após pagamento de parcela
    if (parcela.vendaId.isNotEmpty) {
      try {
        final histRef =
            db.collection('gestao_comercial_vendas').doc(parcela.vendaId);
        final histSnap = await histRef.get();
        if (histSnap.exists) {
          final hData = histSnap.data() ?? {};
          final curPago = _num(hData['valor_pago']);
          final curPend = _num(hData['valor_pendente']);
          final novoPend =
              (curPend - valorPago).clamp(0, double.infinity).toDouble();
          await histRef.update({
            'valor_pago': _roundMoney(curPago + valorPago),
            'valor_pendente': _roundMoney(novoPend),
            'status': novoPend <= 0.009 ? 'pago' : 'parcial',
            if (novoPend <= 0.009)
              'data_pago_em': Timestamp.fromDate(agora),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        // silencioso — registro histórico não crítico
      }
    }

    await _auditarFinanceiro(
      evento: 'comercial_recebimento_parcela',
      lojaId: lojaId,
      clienteId: cliente.id,
      detalhe: {
        'recebimento_id': recebimentoId,
        'parcela_id': parcela.id,
        'valor_pago': valorPago,
        'forma_pagamento': formaPagamento,
        'codigo_venda': parcela.codigoVenda,
      },
    );

    return ComercialRecebimentoResult(
      recebimentoId: recebimentoId,
      parcela: parcelaAtualizada,
      valorPago: valorPago,
      valorRestante: parcelaAtualizada.valorEmAberto,
      formaPagamento: formaPagamento,
      dataPagamento: agora,
      clienteNome: cliente.nome,
      clienteCpf: cliente.cpf,
      clienteTelefone: cliente.telefone,
      lojaNome: lojaNome ?? 'Loja',
      usuarioNome: usuarioNome,
    );
  }

  static List<_ParcelaGerada> _gerarParcelas({
    required int quantidade,
    required double valorFinanciado,
    required DateTime dataCompra,
    required int diaVencimento,
  }) {
    final base = _roundMoney(valorFinanciado / quantidade);
    final lista = <_ParcelaGerada>[];
    var acumulado = 0.0;

    for (var i = 1; i <= quantidade; i++) {
      var valor = base;
      if (i == quantidade) {
        valor = _roundMoney(valorFinanciado - acumulado);
      }
      acumulado = _roundMoney(acumulado + valor);
      lista.add(
        _ParcelaGerada(
          numero: i,
          valor: valor,
          vencimento: _calcularVencimento(
            dataCompra: dataCompra,
            diaVencimento: diaVencimento,
            mesOffset: i,
          ),
        ),
      );
    }
    return lista;
  }

  static DateTime _calcularVencimento({
    required DateTime dataCompra,
    required int diaVencimento,
    required int mesOffset,
  }) {
    var year = dataCompra.year;
    var month = dataCompra.month + mesOffset;
    while (month > 12) {
      month -= 12;
      year++;
    }
    final ultimoDia = DateTime(year, month + 1, 0).day;
    final dia = diaVencimento.clamp(1, ultimoDia);
    return DateTime(year, month, dia);
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  /// Aumenta o limite total de crédito do cliente comercial.
  static Future<ComercialCliente> concederLimiteAdicional({
    required String lojaId,
    required ComercialCliente cliente,
    required double valorAdicionar,
    String? observacao,
  }) async {
    valorAdicionar = _roundMoney(valorAdicionar);
    if (valorAdicionar <= 0) {
      throw ArgumentError('Informe um valor maior que zero.');
    }

    final ref = _clienteDoc(lojaId, cliente.id);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('Cliente não encontrado.');

    final antes = safeWebDocData(snap);
    final limiteAntes = _num(antes['limite_credito']);
    final limiteNovo = _roundMoney(limiteAntes + valorAdicionar);
    final obsAntiga = (antes['observacao_credito'] ?? '').toString().trim();
    final obsNova = observacao?.trim();
    final obsFinal = obsNova != null && obsNova.isNotEmpty
        ? (obsAntiga.isEmpty ? obsNova : '$obsAntiga\n$obsNova')
        : obsAntiga;

    await ref.update({
      'limite_credito': limiteNovo,
      'credito_habilitado': true,
      if (obsFinal.isNotEmpty) 'observacao_credito': obsFinal,
      'updated_at': FieldValue.serverTimestamp(),
    });

    await _auditarFinanceiro(
      evento: 'comercial_credito_limite_concedido',
      lojaId: lojaId,
      clienteId: cliente.id,
      detalhe: {
        'limite_anterior': limiteAntes,
        'limite_novo': limiteNovo,
        'valor_adicionado': valorAdicionar,
        if (obsNova != null && obsNova.isNotEmpty) 'observacao': obsNova,
      },
    );

    final atualizado = await ref.get();
    return ComercialCliente.fromDoc(
      cliente.id,
      lojaId,
      safeWebDocData(atualizado),
      totalComprado: cliente.totalComprado,
      ultimaCompra: cliente.ultimaCompra,
    );
  }

  /// Parcelas de toda a loja (stream).
  static Stream<List<ComercialParcelaCliente>> streamParcelasLoja(
    String lojaId, {
    int limite = 3000,
  }) {
    return _parcelasCol(lojaId)
        .orderBy('data_vencimento', descending: false)
        .limit(limite)
        .snapshots()
        .map((snap) => _ordenarParcelas(_mapParcelasDocs(snap.docs)));
  }

  /// Carga única de parcelas da loja.
  static Future<List<ComercialParcelaCliente>> carregarParcelasLoja(
    String lojaId, {
    int limite = 3000,
  }) async {
    try {
      final snap = await _parcelasCol(lojaId)
          .orderBy('data_vencimento', descending: false)
          .limit(limite)
          .get();
      return _ordenarParcelas(_mapParcelasDocs(snap.docs));
    } catch (_) {
      final snap = await _parcelasCol(lojaId).limit(limite).get();
      return _ordenarParcelas(_mapParcelasDocs(snap.docs));
    }
  }

  /// Recebimentos da loja (stream).
  static Stream<List<ComercialRecebimentoCliente>> streamRecebimentosLoja(
    String lojaId, {
    int limite = 2000,
  }) {
    return _recebimentosCol(lojaId)
        .orderBy('data_pagamento', descending: true)
        .limit(limite)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => ComercialRecebimentoCliente.fromDoc(
                  d.id,
                  safeWebDocData(d),
                ),
              )
              .toList(),
        );
  }

  /// Recebimentos da loja (exportação / relatórios).
  static Future<List<Map<String, dynamic>>> listarRecebimentosLoja(
    String lojaId, {
    int limite = 2000,
  }) async {
    try {
      final snap = await _recebimentosCol(lojaId)
          .orderBy('data_pagamento', descending: true)
          .limit(limite)
          .get();
      return _mapRecebimentos(snap.docs);
    } catch (_) {
      final snap = await _recebimentosCol(lojaId).limit(limite).get();
      return _mapRecebimentos(snap.docs);
    }
  }

  static List<Map<String, dynamic>> _mapRecebimentos(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.map((d) {
        final m = Map<String, dynamic>.from(safeWebDocData(d));
        m['id'] = d.id;
        return m;
      }).toList();

  static Future<void> _auditarFinanceiro({
    required String evento,
    required String lojaId,
    required String clienteId,
    Map<String, dynamic>? detalhe,
  }) async {
    try {
      await callFirebaseFunctionSafe(
        'registrarEventoAuditoriaApp',
        timeout: const Duration(seconds: 12),
        parameters: <String, dynamic>{
          'evento': evento,
          'categoria': 'comercial_financeiro',
          'plataforma': 'painel_web',
          'detalhe': <String, dynamic>{
            'loja_id': lojaId,
            'cliente_id': clienteId,
            ...?detalhe,
          },
        },
      );
    } catch (_) {}
  }

  static Future<void> _atualizarStatusVendaSeQuitada(
    String lojaId,
    String vendaCreditoId,
  ) async {
    if (vendaCreditoId.isEmpty) return;
    final snap = await _parcelasCol(lojaId)
        .where('venda_credito_id', isEqualTo: vendaCreditoId)
        .get();
    if (snap.docs.isEmpty) return;
    for (final doc in snap.docs) {
      final p = ComercialParcelaCliente.fromDoc(doc.id, doc.data());
      if (p.valorEmAberto > 0.009) return;
    }
    await _vendasCol(lojaId).doc(vendaCreditoId).update({
      'status': 'quitado',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}

class _ParcelaGerada {
  const _ParcelaGerada({
    required this.numero,
    required this.valor,
    required this.vencimento,
  });

  final int numero;
  final double valor;
  final DateTime vencimento;
}
