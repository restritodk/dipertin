import 'dart:async';

import 'package:depertin_cliente/screens/lojista/lojista_pedidos_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:depertin_cliente/screens/entregador/entregador_dashboard_screen.dart';
import 'firebase_options.dart';
import 'providers/cart_provider.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';
import 'screens/guards/app_guard.dart';
import 'screens/cliente/vitrine_screen.dart';
import 'screens/cliente/search_screen.dart';
import 'screens/comum/profile_screen.dart';

const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
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

class DiPertinApp extends StatelessWidget {
  const DiPertinApp({super.key});

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
      builder: (context, child) => AppGuard(child: child!),
      home: const SplashScreen(),
      routes: {
        '/pedidos': (context) => const LojistaPedidosScreen(),
        '/home': (context) => const MainNavigator(),
        '/entregador': (context) => const EntregadorDashboardScreen(),
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
    final decorrido =
        DateTime.now().difference(splashInicio).inMilliseconds;
    if (decorrido < 1500) {
      await Future.delayed(Duration(milliseconds: 1500 - decorrido));
    }
  }

  Future<void> _inicializarApp() async {
    setState(() => _erroCidadeNaoIdentificada = false);

    final splashInicio = DateTime.now();
    final connectivity = context.read<ConnectivityService>();
    final location = context.read<LocationService>();

    await _aguardarCondicao(() => connectivity.initialized);
    if (!mounted) return;
    await _aguardarCondicao(() => connectivity.isOnline);
    if (!mounted) return;

    await _aguardarCondicao(() => location.initialized);
    if (!mounted) return;

    if (location.status == LocationStatus.permissaoNegada) {
      await location.solicitarPermissao();
    }

    await _aguardarCondicao(() => location.status == LocationStatus.pronto);
    if (!mounted) return;

    await _configurarFCM()
        .timeout(const Duration(seconds: 8))
        .catchError((_) {});

    if (!mounted) return;

    RemoteMessage? initialMessage;
    try {
      initialMessage = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('getInitialMessage falhou: $e');
    }

    if (initialMessage != null) {
      unawaited(_resolverCidadeParaVitrine());
      await _aplicarDelayMinimoSplash(splashInicio);
      if (!mounted) return;

      final tipoDaNotificacao = initialMessage.data['tipoNotificacao'] ??
          initialMessage.data['tipo'];

      if (tipoDaNotificacao == 'nova_entrega') {
        Navigator.pushReplacementNamed(context, '/entregador');
      } else {
        Navigator.pushReplacementNamed(context, '/pedidos');
      }
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
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    String? token = await messaging.getToken();
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null && token != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? tokenSalvo = prefs.getString('fcm_token');
      String? usuarioSalvo = prefs.getString('fcm_uid');

      if (tokenSalvo != token || usuarioSalvo != user.uid) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcm_token': token,
          'ultimo_acesso': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await prefs.setString('fcm_token', token);
        await prefs.setString('fcm_uid', user.uid);
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'Alertas de Pedidos',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      String? tipoDaNotificacao =
          message.data['tipoNotificacao'] ?? message.data['tipo'];

      if (tipoDaNotificacao == 'nova_entrega') {
        navigatorKey.currentState?.pushNamed('/entregador');
      } else {
        navigatorKey.currentState?.pushNamed('/pedidos');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              if (_erroCidadeNaoIdentificada) ...[
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
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});
  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 1;
  final List<Widget> _telas = [
    const SearchScreen(),
    const VitrineScreen(),
    const ProfileScreen(),
  ];
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
