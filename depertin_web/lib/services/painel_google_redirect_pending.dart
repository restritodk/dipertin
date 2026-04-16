/// UID a processar na tela de login após [signInWithRedirect].
///
/// [FirebaseAuth.getRedirectResult] deve ser chamado **uma vez** após
/// [Firebase.initializeApp] (ver [main.dart]); o resultado guarda-se aqui para o
/// [LoginAdminScreen] completar o fluxo (callable + Firestore).
class PainelGoogleRedirectPending {
  static String? uidParaCompletarLogin;
}
