import 'package:firebase_auth/firebase_auth.dart';

GoogleAuthProvider _painelGoogleAuthProvider() {
  final p = GoogleAuthProvider();
  p.addScope('email');
  p.addScope('profile');
  p.setCustomParameters({'prompt': 'select_account'});
  return p;
}

/// Login Google no **browser** via Firebase Auth.
///
/// [signInWithPopup] — janela pequena (contas Google). Se falhar (`internal-error`,
/// popup bloqueado), usa [signInWithRedirect] (retorno em [main.dart] +
/// [PainelGoogleRedirectPending]).
Future<UserCredential?> painelSignInWithGoogle() async {
  final provider = _painelGoogleAuthProvider();
  try {
    return await FirebaseAuth.instance.signInWithPopup(provider);
  } on FirebaseAuthException catch (e) {
    if (e.code == 'internal-error' || e.code == 'popup-blocked') {
      await FirebaseAuth.instance.signInWithRedirect(provider);
      return null;
    }
    rethrow;
  }
}

Future<void> painelSignOutGoogle() async {}
