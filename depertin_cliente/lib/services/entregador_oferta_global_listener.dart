import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/services/android_nav_intent.dart';

/// Listener GLOBAL de ofertas para entregador.
///
/// Por quê existe isto?
///   O listener de ofertas do `EntregadorDashboardScreen`
///   (`_ofertaFullscreenSub`) só existe enquanto o dashboard está montado.
///   Se o entregador estiver em **qualquer outra tela** (configurações,
///   histórico, veículos, chat, suporte, etc.), o dashboard é descartado
///   e o listener é cancelado em `dispose()`. A partir desse momento, a
///   ÚNICA forma de a oferta aparecer seria via push FCM — que em foreground
///   + Doze + OEMs agressivos (Xiaomi/Realme/Oppo) é historicamente frágil.
///
/// O que fazemos aqui:
///   - Um singleton que observa `FirebaseAuth.currentUser`.
///   - Quando há user autenticado, lê o doc `/users/{uid}`. Se o role é
///     `entregador`, começa a observar pedidos onde
///     `despacho_oferta_uid == uid` e `status == aguardando_entregador`.
///   - Ao detectar uma nova oferta (seq maior que a última aberta por
///     este listener), chama
///     [AndroidNavIntent.openIncomingDeliveryScreen] para abrir a tela
///     nativa fullscreen. A guarda nativa
///     (`IncomingDeliveryFlowState.shouldShowNotification`) e o deduplicador
///     em memória deste singleton evitam abrir duas vezes.
///   - Quando o user faz logout, tudo é desligado.
///
/// Esse listener É COMPLEMENTAR ao do dashboard: os dois podem coexistir
/// sem efeito colateral porque a tela nativa já tem seu próprio controle
/// de re-entrância por `request_id`.
class EntregadorOfertaGlobalListener with WidgetsBindingObserver {
  EntregadorOfertaGlobalListener._();
  static final EntregadorOfertaGlobalListener instance =
      EntregadorOfertaGlobalListener._();

  bool _iniciado = false;

  StreamSubscription<User?>? _authSub;

  /// Observa o doc do user atual pra saber `role` (só entregadores
  /// recebem ofertas). Sem esse stream, um admin/lojista logado receberia
  /// queries inúteis e consumiria cota Firestore sem propósito.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  /// Listener real das ofertas — só ativado quando o user é entregador.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ofertasSub;

  String? _uidAtual;
  String? _roleAtual;

  /// Dedup interno: `pedidoId → maior despacho_oferta_seq já aberto`.
  /// Evita pedir pra abrir a tela nativa duas vezes para a MESMA oferta
  /// (ex.: snapshot repetido após reconexão). Uma nova oferta para o
  /// mesmo pedido tem `seq` maior — libera novo abrir.
  final Map<String, int> _ultimaSeqAbertaPorPedido = <String, int>{};

  /// Ponto único de ativação — chamar uma vez no boot do app
  /// (`main.dart`, após `Firebase.initializeApp`).
  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChange);
  }

  /// Reinscreve o stream de ofertas quando o app volta do background.
  /// Firestore costuma manter a subscription viva, mas em OEMs agressivos
  /// a conexão pode ter sido morta silenciosamente. Recriar é barato e
  /// evita perda silenciosa de oferta.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = _uidAtual;
    final role = _roleAtual;
    if (uid == null || role != 'entregador') return;
    _ressubscreverOfertas(uid);
  }

  void _onAuthChange(User? user) {
    final novoUid = user?.uid;
    if (novoUid == _uidAtual) return;
    _uidAtual = novoUid;
    _roleAtual = null;
    _descartarOfertasSub();
    _descartarUserDocSub();
    if (novoUid == null) return;
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(novoUid)
        .snapshots()
        .listen((snap) => _onUserDoc(novoUid, snap));
  }

  void _onUserDoc(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (uid != _uidAtual) return;
    final data = snap.data();
    final roleBruto =
        (data?['role'] ?? data?['tipoUsuario'] ?? '').toString().toLowerCase();
    final novoRole = roleBruto.isEmpty ? null : roleBruto;
    if (novoRole == _roleAtual) return;
    _roleAtual = novoRole;
    _ressubscreverOfertas(uid);
  }

  void _ressubscreverOfertas(String uid) {
    _descartarOfertasSub();
    if (_roleAtual != 'entregador') return;
    _ofertasSub = FirebaseFirestore.instance
        .collection('pedidos')
        .where('status', isEqualTo: PedidoStatus.aguardandoEntregador)
        .where('despacho_oferta_uid', isEqualTo: uid)
        .snapshots()
        .listen(_onOfertasSnapshot, onError: (Object e, StackTrace s) {
      debugPrint('[EntregadorOfertaGlobalListener] stream erro: $e');
    });
  }

  Future<void> _onOfertasSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (snap.docs.isEmpty) return;
    try {
      final processadas = await AndroidNavIntent.getOfertasProcessadasLocais();
      for (final doc in snap.docs) {
        final data = doc.data();
        final seqAtual = (data['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
        if (seqAtual <= 0) continue;

        final seqDecididoLocal = processadas[doc.id];
        if (seqDecididoLocal != null && seqAtual <= seqDecididoLocal) {
          continue;
        }

        final ultimaAberta = _ultimaSeqAbertaPorPedido[doc.id] ?? 0;
        if (seqAtual <= ultimaAberta) continue;

        final payload = _montarPayload(doc.id, data);
        final ok = await AndroidNavIntent.openIncomingDeliveryScreen(payload);
        if (ok) {
          _ultimaSeqAbertaPorPedido[doc.id] = seqAtual;
        }
      }
    } catch (e) {
      debugPrint('[EntregadorOfertaGlobalListener] $e');
    }
  }

  Map<String, String> _montarPayload(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) {
    final expiraTs = pedido['despacho_oferta_expira_em'] as Timestamp?;
    final expiraMs = expiraTs?.millisecondsSinceEpoch ?? 0;
    final seq = (pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
    final requestId = seq > 0 ? '$pedidoId:$seq' : pedidoId;

    String s(dynamic v) => (v ?? '').toString();

    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String && v.isNotEmpty) return double.tryParse(v);
      return null;
    }

    final taxaBruta = asNum(pedido['taxa_entrega']) ?? 0.0;
    final taxaEntregador = asNum(pedido['taxa_entregador']) ?? 0.0;
    final valorLiquido = asNum(pedido['valor_liquido_entregador']) ??
        (taxaBruta - taxaEntregador).clamp(0, double.infinity).toDouble();

    return <String, String>{
      'orderId': pedidoId,
      'order_id': pedidoId,
      'request_order_id': pedidoId,
      'request_id': requestId,
      'despacho_oferta_seq': seq.toString(),
      'despacho_expira_em_ms': expiraMs.toString(),
      'evento': 'dispatch_request',
      'tipoNotificacao': 'nova_entrega',
      'segmento': 'entregador',
      'loja_nome': s(pedido['loja_nome'] ?? pedido['nome_loja']),
      'loja_foto_url': s(pedido['loja_foto_url']),
      'loja_logo_url': s(pedido['loja_logo_url']),
      'loja_imagem_url': s(pedido['loja_imagem_url']),
      'loja_foto': s(pedido['loja_foto']),
      'store_photo_url': s(pedido['store_photo_url']),
      'store_logo_url': s(pedido['store_logo_url']),
      'store_image_url': s(pedido['store_image_url']),
      'pickup_location': s(pedido['loja_endereco']),
      'delivery_location': s(pedido['endereco_entrega']),
      'delivery_fee': taxaBruta.toStringAsFixed(2),
      'net_delivery_fee': valorLiquido.toStringAsFixed(2),
      'plataforma_fee': taxaEntregador.toStringAsFixed(2),
      'distance_to_store_km':
          (asNum(pedido['distancia_entregador_loja_km']) ?? 0).toStringAsFixed(2),
      'distance_store_to_customer_km':
          (asNum(pedido['distancia_loja_cliente_km']) ?? 0).toStringAsFixed(2),
      'tempo_estimado_min': s(pedido['tempo_estimado_min']),
    };
  }

  void _descartarOfertasSub() {
    _ofertasSub?.cancel();
    _ofertasSub = null;
  }

  void _descartarUserDocSub() {
    _userDocSub?.cancel();
    _userDocSub = null;
  }

  /// Chamado raramente (ex.: hot restart durante dev). Não é estritamente
  /// necessário em runtime pois o app mantém o singleton até ser killed.
  @visibleForTesting
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _authSub = null;
    _descartarUserDocSub();
    _descartarOfertasSub();
    _iniciado = false;
    _uidAtual = null;
    _roleAtual = null;
    _ultimaSeqAbertaPorPedido.clear();
  }
}
