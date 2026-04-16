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
