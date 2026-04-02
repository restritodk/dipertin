import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_sign_in_config.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn(
  serverClientId: kGoogleSignInServerClientId,
  scopes: ['email', 'profile'],
);

/// Login Google -> Firebase Auth.
/// Retorna [UserCredential] ou lança exceção se falhar / usuário cancelar.
Future<UserCredential> signInWithGoogleForFirebase() async {
  try {
    await _googleSignIn.signOut();
  } catch (_) {}

  final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

  if (googleUser == null) {
    throw StateError('Login Google cancelado pelo usuário.');
  }

  final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

  final String? idToken = googleAuth.idToken;
  final String? accessToken = googleAuth.accessToken;

  if (idToken == null && accessToken == null) {
    throw StateError(
      'Google não devolveu idToken nem accessToken. '
      'Confirma SHA-1 no Firebase Console e que o método Google está ativo em Authentication.',
    );
  }

  final OAuthCredential credential = GoogleAuthProvider.credential(
    idToken: idToken,
    accessToken: accessToken,
  );

  return FirebaseAuth.instance.signInWithCredential(credential);
}

/// Sign out do Google (útil para logout completo).
Future<void> signOutGoogle() async {
  try {
    await _googleSignIn.signOut();
  } catch (e) {
    debugPrint('signOutGoogle: $e');
  }
}
