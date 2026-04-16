import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'services/painel_google_redirect_pending.dart';
import 'navigation/painel_routes.dart';
import 'theme/painel_admin_theme.dart';
import 'screens/login_admin_screen.dart';
import 'widgets/painel_shell_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Português do Brasil (Material, intl/DateFormat, números).
  Intl.defaultLocale = 'pt_BR';
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // OAuth redirect: getRedirectResult só pode ser chamado uma vez; com hash routing
  // o resultado perdia-se se fosse só no LoginScreen.
  if (kIsWeb) {
    try {
      final cred = await FirebaseAuth.instance.getRedirectResult();
      if (cred.user != null) {
        PainelGoogleRedirectPending.uidParaCompletarLogin = cred.user!.uid;
      }
    } catch (_) {}
  }
  // Web + hot reload (R): persistência IndexedDB + vários listeners costuma
  // disparar INTERNAL ASSERTION FAILED no SDK Firestore — desliga em debug.
  if (kIsWeb && kDebugMode) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
    } catch (_) {}
  }
  runApp(const DiPertinAdminApp());
}

/// Rota sem animação (troca instantânea) — usada ao abrir URLs diretas do painel no web.
Route<void> _rotaPainelInstantanea(RouteSettings settings, Widget child) {
  return PageRouteBuilder<void>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

class DiPertinAdminApp extends StatelessWidget {
  const DiPertinAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiPertin',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        return const Locale('pt', 'BR');
      },
      theme: PainelAdminTheme.theme(),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginAdminScreen(),
        '/painel': (context) => const PainelShellScreen(),
      },
      onGenerateRoute: (RouteSettings settings) {
        final name = settings.name;
        if (name != null && PainelRoutes.isShellRoute(name)) {
          return _rotaPainelInstantanea(
            settings,
            PainelShellScreen(initialRoute: name),
          );
        }
        return null;
      },
    );
  }
}
