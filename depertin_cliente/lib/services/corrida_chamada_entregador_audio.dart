import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'android_nav_intent.dart';
import 'corrida_foreground_notificacao.dart';

/// Player único para o ringtone de oferta de corrida (FCM em primeiro plano + radar).
/// Garante que aceitar/recusar no dashboard pare todo o áudio da chamada.
class CorridaChamadaEntregadorAudio {
  CorridaChamadaEntregadorAudio._();

  static final AudioPlayer _player = AudioPlayer();

  static Future<void> parar() async {
    try {
      await _player.stop();
      await _player.seek(Duration.zero);
    } catch (e) {
      debugPrint('[CorridaChamadaEntregadorAudio.parar] $e');
    }
  }

  /// Para o MP3, remove a notificação local (foreground) e a heads-up nativa de corrida.
  static Future<void> silenciarAlertaCorridaCompleto(String pedidoId) async {
    await parar();
    final id = pedidoId.trim();
    if (id.isEmpty) return;
    await CorridaForegroundNotificacao.cancelarPedido(id);
    if (!kIsWeb && Platform.isAndroid) {
      await AndroidNavIntent.cancelIncomingCorridaNotification(id);
    }
  }

  static Future<void> tocarChamada() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sond/ChamadaEntregador.mp3'));
    } catch (e) {
      debugPrint('[CorridaChamadaEntregadorAudio.tocarChamada] $e');
    }
  }
}
