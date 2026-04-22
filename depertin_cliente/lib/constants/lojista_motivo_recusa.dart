import 'package:cloud_firestore/cloud_firestore.dart';

/// Motivos estruturados de recusa do cadastro de lojista.
///
/// Dois grupos:
/// - **Correção imediata** ([fotoIlegivel], [dadosInconsistentes]): o lojista
///   pode reenviar documentos logo em seguida.
/// - **Bloqueio temporário de 30 dias** ([desinteresseComercial], [outros]):
///   nova solicitação fica bloqueada até [LojistaMotivoRecusa.bloqueioCadastroAte].
class LojistaMotivoRecusa {
  LojistaMotivoRecusa._();

  static const String fotoIlegivel = 'FOTO_ILEGIVEL';
  static const String dadosInconsistentes = 'DADOS_INCONSISTENTES';
  static const String desinteresseComercial = 'DESINTERESSE_COMERCIAL';
  static const String outros = 'OUTROS';

  /// Duração do bloqueio para [desinteresseComercial] e [outros].
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

  /// Texto longo enviado ao lojista (exibido no e-mail, push e tela de recusa).
  ///
  /// Para [outros], [motivoCustomizado] é incorporado.
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

  /// Lê o código de recusa do documento `users`. Retorna null se ausente/inválido.
  static String? codigoDoDocumento(Map<String, dynamic> d) {
    final c = d['motivo_recusa_codigo'];
    if (c == null) return null;
    final s = c.toString().trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s == fotoIlegivel ||
        s == dadosInconsistentes ||
        s == desinteresseComercial ||
        s == outros) {
      return s;
    }
    return null;
  }

  /// Data até a qual o lojista fica impedido de criar nova solicitação.
  ///
  /// Retorna null quando não há bloqueio ativo (ou já expirou).
  static DateTime? bloqueioCadastroAte(Map<String, dynamic> d) {
    final ts = d['bloqueio_cadastro_ate'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      if (dt.isAfter(DateTime.now())) return dt;
    }
    return null;
  }

  /// `true` se o usuário ainda está no período de bloqueio de 30 dias.
  static bool estaBloqueadoParaNovaSolicitacao(Map<String, dynamic> d) {
    return bloqueioCadastroAte(d) != null;
  }
}
