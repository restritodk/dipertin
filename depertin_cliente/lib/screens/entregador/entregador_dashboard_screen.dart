// Arquivo: lib/screens/entregador/entregador_dashboard_screen.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/services/android_nav_intent.dart';
import 'package:depertin_cliente/services/conta_bloqueio_entregador_service.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/services/permissoes_app_service.dart';
import 'package:depertin_cliente/services/corrida_chamada_entregador_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import 'diagnostico_alertas_corrida_screen.dart';
import 'entrega_concluida_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
const int _kOfertaDuracaoSegundos = 15;

/// Firestore pode devolver [DocumentReference] em campos de uid (legado/import).
String _despachoUidCampo(dynamic v) {
  if (v == null) return '';
  if (v is DocumentReference) return v.id;
  return v.toString().trim();
}

enum _AppNavegacao { googleMaps, waze }

class EntregadorDashboardScreen extends StatefulWidget {
  const EntregadorDashboardScreen({
    super.key,
    this.modoRadarPosEntrega = false,
  });

  /// Após concluir entrega: só o radar, com volta ao [ProfileScreen] (sem
  /// barra Radar/Histórico/Ganhos do [EntregadorHomeScreen]).
  final bool modoRadarPosEntrega;

  @override
  State<EntregadorDashboardScreen> createState() =>
      _EntregadorDashboardScreenState();
}

class _EntregadorDashboardScreenState extends State<EntregadorDashboardScreen>
    with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late String _uid;

  final AudioPlayer _audioPlayer = AudioPlayer();
  int _quantidadePedidosAntiga = 0;

  /// Evita repetir o mesmo alerta sonoro para a mesma sequência de oferta.
  final Map<String, int> _ultimaSeqSomPorPedido = {};

  StreamSubscription<Position>? _rastreadorGps;
  late final Stream<QuerySnapshot> _pedidosStream;

  /// Evita duplo toque enquanto grava no Firestore.
  String? _recusandoPedidoId;
  String? _cancelandoPedidoId;
  final Set<String> _ofertasOcultadasLocalmente = <String>{};
  final Set<String> _pedidosAbrindoConfirmacaoCancelamento = <String>{};
  final Set<String> _pedidosAbrindoRota = <String>{};
  final Set<String> _pedidosAbrindoFluxoEntrega = <String>{};
  final Set<String> _requestsComTelaOficialAberta = <String>{};
  final Map<String, int> _ultimaSeqTelaOficialPorPedido = <String, int>{};
  double? _latAtualLocal;
  double? _lonAtualLocal;
  bool _capturandoPosicaoLocal = false;
  final Map<String, double?> _cacheDistLojaClienteKm = {};
  final Set<String> _resolvendoDistLojaCliente = <String>{};
  final Set<String> _pedidosIndoCliente = <String>{};
  final Set<String> _pedidosSolicitarCodigo = <String>{};
  bool _verificandoPermissoesChamada = false;
  int _pendenciasPermissao = 0;
  bool _floatingIconAtivo = false;

  void _voltarParaMeuPerfil() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (_) => false,
      arguments: 2, // Aba "Perfil" do MainNavigator.
    );
  }

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(',', '.'));
    }
    return null;
  }

  double _ganhoEntregador(Map<String, dynamic> pedido) {
    final liquido = _toDoubleOrNull(pedido['valor_liquido_entregador']);
    if (liquido != null && liquido > 0) {
      return liquido;
    }
    final frete = _toDouble(pedido['taxa_entrega']);
    final desconto = _toDoubleOrNull(pedido['taxa_entregador']) ?? 0;
    return math.max(0, frete - desconto);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uid = _auth.currentUser!.uid;
    _pedidosStream = FirebaseFirestore.instance
        .collection('pedidos')
        .where(
          'status',
          whereIn: [
            PedidoStatus.aguardandoEntregador,
            PedidoStatus.entregadorIndoLoja,
            PedidoStatus.saiuEntrega,
            PedidoStatus.emRota,
            PedidoStatus.aCaminho,
          ],
        )
        .snapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checarConfigAndroidChamadaFullScreen());
      unawaited(_contarPendenciasPermissao());
      unawaited(_syncFloatingIconState());
      unawaited(_ocultarFloatingIconEnquantoAppAberto());
      unawaited(_garantirOnlineApenasComAcaoManual());
    });
  }

  Future<void> _syncFloatingIconState() async {
    final running = await AndroidNavIntent.isFloatingIconRunning();
    if (running) {
      await AndroidNavIntent.stopFloatingIcon();
    }
    if (mounted && running != _floatingIconAtivo) {
      setState(() => _floatingIconAtivo = running);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_contarPendenciasPermissao());
      unawaited(_ocultarFloatingIconEnquantoAppAberto());
    } else if (state == AppLifecycleState.paused) {
      if (_floatingIconAtivo) {
        unawaited(AndroidNavIntent.startFloatingIcon());
      }
    }
  }

  Future<void> _ocultarFloatingIconEnquantoAppAberto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_floatingIconAtivo) return;
    await AndroidNavIntent.stopFloatingIcon();
  }

  Future<void> _garantirOnlineApenasComAcaoManual() async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(_uid);
      final userSnap = await userRef.get();
      final dados = userSnap.data() ?? <String, dynamic>{};
      final onlineAtual = dados['is_online'] == true;
      if (!onlineAtual) return;
      // Mantém online até ação manual do entregador no switch.
      // Não desliga automaticamente ao entrar/sair da tela Radar.
      await _ocultarFloatingIconEnquantoAppAberto();
    } catch (e) {
      debugPrint('[_garantirOnlineApenasComAcaoManual] $e');
    }
  }

  Future<void> _contarPendenciasPermissao() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await AndroidNavIntent.getDeviceInfo();
      final sdk = info['sdk'] as int? ?? 0;

      final checks = await Future.wait([
        sdk < 33
            ? Future.value(true)
            : Permission.notification.status.then((s) => s.isGranted),
        AndroidNavIntent.areNotificationsEnabled(),
        sdk < 34
            ? Future.value(true)
            : AndroidNavIntent.canUseFullScreenIntent(),
        AndroidNavIntent.isIgnoringBatteryOptimizations(),
        AndroidNavIntent.canDrawOverlays(),
      ]);

      int count = 0;
      for (final ok in checks) {
        if (ok != true) count++;
      }

      if (!mounted) return;
      if (count != _pendenciasPermissao) {
        setState(() => _pendenciasPermissao = count);
      }
    } catch (e) {
      debugPrint('[_contarPendenciasPermissao] $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(CorridaChamadaEntregadorAudio.parar());
    _audioPlayer.dispose();
    _pararRastreioGps();
    super.dispose();
  }

  Future<void> _mudarStatusTrabalho(bool ficarOnline) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'is_online': ficarOnline,
      });

      if (ficarOnline) {
        _iniciarRastreioGps();
      } else {
        _pararRastreioGps();
        if (_floatingIconAtivo) {
          await AndroidNavIntent.stopFloatingIcon();
          if (mounted) setState(() => _floatingIconAtivo = false);
        }
      }
    } catch (e) {
      debugPrint('Erro ao mudar status: $e');
    }
  }

  Future<void> _iniciarRastreioGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative o GPS do celular para atualizar sua posição nas corridas.',
            ),
          ),
        );
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      final posInicial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'latitude': posInicial.latitude,
        'longitude': posInicial.longitude,
        'ultima_atualizacao_gps': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _latAtualLocal = posInicial.latitude;
          _lonAtualLocal = posInicial.longitude;
        });
      }
      debugPrint(
        '📍 GPS inicial gravado: ${posInicial.latitude}, ${posInicial.longitude}',
      );
    } catch (e) {
      debugPrint('⚠️ GPS inicial falhou: $e');
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _rastreadorGps =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(_uid)
                .update({
                  'latitude': position.latitude,
                  'longitude': position.longitude,
                  'ultima_atualizacao_gps': FieldValue.serverTimestamp(),
                });
            if (mounted) {
              setState(() {
                _latAtualLocal = position.latitude;
                _lonAtualLocal = position.longitude;
              });
            }
            debugPrint('📍 GPS: ${position.latitude}, ${position.longitude}');
          },
        );
  }

  void _pararRastreioGps() {
    if (_rastreadorGps != null) {
      _rastreadorGps!.cancel();
      _rastreadorGps = null;
      debugPrint('🛑 Rastreador GPS desligado.');
    }
  }

  Future<void> _checarConfigAndroidChamadaFullScreen() async {
    if (!mounted || _verificandoPermissoesChamada) return;
    _verificandoPermissoesChamada = true;
    try {
      final notifStatus =
          await PermissoesAppService.garantirNotificacoesAndroid();
      final okNotif = notifStatus == ResultadoPermissao.concedida;
      final okFull = await AndroidNavIntent.canUseFullScreenIntent();
      final okBateria = await AndroidNavIntent.isIgnoringBatteryOptimizations();
      if (!mounted) return;
      if (okNotif && okFull && okBateria) return;

      final pendencias = <String>[
        if (!okNotif) 'Ativar notificações do app',
        if (!okFull) 'Permitir notificações em tela cheia',
        if (!okBateria) 'Remover restrição de bateria para o DiPertin',
      ];
      final textoPendencias = pendencias.map((e) => '• $e').join('\n');

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Configurar alertas de corrida'),
          content: Text(
            'Para abrir automaticamente a chamada de corrida com o app fechado, em segundo plano ou tela bloqueada, ajuste:\n\n$textoPendencias',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Depois'),
            ),
            FilledButton(
              onPressed: () async {
                if (!okNotif) {
                  await openAppSettings();
                }
                if (!okFull) {
                  await AndroidNavIntent.openFullScreenIntentSettings();
                }
                if (!okBateria) {
                  await AndroidNavIntent.openBatteryOptimizationSettings();
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Configurar agora'),
            ),
          ],
        ),
      );
    } finally {
      _verificandoPermissoesChamada = false;
    }
  }

  Future<void> _garantirPosicaoLocalAtual() async {
    if (_capturandoPosicaoLocal || !mounted) return;
    if (_latAtualLocal != null && _lonAtualLocal != null) return;
    _capturandoPosicaoLocal = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _latAtualLocal = pos.latitude;
        _lonAtualLocal = pos.longitude;
      });
    } catch (_) {
      // Sem interromper a experiência caso não consiga GPS agora.
    } finally {
      _capturandoPosicaoLocal = false;
    }
  }

  static const Set<String> _statusMinhaCorrida = {
    PedidoStatus.emRota,
    PedidoStatus.saiuEntrega,
    PedidoStatus.aCaminho,
    PedidoStatus.entregadorIndoLoja,
  };

  static int _millisDataPedido(Map<String, dynamic> d) {
    final ts = d['data_pedido'];
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    return 0;
  }

  /// Maior = mais avanço na rota (mostrar primeiro). Indo à loja fica por último entre as suas.
  int _prioridadeMinhaCorrida(String pedidoId, Map<String, dynamic> d) {
    final st = d['status'] as String? ?? '';
    if (d['entregador_id'] != _uid || !_statusMinhaCorrida.contains(st)) {
      return 0;
    }
    if (_pedidosSolicitarCodigo.contains(pedidoId)) return 100;
    if (st == PedidoStatus.saiuEntrega ||
        st == PedidoStatus.emRota ||
        st == PedidoStatus.aCaminho ||
        _pedidosIndoCliente.contains(pedidoId)) {
      return 80;
    }
    if (st == PedidoStatus.entregadorIndoLoja) return 20;
    return 10;
  }

  /// Sua corrida em andamento primeiro (a mais avança no topo); depois novas ofertas.
  int _ordenarRadar(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final ma = a.data() as Map<String, dynamic>;
    final mb = b.data() as Map<String, dynamic>;
    final sa = ma['status'] as String? ?? '';
    final sb = mb['status'] as String? ?? '';
    final mineA =
        ma['entregador_id'] == _uid && _statusMinhaCorrida.contains(sa);
    final mineB =
        mb['entregador_id'] == _uid && _statusMinhaCorrida.contains(sb);
    if (mineA && !mineB) return -1;
    if (!mineA && mineB) return 1;
    if (mineA && mineB) {
      final pa = _prioridadeMinhaCorrida(a.id, ma);
      final pb = _prioridadeMinhaCorrida(b.id, mb);
      if (pa != pb) {
        return pa > pb ? -1 : 1;
      }
      final ta = _millisDataPedido(ma);
      final tb = _millisDataPedido(mb);
      if (ta != tb) return ta.compareTo(tb);
      return a.id.compareTo(b.id);
    }
    return 0;
  }

  /// Distância loja do pedido ↔ posição atual do entregador (km), ou null.
  double? _kmDistanciaLojaEntregador(
    Map<String, dynamic> pedido, {
    required double? latEntregador,
    required double? lonEntregador,
  }) {
    final llat = _toDoubleOrNull(pedido['loja_latitude']);
    final llon = _toDoubleOrNull(pedido['loja_longitude']);
    if (llat == null || llon == null || latEntregador == null || lonEntregador == null) {
      return null;
    }
    return Geolocator.distanceBetween(
          llat,
          llon,
          latEntregador,
          lonEntregador,
        ) /
        1000.0;
  }

  /// Oferta direcionada: só o alvo vê. Sem alvo: entregadores num raio de
  /// 40 km veem o pedido no radar (informacional, sem botões de ação).
  bool _entregadorPodeVerPedidoNaLista(
    Map<String, dynamic> data, {
    double? latEntregador,
    double? lonEntregador,
  }) {
    final st = data['status'] as String? ?? '';
    if (st == PedidoStatus.emRota && data['entregador_id'] != _uid) {
      return false;
    }
    if (st == PedidoStatus.saiuEntrega && data['entregador_id'] != _uid) {
      return false;
    }
    if (st == PedidoStatus.entregadorIndoLoja &&
        data['entregador_id'] != _uid) {
      return false;
    }
    if (st == PedidoStatus.aguardandoEntregador) {
      final List<dynamic> recusados = data['despacho_recusados'] ?? const [];
      if (recusados.map((e) => e.toString()).contains(_uid)) {
        return false;
      }
      final alvo = _despachoUidCampo(data['despacho_oferta_uid']);
      if (alvo == _uid) return true;
      if (alvo.isNotEmpty) return false;
      const raioRadarSemAlvoKm = 40.0;
      final km = _kmDistanciaLojaEntregador(
        data,
        latEntregador: latEntregador,
        lonEntregador: lonEntregador,
      );
      return km == null || km <= raioRadarSemAlvoKm;
    }
    return true;
  }

  String _textoDistanciaKm(double? km) {
    if (km == null) return '—';
    if (km < 0.1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  Widget _chipMetrica({
    required IconData icon,
    required String rotulo,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: diPertinRoxo),
          const SizedBox(width: 6),
          Text(
            '$rotulo: $valor',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  double? _distKmLojaCliente(Map<String, dynamic> pedido) {
    final llat = _toDoubleOrNull(pedido['loja_latitude']);
    final llon = _toDoubleOrNull(pedido['loja_longitude']);
    final elat =
        _toDoubleOrNull(pedido['entrega_latitude']) ??
        _toDoubleOrNull(pedido['cliente_latitude']);
    final elon =
        _toDoubleOrNull(pedido['entrega_longitude']) ??
        _toDoubleOrNull(pedido['cliente_longitude']);
    if (llat == null || llon == null || elat == null || elon == null) {
      return null;
    }
    final m = Geolocator.distanceBetween(llat, llon, elat, elon);
    return m / 1000;
  }

  void _resolverDistLojaClienteFallback(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) {
    if (_cacheDistLojaClienteKm.containsKey(pedidoId)) return;
    if (_resolvendoDistLojaCliente.contains(pedidoId)) return;

    final llat = _toDoubleOrNull(pedido['loja_latitude']);
    final llon = _toDoubleOrNull(pedido['loja_longitude']);
    final endereco = (pedido['endereco_entrega'] ?? '').toString().trim();
    if (llat == null || llon == null || endereco.isEmpty) {
      _cacheDistLojaClienteKm[pedidoId] = null;
      return;
    }

    _resolvendoDistLojaCliente.add(pedidoId);
    unawaited(() async {
      double? km;
      try {
        final consultas = <String>[endereco, '$endereco, Brasil'];
        for (final q in consultas) {
          final locs = await locationFromAddress(q);
          if (locs.isEmpty) continue;
          final m = Geolocator.distanceBetween(
            llat,
            llon,
            locs.first.latitude,
            locs.first.longitude,
          );
          km = m / 1000;
          break;
        }
      } catch (_) {
        km = null;
      } finally {
        _resolvendoDistLojaCliente.remove(pedidoId);
        if (mounted) {
          setState(() {
            _cacheDistLojaClienteKm[pedidoId] = km;
          });
        } else {
          _cacheDistLojaClienteKm[pedidoId] = km;
        }
      }
    }());
  }

  void _tentarAlertaSonoro(int quantidade) {
    if (quantidade <= _quantidadePedidosAntiga) return;
    try {
      _audioPlayer.stop();
      _audioPlayer.play(AssetSource('sounds/alerta.mp3'));
    } catch (e) {
      debugPrint('Alerta sonoro: $e');
    }
  }

  void _sincronizarSomChamadaOferta(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) {
    if (_recusandoPedidoId != null) {
      return;
    }
    if (_ofertasOcultadasLocalmente.contains(pedidoId)) return;
    final st = pedido['status'] as String? ?? '';
    if (st != PedidoStatus.aguardandoEntregador) return;
    if (_despachoUidCampo(pedido['despacho_oferta_uid']) != _uid) {
      final seqAtual = (pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
      if (seqAtual > 0) {
        final requestId = _requestIdOferta(pedidoId, pedido);
        _requestsComTelaOficialAberta.remove(requestId);
      }
      return;
    }
    final seq = (pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
    if (seq <= 0) return;
    final anterior = _ultimaSeqSomPorPedido[pedidoId] ?? 0;
    if (seq > anterior) {
      _ultimaSeqSomPorPedido[pedidoId] = seq;
      unawaited(CorridaChamadaEntregadorAudio.tocarChamada());
      unawaited(_abrirTelaOficialChamada(pedidoId, pedido));
    }
  }

  Future<void> _pararSomChamada() async {
    await CorridaChamadaEntregadorAudio.parar();
  }

  String _requestIdOferta(String pedidoId, Map<String, dynamic> pedido) {
    final seq = (pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
    return seq > 0 ? '$pedidoId:$seq' : pedidoId;
  }

  Map<String, String> _payloadTelaOficial(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) {
    final expiraTs = pedido['despacho_oferta_expira_em'] as Timestamp?;
    final expiraMs = expiraTs?.millisecondsSinceEpoch ?? 0;
    final requestId = _requestIdOferta(pedidoId, pedido);
    return <String, String>{
      'orderId': pedidoId,
      'order_id': pedidoId,
      'request_order_id': pedidoId,
      'request_id': requestId,
      'despacho_oferta_seq': ((pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0)
          .toString(),
      'despacho_expira_em_ms': expiraMs.toString(),
      'evento': 'dispatch_request',
      'tipoNotificacao': 'nova_entrega',
      'loja_nome': (pedido['loja_nome'] ?? '').toString(),
      'loja_foto_url': (pedido['loja_foto_url'] ?? '').toString(),
      'loja_logo_url': (pedido['loja_logo_url'] ?? '').toString(),
      'loja_imagem_url': (pedido['loja_imagem_url'] ?? '').toString(),
      'loja_foto': (pedido['loja_foto'] ?? '').toString(),
      'store_photo_url': (pedido['store_photo_url'] ?? '').toString(),
      'store_logo_url': (pedido['store_logo_url'] ?? '').toString(),
      'store_image_url': (pedido['store_image_url'] ?? '').toString(),
      'pickup_location': (pedido['loja_endereco'] ?? '').toString(),
      'delivery_location': (pedido['endereco_entrega'] ?? '').toString(),
      'delivery_fee': _ganhoEntregador(pedido).toStringAsFixed(2),
      'net_delivery_fee': _ganhoEntregador(pedido).toStringAsFixed(2),
      'distance_to_store_km':
          (_kmDistanciaLojaEntregador(pedido, latEntregador: _latAtualLocal, lonEntregador: _lonAtualLocal) ?? 0)
              .toStringAsFixed(2),
      'distance_store_to_customer_km':
          (_distKmLojaCliente(pedido) ?? 0).toStringAsFixed(2),
      'tempo_estimado_min': '',
    };
  }

  Future<void> _abrirTelaOficialChamada(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final requestId = _requestIdOferta(pedidoId, pedido);
    final seqAtual = (pedido['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
    if (requestId.isEmpty || seqAtual <= 0) return;
    if (_requestsComTelaOficialAberta.contains(requestId)) return;
    final ultimaSeqAberta = _ultimaSeqTelaOficialPorPedido[pedidoId] ?? 0;
    if (seqAtual <= ultimaSeqAberta) return;
    _requestsComTelaOficialAberta.add(requestId);
    final payload = _payloadTelaOficial(pedidoId, pedido);
    final abriu = await AndroidNavIntent.openIncomingDeliveryScreen(payload);
    if (abriu) {
      _ultimaSeqTelaOficialPorPedido[pedidoId] = seqAtual;
      await CorridaChamadaEntregadorAudio.silenciarAlertaCorridaCompleto(pedidoId);
      return;
    }
    _requestsComTelaOficialAberta.remove(requestId);
  }

  Future<void> _recusarOferta(String pedidoId) async {
    if (_recusandoPedidoId == pedidoId) return;
    await CorridaChamadaEntregadorAudio.silenciarAlertaCorridaCompleto(pedidoId);
    if (mounted) {
      setState(() {
        _recusandoPedidoId = pedidoId;
        _ofertasOcultadasLocalmente.add(pedidoId);
      });
    }

    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'recusarOfertaCorrida',
      );
      final r = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'pedidoId': pedidoId,
      });
      final dados = r.data;
      final recusado = dados['recusado'] == true;
      final mensagem = recusado
          ? 'Oferta recusada. Aguarde a próxima chamada.'
          : 'Esta oferta já foi encerrada. Aguarde a próxima chamada.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagem), backgroundColor: Colors.grey),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ofertasOcultadasLocalmente.remove(pedidoId);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível recusar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_recusandoPedidoId == pedidoId) _recusandoPedidoId = null;
        });
      }
    }
  }

  Future<void> _cancelarEntregaAtiva(String pedidoId) async {
    if (_cancelandoPedidoId != null) return;
    if (_pedidosAbrindoConfirmacaoCancelamento.contains(pedidoId)) return;
    if (mounted) {
      setState(() {
        _pedidosAbrindoConfirmacaoCancelamento.add(pedidoId);
      });
    }
    // Não bloqueia a confirmação aguardando áudio; popup precisa abrir instantâneo.
    unawaited(_pararSomChamada());
    await Future<void>.delayed(Duration.zero);

    final confirmar = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar entrega'),
        content: const Text('Tem certeza que deseja cancelar esta entrega?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _pedidosAbrindoConfirmacaoCancelamento.remove(pedidoId);
      });
    } else {
      _pedidosAbrindoConfirmacaoCancelamento.remove(pedidoId);
    }

    if (confirmar != true) return;

    if (mounted) {
      setState(() => _cancelandoPedidoId = pedidoId);
    }
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'entregadorCancelarCorridaERedespachar',
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'pedidoId': pedidoId,
      });

      if (!mounted) return;
      setState(() {
        _pedidosIndoCliente.remove(pedidoId);
        _pedidosSolicitarCodigo.remove(pedidoId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entrega cancelada. Corrida reenviada para outro entregador.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final jaLiberado = msg.contains('failed-precondition') ||
          msg.contains('failed_precondition');
      if (jaLiberado) {
        if (!mounted) return;
        setState(() {
          _pedidosIndoCliente.remove(pedidoId);
          _pedidosSolicitarCodigo.remove(pedidoId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta entrega já foi liberada.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final callableNaoPublicada =
          msg.contains('firebase_functions/not-found') ||
          msg.contains('not_found') ||
          msg.contains('not-found');
      if (callableNaoPublicada) {
        try {
          await _cancelarEntregaViaFirestoreFallback(pedidoId);
          if (!mounted) return;
          setState(() {
            _pedidosIndoCliente.remove(pedidoId);
            _pedidosSolicitarCodigo.remove(pedidoId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Entrega cancelada e corrida devolvida para busca de entregador.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        } catch (fallbackErro) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Falha no cancelamento (callable e fallback): $fallbackErro',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cancelar a entrega: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_cancelandoPedidoId == pedidoId) {
            _cancelandoPedidoId = null;
          }
        });
      }
    }
  }

  /// Na fase de oferta (`aguardando_entregador`), "Cancelar" = recusar.
  /// Só após aceite usar [entregadorCancelarCorridaERedespachar].
  Future<void> _cancelarEntregaOuRecusarOferta(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final st = pedido['status'] as String? ?? '';

    if (st == PedidoStatus.aguardandoEntregador) {
      await _recusarOferta(pedidoId);
      return;
    }

    await _cancelarEntregaAtiva(pedidoId);
  }

  Future<void> _cancelarEntregaViaFirestoreFallback(String pedidoId) async {
    final ref = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);
    final uid = _uid;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('Pedido não encontrado.');
      }
      final p = snap.data() ?? <String, dynamic>{};
      final entregadorAtual = (p['entregador_id'] ?? '').toString();
      if (entregadorAtual != uid) {
        throw Exception('Esta corrida não está vinculada ao entregador atual.');
      }

      final statusAtual = (p['status'] ?? '').toString();
      final podeCancelar =
          statusAtual == PedidoStatus.entregadorIndoLoja ||
          statusAtual == PedidoStatus.saiuEntrega ||
          statusAtual == PedidoStatus.emRota ||
          statusAtual == PedidoStatus.aCaminho;
      if (!podeCancelar) {
        throw Exception('Pedido não está em estado de cancelamento.');
      }

      tx.update(ref, {
        'status': PedidoStatus.aguardandoEntregador,
        'cancelado_pelo_entregador': true,
        'cancelado_pelo_entregador_uid': uid,
        'cancelado_pelo_entregador_em': FieldValue.serverTimestamp(),
        'cancelado_pelo_entregador_status_anterior': statusAtual,
        'entregador_id': FieldValue.delete(),
        'entregador_nome': FieldValue.delete(),
        'entregador_foto_url': FieldValue.delete(),
        'entregador_telefone': FieldValue.delete(),
        'entregador_veiculo': FieldValue.delete(),
        'entregador_aceito_em': FieldValue.delete(),
        'despacho_recusados': FieldValue.arrayUnion([uid]),
        'despacho_bloqueados': FieldValue.arrayUnion([uid]),
        'despacho_job_lock': FieldValue.delete(),
        'despacho_abort_flag': FieldValue.delete(),
        'despacho_fila_ids': <String>[],
        'despacho_indice_atual': 0,
        'despacho_oferta_uid': FieldValue.delete(),
        'despacho_oferta_expira_em': FieldValue.delete(),
        'despacho_oferta_seq': 0,
        'despacho_oferta_estado': 'reencaminhando_apos_cancelamento_entregador',
        'despacho_estado': 'aguardando_entregador',
        'despacho_sem_entregadores': FieldValue.delete(),
        'despacho_redirecionado_para_proximo': FieldValue.delete(),
        'despacho_erro_msg': FieldValue.delete(),
        'busca_entregadores_notificados': <String>[],
        'despacho_auto_encerrada_sem_entregador': FieldValue.delete(),
        'despacho_msg_busca_entregador':
            'Entrega cancelada pelo entregador. Buscando novo parceiro automaticamente.',
        'despacho_aguarda_decisao_lojista': FieldValue.delete(),
        'despacho_macro_ciclo_atual': FieldValue.delete(),
        'despacho_busca_extensao_usada': FieldValue.delete(),
        'busca_raio_km': FieldValue.delete(),
        'busca_entregador_inicio': FieldValue.delete(),
      });
    });
  }

  Future<Map<String, dynamic>> _validarCodigoEntregaBackend({
    required String pedidoId,
    required String codigo,
  }) async {
    final callable = appFirebaseFunctions.httpsCallable(
      'entregadorValidarCodigoEntrega',
    );
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'pedidoId': pedidoId,
      'codigo': codigo,
    });
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> _abrirFluxoFinalizarEntrega({
    required String pedidoId,
    required Map<String, dynamic> pedido,
  }) async {
    if (_pedidosAbrindoFluxoEntrega.contains(pedidoId)) return;
    if (mounted) {
      setState(() => _pedidosAbrindoFluxoEntrega.add(pedidoId));
    }
    final controller = TextEditingController();
    try {
      String? erro;
      bool validando = false;
      Map<String, dynamic>? resumo;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              Future<void> confirmar() async {
                final codigo = controller.text.trim().toUpperCase();
                if (codigo.length < 6) {
                  setDialogState(() {
                    erro = 'Informe o código com 6 dígitos.';
                  });
                  return;
                }
                setDialogState(() {
                  validando = true;
                  erro = null;
                });
                try {
                  final resposta = await _validarCodigoEntregaBackend(
                    pedidoId: pedidoId,
                    codigo: codigo,
                  );
                  if (resposta['tokenValido'] != true) {
                    setDialogState(() {
                      erro =
                          (resposta['mensagem']?.toString().trim().isNotEmpty ??
                              false)
                          ? resposta['mensagem'].toString()
                          : 'Código inválido. Confira e tente novamente.';
                      validando = false;
                    });
                    return;
                  }
                  resumo = resposta;
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                } catch (e) {
                  setDialogState(() {
                    erro = 'Falha ao validar código: $e';
                    validando = false;
                  });
                }
              }

              return AlertDialog(
                title: const Text('Entregar e solicitar código'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Digite o código de entrega informado pelo cliente.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      enabled: !validando,
                      maxLength: 6,
                      textCapitalization: TextCapitalization.characters,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Código de 6 dígitos',
                        counterText: '',
                        errorText: erro,
                      ),
                      onSubmitted: (_) {
                        if (!validando) {
                          unawaited(confirmar());
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: validando
                        ? null
                        : () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Voltar'),
                  ),
                  FilledButton(
                    onPressed: validando ? null : confirmar,
                    child: validando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Validar código'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted || resumo == null) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Entrega confirmada'),
          content: const Text('Entrega confirmada com sucesso.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (!mounted) return;

      setState(() {
        _pedidosSolicitarCodigo.remove(pedidoId);
        _pedidosIndoCliente.remove(pedidoId);
      });

      ScaffoldMessenger.of(context).clearSnackBars();

      final valorTotal = _toDouble(
        resumo!['valor_total_corrida'] ?? pedido['taxa_entrega'],
      );
      final taxaPlataforma = _toDouble(
        resumo!['taxa_plataforma'] ?? pedido['taxa_entregador'],
      );
      final valorLiquido = _toDouble(
        resumo!['valor_liquido_entregador'] ?? _ganhoEntregador(pedido),
      );
      final tipoCorrida =
          (resumo!['tipo_corrida'] ?? pedido['tipo_entrega'] ?? '').toString();
      final temProxima = resumo!['tem_proxima_corrida'] == true;
      final proximaId = (resumo!['proxima_corrida_id'] ?? '').toString();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EntregaConcluidaScreen(
            pedidoId: pedidoId,
            valorTotalCorrida: valorTotal,
            taxaPlataforma: taxaPlataforma,
            valorLiquidoEntregador: valorLiquido,
            tipoCorrida: tipoCorrida,
            temProximaCorrida: temProxima,
            proximaCorridaId: proximaId.isEmpty ? null : proximaId,
          ),
        ),
      );
    } finally {
      controller.dispose();
      if (mounted) {
        setState(() => _pedidosAbrindoFluxoEntrega.remove(pedidoId));
      } else {
        _pedidosAbrindoFluxoEntrega.remove(pedidoId);
      }
    }
  }

  Future<_AppNavegacao?> _selecionarAppNavegacao(String titulo) {
    return showModalBottomSheet<_AppNavegacao>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.map_outlined, color: diPertinRoxo),
                  title: const Text('Google Maps'),
                  onTap: () => Navigator.of(ctx).pop(_AppNavegacao.googleMaps),
                ),
                ListTile(
                  leading: const Icon(Icons.navigation, color: diPertinRoxo),
                  title: const Text('Waze'),
                  onTap: () => Navigator.of(ctx).pop(_AppNavegacao.waze),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _abrirPrimeiraUriDisponivel(List<Uri> uris) async {
    for (final uri in uris) {
      if (await canLaunchUrl(uri)) {
        final abriu = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (abriu) return true;
      }
    }
    return false;
  }

  Future<bool> _abrirNavegacaoExterna({
    required String endereco,
    required double? latitude,
    required double? longitude,
    required _AppNavegacao app,
  }) {
    final query = Uri.encodeComponent(endereco);
    final temCoords = latitude != null && longitude != null;

    if (app == _AppNavegacao.googleMaps) {
      return _abrirPrimeiraUriDisponivel([
        if (temCoords) Uri.parse('google.navigation:q=$latitude,$longitude'),
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      ]);
    }

    return _abrirPrimeiraUriDisponivel([
      if (temCoords) Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes'),
      Uri.parse('https://waze.com/ul?q=$query&navigate=yes'),
    ]);
  }

  Future<void> _promoverParaIndoClienteSeNecessario(
    String pedidoId,
    Map<String, dynamic> pedido,
  ) async {
    final statusAtual = (pedido['status'] ?? '').toString();
    if (statusAtual != PedidoStatus.entregadorIndoLoja) return;

    final ref = FirebaseFirestore.instance.collection('pedidos').doc(pedidoId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final dados = snap.data() ?? <String, dynamic>{};
      final st = (dados['status'] ?? '').toString();
      final entregadorId = (dados['entregador_id'] ?? '').toString();
      if (entregadorId != _uid) return;
      if (st != PedidoStatus.entregadorIndoLoja) return;
      tx.update(ref, {'status': PedidoStatus.saiuEntrega});
    });

    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'entregador_operacao_status': 'INDO_PARA_CLIENTE',
      'entregador_corridas_pendentes': 0,
      'entregador_estado_operacao_atualizado_em': FieldValue.serverTimestamp(),
      'entregador_estado_operacao_origem': 'radar_ir_para_cliente',
      'entregador_estado_operacao_pedido_id': pedidoId,
    }, SetOptions(merge: true));
  }

  Future<void> _abrirRotaEntrega({
    required String pedidoId,
    required Map<String, dynamic> pedido,
    required bool irParaCliente,
  }) async {
    if (_pedidosAbrindoRota.contains(pedidoId)) return;
    if (mounted) {
      setState(() => _pedidosAbrindoRota.add(pedidoId));
    }
    try {
      final endereco =
          (irParaCliente ? pedido['endereco_entrega'] : pedido['loja_endereco'])
              ?.toString()
              .trim();

      final latitude = irParaCliente
          ? (_toDoubleOrNull(pedido['entrega_latitude']) ??
                _toDoubleOrNull(pedido['cliente_latitude']))
          : _toDoubleOrNull(pedido['loja_latitude']);
      final longitude = irParaCliente
          ? (_toDoubleOrNull(pedido['entrega_longitude']) ??
                _toDoubleOrNull(pedido['cliente_longitude']))
          : _toDoubleOrNull(pedido['loja_longitude']);

      final semEndereco = endereco == null || endereco.isEmpty;
      final semCoords = latitude == null || longitude == null;
      if (semEndereco && semCoords) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Endereço da rota não disponível neste pedido.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final app = await _selecionarAppNavegacao(
        irParaCliente
            ? 'Escolha o app para navegar até o cliente'
            : 'Escolha o app para navegar até a loja',
      );
      if (app == null) return;

      final abriu = await _abrirNavegacaoExterna(
        endereco: endereco ?? '',
        latitude: latitude,
        longitude: longitude,
        app: app,
      );

      if (!abriu) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o aplicativo de navegação.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!irParaCliente && mounted) {
        setState(() => _pedidosIndoCliente.add(pedidoId));
      }
      if (irParaCliente && mounted) {
        setState(() => _pedidosSolicitarCodigo.add(pedidoId));
        unawaited(_promoverParaIndoClienteSeNecessario(pedidoId, pedido));
      }
    } finally {
      if (mounted) {
        setState(() => _pedidosAbrindoRota.remove(pedidoId));
      } else {
        _pedidosAbrindoRota.remove(pedidoId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots(),
      builder: (context, snapshotUser) {
        if (snapshotUser.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey[100],
            body: Center(child: CircularProgressIndicator(color: diPertinRoxo)),
          );
        }

        if (!snapshotUser.hasData || !snapshotUser.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Erro ao carregar seu perfil.')),
          );
        }

        final dadosEntregador =
            snapshotUser.data!.data() as Map<String, dynamic>;
        unawaited(
          ContaBloqueioEntregadorService.sincronizarLiberacaoSeExpirado(_uid),
        );

        if (ContaBloqueioEntregadorService.estaBloqueadoParaOperacoes(
          dadosEntregador,
        )) {
          return Scaffold(
            backgroundColor: Colors.grey[100],
            body: const Center(child: SizedBox.shrink()),
          );
        }

        final statusAprovacao =
            dadosEntregador['entregador_status'] ?? 'pendente';
        final isOnline = dadosEntregador['is_online'] ?? false;

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: 'Voltar para meu perfil',
              icon: const Icon(Icons.arrow_back),
              onPressed: _voltarParaMeuPerfil,
            ),
            title: const Text(
              'Radar de corridas',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: diPertinRoxo,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'Diagnóstico de alertas',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticoAlertasCorridaScreen(),
                    ),
                  );
                  unawaited(_contarPendenciasPermissao());
                },
                icon: Badge(
                  isLabelVisible: _pendenciasPermissao > 0,
                  label: Text(
                    '$_pendenciasPermissao',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: diPertinLaranja,
                  child: const Icon(Icons.health_and_safety_outlined),
                ),
              ),
              if (statusAprovacao == 'aprovado')
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isOnline
                              ? Colors.lightGreenAccent
                              : Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Switch(
                        value: isOnline,
                        activeThumbColor: Colors.lightGreenAccent,
                        activeTrackColor: Colors.white24,
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white24,
                        onChanged: (val) => _mudarStatusTrabalho(val),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (statusAprovacao == 'pendente') {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.access_time_filled,
                          size: 80,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Em análise',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Recebemos seus documentos! Nossa equipe está analisando seu cadastro. Volte mais tarde.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (statusAprovacao == 'bloqueado') {
                final motivo =
                    dadosEntregador['motivo_recusa']?.toString().trim() ?? '';
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 80,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Cadastro precisa de ajustes',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Abra o perfil e use «Corrigir cadastro de entregador» para enviar os documentos novamente.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                        if (motivo.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Text(
                              'Motivo informado pela equipe:\n$motivo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              if (!isOnline) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Você está offline',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Use o interruptor no topo da tela para ficar online '
                          'e receber pedidos prontos para retirada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  _buildFloatingIconToggle(),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _pedidosStream,
                      builder: (context, snapshotPedidos) {
                        if ((dadosEntregador['latitude'] == null ||
                                dadosEntregador['longitude'] == null) &&
                            (_latAtualLocal == null ||
                                _lonAtualLocal == null)) {
                          unawaited(_garantirPosicaoLocalAtual());
                        }

                        if (snapshotPedidos.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: diPertinRoxo,
                            ),
                          );
                        }

                        if (!snapshotPedidos.hasData ||
                            snapshotPedidos.data!.docs.isEmpty) {
                          _quantidadePedidosAntiga = 0;
                          return RefreshIndicator(
                            color: diPertinLaranja,
                            onRefresh: () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 400),
                              );
                            },
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(24),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.12,
                                ),
                                Icon(
                                  Icons.radar,
                                  size: 72,
                                  color: diPertinLaranja.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Aguardando corridas',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Fique online e com o app aberto. Quando um pedido '
                                  'estiver pronto na loja, ele aparece aqui e um '
                                  'alerta sonoro pode tocar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 15,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final latE =
                            _toDoubleOrNull(dadosEntregador['latitude']) ??
                            _latAtualLocal;
                        final lonE =
                            _toDoubleOrNull(dadosEntregador['longitude']) ??
                            _lonAtualLocal;

                        final allDocs = snapshotPedidos.data!.docs;
                        final estouIndoParaLoja = allDocs.any((d) {
                          final dd = d.data() as Map<String, dynamic>;
                          return dd['entregador_id'] == _uid &&
                              (dd['status'] as String? ?? '') ==
                                  PedidoStatus.entregadorIndoLoja;
                        });

                        var pedidos = allDocs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (_ofertasOcultadasLocalmente.contains(doc.id) &&
                              (data['status'] as String? ?? '') ==
                                  PedidoStatus.aguardandoEntregador) {
                            return false;
                          }
                          if (estouIndoParaLoja &&
                              (data['status'] as String? ?? '') ==
                                  PedidoStatus.aguardandoEntregador) {
                            return false;
                          }
                          return _entregadorPodeVerPedidoNaLista(
                            data,
                            latEntregador: latE,
                            lonEntregador: lonE,
                          );
                        }).toList();

                        pedidos.sort(_ordenarRadar);

                        _tentarAlertaSonoro(pedidos.length);
                        _quantidadePedidosAntiga = pedidos.length;

                        if (pedidos.isEmpty) {
                          _quantidadePedidosAntiga = 0;
                          return RefreshIndicator(
                            color: diPertinLaranja,
                            onRefresh: () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 400),
                              );
                            },
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(24),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.12,
                                ),
                                Icon(
                                  Icons.radar,
                                  size: 72,
                                  color: diPertinLaranja.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Nada no radar agora',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Novos pedidos surgem quando a loja marcar como '
                                  'a caminho. Puxe para atualizar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 15,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: diPertinLaranja,
                          onRefresh: () async {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 450),
                            );
                          },
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    8,
                                  ),
                                  child: Text(
                                    'Oferta em destaque para decisão rápida: confira valor, rota e aceite antes do tempo acabar.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  24,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final doc = pedidos[index];
                                    final pedido =
                                        doc.data() as Map<String, dynamic>;
                                    final pedidoId = doc.id;
                                    final statusAtual =
                                        pedido['status'] as String? ?? '';
                                    final isNova =
                                        statusAtual ==
                                            PedidoStatus.aguardandoEntregador;
                                    final taxa = _ganhoEntregador(pedido);
                                    final loja =
                                        pedido['loja_nome'] ?? 'Loja parceira';
                                    final lojaEndereco =
                                        pedido['loja_endereco']?.toString() ??
                                        'Endereço da loja não informado';
                                    final endereco =
                                        pedido['endereco_entrega']
                                            ?.toString() ??
                                        'Endereço não informado';
                                    final cancelando =
                                        _cancelandoPedidoId == pedidoId;
                                    final abrindoConfirmacaoCancelamento =
                                        _pedidosAbrindoConfirmacaoCancelamento
                                            .contains(pedidoId);
                                    final abrindoRota =
                                        _pedidosAbrindoRota.contains(pedidoId);
                                    final abrindoFluxoEntrega =
                                        _pedidosAbrindoFluxoEntrega.contains(
                                          pedidoId,
                                        );
                                    final etapaCliente =
                                        _pedidosIndoCliente.contains(
                                          pedidoId,
                                        ) ||
                                        statusAtual ==
                                            PedidoStatus.saiuEntrega ||
                                        statusAtual == PedidoStatus.emRota ||
                                        statusAtual == PedidoStatus.aCaminho;
                                    final solicitarCodigo =
                                        _pedidosSolicitarCodigo.contains(
                                          pedidoId,
                                        ) ||
                                        statusAtual ==
                                            PedidoStatus.saiuEntrega ||
                                        statusAtual == PedidoStatus.emRota ||
                                        statusAtual == PedidoStatus.aCaminho;

                                    _sincronizarSomChamadaOferta(
                                      pedidoId,
                                      pedido,
                                    );

                                    double? distAteLojaKm;
                                    if (latE != null &&
                                        lonE != null &&
                                        pedido['loja_latitude'] != null &&
                                        pedido['loja_longitude'] != null) {
                                      final latEnt = latE;
                                      final lonEnt = lonE;
                                      final latLoja = _toDoubleOrNull(
                                        pedido['loja_latitude'],
                                      );
                                      final lonLoja = _toDoubleOrNull(
                                        pedido['loja_longitude'],
                                      );
                                      if (latLoja != null && lonLoja != null) {
                                        distAteLojaKm =
                                            Geolocator.distanceBetween(
                                              latEnt,
                                              lonEnt,
                                              latLoja,
                                              lonLoja,
                                            ) /
                                            1000;
                                      }
                                    }
                                    final distLojaClienteKm =
                                        _distKmLojaCliente(pedido) ??
                                        _cacheDistLojaClienteKm[pedidoId];
                                    if (distLojaClienteKm == null) {
                                      _resolverDistLojaClienteFallback(
                                        pedidoId,
                                        pedido,
                                      );
                                    }
                                    final tempoEstimadoMin =
                                        distAteLojaKm != null
                                        ? (distAteLojaKm / 25 * 60).ceil()
                                        : null;

                                    final corBorda = isNova
                                        ? diPertinLaranja
                                        : diPertinRoxo;

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Card(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          side: BorderSide(
                                            color: corBorda,
                                            width: 2,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Chip(
                                                          avatar: Icon(
                                                            isNova
                                                                ? Icons
                                                                      .fiber_new_rounded
                                                                : Icons
                                                                      .delivery_dining,
                                                            size: 18,
                                                            color: isNova
                                                                ? diPertinLaranja
                                                                : diPertinRoxo,
                                                          ),
                                                          label: Text(
                                                            isNova
                                                                ? 'Nova oferta'
                                                                : 'Sua entrega',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: isNova
                                                                  ? diPertinLaranja
                                                                  : diPertinRoxo,
                                                            ),
                                                          ),
                                                          backgroundColor:
                                                              isNova
                                                              ? diPertinLaranja
                                                                    .withValues(
                                                                      alpha:
                                                                          0.12,
                                                                    )
                                                              : diPertinRoxo
                                                                    .withValues(
                                                                      alpha:
                                                                          0.12,
                                                                    ),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          materialTapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        _moeda.format(taxa),
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 28,
                                                          color:
                                                              diPertinLaranja,
                                                        ),
                                                      ),
                                                      Text(
                                                        'ganho líquido',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              const Divider(height: 20),
                                              if (statusAtual ==
                                                      PedidoStatus
                                                          .aguardandoEntregador &&
                                                  _despachoUidCampo(
                                                        pedido['despacho_oferta_uid'],
                                                      ) ==
                                                      _uid &&
                                                  pedido['despacho_oferta_expira_em'] !=
                                                      null)
                                                _ContadorAceiteOferta(
                                                  expiraEm:
                                                      pedido['despacho_oferta_expira_em']
                                                          as Timestamp?,
                                                  duracaoSegundos:
                                                      _kOfertaDuracaoSegundos,
                                                ),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.storefront_outlined,
                                                    color: diPertinRoxo,
                                                    size: 22,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Coleta: $loja',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 15,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          lojaEndereco,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            height: 1.3,
                                                            color: Colors
                                                                .grey[800],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.location_on_outlined,
                                                    color: Colors.red[400],
                                                    size: 22,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Entrega: $endereco',
                                                      maxLines: 4,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        height: 1.35,
                                                        color: Colors.grey[800],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _chipMetrica(
                                                      icon: Icons
                                                          .navigation_outlined,
                                                      rotulo: 'Você→Loja',
                                                      valor: _textoDistanciaKm(
                                                        distAteLojaKm,
                                                      ),
                                                    ),
                                                    _chipMetrica(
                                                      icon: Icons
                                                          .store_mall_directory,
                                                      rotulo: 'Loja→Cliente',
                                                      valor: _textoDistanciaKm(
                                                        distLojaClienteKm,
                                                      ),
                                                    ),
                                                    _chipMetrica(
                                                      icon:
                                                          Icons.route_outlined,
                                                      rotulo: 'Total',
                                                      valor:
                                                          (distAteLojaKm !=
                                                                  null &&
                                                              distLojaClienteKm !=
                                                                  null)
                                                          ? _textoDistanciaKm(
                                                              distAteLojaKm +
                                                                  distLojaClienteKm,
                                                            )
                                                          : '—',
                                                    ),
                                                    _chipMetrica(
                                                      icon: Icons
                                                          .schedule_outlined,
                                                      rotulo: 'Tempo',
                                                      valor:
                                                          tempoEstimadoMin !=
                                                              null
                                                          ? '~$tempoEstimadoMin min'
                                                          : '—',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              if (isNova)
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.stretch,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: diPertinRoxo
                                                            .withValues(
                                                              alpha: 0.08,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'A decisão desta oferta acontece na tela oficial de chamada para evitar duplicidade de fluxo.',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[800],
                                                          fontSize: 12,
                                                          height: 1.35,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    FilledButton.icon(
                                                      onPressed:
                                                          _requestsComTelaOficialAberta
                                                              .contains(
                                                                _requestIdOferta(
                                                                  pedidoId,
                                                                  pedido,
                                                                ),
                                                              )
                                                          ? null
                                                          : () => _abrirTelaOficialChamada(
                                                              pedidoId,
                                                              pedido,
                                                            ),
                                                      icon: const Icon(
                                                        Icons.call_outlined,
                                                        color: Colors.white,
                                                      ),
                                                      label: const Text(
                                                        'Abrir chamada oficial',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      style: FilledButton
                                                          .styleFrom(
                                                            backgroundColor:
                                                                diPertinRoxo,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 14,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                        12,
                                                                      ),
                                                            ),
                                                          ),
                                                    ),
                                                  ],
                                                )
                                              else
                                                Column(
                                                  children: [
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: FilledButton.icon(
                                                        onPressed:
                                                            (cancelando ||
                                                                abrindoRota ||
                                                                abrindoFluxoEntrega ||
                                                                abrindoConfirmacaoCancelamento)
                                                            ? null
                                                            : () {
                                                                if (etapaCliente &&
                                                                    solicitarCodigo) {
                                                                  unawaited(
                                                                    _abrirFluxoFinalizarEntrega(
                                                                      pedidoId:
                                                                          pedidoId,
                                                                      pedido:
                                                                          pedido,
                                                                    ),
                                                                  );
                                                                  return;
                                                                }
                                                                _abrirRotaEntrega(
                                                                  pedidoId:
                                                                      pedidoId,
                                                                  pedido:
                                                                      pedido,
                                                                  irParaCliente:
                                                                      etapaCliente,
                                                                );
                                                              },
                                                        icon: Icon(
                                                          (abrindoRota ||
                                                                  abrindoFluxoEntrega)
                                                              ? Icons
                                                                    .hourglass_top
                                                              : etapaCliente &&
                                                                  solicitarCodigo
                                                              ? Icons
                                                                    .verified_user
                                                              : etapaCliente
                                                              ? Icons
                                                                    .person_pin_circle
                                                              : Icons
                                                                    .storefront,
                                                          color: Colors.white,
                                                        ),
                                                        label: Text(
                                                          (abrindoRota ||
                                                                  abrindoFluxoEntrega)
                                                              ? 'Abrindo...'
                                                              : etapaCliente &&
                                                                  solicitarCodigo
                                                              ? 'Entregar e pedir código'
                                                              : etapaCliente
                                                              ? 'Ir para cliente'
                                                              : 'Ir para loja',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                        style: FilledButton.styleFrom(
                                                          backgroundColor:
                                                              const Color(
                                                                0xFF2E7D32,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 14,
                                                              ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: FilledButton.icon(
                                                        onPressed:
                                                            (cancelando ||
                                                                abrindoRota ||
                                                                abrindoFluxoEntrega ||
                                                                abrindoConfirmacaoCancelamento)
                                                            ? null
                                                            : () =>
                                                                  _cancelarEntregaOuRecusarOferta(
                                                                    pedidoId,
                                                                    pedido,
                                                                  ),
                                                        icon: cancelando
                                                            ? const SizedBox(
                                                                width: 18,
                                                                height: 18,
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              )
                                                            : abrindoConfirmacaoCancelamento
                                                            ? const Icon(
                                                                Icons
                                                                    .hourglass_top,
                                                                color: Colors
                                                                    .white,
                                                              )
                                                            : const Icon(
                                                                Icons
                                                                    .cancel_outlined,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        label: Text(
                                                          cancelando
                                                              ? 'Cancelando...'
                                                              : abrindoConfirmacaoCancelamento
                                                              ? 'Abrindo confirmação...'
                                                              : 'Cancelar entrega',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                        style: FilledButton.styleFrom(
                                                          backgroundColor:
                                                              Colors
                                                                  .red
                                                                  .shade700,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 14,
                                                              ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }, childCount: pedidos.length),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFloatingIconToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _floatingIconAtivo
          ? diPertinRoxo.withAlpha(20)
          : Colors.transparent,
      child: Row(
        children: [
          Icon(
            _floatingIconAtivo ? Icons.circle : Icons.circle_outlined,
            size: 10,
            color: _floatingIconAtivo ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ícone flutuante',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  _floatingIconAtivo
                      ? 'Ativo — aparece ao minimizar o app'
                      : 'Inativo — ative para ver o ícone fora do app',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Switch(
            value: _floatingIconAtivo,
            activeColor: diPertinRoxo,
            onChanged: (val) async {
              if (val) {
                final temOverlay = await AndroidNavIntent.canDrawOverlays();
                if (!temOverlay) {
                  if (!mounted) return;
                  final ok = await PermissoesFeedback.verificarEGarantirOverlay(
                    context,
                  );
                  if (!ok) return;
                }
                await AndroidNavIntent.startFloatingIcon();
              } else {
                await AndroidNavIntent.stopFloatingIcon();
              }
              if (mounted) setState(() => _floatingIconAtivo = val);
            },
          ),
        ],
      ),
    );
  }
}

/// Contador regressivo alinhado ao `despacho_oferta_expira_em` do Firestore.
class _ContadorAceiteOferta extends StatefulWidget {
  const _ContadorAceiteOferta({
    required this.expiraEm,
    required this.duracaoSegundos,
  });

  final Timestamp? expiraEm;
  final int duracaoSegundos;

  @override
  State<_ContadorAceiteOferta> createState() => _ContadorAceiteOfertaState();
}

class _ContadorAceiteOfertaState extends State<_ContadorAceiteOferta> {
  Timer? _timer;
  int _segundos = 0;

  @override
  void initState() {
    super.initState();
    _atualizar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _atualizar());
  }

  void _atualizar() {
    final exp = widget.expiraEm?.toDate();
    if (exp == null) {
      if (mounted) setState(() => _segundos = 0);
      return;
    }
    final s = exp.difference(DateTime.now()).inSeconds;
    if (mounted) setState(() => _segundos = s < 0 ? 0 : s);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duracao = widget.duracaoSegundos <= 0 ? 1 : widget.duracaoSegundos;
    final progresso = (_segundos / duracao).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: diPertinLaranja.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: diPertinLaranja, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer, color: diPertinLaranja, size: 22),
              const SizedBox(width: 8),
              Text(
                _segundos <= 0 ? 'Tempo esgotado' : 'Aceite em $_segundos s',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: diPertinLaranja,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progresso,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(diPertinLaranja),
            ),
          ),
        ],
      ),
    );
  }
}
