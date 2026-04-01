import 'package:depertin_web/screens/configuracoes_screen.dart';
import 'package:depertin_web/screens/financeiro_screen.dart';
import 'package:depertin_web/screens/utilidades_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_admin_screen.dart';
import 'screens/atendimento_suporte_screen.dart';
import 'screens/admin_city_screen.dart';
import 'screens/lojas_screen.dart';
import 'screens/entregadores_screen.dart';
import 'screens/banners_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const DiPertinAdminApp());
}

class DiPertinAdminApp extends StatelessWidget {
  const DiPertinAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiPertin Admin',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Define o idioma como Português do Brasil
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A1B9A)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      // MUDANÇA AQUI: A rota inicial agora é o Login
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginAdminScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/admincity': (context) => const AdminCityScreen(),
        '/lojas': (context) => const LojasScreen(),
        '/utilidades': (context) => const UtilidadesScreen(),
        '/financeiro': (context) => const FinanceiroScreen(),
        '/configuracoes': (context) => const ConfiguracoesScreen(),
        '/entregadores': (context) => const EntregadoresScreen(),
        '/banners': (context) => const BannersScreen(),
        '/atendimento_suporte': (context) =>
            const Center(child: Text("Tela de Suporte em Construção")),
        // ignore: equal_keys_in_map
        '/atendimento_suporte': (context) => const AtendimentoSuporteScreen(),
      },
    );
  }
}
