import 'package:cloud_functions/cloud_functions.dart';

/// Mensagem legível quando uma callable falha (ex.: `message` vazio no plugin).
String mensagemFirebaseFunctionsException(FirebaseFunctionsException e) {
  final codeLower = e.code.toLowerCase();
  if (codeLower == 'not-found') {
    return 'Serviço não encontrado no servidor. Publique as Cloud Functions mais recentes.';
  }
  final m = e.message?.trim();
  if (m != null && m.isNotEmpty) return m;
  final d = e.details;
  if (d != null && '$d'.trim().isNotEmpty) return '$d';
  return e.code;
}

/// Região do deploy das Cloud Functions (mesma de `firebase deploy --only functions`).
/// URL: `https://<região>-depertin-f940f.cloudfunctions.net/<nomeDaFunção>`
const String kFirebaseFunctionsRegion = 'us-central1';

/// Instância única para callables (evita região errada com `FirebaseFunctions.instance`).
final FirebaseFunctions appFirebaseFunctions = FirebaseFunctions.instanceFor(
  region: kFirebaseFunctionsRegion,
);
