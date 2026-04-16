import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// IDs da notificação local de corrida (FCM em primeiro plano) — cancelável pelo [pedidoId].
class CorridaForegroundNotificacao {
  CorridaForegroundNotificacao._();

  static FlutterLocalNotificationsPlugin? _plugin;

  static void registrar(FlutterLocalNotificationsPlugin plugin) {
    _plugin = plugin;
  }

  /// Faixa distinta do antigo `message.hashCode` para evitar colisões com outros pushes.
  static int idParaPedido(String pedidoId) {
    final h = pedidoId.hashCode & 0x3FFFFFFF;
    return 0x50000000 | h;
  }

  static Future<void> cancelarPedido(String pedidoId) async {
    final p = _plugin;
    if (p == null || pedidoId.trim().isEmpty) return;
    try {
      await p.cancel(id: idParaPedido(pedidoId.trim()));
    } catch (_) {}
  }
}
