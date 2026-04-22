import 'package:cloud_firestore/cloud_firestore.dart';

/// Motivos estruturados de recusa do cadastro de lojista (painel master).
///
/// Alinhado com [depertin_cliente/lib/constants/lojista_motivo_recusa.dart].
class LojistaMotivoRecusa {
  LojistaMotivoRecusa._();

  static const String fotoIlegivel = 'FOTO_ILEGIVEL';
  static const String dadosInconsistentes = 'DADOS_INCONSISTENTES';
  static const String desinteresseComercial = 'DESINTERESSE_COMERCIAL';
  static const String outros = 'OUTROS';

  static const Duration duracaoBloqueio = Duration(days: 30);

  static bool exigeBloqueioDe30Dias(String codigo) {
    return codigo == desinteresseComercial || codigo == outros;
  }

  static bool permiteReenvioImediato(String codigo) {
    return codigo == fotoIlegivel || codigo == dadosInconsistentes;
  }

  static String rotulo(String codigo) {
    switch (codigo) {
      case fotoIlegivel:
        return 'Foto/documento ilegível';
      case dadosInconsistentes:
        return 'Dados inconsistentes';
      case desinteresseComercial:
        return 'Sem interesse comercial no momento';
      case outros:
        return 'Outros';
      default:
        return 'Motivo não informado';
    }
  }

  /// Texto longo persistido em [motivo_recusa] (lido pelo
  /// `lojista_status_notificacao.js` — e-mail + push — sem alterações).
  static String mensagemParaLojista(String codigo, {String? motivoCustomizado}) {
    switch (codigo) {
      case fotoIlegivel:
        return 'A imagem enviada está ilegível. Por favor, realize um novo '
            'envio diretamente pelo aplicativo.';
      case dadosInconsistentes:
        return 'Identificamos inconsistências nos dados enviados. Por favor, '
            'revise e envie novamente.';
      case desinteresseComercial:
        return 'No momento, não temos interesse comercial na sua região ou '
            'perfil. Você poderá realizar uma nova solicitação após 30 dias.';
      case outros: {
        final extra = (motivoCustomizado ?? '').trim();
        final base = extra.isEmpty
            ? 'Cadastro não aprovado neste momento.'
            : extra;
        return '$base\n\nVocê poderá realizar uma nova solicitação após 30 dias.';
      }
      default:
        return 'Cadastro não aprovado.';
    }
  }

  /// Timestamp de liberação do bloqueio (30 dias) — apenas para motivos aplicáveis.
  static Timestamp? calcularBloqueioAte(String codigo, {DateTime? referencia}) {
    if (!exigeBloqueioDe30Dias(codigo)) return null;
    final base = referencia ?? DateTime.now();
    return Timestamp.fromDate(base.add(duracaoBloqueio));
  }
}
