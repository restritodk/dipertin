import 'package:flutter/foundation.dart' show kIsWeb;

/// OAuth 2.0 "Web client" (tipo 3 no google-services.json / Console Firebase).
/// Usado no Android do app mobile como `serverClientId`; no painel web como `clientId`.
const String kGoogleOAuthWebClientId =
    '939151024179-1aibtpudtpmvtki6g6du878i0j2012mj.apps.googleusercontent.com';

/// No Flutter Web o [GoogleSignIn] exige [clientId] explícito.
String? get googleSignInClientIdOrNull => kIsWeb ? kGoogleOAuthWebClientId : null;
