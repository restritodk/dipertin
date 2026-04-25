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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:depertin_cliente/constants/pedido_status.dart';
import 'package:depertin_cliente/constants/tipos_entrega.dart';
import 'package:depertin_cliente/services/android_nav_intent.dart';
import 'package:depertin_cliente/services/conta_bloqueio_entregador_service.dart';
import 'package:depertin_cliente/services/firebase_functions_config.dart';
import 'package:depertin_cliente/services/permissoes_app_service.dart';
import 'package:depertin_cliente/services/corrida_chamada_entregador_audio.dart';
import 'package:depertin_cliente/services/acessibilidade_prefs_service.dart';
import 'package:depertin_cliente/services/alerta_corrida_nativo.dart';
import 'package:depertin_cliente/services/flash_alerta_corrida.dart';
import 'package:permission_handler/permission_handler.dart';

import 'configuracoes/gerenciar_veiculos_screen.dart';
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

  /// Listener dedicado pro disparo de tela fullscreen / áudio. Roda
  /// **independente** do build da lista — assim a chamada aparece na hora
  /// que `despacho_oferta_uid` é gravado pelo backend, mesmo que o item
  /// ainda não tenha sido renderizado pelo `SliverChildBuilderDelegate`.
  StreamSubscription<QuerySnapshot>? _ofertaFullscreenSub;

  /// Listener auxiliar — observa quando o backend confirma o aceite
  /// (`entregador_id == _uid`) e libera o bloqueio local da oferta
  /// correspondente.
  StreamSubscription<QuerySnapshot>? _confirmacoesBackendSub;

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
  // Cache de telefones de usuários (loja/cliente) exibidos nos cards de corrida.
  // Valor `null` significa "usuário não tem telefone cadastrado".
  final Map<String, String?> _cacheTelefonePorUid = <String, String?>{};
  final Set<String> _buscandoTelefonePorUid = <String>{};
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
    unawaited(AcessibilidadePrefsService.instance.carregarESincronizar());
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

    // Listener dedicado pra disparar o fullscreen assim que o backend
    // me atribui como `despacho_oferta_uid` — não depende da UI ter
    // renderizado o item da lista.
    _ofertaFullscreenSub = FirebaseFirestore.instance
        .collection('pedidos')
        .where('status', isEqualTo: PedidoStatus.aguardandoEntregador)
        .where('despacho_oferta_uid', isEqualTo: _uid)
        .snapshots()
        .listen(_processarOfertasParaMim);
    // Listener auxiliar dedicado (NÃO compartilha com `_pedidosStream`
    // porque snapshots() do Firestore é single-subscription — uma
    // segunda escuta deixaria o `StreamBuilder` do radar travado em
    // ConnectionState.waiting). Aqui filtramos só pelos pedidos onde
    // `entregador_id == meu uid`. Quando o backend confirma o aceite,
    // liberamos o bloqueio local da oferta correspondente.
    _confirmacoesBackendSub = FirebaseFirestore.instance
        .collection('pedidos')
        .where('entregador_id', isEqualTo: _uid)
        .snapshots()
        .listen(_observarConfirmacoesBackend);
    // Sincronização inicial do bloqueio nativo (sobrevive à recriação
    // do widget — ex.: voltei do IncomingDeliveryActivity após Aceitar).
    unawaited(_carregarOfertasProcessadasLocais());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checarConfigAndroidChamadaFullScreen());
      unawaited(_contarPendenciasPermissao());
      unawaited(_syncFloatingIconState());
      unawaited(_ocultarFloatingIconEnquantoAppAberto());
      unawaited(_garantirOnlineApenasComAcaoManual());
      // Logo após o widget renderizar, verifica se houve falha no
      // último aceite executado pela fullscreen nativa — sem isso, o
      // entregador toca em "Aceitar" e o pedido some sem feedback.
      unawaited(_consumirFeedbackFalhaAceite());
    });
  }

  /// Cache em memória do estado nativo `MainActivity.ofertasProcessadasLocais`.
  /// Mapa `pedidoId → despacho_oferta_seq` da última oferta que o
  /// entregador decidiu localmente. Usado por `_processarOfertasParaMim`
  /// para distinguir lock obsoleto (mesmo seq) vs. re-dispatch (seq maior).
  final Map<String, int> _ofertasDecididasNativas = <String, int>{};

  /// Importa para o estado em memória (`_ofertasOcultadasLocalmente` e
  /// `_ofertasDecididasNativas`) a lista de pedidos que o entregador já
  /// decidiu na fullscreen nativa (`MainActivity.ofertasProcessadasLocais`).
  /// Esse import é crítico imediatamente após o widget ser recriado pelo
  /// `pushNamedAndRemoveUntil('/entregador')` do
  /// `IncomingDeliveryActivity.openMainRadar`: sem isso, o
  /// `_ofertaFullscreenSub` pega a snapshot inicial com o pedido ainda em
  /// `aguardando_entregador` (backend processando o aceite) e reabre a
  /// fullscreen — o bug exato reportado.
  Future<void> _carregarOfertasProcessadasLocais() async {
    try {
      final mapa = await AndroidNavIntent.getOfertasProcessadasLocais();
      if (!mounted || mapa.isEmpty) return;
      mapa.forEach((id, seq) {
        _ofertasDecididasNativas[id] = seq;
        _ofertasOcultadasLocalmente.add(id);
      });
    } catch (e) {
      debugPrint('[_carregarOfertasProcessadasLocais] $e');
    }
  }

  /// Lê e LIMPA, no nativo, o motivo da última falha de aceite (callable
  /// `aceitarOfertaCorrida` retornou aceito=false ou erro de rede).
  /// Mostra SnackBar para o entregador entender por que a oferta sumiu
  /// logo após tocar Aceitar — sem isso, ficaria como uma "tela
  /// fantasma" que aceita e some sem feedback nenhum.
  Future<void> _consumirFeedbackFalhaAceite() async {
    try {
      final dados = await AndroidNavIntent.consumirUltimaFalhaAceite();
      if (!mounted || dados == null) return;
      final mensagem = (dados['mensagem'] as String?)?.trim() ?? '';
      if (mensagem.isEmpty) return;
      final motivo = (dados['motivo'] as String?)?.trim() ?? '';
      final isCriticoVeiculo = motivo == 'veiculo_nao_configurado';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          backgroundColor: isCriticoVeiculo ? Colors.deepOrange : Colors.black87,
          content: Text(
            mensagem,
            style: const TextStyle(color: Colors.white),
          ),
          action: isCriticoVeiculo
              ? SnackBarAction(
                  label: 'Veículos',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GerenciarVeiculosScreen(),
                      ),
                    );
                  },
                )
              : SnackBarAction(
                  label: 'OK',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
        ),
      );
    } catch (e) {
      debugPrint('[_consumirFeedbackFalhaAceite] $e');
    }
  }

  /// Para cada snapshot do `_pedidosStream`, se vejo um pedido cujo
  /// `entregador_id == _uid` (backend já gravou o aceite), libero o
  /// bloqueio local pra que o radar mostre o pedido normalmente e
  /// futuras re-ofertas (após uma recusa que não foi confirmada, p.ex.)
  /// possam disparar a fullscreen de novo.
  void _observarConfirmacoesBackend(QuerySnapshot snap) {
    if (!mounted) return;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final entregadorId = data['entregador_id']?.toString().trim() ?? '';
      if (entregadorId != _uid) continue;
      final st = data['status'] as String? ?? '';
      // Status pós-aceite: aceite confirmado pelo backend.
      if (st == PedidoStatus.entregadorIndoLoja ||
          st == PedidoStatus.aCaminho ||
          st == PedidoStatus.emRota ||
          st == PedidoStatus.saiuEntrega) {
        final removeu = _ofertasOcultadasLocalmente.remove(doc.id);
        _ofertasDecididasNativas.remove(doc.id);
        if (removeu) {
          unawaited(
            AndroidNavIntent.confirmarOfertaProcessadaPorBackend(doc.id),
          );
        }
      }
    }
  }

  /// Chave de preferência que guarda a escolha do entregador para o
  /// ícone flutuante. A política é:
  ///   - Ligado: o ícone APARECE sempre que o app entra em background
  ///     (paused), ficando escondido enquanto o app está em foreground
  ///     (para não sobrepor a UI).
  ///   - Desligado: nunca aparece.
  ///
  /// Esta preferência é preservada entre navegações de aba (Perfil,
  /// Vitrine) e entre reinícios do app. Só é alterada por duas ações:
  ///   - O entregador tocar no switch manualmente (on/off).
  ///   - O entregador ficar OFFLINE (o ícone é limpado automaticamente).
  static const String _kPrefFloatingIconLigado =
      'entregador.floating_icon_ligado';

  Future<bool> _lerPrefFloatingIcon() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kPrefFloatingIconLigado) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _salvarPrefFloatingIcon(bool ligado) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefFloatingIconLigado, ligado);
    } catch (_) {}
  }

  /// Sincroniza o estado do widget (`_floatingIconAtivo`) com a
  /// preferência persistida e garante que, enquanto o app estiver em
  /// foreground, o serviço nativo não desenhe o ícone por cima da UI.
  ///
  /// **Importante**: esta função **NÃO** desliga a preferência quando
  /// encontra o serviço rodando. Antes a gente fazia isso e o resultado
  /// era o bug reportado em 04/2026 ("entregador vai pra aba Perfil/
  /// Vitrine e o ícone desaparece"). A preferência só muda por ação
  /// manual no switch ou quando o entregador fica offline.
  Future<void> _syncFloatingIconState() async {
    final pref = await _lerPrefFloatingIcon();
    // Em foreground, nunca queremos o ícone desenhado. Se estiver
    // rodando por alguma razão (app retornou de background, OEM que
    // re-subiu o serviço), mandamos parar — sem tocar na preferência.
    try {
      final running = await AndroidNavIntent.isFloatingIconRunning();
      if (running) {
        await AndroidNavIntent.stopFloatingIcon();
      }
    } catch (_) {}
    if (!mounted) return;
    if (pref != _floatingIconAtivo) {
      setState(() => _floatingIconAtivo = pref);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_contarPendenciasPermissao());
      unawaited(_ocultarFloatingIconEnquantoAppAberto());
      // App veio do background (incluindo retorno da fullscreen nativa
      // após Aceitar/Recusar). Re-importa o set de ofertas decididas
      // localmente — janela crítica do bug "ACEITAR → some → ACEITAR".
      unawaited(_carregarOfertasProcessadasLocais());
      // Pode haver uma falha de aceite registrada enquanto a callable
      // rodava em background — exibe SnackBar agora que estamos visíveis.
      unawaited(_consumirFeedbackFalhaAceite());
    } else if (state == AppLifecycleState.paused) {
      // Respeita a PREFERÊNCIA do entregador (persistida). Não usa
      // apenas o flag em memória porque, dependendo de navegações
      // entre abas (Perfil/Vitrine) e re-montagens de widget, a
      // variável `_floatingIconAtivo` pode estar num estado
      // transitório. A verdade sobre "o entregador quer o ícone?"
      // mora no SharedPreferences.
      unawaited(_ligarFloatingIconSePreferido());
    }
  }

  Future<void> _ligarFloatingIconSePreferido() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final pref = await _lerPrefFloatingIcon();
    if (!pref) return;
    try {
      await AndroidNavIntent.startFloatingIcon();
    } catch (_) {}
  }

  Future<void> _ocultarFloatingIconEnquantoAppAberto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Para o ícone em foreground INDEPENDENTE da preferência — evita
    // desenhar a bolha por cima da própria UI do app. A preferência
    // continua intacta para o próximo pause.
    try {
      await AndroidNavIntent.stopFloatingIcon();
    } catch (_) {}
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
    FlashAlertaCorrida.parar();
    unawaited(CorridaChamadaEntregadorAudio.parar());
    _audioPlayer.dispose();
    _pararRastreioGps();
    unawaited(_ofertaFullscreenSub?.cancel());
    _ofertaFullscreenSub = null;
    unawaited(_confirmacoesBackendSub?.cancel());
    _confirmacoesBackendSub = null;
    super.dispose();
  }

  /// Recebe **apenas** os pedidos cujo backend já gravou
  /// `despacho_oferta_uid == este entregador`. Para cada um, dispara
  /// `_sincronizarSomChamadaOferta` — que abre a tela oficial de chamada
  /// (`IncomingDeliveryActivity` no Android) e o som.
  ///
  /// Faz isso fora do build da lista pra não depender do
  /// `SliverChildBuilderDelegate.builder` ter renderizado o item — assim a
  /// fullscreen aparece imediatamente quando a oferta passa a ser minha,
  /// independentemente de qual aba/scroll position o entregador está.
  ///
  /// **Importante**: antes de processar, sincroniza com o estado nativo
  /// `MainActivity.ofertasProcessadasLocais` para NÃO reabrir a fullscreen
  /// de uma oferta que o entregador acabou de aceitar/recusar (entre o
  /// tap e o backend gravar `entregador_id`/`despacho_recusados`). Sem
  /// essa guarda, o widget recriado por `pushNamedAndRemoveUntil` cai
  /// no loop "ACEITAR → some → ACEITAR de novo".
  Future<void> _processarOfertasParaMim(QuerySnapshot snap) async {
    if (!mounted) return;
    if (snap.docs.isEmpty) return;
    try {
      final processadas = await AndroidNavIntent.getOfertasProcessadasLocais();
      _ofertasDecididasNativas
        ..clear()
        ..addAll(processadas);
      processadas.forEach((id, _) => _ofertasOcultadasLocalmente.add(id));
    } catch (e) {
      debugPrint('[_processarOfertasParaMim] sync nativo: $e');
    }
    if (!mounted) return;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      // Compara o seq atual do Firestore com o seq armazenado quando o
      // entregador decidiu localmente. Se o backend emitiu uma NOVA
      // oferta (re-dispatch após recusa/expiração), o seq aumenta e o
      // lock local é liberado automaticamente — o entregador volta a
      // receber a fullscreen normalmente.
      final seqAtual =
          (data['despacho_oferta_seq'] as num?)?.toInt() ?? 0;
      final seqDecididoLocal = _ofertasDecididasNativas[doc.id];
      if (seqDecididoLocal != null && seqAtual <= seqDecididoLocal) {
        // Mesma oferta da última decisão local → ainda esperando backend
        // processar. Não toca/abre fullscreen.
        continue;
      }
      if (seqDecididoLocal != null && seqAtual > seqDecididoLocal) {
        // Re-dispatch confirmado: libera o lock local (nativo + memória).
        _ofertasDecididasNativas.remove(doc.id);
        _ofertasOcultadasLocalmente.remove(doc.id);
        unawaited(
          AndroidNavIntent.confirmarOfertaProcessadaPorBackend(doc.id),
        );
      }
      _sincronizarSomChamadaOferta(doc.id, data);
    }
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
        // Ao ficar offline, o ícone flutuante deixa de fazer sentido
        // (não vai haver oferta). Limpa o serviço nativo E a
        // preferência persistida — conforme política: fica offline =
        // desliga o ícone. Ao voltar online, o entregador precisa
        // reativar o switch manualmente.
        if (_floatingIconAtivo) {
          try {
            await AndroidNavIntent.stopFloatingIcon();
          } catch (_) {}
          await _salvarPrefFloatingIcon(false);
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
  ///
  /// Também aplica o filtro de compatibilidade de veículo: se a loja configurou
  /// `tipos_entrega_permitidos` (snapshot em `tipos_entrega_permitidos_loja`
  /// no pedido), o entregador só enxerga o pedido se seu
  /// `tipo_veiculo_canonico` estiver na lista aceita. Isso mantém o radar
  /// consistente com o critério de despacho — um entregador de moto não vê
  /// pedidos de lojas que aceitam só `carro`/`carro_frete`, e vice-versa.
  /// Pedidos sem snapshot (lojas legado sem config) continuam visíveis para
  /// todos, preservando retrocompatibilidade.
  bool _entregadorPodeVerPedidoNaLista(
    Map<String, dynamic> data, {
    double? latEntregador,
    double? lonEntregador,
    String? tipoVeiculoCanonicoEntregador,
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
      // Despacho sequencial estrito (regra do produto):
      //
      //   1. O pedido só aparece para o entregador atualmente atribuído
      //      pelo backend — ou seja, `despacho_oferta_uid == _uid`.
      //   2. Os outros entregadores compatíveis NÃO veem o pedido no
      //      radar enquanto a oferta está com outra pessoa, mesmo
      //      estando próximos. A corrida deixa de ser "pública".
      //   3. Se a oferta expirou (`despacho_oferta_expira_em` no
      //      passado), também não mostro mais — o backend vai re-rotear
      //      pro próximo da fila num batimento subsequente.
      //
      // Com isso, a tela Radar do entregador é, em essência, um espelho
      // do estado: "a chamada está vindo pra mim?". Sem listas de
      // pedidos abertos.
      final alvo = _despachoUidCampo(data['despacho_oferta_uid']);
      if (alvo != _uid) {
        return false;
      }

      // Categoria: paridade com backend `construirFilaEntregadores`. Se
      // houver `tipo_entrega_solicitado`, só entregadores **desse tipo
      // exato** veem; senão, cai no `tipos_entrega_permitidos_loja`. Esta
      // checagem é defensiva — o backend já só atribui `despacho_oferta_uid`
      // pra entregadores compatíveis, mas mantemos a guarda no app.
      final tiposAceitosLoja = TiposEntrega.normalizarLista(
        data['tipos_entrega_permitidos_loja'],
      );
      final tipoSolicitado = TiposEntrega.normalizarTipoSolicitado(
        data['tipo_entrega_solicitado'],
      );
      final List<String> tiposElegiveis;
      if (tipoSolicitado.isNotEmpty) {
        tiposElegiveis = <String>[tipoSolicitado];
      } else if (tiposAceitosLoja.length == 1) {
        tiposElegiveis = <String>[tiposAceitosLoja.first];
      } else {
        tiposElegiveis = tiposAceitosLoja;
      }
      final tipoEntregador = (tipoVeiculoCanonicoEntregador ?? '')
          .trim()
          .toLowerCase();
      if (tiposElegiveis.isNotEmpty) {
        if (tipoEntregador.isEmpty) {
          return false;
        }
        if (!TiposEntrega.compativel(tipoEntregador, tiposElegiveis)) {
          return false;
        }
      }

      // Expirado? então não mostra — backend está prestes a reatribuir.
      final expiraTs = data['despacho_oferta_expira_em'];
      if (expiraTs is Timestamp) {
        if (DateTime.now().isAfter(expiraTs.toDate())) {
          return false;
        }
      }

      // Recusados nunca recebem a mesma oferta — nem no radar.
      final List<dynamic> recusados = data['despacho_recusados'] ?? const [];
      if (recusados.map((e) => e.toString()).contains(_uid)) {
        return false;
      }

      return true;
    }
    return true;
  }

  String _textoDistanciaKm(double? km) {
    if (km == null) return '—';
    if (km < 0.1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  /// Mostra ao entregador o aviso de pagamento em dinheiro com valor a
  /// receber e troco a devolver. Modelo iFood: o entregador é o responsável
  /// pelo dinheiro físico; o lojista nunca lida com troco. Devolve lista
  /// vazia se o pedido não for em dinheiro.
  List<Widget> _blocoPagamentoDinheiro(Map<String, dynamic> pedido) {
    final formaBruta = (pedido['forma_pagamento'] ?? '').toString().trim();
    final isDinheiro = formaBruta.toLowerCase() == 'dinheiro';
    if (!isDinheiro) return const [];

    double parseMoney(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
    }

    final total = parseMoney(pedido['total']);
    final precisaTroco = pedido['pagamento_dinheiro_precisa_troco'] == true;
    final trocoPara = parseMoney(
      pedido['pagamento_dinheiro_troco_para'] ?? pedido['troco_para'],
    );
    final trocoDevolverDoc = parseMoney(
      pedido['pagamento_dinheiro_troco_valor'] ?? pedido['troco_valor'],
    );
    final trocoDevolver = trocoDevolverDoc > 0
        ? trocoDevolverDoc
        : (precisaTroco && trocoPara > total ? trocoPara - total : 0.0);

    return [
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  color: Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pagamento em DINHEIRO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.orange.shade900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Receba do cliente:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Text(
                  _moeda.format(total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            if (precisaTroco && trocoPara > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cliente vai pagar com:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  Text(
                    _moeda.format(trocoPara),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Devolva de troco:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _moeda.format(trocoDevolver),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'Cliente NÃO precisa de troco — pagará o valor exato.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Você é o responsável pelo dinheiro: receba do cliente e dê o troco. A loja não lida com esse valor.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
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

  /// Busca sob demanda o telefone de `users/{uid}` e guarda em cache, para
  /// exibir o contato da loja (antes de sair com o pedido) ou do cliente
  /// (após o botão "Ir para cliente") no card da corrida.
  void _agendarBuscaTelefoneUsuario(String uid) {
    if (uid.isEmpty) return;
    if (_cacheTelefonePorUid.containsKey(uid)) return;
    if (_buscandoTelefonePorUid.contains(uid)) return;
    _buscandoTelefonePorUid.add(uid);
    unawaited(() async {
      String? telefone;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final dados = doc.data() ?? <String, dynamic>{};
        final candidatos = <dynamic>[
          dados['telefone'],
          dados['whatsapp'],
          dados['celular'],
          dados['telefone_contato'],
        ];
        for (final c in candidatos) {
          final s = (c ?? '').toString().trim();
          if (s.isNotEmpty) {
            telefone = s;
            break;
          }
        }
      } catch (_) {
        telefone = null;
      } finally {
        _buscandoTelefonePorUid.remove(uid);
        if (mounted) {
          setState(() {
            _cacheTelefonePorUid[uid] =
                (telefone == null || telefone.isEmpty) ? null : telefone;
          });
        } else {
          _cacheTelefonePorUid[uid] =
              (telefone == null || telefone.isEmpty) ? null : telefone;
        }
      }
    }());
  }

  Future<void> _abrirWhatsAppContato(String telefone) async {
    String numero = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.isEmpty) return;
    if (!numero.startsWith('55') && numero.length >= 10) {
      numero = '55$numero';
    }
    final urls = <Uri>[
      Uri.parse('https://wa.me/$numero'),
      Uri.parse('https://api.whatsapp.com/send?phone=$numero'),
      Uri.parse('tel:$numero'),
    ];
    for (final uri in urls) {
      try {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      } catch (_) {
        // tenta próximo formato
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatarTelefoneBr(String bruto) {
    final d = bruto.replaceAll(RegExp(r'[^0-9]'), '');
    String s = d;
    if (s.startsWith('55') && s.length > 11) {
      s = s.substring(2);
    }
    if (s.length == 11) {
      return '(${s.substring(0, 2)}) ${s.substring(2, 7)}-${s.substring(7)}';
    }
    if (s.length == 10) {
      return '(${s.substring(0, 2)}) ${s.substring(2, 6)}-${s.substring(6)}';
    }
    return bruto.trim();
  }

  /// Bloco visual de contato (WhatsApp) da loja ou do cliente,
  /// alternado conforme a etapa da corrida.
  ///
  /// Estratégia:
  /// 1) Usa o telefone denormalizado no próprio `pedido` (gravado no checkout
  ///    e mantido em dia pelo trigger `sincronizarIdentidadePedidosOnUpdate`).
  /// 2) Se o campo não existir (pedidos antigos), tenta buscar em
  ///    `users/{uid}` — funcionará apenas se as rules permitirem.
  Widget _blocoContatoWhatsApp({
    required Map<String, dynamic> pedido,
    required bool etapaCliente,
  }) {
    final String uidAlvo = etapaCliente
        ? (pedido['cliente_id']?.toString() ?? '')
        : (pedido['loja_id']?.toString() ?? '');

    String? telefoneDoPedido;
    final dynamic bruto = etapaCliente
        ? pedido['cliente_telefone']
        : pedido['loja_telefone'];
    final tel = (bruto ?? '').toString().trim();
    if (tel.isNotEmpty) telefoneDoPedido = tel;

    // Sem telefone no pedido e sem uid para fallback → não mostra card.
    if (telefoneDoPedido == null && uidAlvo.isEmpty) {
      return const SizedBox.shrink();
    }

    // Quando o telefone está no próprio pedido, não precisamos buscar users.
    final bool temTelefoneNoPedido = telefoneDoPedido != null;
    if (!temTelefoneNoPedido && uidAlvo.isNotEmpty) {
      _agendarBuscaTelefoneUsuario(uidAlvo);
    }

    final bool jaCarregou = temTelefoneNoPedido ||
        _cacheTelefonePorUid.containsKey(uidAlvo);
    final String? telefone = temTelefoneNoPedido
        ? telefoneDoPedido
        : _cacheTelefonePorUid[uidAlvo];
    final String rotulo = etapaCliente
        ? 'Contato do cliente'
        : 'Contato da loja';
    final IconData icone = etapaCliente
        ? Icons.person_outline
        : Icons.storefront_outlined;
    final Color corAcento = etapaCliente
        ? const Color(0xFF2E7D32)
        : diPertinRoxo;

    Widget conteudo;
    if (!jaCarregou) {
      conteudo = Row(
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Carregando contato...',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      );
    } else if (telefone == null || telefone.isEmpty) {
      conteudo = Text(
        etapaCliente
            ? 'Cliente sem telefone cadastrado'
            : 'Loja sem telefone cadastrado',
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      );
    } else {
      final String formatado = _formatarTelefoneBr(telefone);
      conteudo = Row(
        children: [
          Expanded(
            child: Text(
              formatado,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF25D366),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chat_rounded,
            color: Color(0xFF25D366),
            size: 20,
          ),
          const SizedBox(width: 2),
          const Text(
            'WhatsApp',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF25D366),
            ),
          ),
        ],
      );
    }

    final bool clicavel =
        jaCarregou && telefone != null && telefone.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: clicavel ? () => _abrirWhatsAppContato(telefone) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: corAcento.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: corAcento.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(icone, color: corAcento, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rotulo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: corAcento,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      conteudo,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      // Ordem importante: a tela oficial nativa (IncomingDeliveryActivity) é
      // o alerta visual primário. O overlay laranja do Flutter
      // (`FlashAlertaCorrida`) só é acionado como fallback quando a tela
      // nativa NÃO conseguiu abrir — assim evitamos o conflito visual de
      // dois alertas fullscreen sobrepostos disputando o mesmo frame. O LED
      // e a vibração (alertas de acessibilidade autênticos, funcionam com
      // celular bloqueado/no bolso) sempre disparam.
      unawaited(_dispararAlertasAcessibilidade());
      unawaited(_abrirTelaOficialChamada(pedidoId, pedido));
    }
  }

  /// Dispara os alertas nativos de acessibilidade (vibração em padrão e LED
  /// da câmera). Esses alertas coexistem com a tela oficial nativa de
  /// chamada sem conflito — são hardware, não widgets.
  ///
  /// O flash-overlay do Flutter (tela laranja piscando) NÃO é disparado aqui
  /// justamente para evitar colisão com a `IncomingDeliveryActivity`
  /// fullscreen. Ele é chamado apenas no fallback via
  /// [_dispararOverlayFlashFallback], quando a tela nativa não pôde abrir.
  Future<void> _dispararAlertasAcessibilidade() async {
    try {
      final prefs = await AcessibilidadePrefsService.instance.lerCacheLocal();
      if (prefs.vibracao) {
        // Vibração nativa em padrão longo (tipo chamada recebida). Usa o
        // canal `dipertin.android/nav` → VibrationHelper no Kotlin, com a
        // permissão android.permission.VIBRATE declarada no manifest.
        // Funciona com celular bloqueado.
        final ok = await AlertaCorridaNativo.vibrarPadraoChamada();
        if (!ok) {
          // Fallback para quando o MethodChannel não responder (dispositivo
          // sem vibrador ou erro de permissão no momento).
          await HapticFeedback.heavyImpact();
          for (int i = 0; i < 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 280));
            await HapticFeedback.vibrate();
          }
        }
      }
      if (prefs.flash) {
        // LED da câmera piscando — funciona mesmo com a tela bloqueada e
        // por trás da tela oficial nativa (IncomingDeliveryActivity). É o
        // comportamento que as pessoas esperam quando marcam "Flash" em
        // chamadas recebidas. O LED se encerra naturalmente ao fim das
        // pulsações ou quando o entregador aceita/recusa pelo dashboard.
        unawaited(AlertaCorridaNativo.piscarFlash());
      }
    } catch (e) {
      debugPrint('[alerta-acessibilidade] $e');
    }
  }

  /// Fallback visual para quando a `IncomingDeliveryActivity` nativa não
  /// pôde abrir (ex.: iOS, permissão de overlay negada em algum OEM, falha
  /// no intent). Pisca o overlay laranja do Flutter para garantir ao menos
  /// um sinal visual da chamada — só respeitado se o usuário ativou flash.
  Future<void> _dispararOverlayFlashFallback() async {
    try {
      final prefs = await AcessibilidadePrefsService.instance.lerCacheLocal();
      if (!prefs.flash) return;
      if (!mounted) return;
      FlashAlertaCorrida.disparar(context: context);
    } catch (e) {
      debugPrint('[alerta-acessibilidade:overlay-fallback] $e');
    }
  }

  Future<void> _pararSomChamada() async {
    FlashAlertaCorrida.parar();
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
      // A partir daqui a tela nativa assume o alerta visual da chamada.
      // Preservamos vibração e LED (acessibilidade) — silenciamos só o MP3
      // + notificação para não haver toque duplicado.
      await CorridaChamadaEntregadorAudio.silenciarAlertaCorridaCompleto(pedidoId);
      return;
    }
    // A tela nativa não pôde abrir (iOS, OEM sem permissão fullscreen-intent
    // etc.). Para garantir reforço visual ao entregador que ativou flash,
    // acionamos o overlay laranja do Flutter como substituto.
    _requestsComTelaOficialAberta.remove(requestId);
    unawaited(_dispararOverlayFlashFallback());
  }

  Future<void> _recusarOferta(String pedidoId) async {
    if (_recusandoPedidoId == pedidoId) return;
    FlashAlertaCorrida.parar();
    await CorridaChamadaEntregadorAudio.parar();
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
    unawaited(_pararSomChamada());
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      _pedidosAbrindoConfirmacaoCancelamento.remove(pedidoId);
      return;
    }

    // Diálogo com 2 motivos:
    //   - 'normal'      → entregadorCancelarCorridaERedespachar (cancelamento
    //                     do entregador, pode impactar métricas — coleta
    //                     observação opcional no próximo passo)
    //   - 'incompat'    → entregadorCancelarPorIncompatibilidade (sem
    //                     penalidade, cancela direto e devolve o controle
    //                     ao lojista via painel)
    final motivo = await _showDialogCancelarEntrega(context);
    if (mounted) {
      setState(() {
        _pedidosAbrindoConfirmacaoCancelamento.remove(pedidoId);
      });
    } else {
      _pedidosAbrindoConfirmacaoCancelamento.remove(pedidoId);
    }

    if (motivo == null) return;

    if (motivo == 'incompat') {
      // UX (solicitado pelo lojista em 04/2026): cancelar DIRETO sem pedir
      // observação. O painel do lojista já mostra a mensagem padronizada
      // `despacho_msg_busca_entregador` quando este motivo acontece.
      await _cancelarEntregaPorIncompatibilidade(pedidoId);
      return;
    }

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

  /// Diálogo profissional que coleta o motivo do cancelamento.
  ///
  /// Retorna:
  ///   - `'incompat'` — o produto não cabe / não é seguro no veículo do
  ///     entregador. Cancela sem penalidade e devolve ao lojista.
  ///   - `'normal'`   — qualquer outro motivo. Continua fluxo antigo de
  ///     cancelamento + re-despacho automático.
  ///   - `null`       — usuário fechou o diálogo sem confirmar.
  Future<String?> _showDialogCancelarEntrega(BuildContext rootContext) {
    return showDialog<String>(
      context: rootContext,
      useRootNavigator: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 16,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cancelar entrega',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Qual o motivo? A escolha correta mantém seu histórico '
                    'limpo e ajuda a plataforma a prevenir problemas.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _CancelOptionTile(
                    icon: Icons.report_gmailerrorred_outlined,
                    iconColor: Colors.orange.shade700,
                    iconBg: Colors.orange.shade50,
                    title: 'Produto incompatível',
                    subtitle:
                        'Não cabe ou não é seguro no seu veículo. '
                        'Sem penalidade — o lojista é notificado.',
                    onTap: () => Navigator.of(ctx).pop('incompat'),
                  ),
                  const SizedBox(height: 10),
                  _CancelOptionTile(
                    icon: Icons.edit_note_outlined,
                    iconColor: Colors.blueGrey.shade700,
                    iconBg: Colors.blueGrey.shade50,
                    title: 'Outro motivo',
                    subtitle:
                        'Cancelar e permitir que o sistema busque outro '
                        'entregador automaticamente.',
                    onTap: () => Navigator.of(ctx).pop('normal'),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Voltar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Cancelamento SEM penalidade — o produto é incompatível com o veículo
  /// ativo do entregador. Chama o callable diretamente (sem segundo diálogo
  /// de observação, por UX solicitada em 04/2026). O callable:
  ///   - NÃO registra cancelamento "negativo" no perfil do entregador
  ///   - Volta o pedido para `em_preparo` e anexa alerta ao lojista
  ///   - NÃO re-despacha automaticamente — o lojista vê a mensagem no
  ///     painel e decide chamar outro entregador
  Future<void> _cancelarEntregaPorIncompatibilidade(String pedidoId) async {
    if (mounted) {
      setState(() => _cancelandoPedidoId = pedidoId);
    }
    try {
      final callable = appFirebaseFunctions.httpsCallable(
        'entregadorCancelarPorIncompatibilidade',
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'pedidoId': pedidoId,
        // Observação é opcional no backend — passamos string vazia pra
        // manter compatibilidade com versões antigas do callable.
        'observacao': '',
      });

      if (!mounted) return;
      setState(() {
        _pedidosIndoCliente.remove(pedidoId);
        _pedidosSolicitarCodigo.remove(pedidoId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entrega cancelada sem penalidade. O lojista foi avisado e vai solicitar outro entregador.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cancelar: $e'),
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
              Future<void> confirmar(String codigo) async {
                if (codigo.length < 6) {
                  setDialogState(() {
                    erro = 'Informe o código completo com 6 dígitos.';
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
                    FocusManager.instance.primaryFocus?.unfocus();
                    final tinhaTeclado =
                        MediaQuery.of(ctx).viewInsets.bottom > 0;
                    if (tinhaTeclado) {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 180),
                      );
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }
                } catch (e) {
                  setDialogState(() {
                    erro = 'Não foi possível validar o código. Tente novamente.';
                    validando = false;
                  });
                }
              }

              return _DialogSolicitarCodigoEntrega(
                validando: validando,
                erro: erro,
                onLimparErro: () {
                  if (erro != null) {
                    setDialogState(() => erro = null);
                  }
                },
                onVoltar: validando
                    ? null
                    : () => Navigator.of(dialogCtx).pop(),
                onConfirmar: validando ? null : confirmar,
              );
            },
          );
        },
      );

      // Aguarda a animação de fechamento do dialog terminar antes de
      // continuar. O Future de showDialog resolve no momento do pop
      // (antes da animação completa), e widgets internos ainda podem
      // estar sendo reconciliados.
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || resumo == null) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _DialogEntregaConfirmada(
          onContinuar: () => Navigator.of(ctx).pop(),
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
                        final tipoVeiculoEntregador =
                            TiposEntrega.normalizarTipoVeiculo(
                              dadosEntregador['tipo_veiculo_canonico'] ??
                                  dadosEntregador['veiculoTipo'] ??
                                  dadosEntregador['veiculo'] ??
                                  dadosEntregador['tipo_veiculo'],
                            );

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
                            tipoVeiculoCanonicoEntregador:
                                tipoVeiculoEntregador,
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
                                              ..._blocoPagamentoDinheiro(
                                                pedido,
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
                                                    // Contato do cliente só é
                                                    // liberado APÓS o clique
                                                    // em "Ir para cliente"
                                                    // (confirma a coleta),
                                                    // quando `solicitarCodigo`
                                                    // fica `true`. Antes disso
                                                    // mostra o telefone da
                                                    // loja, mesmo que o botão
                                                    // já tenha mudado para
                                                    // "Ir para cliente".
                                                    _blocoContatoWhatsApp(
                                                      pedido: pedido,
                                                      etapaCliente:
                                                          solicitarCodigo,
                                                    ),
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
                // Persiste a preferência ANTES de chamar start, para
                // que um lifecycle race-condition (pause logo após
                // tocar) não ache pref=false e apague o ícone.
                await _salvarPrefFloatingIcon(true);
                try {
                  await AndroidNavIntent.startFloatingIcon();
                } catch (_) {}
              } else {
                await _salvarPrefFloatingIcon(false);
                try {
                  await AndroidNavIntent.stopFloatingIcon();
                } catch (_) {}
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

/// Dialog moderno para o entregador digitar o código de entrega informado
/// pelo cliente. Centraliza o campo em estilo "token" com letterSpacing e
/// destaca ações primárias/secundárias.
///
/// Convertido para StatefulWidget para criar e controlar o
/// [TextEditingController] e o [FocusNode] internamente. Isso é essencial
/// porque o `Future` retornado por `showDialog` resolve no momento do
/// `Navigator.pop`, antes da animação de fechamento terminar. Se o
/// controller fosse criado e disposed pelo chamador, o `TextField` ainda
/// montado durante a animação tentaria acessar um notifier disposed,
/// disparando assertions como `_dependents.isEmpty` e
/// `TextEditingController was used after being disposed`.
class _DialogSolicitarCodigoEntrega extends StatefulWidget {
  const _DialogSolicitarCodigoEntrega({
    required this.validando,
    required this.erro,
    required this.onLimparErro,
    required this.onVoltar,
    required this.onConfirmar,
  });

  final bool validando;
  final String? erro;
  final VoidCallback onLimparErro;
  final VoidCallback? onVoltar;
  final ValueChanged<String>? onConfirmar;

  @override
  State<_DialogSolicitarCodigoEntrega> createState() =>
      _DialogSolicitarCodigoEntregaState();
}

class _DialogSolicitarCodigoEntregaState
    extends State<_DialogSolicitarCodigoEntrega> {
  late final TextEditingController _controller;
  late final FocusNode _focoCampo;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focoCampo = FocusNode(debugLabel: 'codigoEntrega');
    // Pede foco após o primeiro frame para não colidir com a animação de
    // abertura do dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoCampo.requestFocus();
    });
  }

  @override
  void dispose() {
    _focoCampo.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _saindo = false;

  /// Fecha o teclado e só depois executa [acao] (o `Navigator.pop`).
  ///
  /// Se o teclado estiver aberto, o `unfocus` dispara uma animação do
  /// sistema que altera `MediaQuery.viewInsets.bottom` ao longo de ~250ms.
  /// Chamar `Navigator.pop` no mesmo frame provoca colisão entre a
  /// animação do teclado e a animação de fechamento do dialog, causando
  /// assertions como `_dependents.isEmpty` e overflow gigantesco do
  /// RenderFlex. Esperamos o teclado começar a fechar para só então
  /// fechar o dialog.
  Future<void> _executarSaindoFoco(VoidCallback? acao) async {
    if (acao == null || _saindo) return;
    _saindo = true;
    final tinhaTeclado =
        MediaQuery.of(context).viewInsets.bottom > 0 || _focoCampo.hasFocus;
    _focoCampo.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    if (tinhaTeclado) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    if (!mounted) return;
    acao();
  }

  void _disparaConfirmar() {
    final callback = widget.onConfirmar;
    if (callback == null) return;
    final codigo = _controller.text.trim().toUpperCase();
    callback(codigo);
  }

  @override
  Widget build(BuildContext context) {
    final tamanhoTela = MediaQuery.of(context).size;
    final validando = widget.validando;
    final erro = widget.erro;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: tamanhoTela.height),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho com gradiente roxo DiPertin e ícone em destaque.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      diPertinRoxo,
                      Color(0xFF8E24AA),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Código de entrega',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Peça ao cliente o código de 6 dígitos para confirmar a entrega.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Corpo com campo de código em destaque.
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focoCampo,
                      enabled: !validando,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 10,
                        color: diPertinRoxo,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      onChanged: (_) => widget.onLimparErro(),
                      onSubmitted: (_) => _disparaConfirmar(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '— — — — — —',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w600,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF6F2FA),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: erro != null
                                ? Colors.red.shade300
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: erro != null ? Colors.red : diPertinRoxo,
                            width: 1.8,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    if (erro != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEECEC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF8C8C8)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFB91C1C),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                erro,
                                style: const TextStyle(
                                  color: Color(0xFF7F1D1D),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: diPertinRoxo,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'O cliente recebe o código no pedido. Sem o código correto, a entrega não pode ser concluída.',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Rodapé com ações.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: widget.onVoltar == null
                            ? null
                            : () => _executarSaindoFoco(widget.onVoltar),
                        child: const Text('Voltar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: diPertinLaranja,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              diPertinLaranja.withValues(alpha: 0.55),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed:
                            (widget.onConfirmar == null || validando)
                                ? null
                                : _disparaConfirmar,
                        child: validando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text('Validar código'),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog de sucesso exibido após a validação do código de entrega.
class _DialogEntregaConfirmada extends StatelessWidget {
  const _DialogEntregaConfirmada({required this.onContinuar});

  final VoidCallback onContinuar;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF059669),
                      Color(0xFF10B981),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Entrega confirmada!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Parabéns, você concluiu mais uma entrega com sucesso.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: diPertinLaranja,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: onContinuar,
                    child: const Text('Continuar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile clicável usado dentro do diálogo "Cancelar entrega".
///
/// Mostra um ícone em um card colorido, o título em negrito e uma
/// descrição curta em cinza. Ao ser tocado, invoca [onTap] — que os
/// chamadores usam para retornar o motivo do cancelamento via
/// `Navigator.pop`.
class _CancelOptionTile extends StatelessWidget {
  const _CancelOptionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
