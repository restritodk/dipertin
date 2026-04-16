import 'package:firebase_auth/firebase_auth.dart';

import 'painel_google_auth_impl_web.dart'
    if (dart.library.io) 'painel_google_auth_impl_io.dart' as impl;

/// Login Google → Firebase Auth (web: popup/redirect; mobile/desktop: `google_sign_in`).
Future<UserCredential?> painelSignInWithGoogle() => impl.painelSignInWithGoogle();

Future<void> painelSignOutGoogle() => impl.painelSignOutGoogle();
