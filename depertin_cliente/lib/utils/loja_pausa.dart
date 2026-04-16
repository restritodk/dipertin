import 'package:cloud_firestore/cloud_firestore.dart';

/// Motivos de pausa manual (campo `pausa_motivo` em `users`).
abstract final class PausaMotivoLoja {
  static const almoco = 'almoco';
  static const temporario = 'temporario';
  static const manutencao = 'manutencao';

  static String labelPt(String? codigo) {
    switch (codigo) {
      case almoco:
        return 'Fechado para almoço';
      case temporario:
        return 'Fechado temporariamente';
      case manutencao:
        return 'Fechado para manutenção';
      default:
        return 'Pausa manual';
    }
  }
}

/// Regras de pausa na vitrine: após [pausa_volta_at] em almoço, a loja volta a
/// aparecer como aberta sem precisar de Cloud Function (clientes leem horário).
class LojaPausa {
  LojaPausa._();

  static bool lojaEfetivamentePausada(Map<String, dynamic> d) {
    if (d['pausado_manualmente'] != true) return false;
    final m = d['pausa_motivo']?.toString();
    final vt = d['pausa_volta_at'];
    if (m == PausaMotivoLoja.almoco && vt is Timestamp) {
      final fim = vt.toDate();
      if (DateTime.now().isAfter(fim)) return false;
    }
    return true;
  }

  /// Texto para cliente (vitrine, perfil da loja).
  static String textoMotivoPublico(Map<String, dynamic> d) {
    if (!lojaEfetivamentePausada(d)) return '';
    final m = d['pausa_motivo']?.toString();
    final vt = d['pausa_volta_at'];
    switch (m) {
      case PausaMotivoLoja.almoco:
        if (vt is Timestamp) {
          final dt = vt.toDate();
          final hh = dt.hour.toString().padLeft(2, '0');
          final mm = dt.minute.toString().padLeft(2, '0');
          return 'Fechado para almoço — volta às $hh:$mm';
        }
        return 'Fechado para almoço';
      case PausaMotivoLoja.temporario:
        return 'Fechado temporariamente';
      case PausaMotivoLoja.manutencao:
        return 'Fechado para manutenção';
      default:
        return 'Fechada no momento';
    }
  }

  /// Rótulo curto para chip na foto do produto.
  static String rotuloChip(Map<String, dynamic> d) {
    if (!lojaEfetivamentePausada(d)) return '';
    final m = d['pausa_motivo']?.toString();
    switch (m) {
      case PausaMotivoLoja.almoco:
        return 'Almoço';
      case PausaMotivoLoja.temporario:
        return 'Pausa';
      case PausaMotivoLoja.manutencao:
        return 'Manutenção';
      default:
        return 'Fechada';
    }
  }

  /// Calcula o próximo instante de “volta” a partir do horário escolhido (hoje
  /// se ainda não passou, senão amanhã), hora local do dispositivo.
  static DateTime proximaDataHoraVoltaAlmoco(
    int hora,
    int minuto,
    DateTime agora,
  ) {
    var candidato = DateTime(
      agora.year,
      agora.month,
      agora.day,
      hora,
      minuto,
    );
    if (!candidato.isAfter(agora)) {
      candidato = candidato.add(const Duration(days: 1));
    }
    return candidato;
  }

  /// Verifica se a loja está efetivamente aberta considerando pausa manual,
  /// horários de funcionamento e campo `loja_aberta`.
  static bool lojaEstaAberta(Map<String, dynamic> loja) {
    if (lojaEfetivamentePausada(loja)) return false;
    if (!loja.containsKey('horarios') || loja['horarios'] == null) {
      return loja['loja_aberta'] ?? true;
    }

    final Map<String, dynamic> horarios = loja['horarios'] as Map<String, dynamic>;
    final DateTime agora = DateTime.now();
    const List<String> diasDaSemana = [
      'segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo',
    ];
    final String diaDeHoje = diasDaSemana[agora.weekday - 1];

    if (horarios[diaDeHoje] == null || horarios[diaDeHoje]['ativo'] == false) {
      return false;
    }

    try {
      final String horaAbre = horarios[diaDeHoje]['abre'];
      final String horaFecha = horarios[diaDeHoje]['fecha'];
      final int minAtual = agora.hour * 60 + agora.minute;
      final int minAbre =
          int.parse(horaAbre.split(':')[0]) * 60 +
          int.parse(horaAbre.split(':')[1]);
      final int minFecha =
          int.parse(horaFecha.split(':')[0]) * 60 +
          int.parse(horaFecha.split(':')[1]);

      if (minFecha < minAbre) {
        return minAtual >= minAbre || minAtual <= minFecha;
      }
      return minAtual >= minAbre && minAtual <= minFecha;
    } catch (_) {
      return true;
    }
  }

  /// Se a pausa de almoço já expirou no documento, devolve patch para limpar
  /// flags (persistência alinhada à vitrine).
  static Map<String, dynamic> patchSePausaAlmocoExpirada(
    Map<String, dynamic> d,
  ) {
    if (d['pausado_manualmente'] != true) return {};
    if (d['pausa_motivo']?.toString() != PausaMotivoLoja.almoco) return {};
    final vt = d['pausa_volta_at'];
    if (vt is! Timestamp) return {};
    if (DateTime.now().isBefore(vt.toDate())) return {};
    return {
      'pausado_manualmente': false,
      'pausa_motivo': FieldValue.delete(),
      'pausa_volta_at': FieldValue.delete(),
    };
  }
}
