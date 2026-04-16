import 'dart:io';

/// Android/iOS/desktop: teste real de DNS (evita Wi‑Fi sem internet).
Future<bool> verificarDnsAcessoReal() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
