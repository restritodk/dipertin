// Arquivo: lib/main.dart

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
import 'screens/cliente/vitrine_screen.dart';
import 'screens/cliente/search_screen.dart';
import 'screens/comum/profile_screen.dart';

// ==========================================
// VARIÁVEIS GLOBAIS E CORES
// ==========================================
const Color diPertinRoxo = Color(0xFF6A1B9A);
const Color diPertinLaranja = Color(0xFFFF8F00);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Instância do Plugin de Notificação Local
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Handler para notificações em background (App Fechado ou em Segundo Plano)
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
    ChangeNotifierProvider(
      create: (context) => CartProvider(),
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
      title: 'DiPertin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: diPertinRoxo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: diPertinRoxo,
          secondary: diPertinLaranja,
        ),
        useMaterial3: true,
      ),
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
  @override
  void initState() {
    super.initState();
    _inicializarApp();
  }

  Future<void> _inicializarApp() async {
    await _configurarFCM();

    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    if (initialMessage != null) {
      String? tipoDaNotificacao =
          initialMessage.data['tipoNotificacao'] ?? initialMessage.data['tipo'];

      if (tipoDaNotificacao == 'nova_entrega') {
        Navigator.pushReplacementNamed(context, '/entregador');
      } else {
        Navigator.pushReplacementNamed(context, '/pedidos');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _configurarFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    String? token = await messaging.getToken();
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null && token != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Lemos o token E o utilizador guardados na memória do telemóvel
      String? tokenSalvo = prefs.getString('fcm_token');
      String? utilizadorSalvo = prefs.getString('fcm_uid');

      // Se o token mudou OU se é um utilizador diferente logado, forçamos a gravação!
      if (tokenSalvo != token || utilizadorSalvo != user.uid) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcm_token': token,
          'ultimo_acesso': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Atualizamos a memória do telemóvel
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
            const CircularProgressIndicator(color: diPertinLaranja),
          ],
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
