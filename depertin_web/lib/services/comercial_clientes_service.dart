import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:intl/intl.dart';

/// CRUD e agregações de `users/{lojaId}/clientes_comercial`.
abstract final class ComercialClientesService {
  static const _limitePedidos = 5000;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _numero = NumberFormat('#,##0', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dataHora = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  static CollectionReference<Map<String, dynamic>> _col(String lojaId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(lojaId)
          .collection('clientes_comercial');

  static String formatarMoeda(double v) => _moeda.format(v);
  static String formatarNumero(int v) => _numero.format(v);
  static String formatarData(DateTime? d) => d == null ? '—' : _data.format(d);
  static String formatarDataHora(DateTime? d) =>
      d == null ? '—' : _dataHora.format(d);

  /// Resumo de pedidos entregues para um cliente específico.
  static ClientePedidoResumo resumoParaCliente(
    ComercialCliente cliente,
    Map<String, ClientePedidoResumo> resumos,
  ) {
    final chaves = <String>{
      cliente.id,
      if (cliente.cpf != null && cliente.cpf!.isNotEmpty)
        'cpf:${_normCpf(cliente.cpf)}',
      if (cliente.telefone != null && cliente.telefone!.isNotEmpty)
        'tel:${_normTel(cliente.telefone)}',
    };
    double total = 0;
    DateTime? ultima;
    for (final k in chaves) {
      final r = resumos[k];
      if (r == null) continue;
      total += r.total;
      if (ultima == null || (r.ultima != null && r.ultima!.isAfter(ultima))) {
        ultima = r.ultima;
      }
    }
    return ClientePedidoResumo(total: total, ultima: ultima);
  }

  /// Total comprado e última compra a partir dos lançamentos carregados.
  static ClientePedidoResumo historicoDeLancamentos(
    List<ComercialClienteLancamento> lancamentos,
  ) {
    double total = 0;
    DateTime? ultima;
    for (final l in lancamentos) {
      if (!ComercialClienteLancamento.statusContaComoCompra(l.status)) continue;
      total += l.total;
      if (l.dataHora != null &&
          (ultima == null || l.dataHora!.isAfter(ultima))) {
        ultima = l.dataHora;
      }
    }
    return ClientePedidoResumo(total: total, ultima: ultima);
  }

  /// Texto de pendências financeiras (parcelas do crediário).
  static String rotuloPendenciasCliente(ComercialResumoParcelas resumo) {
    if (resumo.totalEmAberto <= 0.009) return 'Nenhuma';
    if (resumo.parcelasVencidas > 0) {
      return '${formatarMoeda(resumo.totalEmAberto)} · '
          '${resumo.parcelasVencidas} atrasada${resumo.parcelasVencidas > 1 ? 's' : ''}';
    }
    return '${formatarMoeda(resumo.totalEmAberto)} em aberto';
  }

  /// Total comprado e última compra a partir das vendas a crédito.
  static ClientePedidoResumo historicoDeVendasCredito(
    List<ComercialVendaCredito> vendas,
  ) {
    double total = 0;
    DateTime? ultima;
    for (final v in vendas) {
      total += v.valorTotal;
      final data = v.dataCompra ?? v.createdAt;
      if (data != null && (ultima == null || data.isAfter(ultima))) {
        ultima = data;
      }
    }
    return ClientePedidoResumo(total: total, ultima: ultima);
  }

  /// Escolhe o melhor total/data entre várias fontes (evita dupla contagem).
  static ClientePedidoResumo melhorResumoHistorico(
    Iterable<ClientePedidoResumo> fontes,
  ) {
    double total = 0;
    DateTime? ultima;
    for (final f in fontes) {
      if (f.total > total) total = f.total;
      if (f.ultima != null && (ultima == null || f.ultima!.isAfter(ultima))) {
        ultima = f.ultima;
      }
    }
    return ClientePedidoResumo(total: total, ultima: ultima);
  }

  static Future<void> _carregarPedidosPorIds(
    Iterable<String> ids,
    void Function(String id, Map<String, dynamic> dados) onDoc,
  ) async {
    final unicos = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (unicos.isEmpty) return;

    final lista = unicos.toList(growable: false);
    for (var i = 0; i < lista.length; i += 10) {
      final lote = lista.skip(i).take(10).toList(growable: false);
      final snaps = await Future.wait(
        lote.map(
          (id) => FirebaseFirestore.instance.collection('pedidos').doc(id).get(),
        ),
      );
      for (final snap in snaps) {
        if (!snap.exists) continue;
        onDoc(snap.id, safeWebDocData(snap));
      }
    }
  }

  /// Lançamentos (vendas/pedidos) do cliente — PDV e marketplace da loja.
  static Future<List<ComercialClienteLancamento>> carregarLancamentosCliente({
    required String lojaId,
    required ComercialCliente cliente,
    int limite = 80,
    List<ComercialParcelaCliente>? parcelasCliente,
    List<ComercialVendaCredito>? vendasCredito,
  }) async {
    final vistos = <String>{};
    final lista = <ComercialClienteLancamento>[];

    void adicionarDoc(String id, Map<String, dynamic> dados) {
      if (vistos.contains(id)) return;
      if (!_pedidoPertenceAoCliente(dados, cliente)) return;
      vistos.add(id);
      lista.add(ComercialClienteLancamento.fromPedidoDoc(id, dados));
    }

    try {
      final porId = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: lojaId)
          .where('cliente_id', isEqualTo: cliente.id)
          .orderBy('data_pedido', descending: true)
          .limit(limite)
          .get();
      for (final doc in porId.docs) {
        adicionarDoc(doc.id, safeWebDocData(doc));
      }
    } catch (_) {
      // Índice composto pode não existir ainda — fallback abaixo.
    }

    if (lista.length < limite) {
      try {
        final inicio = DateTime.now().subtract(const Duration(days: 730));
        final snap = await FirebaseFirestore.instance
            .collection('pedidos')
            .where('loja_id', isEqualTo: lojaId)
            .where('data_pedido',
                isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
            .orderBy('data_pedido', descending: true)
            .limit(_limitePedidos)
            .get();
        for (final doc in snap.docs) {
          if (lista.length >= limite) break;
          adicionarDoc(doc.id, safeWebDocData(doc));
        }
      } catch (_) {
        // Fallback: busca só por loja (sem orderBy) e filtra no cliente.
        try {
          final snap = await FirebaseFirestore.instance
              .collection('pedidos')
              .where('loja_id', isEqualTo: lojaId)
              .limit(_limitePedidos)
              .get();
          for (final doc in snap.docs) {
            if (lista.length >= limite) break;
            adicionarDoc(doc.id, safeWebDocData(doc));
          }
        } catch (_) {}
      }
    }

    final idsCredito = <String>{
      ...?parcelasCliente?.map((p) => p.vendaId),
      ...?vendasCredito?.map((v) => v.vendaId),
    };
    await _carregarPedidosPorIds(idsCredito, adicionarDoc);

    lista.sort((a, b) {
      final da = a.dataHora ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.dataHora ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    final parcelas = parcelasCliente ?? const <ComercialParcelaCliente>[];
    final enriquecidos = lista
        .take(limite)
        .map((l) => l.comStatusPagamento(parcelas))
        .toList(growable: false);
    return enriquecidos;
  }

  static bool _pedidoPertenceAoCliente(
    Map<String, dynamic> d,
    ComercialCliente cliente,
  ) {
    final cid = d['cliente_id']?.toString().trim();
    if (cid != null && cid.isNotEmpty && cid == cliente.id) return true;

    final cpfDoc = d['cliente_cpf'] ?? d['cpf_cliente'];
    if (cliente.cpf != null &&
        cliente.cpf!.isNotEmpty &&
        cpfDoc != null &&
        _normCpf(cpfDoc) == _normCpf(cliente.cpf)) {
      return true;
    }

    final telDoc = d['cliente_telefone'] ?? d['telefone_cliente'];
    if (cliente.telefone != null &&
        cliente.telefone!.isNotEmpty &&
        telDoc != null &&
        _normTel(telDoc) == _normTel(cliente.telefone)) {
      return true;
    }

    return false;
  }

  static Stream<List<ComercialCliente>> streamClientes(String lojaId) {
    return _col(lojaId).snapshots().map((snap) {
      final lista = snap.docs
          .map(
            (d) => ComercialCliente.fromDoc(
              d.id,
              lojaId,
              safeWebDocData(d),
            ),
          )
          .toList();
      lista.sort(_ordenarPorRecentes);
      return lista;
    });
  }

  /// Resumos de pedidos (total/última compra) — carregar uma vez e mesclar na UI.
  static Future<Map<String, ClientePedidoResumo>> carregarResumosPedidos(
    String lojaId,
  ) async {
    final raw = await _carregarResumosPedidos(lojaId);
    return raw.map((k, v) => MapEntry(k, ClientePedidoResumo(total: v.total, ultima: v.ultima)));
  }

  static List<ComercialCliente> aplicarResumosPedidos(
    List<ComercialCliente> clientes,
    Map<String, ClientePedidoResumo> resumos,
  ) {
    if (resumos.isEmpty) return clientes;
    return clientes
        .map(
          (c) => _enriquecerComResumos(
            c,
            resumos.map(
              (k, v) => MapEntry(
                k,
                _ResumoPedidoCliente(total: v.total, ultima: v.ultima),
              ),
            ),
          ),
        )
        .toList();
  }

  static ComercialCliente _enriquecerComResumos(
    ComercialCliente c,
    Map<String, _ResumoPedidoCliente> resumos,
  ) {
    final chaves = <String>{
      c.id,
      if (c.cpf != null && c.cpf!.isNotEmpty) 'cpf:${_normCpf(c.cpf)}',
      if (c.telefone != null && c.telefone!.isNotEmpty) 'tel:${_normTel(c.telefone)}',
    };
    double total = 0;
    DateTime? ultima;
    for (final k in chaves) {
      final r = resumos[k];
      if (r == null) continue;
      total += r.total;
      if (ultima == null || (r.ultima != null && r.ultima!.isAfter(ultima))) {
        ultima = r.ultima;
      }
    }
    return c.copyWith(totalComprado: total, ultimaCompra: ultima);
  }

  static Future<List<ComercialCliente>> listar(String lojaId) async {
    final snap = await _col(lojaId).get();
    final lista = snap.docs
        .map(
          (d) => ComercialCliente.fromDoc(d.id, lojaId, safeWebDocData(d)),
        )
        .toList();
    lista.sort(_ordenarPorRecentes);
    final resumos = await carregarResumosPedidos(lojaId);
    return aplicarResumosPedidos(lista, resumos);
  }

  static int _ordenarPorRecentes(ComercialCliente a, ComercialCliente b) {
    final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  }

  /// Lista simplificada para integração PDV (atalho F3).
  static Future<List<Map<String, dynamic>>> listarParaPdv(String lojaId) async {
    final clientes = await listar(lojaId);
    return clientes
        .where((c) => c.status != 'bloqueado')
        .map((c) => c.toPdvMap())
        .toList();
  }

  static ComercialClientesIndicadores calcularIndicadores(
    List<ComercialCliente> clientes,
  ) {
    final total = clientes.length;
    var ativos = 0;
    var comCredito = 0;
    var comPendencias = 0;
    for (final c in clientes) {
      if (c.statusExibicao == 'ativo') ativos++;
      if (c.temCredito) comCredito++;
      if (c.temPendenciaAberta) comPendencias++;
    }
    return ComercialClientesIndicadores(
      total: total,
      ativos: ativos,
      comCredito: comCredito,
      comPendencias: comPendencias,
    );
  }

  static Future<String> salvar({
    required String lojaId,
    required ComercialCliente cliente,
    String? id,
  }) async {
    final docId = (id ?? cliente.id).trim();
    final criando = docId.isEmpty;
    final dados = cliente.toFirestore(criando: criando);
    if (criando) {
      final ref = await _col(lojaId).add(dados);
      return ref.id;
    }
    await _col(lojaId).doc(docId).set(dados, SetOptions(merge: true));
    return docId;
  }

  static Future<void> excluir(String lojaId, String id) =>
      _col(lojaId).doc(id).delete();

  static Future<void> bloquear(String lojaId, String id, {required bool bloquear}) =>
      _col(lojaId).doc(id).update({
        'status': bloquear ? 'bloqueado' : 'ativo',
        'updated_at': FieldValue.serverTimestamp(),
      });

  static Future<Map<String, _ResumoPedidoCliente>> _carregarResumosPedidos(
    String lojaId,
  ) async {
    try {
      return await _carregarResumosPedidosComposto(lojaId);
    } catch (_) {
      try {
        return await _carregarResumosPedidosFallback(lojaId);
      } catch (_) {
        return {};
      }
    }
  }

  static Future<Map<String, _ResumoPedidoCliente>> _carregarResumosPedidosComposto(
    String lojaId,
  ) async {
    final inicio = DateTime.now().subtract(const Duration(days: 730));
    final snap = await FirebaseFirestore.instance
        .collection('pedidos')
        .where('loja_id', isEqualTo: lojaId)
        .where('status', isEqualTo: 'entregue')
        .where('data_pedido', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
        .orderBy('data_pedido', descending: true)
        .limit(_limitePedidos)
        .get();
    return _agregarResumosPedidos(snap.docs);
  }

  static Future<Map<String, _ResumoPedidoCliente>> _carregarResumosPedidosFallback(
    String lojaId,
  ) async {
    final inicio = DateTime.now().subtract(const Duration(days: 730));
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: lojaId)
          .where('data_pedido', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .orderBy('data_pedido', descending: true)
          .limit(_limitePedidos)
          .get();
    } catch (_) {
      snap = await FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: lojaId)
          .limit(_limitePedidos)
          .get();
    }
    return _agregarResumosPedidos(snap.docs);
  }

  static Map<String, _ResumoPedidoCliente> _agregarResumosPedidos(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <String, _ResumoPedidoCliente>{};
    for (final doc in docs) {
      final d = safeWebDocData(doc);
      if ((d['status'] ?? '').toString() != 'entregue') continue;

      final valor = _numPedido(d);
      final data = _parseDataPedido(d['data_pedido'] ?? d['data_entrega']);
      if (data == null) continue;

      void add(String key) {
        final atual = map[key];
        if (atual == null) {
          map[key] = _ResumoPedidoCliente(total: valor, ultima: data);
        } else {
          map[key] = _ResumoPedidoCliente(
            total: atual.total + valor,
            ultima: atual.ultima == null || data.isAfter(atual.ultima!)
                ? data
                : atual.ultima,
          );
        }
      }

      final cid = d['cliente_id']?.toString().trim();
      if (cid != null && cid.isNotEmpty && cid != 'venda_balcao') add(cid);

      final cpf = d['cliente_cpf'] ?? d['cpf_cliente'];
      if (cpf != null) add('cpf:${_normCpf(cpf)}');

      final tel = d['cliente_telefone'] ?? d['telefone_cliente'];
      if (tel != null) add('tel:${_normTel(tel)}');
    }
    return map;
  }

  static double _numPedido(Map<String, dynamic> d) {
    final v = d['valor_total'] ?? d['total'] ?? d['valor_produtos'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDataPedido(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v?.toString() ?? '');
  }

  static String _normCpf(dynamic v) =>
      v.toString().replaceAll(RegExp(r'\D'), '');

  static String _normTel(dynamic v) =>
      v.toString().replaceAll(RegExp(r'\D'), '');

  /// Filtra clientes por nome ou CPF (busca local).
  static List<ComercialCliente> filtrarClientesBusca(
    List<ComercialCliente> todos,
    String query, {
    int limite = 40,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return todos.take(limite).toList();
    final cpfQ = q.replaceAll(RegExp(r'\D'), '');
    return todos
        .where((c) {
          if (c.nome.toLowerCase().contains(q)) return true;
          if (cpfQ.length >= 3) {
            final cpf = (c.cpf ?? '').replaceAll(RegExp(r'\D'), '');
            if (cpf.contains(cpfQ)) return true;
          }
          final tel = (c.telefone ?? '').replaceAll(RegExp(r'\D'), '');
          if (cpfQ.length >= 4 && tel.contains(cpfQ)) return true;
          return false;
        })
        .take(limite)
        .toList();
  }

  /// Clientes com parcelas em aberto na loja.
  static Future<List<ClientePendenciaResumo>> carregarClientesComPendencias(
    String lojaId,
  ) async {
    final clientes = await listar(lojaId);
    final mapaClientes = {for (final c in clientes) c.id: c};

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(lojaId)
        .collection('parcelas_cliente')
        .get();

    final porCliente = <String, List<ComercialParcelaCliente>>{};
    for (final doc in snap.docs) {
      final p = ComercialParcelaCliente.fromDoc(doc.id, safeWebDocData(doc));
      if (!p.podeReceber) continue;
      porCliente.putIfAbsent(p.clienteId, () => []).add(p);
    }

    final lista = <ClientePendenciaResumo>[];
    for (final entry in porCliente.entries) {
      final cliente = mapaClientes[entry.key];
      if (cliente == null) continue;
      final resumo = ComercialCreditoService.calcularResumo(entry.value);
      if (resumo.totalEmAberto <= 0.009) continue;
      lista.add(
        ClientePendenciaResumo(
          cliente: cliente,
          totalEmAberto: resumo.totalEmAberto,
          parcelasVencidas: resumo.parcelasVencidas,
          proximoVencimento: resumo.proximaParcela?.dataVencimento,
        ),
      );
    }

    lista.sort((a, b) => b.totalEmAberto.compareTo(a.totalEmAberto));
    return lista;
  }

  static String formatarCpfExibicao(String? cpf) {
    if (cpf == null || cpf.isEmpty) return '—';
    final d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return cpf;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }
}

class _ResumoPedidoCliente {
  const _ResumoPedidoCliente({required this.total, this.ultima});
  final double total;
  final DateTime? ultima;
}

/// Resumo agregado de pedidos por cliente (chave doc/cpf/tel).
class ClientePedidoResumo {
  const ClientePedidoResumo({required this.total, this.ultima});
  final double total;
  final DateTime? ultima;
}

/// Cliente com pendências financeiras (parcelas em aberto).
class ClientePendenciaResumo {
  const ClientePendenciaResumo({
    required this.cliente,
    required this.totalEmAberto,
    required this.parcelasVencidas,
    this.proximoVencimento,
  });

  final ComercialCliente cliente;
  final double totalEmAberto;
  final int parcelasVencidas;
  final DateTime? proximoVencimento;
}

/// Pont temporário para abrir o PDV com cliente pré-selecionado (F3 / Nova venda).
abstract final class PdvClientePendente {
  static Map<String, dynamic>? _cliente;

  static void definir(Map<String, dynamic> cliente) => _cliente = cliente;

  static Map<String, dynamic>? consumir() {
    final c = _cliente;
    _cliente = null;
    return c;
  }
}
