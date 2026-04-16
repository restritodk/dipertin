import 'notificacoes_prefs.dart';

/// Preferências do chat de suporte — delega a [NotificacoesPrefs] (mesmas chaves).
///
/// Tipos FCM: `suporte_inicio`, `atendimento_iniciado`, `suporte_mensagem`,
/// `suporte_encerrado`.
class ChatNotificacoesPrefs {
  ChatNotificacoesPrefs._();

  static Future<bool> atendimentoIniciado() =>
      NotificacoesPrefs.chatAtendimentoIniciado();

  static Future<bool> mensagensRecebidas() =>
      NotificacoesPrefs.chatMensagensRecebidas();

  static Future<bool> atendimentoFinalizado() =>
      NotificacoesPrefs.chatAtendimentoFinalizado();

  static Future<void> setAtendimentoIniciado(bool value) =>
      NotificacoesPrefs.setChatAtendimentoIniciado(value);

  static Future<void> setMensagensRecebidas(bool value) =>
      NotificacoesPrefs.setChatMensagensRecebidas(value);

  static Future<void> setAtendimentoFinalizado(bool value) =>
      NotificacoesPrefs.setChatAtendimentoFinalizado(value);

  static Future<bool> deveExibirNotificacaoLocal(String? tipoNotificacao) =>
      NotificacoesPrefs.deveExibirNotificacaoLocal(tipoNotificacao);
}
