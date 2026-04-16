import 'package:cloud_functions/cloud_functions.dart';

/// Região do deploy das Cloud Functions (mesma de `firebase deploy --only functions`).
/// URL: `https://<região>-depertin-f940f.cloudfunctions.net/<nomeDaFunção>`
const String kFirebaseFunctionsRegion = 'us-central1';

/// Instância única para callables (evita região errada com `FirebaseFunctions.instance`).
final FirebaseFunctions appFirebaseFunctions = FirebaseFunctions.instanceFor(
  region: kFirebaseFunctionsRegion,
);
