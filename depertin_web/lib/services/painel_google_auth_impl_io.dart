import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_sign_in_config.dart';

final GoogleSignIn _painelGoogleSignIn = GoogleSignIn(
  clientId: googleSignInClientIdOrNull,
  scopes: const ['email', 'profile'],
);

/// Login Google → Firebase Auth (Android / iOS / desktop do painel).
Future<UserCredential?> painelSignInWithGoogle() async {
  try {
    await _painelGoogleSignIn.signOut();
  } catch (_) {}

  final GoogleSignInAccount? googleUser = await _painelGoogleSignIn.signIn();
  if (googleUser == null) {
    throw StateError('Login Google cancelado pelo usuário.');
  }

  final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
  final String? idToken = googleAuth.idToken;
  final String? accessToken = googleAuth.accessToken;

  if (idToken == null && accessToken == null) {
    throw StateError(
      'Google não devolveu idToken. Confirme o cliente OAuth Web no Firebase Console.',
    );
  }

  final OAuthCredential credential = GoogleAuthProvider.credential(
    idToken: idToken,
    accessToken: accessToken,
  );

  return FirebaseAuth.instance.signInWithCredential(credential);
}

Future<void> painelSignOutGoogle() async {
  try {
    await _painelGoogleSignIn.signOut();
  } catch (e) {
    debugPrint('painelSignOutGoogle: $e');
  }
}
