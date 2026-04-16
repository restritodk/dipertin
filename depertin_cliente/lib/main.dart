import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:depertin_cliente/screens/cliente/chat_suporte_screen.dart';
import 'package:depertin_cliente/screens/cliente/orders_screen.dart';
import 'package:depertin_cliente/screens/lojista/lojista_pedidos_screen.dart';
import 'package:depertin_cliente/services/fcm_notification_eventos.dart';
import 'package:depertin_cliente/services/fcm_rota.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:depertin_cliente/app_navigator_key.dart';
import 'package:depertin_cliente/screens/entregador/entregador_home_screen.dart';
import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';
import 'services/permissoes_app_service.dart';
import 'services/notificacoes_prefs.dart';
import 'services/app_atualizacao_obrigatoria_service.dart';
import 'services/android_nav_intent.dart';
import 'services/corrida_chamada_entregador_audio.dart';
import 'services/corrida_foreground_notificacao.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/guards/app_guard.dart';
import 'screens/cliente/vitrine_screen.dart';
import 'screens/cliente/meus_enderecos_screen.dart';
import 'screens/cliente/search_screen.dart';
import 'screens/comum/profile_screen.dart';
import 'screens/comum/comunicados_app_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Som local (foreground) para novo pedido — alinhado a [AssetSource] `sond/pedido.mp3`.
final AudioPlayer _audioNovoPedidoLoja = AudioPlayer();

/// App Check em isolates que usam Firebase (ex.: handler de FCM em background).
/// Não altera entrega de push; só anexa token se algo no isolate chamar APIs protegidas.
Future<void> _ativarFirebaseAppCheckNoIsolate() async {
  if (kIsWeb) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleDeviceCheckProvider(),
      );
    }
  } catch (e, _) {
    debugPrint('FirebaseAppCheck (isolate): $e');
  }
}

/// Isolate de background do FCM: inicializa Firebase (+ App Check leve).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _ativarFirebaseAppCheckNoIsolate();
}

/// Android: esconde a barra de navegação (voltar/home/recentes). O usuário pode
/// deslizar de baixo para cima para exibi-la por um instante.
Future<void> configurarBarraNavegacaoAndroidOculta() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
}

/// App Check: valida que chamadas (Functions, etc.) vêm do app. Não interfere no FCM.
///
/// Em **debug**, use o token que aparece no Logcat e cadastre em Firebase Console →
/// App Check → app Android → Gerenciar tokens de debug. Sem isso, callables com
/// `enforceAppCheck: true` falham em desenvolvimento.
Future<void> ativarFirebaseAppCheck() async {
  await _ativarFirebaseAppCheckNoIsolate();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configurarBarraNavegacaoAndroidOculta();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ativarFirebaseAppCheck();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final p = response.payload;
      if (p == null || p.isEmpty) return;
      try {
        final map = jsonDecode(p) as Map<String, dynamic>;
        navigatorKey.currentState?.pushNamed(rotaPorPayloadFcm(map));
      } catch (_) {}
    },
  );
  CorridaForegroundNotificacao.registrar(flutterLocalNotificationsPlugin);

  final androidNotifPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidNotifPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'high_importance_channel',
      'Alertas DiPertin',
      description: 'Pedidos, entregas e central de ajuda',
      importance: Importance.high,
      playSound: true,
    ),
  );
  await androidNotifPlugin?.createNotificationChannel(
    AndroidNotificationChannel(
      'corrida_chamada',
      'Chamadas de corrida',
      description: 'Alerta sonoro de nova entrega para entregadores',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('chamada_entregador'),
    ),
  );
  await androidNotifPlugin?.createNotificationChannel(
    AndroidNotificationChannel(
      'loja_novo_pedido',
      'Novos pedidos na loja',
      description: 'Alerta sonoro exclusivo para novos pedidos (lojista)',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('pedido'),
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: const DiPertinApp(),
    ),
  );
}

class DiPertinApp extends StatefulWidget {
  const DiPertinApp({super.key});

  @override
  State<DiPertinApp> createState() => _DiPertinAppState();
}

class _DiPertinAppState extends State<DiPertinApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      configurarBarraNavegacaoAndroidOculta();
      unawaited(_consumirNavAndroidSeHouver());
    }
  }

  Future<void> _consumirNavAndroidSeHouver() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final nav = await AndroidNavIntent.consumePendingNav();
    if (nav == null || nav['openEntregador'] != true) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pushNamedAndRemoveUntil('/entregador', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DiPertin - O que você precisa, bem aqui!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: diPertinRoxo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: diPertinRoxo,
          secondary: diPertinLaranja,
        ),
        useMaterial3: true,
      ),
      // `child` pode ser null por um frame ao trocar a pilha de rotas.
      builder: (context, child) =>
          AppGuard(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
      routes: {
        '/pedidos': (context) => const LojistaPedidosScreen(),
        '/meus-pedidos': (context) => const OrdersScreen(),
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final tab = args is int ? args : null;
          return MainNavigator(initialTabIndex: tab);
        },
        '/entregador': (context) => const EntregadorHomeScreen(),
        '/entregador-pos-entrega': (context) => const EntregadorHomeScreen(),
        '/suporte': (context) => const ChatSuporteScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _erroCidadeNaoIdentificada = false;
  AppAtualizacaoVerificacao? _bloqueioAtualizacao;

  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _aguardarCondicao(bool Function() condicao) async {
    while (!condicao()) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
    }
  }

  /// Abre a vitrine só com cidade+UF já resolvidos pelo GPS nesta sessão.
  Future<bool> _resolverCidadeParaVitrine() async {
    const maxTentativas = 5;
    for (var t = 0; t < maxTentativas; t++) {
      if (!mounted) return false;
      await context.read<LocationService>().detectarCidade();
      if (!mounted) return false;
      if (context.read<LocationService>().cidadePronta) return true;
      await Future.delayed(Duration(milliseconds: 500 + t * 350));
    }
    return false;
  }

  Future<void> _aplicarDelayMinimoSplash(DateTime splashInicio) async {
    final decorrido = DateTime.now().difference(splashInicio).inMilliseconds;
    if (decorrido < 1500) {
      await Future.delayed(Duration(milliseconds: 1500 - decorrido));
    }
  }

  Future<void> _inicializarApp() async {
    setState(() {
      _erroCidadeNaoIdentificada = false;
      _bloqueioAtualizacao = null;
    });

    final splashInicio = DateTime.now();
    final connectivity = context.read<ConnectivityService>();
    final location = context.read<LocationService>();

    await _aguardarCondicao(() => connectivity.initialized);
    if (!mounted) return;
    await _aguardarCondicao(() => connectivity.isOnline);
    if (!mounted) return;

    final atualizacao = await AppAtualizacaoObrigatoriaService.verificar();
    if (!mounted) return;
    if (atualizacao.bloqueado) {
      setState(() => _bloqueioAtualizacao = atualizacao);
      return;
    }

    await _aguardarCondicao(() => location.initialized);
    if (!mounted) return;

    if (location.status == LocationStatus.permissaoNegada) {
      await location.solicitarPermissao();
    }

    await _aguardarCondicao(() => location.status == LocationStatus.pronto);
    if (!mounted) return;

    try {
      await _configurarFCM().timeout(const Duration(seconds: 12));
      debugPrint('[FCM] Configuração concluída com sucesso');
    } catch (e) {
      debugPrint('[FCM] ERRO na configuração: $e');
    }

    if (!mounted) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final nav = await AndroidNavIntent.consumePendingNav();
      if (nav != null && nav['openEntregador'] == true) {
        await _aplicarDelayMinimoSplash(splashInicio);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/entregador');
        return;
      }
    }

    RemoteMessage? initialMessage;
    try {
      initialMessage = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('getInitialMessage falhou: $e');
    }

    if (initialMessage != null) {
      unawaited(CorridaChamadaEntregadorAudio.parar());
      unawaited(_resolverCidadeParaVitrine());
      await _aplicarDelayMinimoSplash(splashInicio);
      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        rotaPorPayloadFcm(initialMessage.data),
      );
      return;
    }

    final ok = await _resolverCidadeParaVitrine();
    if (!mounted) return;

    if (!ok) {
      setState(() => _erroCidadeNaoIdentificada = true);
      return;
    }

    await _aplicarDelayMinimoSplash(splashInicio);
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _abrirLojaParaAtualizarApp() async {
    final u = _bloqueioAtualizacao?.urlLoja;
    if (u == null || u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[atualizacao_app] launchUrl: $e');
    }
  }

  Future<void> _verificarAtualizacaoNovamente() async {
    setState(() => _bloqueioAtualizacao = null);
    await _inicializarApp();
  }

  Future<void> _tentarNovamenteIdentificarCidade() async {
    setState(() => _erroCidadeNaoIdentificada = false);
    final splashInicio = DateTime.now();
    final ok = await _resolverCidadeParaVitrine();
    if (!mounted) return;
    if (!ok) {
      setState(() => _erroCidadeNaoIdentificada = true);
      return;
    }
    await _aplicarDelayMinimoSplash(splashInicio);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _configurarFCM() async {
    Future<void> pararSomCorridaForeground() async {
      await CorridaChamadaEntregadorAudio.parar();
    }

    // 1) Listeners PRIMEIRO — independem de permissão/token.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        '[FCM] onMessage recebido — tipo=${message.data['tipoNotificacao']} '
        'type=${message.data['type']} title=${message.notification?.title}',
      );
      unawaited(_mostrarNotificacaoForegroundSePermitido(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessageOpenedApp — ${message.data}');
      unawaited(pararSomCorridaForeground());
      navigatorKey.currentState?.pushNamed(rotaPorPayloadFcm(message.data));
    });

    // 2) Permissão Android 13+ (POST_NOTIFICATIONS).
    try {
      final resultadoPerm =
          await PermissoesAppService.garantirNotificacoesAndroid();
      debugPrint('[FCM] Permissão Android: $resultadoPerm');
    } catch (e) {
      debugPrint('[FCM] Erro ao pedir permissão Android: $e');
    }

    // 3) Permissão FCM (iOS APNS / Android).
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] Permissão FCM: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] Erro requestPermission: $e');
    }

    // 4) iOS foreground presentation.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (e) {
        debugPrint('[FCM] Erro setForegroundPresentationOptions: $e');
      }
    }

    // 5) Token + persistência.
    String? token;
    try {
      token = await messaging.getToken();
      debugPrint(
        '[FCM] Token obtido: ${token != null ? '${token.substring(0, 12)}…' : 'NULO'}',
      );
    } catch (e) {
      debugPrint('[FCM] ERRO ao obter token: $e');
    }

    final User? user = FirebaseAuth.instance.currentUser;
    debugPrint('[FCM] Usuário logado: ${user?.uid ?? 'NÃO LOGADO'}');

    if (user != null && token != null) {
      await _persistirTokenFcm(token, forcar: true);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((novoToken) {
      debugPrint('[FCM] Token atualizado (refresh)');
      unawaited(_persistirTokenFcm(novoToken));
    });
  }

  Future<void> _persistirTokenFcm(
    String novoToken, {
    bool forcar = false,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      debugPrint('[FCM] Token NÃO salvo — sem usuário logado');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!forcar) {
        final tokenSalvo = prefs.getString('fcm_token');
        final usuarioSalvo = prefs.getString('fcm_uid');
        if (tokenSalvo == novoToken && usuarioSalvo == u.uid) {
          debugPrint('[FCM] Token já persistido — skip');
          return;
        }
      }
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'fcm_token': novoToken,
        'ultimo_acesso': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await prefs.setString('fcm_token', novoToken);
      await prefs.setString('fcm_uid', u.uid);
      debugPrint('[FCM] Token SALVO no Firestore para uid=${u.uid}');
    } catch (e) {
      debugPrint('[FCM] ERRO ao salvar token: $e');
    }
  }

  Future<void> _mostrarNotificacaoForegroundSePermitido(
    RemoteMessage message,
  ) async {
    var tipo =
        message.data['tipoNotificacao']?.toString() ??
        message.data['tipo']?.toString() ??
        '';
    final typeRaw = message.data['type']?.toString() ?? '';
    if (tipo.isEmpty &&
        typeRaw == FcmNotificationEventos.typeNovoPedido) {
      tipo = FcmNotificationEventos.tipoNovoPedido;
    }
    final evento = message.data['evento']?.toString() ?? '';
    if (tipo.isEmpty &&
        evento == FcmNotificationEventos.eventoDispatchRequest) {
      tipo = FcmNotificationEventos.tipoNovaEntrega;
    }
    if (tipo.isEmpty &&
        typeRaw.toLowerCase() ==
            FcmNotificationEventos.typeNovaCorrida.toLowerCase()) {
      tipo = FcmNotificationEventos.tipoNovaEntrega;
    }
    // Chamada de despacho: não pode ficar silenciosa por causa do toggle em Configurações.
    final isChamadaOperacional =
        evento == FcmNotificationEventos.eventoDispatchRequest ||
        typeRaw.toLowerCase() ==
            FcmNotificationEventos.typeNovaCorrida.toLowerCase() ||
        tipo.toLowerCase() == FcmNotificationEventos.tipoNovaEntrega.toLowerCase();
    final permitido = await NotificacoesPrefs.deveExibirNotificacaoLocal(tipo);
    final mostrar = permitido || isChamadaOperacional;
    debugPrint(
      '[FCM] foreground tipo=$tipo typeRaw=$typeRaw evento=$evento '
      'permitido=$permitido chamadaOp=$isChamadaOperacional mostrar=$mostrar',
    );
    if (!mostrar) return;

    final isCorrida =
        tipo == FcmNotificationEventos.tipoNovaEntrega ||
        evento == FcmNotificationEventos.eventoDispatchRequest ||
        typeRaw.toLowerCase() ==
            FcmNotificationEventos.typeNovaCorrida.toLowerCase();
    final isNovoPedidoLoja =
        tipo == FcmNotificationEventos.tipoNovoPedido ||
        typeRaw == FcmNotificationEventos.typeNovoPedido;
    final n = message.notification;
    String title = n?.title ?? '';
    String body = n?.body ?? '';
    if (title.isEmpty && body.isEmpty) {
      if (!isCorrida) return;
      title = 'Nova corrida DiPertin';
      body = 'Toque para abrir o radar e aceitar.';
    }

    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final AndroidNotificationDetails androidDetails;
    if (isAndroid && isCorrida) {
      androidDetails = AndroidNotificationDetails(
        'corrida_chamada',
        'Chamadas de corrida',
        channelDescription: 'Alerta sonoro de nova entrega para entregadores',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('chamada_entregador'),
        playSound: true,
        fullScreenIntent: true,
      );
    } else if (isAndroid && isNovoPedidoLoja) {
      androidDetails = AndroidNotificationDetails(
        'loja_novo_pedido',
        'Novos pedidos na loja',
        channelDescription:
            'Alerta sonoro exclusivo para novos pedidos (lojista)',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('pedido'),
        playSound: true,
      );
    } else if (isAndroid) {
      androidDetails = const AndroidNotificationDetails(
        'high_importance_channel',
        'Alertas DiPertin',
        channelDescription: 'Pedidos, entregas e central de ajuda',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        'high_importance_channel',
        'Alertas DiPertin',
        channelDescription: 'Pedidos, entregas e central de ajuda',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
    }

    final bool isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    String orderIdCorrida = '';
    if (isCorrida) {
      for (final k in <String>[
        'orderId',
        'order_id',
        'pedido_id',
        'pedidoId',
      ]) {
        final v = message.data[k]?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          orderIdCorrida = v;
          break;
        }
      }
    }
    try {
      final notifId = isCorrida && orderIdCorrida.isNotEmpty
          ? CorridaForegroundNotificacao.idParaPedido(orderIdCorrida)
          : (message.hashCode & 0x7FFFFFFF);
      await flutterLocalNotificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: isIos
              ? const DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: true,
                )
              : null,
        ),
        payload: jsonEncode(message.data),
      );
      debugPrint('[FCM] Notificação local exibida: $title');
    } catch (e) {
      debugPrint('[FCM] ERRO ao exibir notificação local: $e');
    }

    if (isNovoPedidoLoja) {
      try {
        await _audioNovoPedidoLoja.stop();
        await _audioNovoPedidoLoja.play(AssetSource('sond/pedido.mp3'));
      } catch (e) {
        debugPrint('Som novo pedido (foreground): $e');
      }
    }
    if (isCorrida) {
      try {
        await CorridaChamadaEntregadorAudio.tocarChamada();
      } catch (e) {
        debugPrint('Som corrida entregador (foreground): $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado =
        _bloqueioAtualizacao != null && _bloqueioAtualizacao!.bloqueado;

    return PopScope(
      canPop: !bloqueado,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 1),
                  builder: (context, double value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        child: child,
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/logo.png',
                    height: 180,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.storefront,
                      size: 100,
                      color: diPertinLaranja,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                if (bloqueado) ...[
                  const Icon(
                    Icons.system_update,
                    size: 48,
                    color: diPertinRoxo,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Atualização necessária',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sua versão: ${_bloqueioAtualizacao!.versaoAtual ?? "—"}\n'
                    'Versão mínima: ${_bloqueioAtualizacao!.versaoMinima ?? "—"}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.45,
                    ),
                  ),
                  if ((_bloqueioAtualizacao!.mensagem ?? '')
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _bloqueioAtualizacao!.mensagem!.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _abrirLojaParaAtualizarApp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Atualizar na loja',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _verificarAtualizacaoNovamente,
                    child: const Text(
                      'Já atualizei — verificar de novo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: diPertinRoxo,
                      ),
                    ),
                  ),
                ] else if (_erroCidadeNaoIdentificada) ...[
                  const Text(
                    'Não foi possível identificar sua cidade',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ative o GPS, conceda permissão de localização e '
                    'certifique-se de ter sinal. Depois tente novamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _tentarNovamenteIdentificarCidade,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: diPertinLaranja,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Tentar novamente',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else
                  const CircularProgressIndicator(color: diPertinLaranja),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.initialTabIndex});

  /// Índice da aba inferior (0 Buscar, 1 Vitrine, 2 Perfil), se informado.
  final int? initialTabIndex;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  late int _selectedIndex;
  bool _onboardingEnderecoProcessado = false;
  bool _comunicadosExibidos = false;
  String? _ultimoUidOnboarding;
  StreamSubscription<User?>? _authSub;
  final List<Widget> _telas = [
    const SearchScreen(),
    const VitrineScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.initialTabIndex;
    _selectedIndex =
        (t != null && t >= 0 && t < _telas.length) ? t : 1;
    _ultimoUidOnboarding = FirebaseAuth.instance.currentUser?.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executarOnboardingEnderecoPrimeiroAcesso().then((_) {
        _exibirComunicadosNaoLidos();
      });
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid == null) {
        _ultimoUidOnboarding = null;
        _onboardingEnderecoProcessado = false;
        _comunicadosExibidos = false;
        return;
      }

      if (_ultimoUidOnboarding != uid) {
        _ultimoUidOnboarding = uid;
        _onboardingEnderecoProcessado = false;
        _comunicadosExibidos = false;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executarOnboardingEnderecoPrimeiroAcesso().then((_) {
          _exibirComunicadosNaoLidos();
        });
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _executarOnboardingEnderecoPrimeiroAcesso() async {
    if (_onboardingEnderecoProcessado || !mounted) return;
    _onboardingEnderecoProcessado = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userSnap = await userRef.get();
    if (!userSnap.exists || !mounted) return;

    final dados = userSnap.data() ?? <String, dynamic>{};
    final role = (dados['role'] ?? dados['tipoUsuario'] ?? '')
        .toString()
        .toLowerCase();
    if (role != 'cliente') return;

    final onboardingPendente = dados['onboarding_endereco_pendente'] == true;
    if (!onboardingPendente) return;

    final ep = dados['endereco_entrega_padrao'];
    final temEnderecoPadrao = ep is Map &&
        (ep['rua'] ?? '').toString().trim().isNotEmpty;
    final enderecosSnap = await userRef.collection('enderecos').limit(1).get();
    final temEnderecoNaLista = enderecosSnap.docs.isNotEmpty;

    if (temEnderecoPadrao || temEnderecoNaLista) {
      await userRef.set({
        'onboarding_endereco_pendente': false,
        'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    if (!mounted) return;
    final deveCadastrar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: const [
            CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFEDE7F6),
              child: Icon(Icons.place_rounded, color: diPertinRoxo),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Quase tudo pronto!',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
              ),
            ),
          ],
        ),
        content: const Text(
          'Para finalizar seu primeiro acesso, cadastre seu endereço de entrega. '
          'Assim conseguimos mostrar ofertas e calcular frete com precisão na sua região.',
          style: TextStyle(height: 1.42, fontSize: 14),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: diPertinRoxo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text(
                'Cadastrar endereço',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );

    if (deveCadastrar == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const MeusEnderecosScreen(),
        ),
      );

      if (!mounted) return;
      final recheck = await userRef.collection('enderecos').limit(1).get();
      if (recheck.docs.isNotEmpty) {
        await userRef.set({
          'onboarding_endereco_pendente': false,
          'onboarding_endereco_concluido_em': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  Future<void> _exibirComunicadosNaoLidos() async {
    if (_comunicadosExibidos || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _comunicadosExibidos = true;

    try {
      await mostrarComunicadosNaoLidos(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _telas[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: diPertinLaranja,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: "Buscar/Serviços",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront),
            label: "Vitrine",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Perfil"),
        ],
      ),
    );
  }
}
