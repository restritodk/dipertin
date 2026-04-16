import 'package:shared_preferences/shared_preferences.dart';

/// Preferências locais para alertas push (notificações em **primeiro plano**).
///
/// Tipos FCM usados hoje: ver [Cloud Functions](functions/index.js) e [main.dart].
/// Tipos futuros (pedido/pagamento) entram pelo mesmo [deveExibirNotificacaoLocal].
class NotificacoesPrefs {
  NotificacoesPrefs._();

  // --- Chaves (mesmas do chat onde aplicável, para não perder preferências) ---
  static const String kChatAtendimentoIniciado =
      'chat_notif_atendimento_iniciado';
  static const String kChatMensagens = 'chat_notif_mensagens_recebidas';
  static const String kChatAtendimentoFinalizado =
      'chat_notif_atendimento_finalizado';

  static const String kClientePedidos = 'notif_cliente_pedidos_status';
  static const String kClientePagamentos = 'notif_cliente_pagamentos';
  static const String kPromocoes = 'notif_promocoes_novidades';

  static const String kLojaNovoPedido = 'notif_loja_novo_pedido';
  static const String kEntregadorCorrida = 'notif_entregador_nova_corrida';

  static Future<bool> _get(String key, [bool padrao = true]) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(key) ?? padrao;
  }

  static Future<void> _set(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
  }

  // --- Chat / suporte (compatível com [ChatNotificacoesPrefs]) ---
  static Future<bool> chatAtendimentoIniciado() async =>
      _get(kChatAtendimentoIniciado);
  static Future<void> setChatAtendimentoIniciado(bool v) async =>
      _set(kChatAtendimentoIniciado, v);

  static Future<bool> chatMensagensRecebidas() async => _get(kChatMensagens);
  static Future<void> setChatMensagensRecebidas(bool v) async =>
      _set(kChatMensagens, v);

  static Future<bool> chatAtendimentoFinalizado() async =>
      _get(kChatAtendimentoFinalizado);
  static Future<void> setChatAtendimentoFinalizado(bool v) async =>
      _set(kChatAtendimentoFinalizado, v);

  // --- Cliente: pedidos e pagamentos (futuro + genérico) ---
  static Future<bool> clientePedidosECompras() async => _get(kClientePedidos);
  static Future<void> setClientePedidosECompras(bool v) async =>
      _set(kClientePedidos, v);

  static Future<bool> clientePagamentos() async => _get(kClientePagamentos);
  static Future<void> setClientePagamentos(bool v) async =>
      _set(kClientePagamentos, v);

  static Future<bool> promocoesENovidades() async => _get(kPromocoes);
  static Future<void> setPromocoesENovidades(bool v) async =>
      _set(kPromocoes, v);

  // --- Lojista ---
  static Future<bool> lojaNovosPedidos() async => _get(kLojaNovoPedido);
  static Future<void> setLojaNovosPedidos(bool v) async =>
      _set(kLojaNovoPedido, v);

  // --- Entregador ---
  static Future<bool> entregadorCorridas() async => _get(kEntregadorCorrida);
  static Future<void> setEntregadorCorridas(bool v) async =>
      _set(kEntregadorCorrida, v);

  /// Decide se o banner local (app aberto) deve aparecer para o [tipo] vindo do FCM.
  static Future<bool> deveExibirNotificacaoLocal(String? tipoNotificacao) async {
    final t = tipoNotificacao?.trim().toLowerCase() ?? '';
    if (t.isEmpty) return true;

    // Suporte / chat
    if (t == 'suporte_inicio' || t == 'atendimento_iniciado') {
      return await chatAtendimentoIniciado();
    }
    if (t == 'suporte_mensagem') {
      return await chatMensagensRecebidas();
    }
    if (t == 'suporte_encerrado') {
      return await chatAtendimentoFinalizado();
    }

    // Lojista: novo pedido na loja
    if (t == 'novo_pedido') {
      return await lojaNovosPedidos();
    }

    // Entregador: pedido pronto / nova corrida / cancelamento pelo cliente
    if (t == 'nova_entrega' ||
        t == 'nova_corrida' ||
        t == 'cliente_cancelou_pedido_entregador') {
      return await entregadorCorridas();
    }

    // Cliente: status de pedido, preparo, envio, etc. (quando o backend enviar)
    if (t.startsWith('pedido_') ||
        t == 'pedido' ||
        t == 'status_pedido' ||
        t == 'compra' ||
        t == 'pedido_confirmado') {
      return await clientePedidosECompras();
    }

    // Pagamentos: PIX, cartão, recusa, etc.
    if (t.startsWith('pagamento') ||
        t == 'pix' ||
        t == 'mercadopago' ||
        t == 'pagamento_confirmado' ||
        t == 'pagamento_recusado') {
      return await clientePagamentos();
    }

    // Promoções e marketing
    if (t.startsWith('promo') ||
        t == 'marketing' ||
        t == 'oferta' ||
        t == 'desconto') {
      return await promocoesENovidades();
    }

    // Desconhecido: mantém comportamento permissivo
    return true;
  }
}
