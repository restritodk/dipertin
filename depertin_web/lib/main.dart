import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'services/painel_google_redirect_pending.dart';
import 'navigation/painel_routes.dart';
import 'theme/painel_admin_theme.dart';
import 'screens/login_admin_screen.dart';
import 'widgets/painel_shell_screen.dart';

/// Site Key do reCAPTCHA v3 (app "depertin_web" no Firebase App Check).
/// Público por design — pode ficar em código versionado. Par privado (secret)
/// fica só no Firebase Console.
const String _recaptchaV3SiteKey = '6LeKK70sAAAAAILrKAehrUn8KMVogIAc_B2moo-e';

/// Ativa Firebase App Check no painel web.
///
/// Em **produção** (Chrome/Edge) usa reCAPTCHA v3 — o browser obtém um token
/// silencioso (sem checkbox) baseado em comportamento; o Firebase valida com
/// o `secret key` guardado no console. Se o Firebase considerar suspeito,
/// nega o token e as callables/Firestore/Storage que tiverem enforce rejeitam.
///
/// Em **debug** (`flutter run -d chrome`) usa [AppCheckProvider.debug] — o SDK
/// imprime um debug token no console do navegador uma vez; esse token precisa
/// ser registrado no Firebase Console → App Check → apps → depertin_web →
/// "Gerenciar tokens de debug" pra ser aceito.
///
/// **Não enforça nada por si só** — a ativação só anexa o token nas requests.
/// O enforcement continua sendo decidido por cada Cloud Function / rule.
// ignore: unused_element
Future<void> _ativarAppCheckPainel() async {
  if (!kIsWeb) return;
  try {
    await FirebaseAppCheck.instance
        .activate(webProvider: ReCaptchaV3Provider(_recaptchaV3SiteKey))
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('FirebaseAppCheck (painel): $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Português do Brasil (Material, intl/DateFormat, números).
  Intl.defaultLocale = 'pt_BR';
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // App Check DESATIVADO temporariamente: o reCAPTCHA v3 estava retornando
  // `appCheck/recaptcha-error` em produção (provavelmente porque o domínio
  // www.dipertin.com.br não está registrado no site key do reCAPTCHA, ou porque
  // o Chrome está bloqueando cookies de terceiros). Com o provider ativo,
  // cada chamada Firebase tentava obter um token, falhava, e o login quebrava.
  // Para reativar: verificar em Firebase Console → App Check → apps →
  // depertin_web se o site key está vinculado aos domínios certos
  // (dipertin.com.br E www.dipertin.com.br), e depois descomentar a linha abaixo.
  // await _ativarAppCheckPainel();
  // OAuth redirect: getRedirectResult só pode ser chamado uma vez; com hash routing
  // o resultado perdia-se se fosse só no LoginScreen.
  // Timeout defensivo: em alguns cenários (CSP, iframe bloqueado, 3rd party cookies
  // off) a Promise nunca resolve e o app ficava em tela branca em produção.
  if (kIsWeb) {
    try {
      final cred = await FirebaseAuth.instance
          .getRedirectResult()
          .timeout(const Duration(seconds: 5));
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
