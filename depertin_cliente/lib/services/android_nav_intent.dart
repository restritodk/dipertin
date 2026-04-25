import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ponte nativa Android via MethodChannel.
///
/// Cobre permissões padrão e intents OEM para:
/// Xiaomi, Samsung, Oppo, Vivo, Huawei, Honor, OnePlus, Realme, Asus,
/// Lenovo, Motorola, Infinix, Tecno, Meizu, Letv/LeEco, Nokia, Sony, LG.
class AndroidNavIntent {
  static const _ch = MethodChannel('dipertin.android/nav');

  // ── helpers ────────────────────────────────────────────────────────

  static bool get _skip => kIsWeb || !Platform.isAndroid;

  static Future<bool> _callBool(String method, {bool fallback = true}) async {
    if (_skip) return fallback;
    try {
      final dynamic r = await _ch.invokeMethod(method);
      return r == true;
    } catch (e) {
      debugPrint('[AndroidNavIntent.$method] $e');
      return fallback;
    }
  }

  static Future<bool> _callOpen(String method) => _callBool(method, fallback: false);

  // ── navegação pendente ─────────────────────────────────────────────

  static Future<Map<String, dynamic>?> consumePendingNav() async {
    if (_skip) return null;
    try {
      final dynamic r = await _ch.invokeMethod('consumePendingNav');
      if (r is! Map) return null;
      return Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[AndroidNavIntent] $e');
      return null;
    }
  }

  // ── full-screen intent ─────────────────────────────────────────────

  static Future<bool> canUseFullScreenIntent() => _callBool('canUseFullScreenIntent');
  static Future<bool> openFullScreenIntentSettings() => _callOpen('openFullScreenIntentSettings');

  // ── bateria (padrão Android) ───────────────────────────────────────

  static Future<bool> isIgnoringBatteryOptimizations() => _callBool('isIgnoringBatteryOptimizations');
  static Future<bool> openBatteryOptimizationSettings() => _callOpen('openBatteryOptimizationSettings');

  // ── overlay (exibir sobre outros apps) ─────────────────────────────

  static Future<bool> canDrawOverlays() => _callBool('canDrawOverlays');
  static Future<bool> openOverlayPermissionSettings() => _callOpen('openOverlayPermissionSettings');

  // ── autostart (OEM-specific) ───────────────────────────────────────

  static Future<bool> openAutostartSettings() => _callOpen('openAutostartSettings');

  // ── bateria OEM (gerenciador proprietário) ─────────────────────────

  static Future<bool> openOemBatterySettings() => _callOpen('openOemBatterySettings');

  // ── notificações ───────────────────────────────────────────────────

  static Future<bool> areNotificationsEnabled() => _callBool('areNotificationsEnabled');
  static Future<bool> openNotificationSettings() => _callOpen('openNotificationSettings');

  /// Cancela a notificação nativa de oferta de corrida (mesmo id que [CorridaIncomingNotifier]).
  static Future<void> cancelIncomingCorridaNotification(String pedidoId) async {
    if (_skip || pedidoId.trim().isEmpty) return;
    try {
      await _ch.invokeMethod<void>(
        'cancelIncomingCorridaNotification',
        pedidoId.trim(),
      );
    } catch (e) {
      debugPrint('[AndroidNavIntent.cancelIncomingCorridaNotification] $e');
    }
  }

  /// Abre a tela oficial nativa de chamada de corrida (Android).
  static Future<bool> openIncomingDeliveryScreen(
    Map<String, String> payload,
  ) async {
    if (_skip) return false;
    if (payload.isEmpty) return false;
    try {
      final dynamic r = await _ch.invokeMethod(
        'openIncomingDeliveryScreen',
        payload,
      );
      return r == true;
    } catch (e) {
      debugPrint('[AndroidNavIntent.openIncomingDeliveryScreen] $e');
      return false;
    }
  }

  /// Mapa `pedidoId → despacho_oferta_seq` das ofertas que o entregador
  /// acabou de aceitar/recusar na fullscreen nativa, mas cujo estado
  /// final no Firestore (`entregador_id`/`status`) o backend ainda pode
  /// não ter gravado.
  ///
  /// O dashboard do entregador consulta este mapa antes de reabrir uma
  /// fullscreen via stream de `despacho_oferta_uid`, evitando o loop em
  /// que a tela de aceitar volta a aparecer logo após o tap. O `seq` é
  /// usado para distinguir um lock obsoleto (mesmo seq → ainda sou eu na
  /// mesma chamada) de um re-dispatch (seq maior → nova oferta válida).
  static Future<Map<String, int>> getOfertasProcessadasLocais() async {
    if (_skip) return const <String, int>{};
    try {
      final dynamic r = await _ch.invokeMethod('getOfertasProcessadasLocais');
      if (r is Map) {
        final out = <String, int>{};
        r.forEach((k, v) {
          final id = k?.toString().trim() ?? '';
          if (id.isEmpty) return;
          final seq = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
          out[id] = seq;
        });
        return out;
      }
    } catch (e) {
      debugPrint('[AndroidNavIntent.getOfertasProcessadasLocais] $e');
    }
    return const <String, int>{};
  }

  /// Sinaliza ao estado nativo que o backend já confirmou a oferta para
  /// este pedido (i.e. `entregador_id` chegou no Firestore). Libera o
  /// pedido para que, no futuro, possa receber novas ofertas (ex.:
  /// re-despacho após uma recusa não confirmada).
  static Future<void> confirmarOfertaProcessadaPorBackend(String pedidoId) async {
    if (_skip) return;
    final id = pedidoId.trim();
    if (id.isEmpty) return;
    try {
      await _ch.invokeMethod<void>('confirmarOfertaProcessadaPorBackend', id);
    } catch (e) {
      debugPrint('[AndroidNavIntent.confirmarOfertaProcessadaPorBackend] $e');
    }
  }

  /// Lê e LIMPA, de forma atômica, o motivo da última falha de aceite
  /// que o `IncomingDeliveryActivity` (ou o
  /// `IncomingDeliveryActionReceiver`) registrou após chamar a callable
  /// `aceitarOfertaCorrida`.
  ///
  /// Retorna `null` quando não há falha pendente (caso comum) ou quando
  /// a falha é mais antiga que o TTL do nativo (5 minutos).
  ///
  /// Quando há, o mapa contém:
  ///   - `pedidoId` (String)  → id do pedido afetado
  ///   - `motivo`   (String)  → código bruto do backend
  ///                            (ex.: `corrida_ja_aceita`,
  ///                            `veiculo_incompativel_loja`)
  ///   - `mensagem` (String)  → frase pronta pra exibir ao entregador
  ///   - `timestampMs` (int)  → quando aconteceu (epoch ms)
  ///
  /// O dashboard do entregador chama isso no `initState` e a cada
  /// `AppLifecycleState.resumed` para mostrar SnackBar — o entregador
  /// precisa entender por que a oferta sumiu logo após tocar Aceitar.
  static Future<Map<String, dynamic>?> consumirUltimaFalhaAceite() async {
    if (_skip) return null;
    try {
      final dynamic r = await _ch.invokeMethod('consumirUltimaFalhaAceite');
      if (r is Map) return Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[AndroidNavIntent.consumirUltimaFalhaAceite] $e');
    }
    return null;
  }

  // ── ícone flutuante ─────────────────────────────────────────────

  static Future<bool> startFloatingIcon() => _callOpen('startFloatingIcon');
  static Future<bool> stopFloatingIcon() => _callOpen('stopFloatingIcon');
  static Future<bool> isFloatingIconRunning() => _callBool('isFloatingIconRunning', fallback: false);

  // ── detalhes do app no sistema ─────────────────────────────────────

  static Future<bool> openAppDetailsSettings() => _callOpen('openAppDetailsSettings');

  // ── info do dispositivo ────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    if (_skip) {
      return {'manufacturer': '', 'brand': '', 'model': '', 'sdk': 0};
    }
    try {
      final dynamic r = await _ch.invokeMethod('getDeviceInfo');
      if (r is Map) return Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[AndroidNavIntent.getDeviceInfo] $e');
    }
    return {'manufacturer': '', 'brand': '', 'model': '', 'sdk': 0};
  }
}
