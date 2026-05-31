/// Motivos de bloqueio total (inadimplência) aplicados pelo painel admin.
class EntregadorMotivoBloqueioAdmin {
  EntregadorMotivoBloqueioAdmin._();

  static const String codigoInadimplencia = 'INADIMPLENCIA';
  static const String codigoFaltaPagamento = 'FALTA_PAGAMENTO';
  static const String codigoDocumentacao = 'DOCUMENTACAO_PENDENTE';
  static const String codigoConduta = 'CONDUTA_INADEQUADA';
  static const String codigoViolacaoTermos = 'VIOLACAO_TERMOS';
  static const String codigoFraude = 'SUSPEITA_FRAUDE';
  static const String codigoOutros = 'OUTROS';

  static const List<EntregadorMotivoBloqueioAdminOpcao> opcoesBloqueioTotal = [
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoInadimplencia,
      titulo: 'Inadimplência',
      subtitulo: 'Mensalidade, plano ou taxa em atraso.',
      textoMotivo: 'Inadimplência: regularize pendências financeiras com o suporte.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoFaltaPagamento,
      titulo: 'Falta de pagamento',
      subtitulo: 'Débito ou cobrança não quitada no prazo.',
      textoMotivo: 'Falta de pagamento: entre em contato com o suporte para regularizar.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoDocumentacao,
      titulo: 'Documentação pendente',
      subtitulo: 'CNH, CRLV ou outros documentos vencidos ou ilegíveis.',
      textoMotivo:
          'Documentação pendente: atualize seus documentos para nova análise.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoConduta,
      titulo: 'Conduta inadequada',
      subtitulo: 'Comportamento incompatível com as regras da plataforma.',
      textoMotivo:
          'Conduta inadequada: o acesso ao painel foi suspenso pela administração.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoViolacaoTermos,
      titulo: 'Violação dos termos',
      subtitulo: 'Descumprimento dos termos de uso ou políticas.',
      textoMotivo:
          'Violação dos termos de uso: contate o suporte para mais informações.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoFraude,
      titulo: 'Suspeita de fraude',
      subtitulo: 'Irregularidade ou suspeita que exige bloqueio preventivo.',
      textoMotivo:
          'Suspeita de irregularidade: o perfil foi bloqueado preventivamente.',
    ),
    EntregadorMotivoBloqueioAdminOpcao(
      codigo: codigoOutros,
      titulo: 'Outros',
      subtitulo: 'Descreva o motivo — o texto será exibido ao entregador.',
      textoMotivo: '',
      exigeDescricao: true,
    ),
  ];

  static EntregadorMotivoBloqueioAdminOpcao? opcaoPorCodigo(String? codigo) {
    if (codigo == null || codigo.isEmpty) return null;
    for (final o in opcoesBloqueioTotal) {
      if (o.codigo == codigo) return o;
    }
    return null;
  }

  /// Texto gravado em [motivo_bloqueio] (exibido no app do entregador).
  static String textoMotivoParaFirestore({
    required String codigo,
    String? descricaoOutros,
  }) {
    final op = opcaoPorCodigo(codigo);
    if (op == null) return 'Bloqueio administrativo';
    if (op.exigeDescricao) {
      return (descricaoOutros ?? '').trim();
    }
    return op.textoMotivo;
  }

  /// Valor de [block_reason] no Firestore.
  static String blockReasonParaFirestore(String codigo) {
    if (codigo == codigoOutros) return codigoOutros;
    if (codigo == codigoInadimplencia || codigo == codigoFaltaPagamento) {
      return codigoInadimplencia;
    }
    return codigo;
  }
}

class EntregadorMotivoBloqueioAdminOpcao {
  const EntregadorMotivoBloqueioAdminOpcao({
    required this.codigo,
    required this.titulo,
    required this.subtitulo,
    required this.textoMotivo,
    this.exigeDescricao = false,
  });

  final String codigo;
  final String titulo;
  final String subtitulo;
  final String textoMotivo;
  final bool exigeDescricao;
}

/// Motivos registrados na auditoria ao desbloquear entregador no painel admin.
class EntregadorMotivoDesbloqueioAdmin {
  EntregadorMotivoDesbloqueioAdmin._();

  static const String codigoRegularizacao = 'REGULARIZACAO_FINANCEIRA';
  static const String codigoDocumentacao = 'DOCUMENTACAO_APROVADA';
  static const String codigoRevisao = 'REVISAO_ADMINISTRATIVA';
  static const String codigoPrazoTemporario = 'BLOQUEIO_TEMPORARIO_ENCERRADO';
  static const String codigoSolicitacao = 'SOLICITACAO_ATENDIDA';
  static const String codigoErro = 'ERRO_BLOQUEIO';
  static const String codigoOutros = 'OUTROS';

  static const List<EntregadorMotivoDesbloqueioAdminOpcao> opcoes = [
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoRegularizacao,
      titulo: 'Regularização financeira',
      subtitulo: 'Pagamento ou pendência financeira regularizada.',
      textoMotivo: 'Desbloqueio após regularização financeira.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoDocumentacao,
      titulo: 'Documentação aprovada',
      subtitulo: 'CNH, CRLV ou documentos revisados e aceitos.',
      textoMotivo: 'Desbloqueio após aprovação da documentação.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoRevisao,
      titulo: 'Revisão administrativa',
      subtitulo: 'Análise interna concluída com liberação do perfil.',
      textoMotivo: 'Desbloqueio após revisão administrativa.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoPrazoTemporario,
      titulo: 'Bloqueio temporário encerrado',
      subtitulo: 'Liberação manual antes ou após o prazo do bloqueio temporário.',
      textoMotivo: 'Desbloqueio: bloqueio temporário encerrado pela administração.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoSolicitacao,
      titulo: 'Solicitação atendida',
      subtitulo: 'Demanda do entregador resolvida via suporte ou painel.',
      textoMotivo: 'Desbloqueio após atendimento da solicitação do entregador.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoErro,
      titulo: 'Bloqueio aplicado por engano',
      subtitulo: 'Correção de bloqueio indevido ou duplicado.',
      textoMotivo: 'Desbloqueio: bloqueio administrativo corrigido.',
    ),
    EntregadorMotivoDesbloqueioAdminOpcao(
      codigo: codigoOutros,
      titulo: 'Outros',
      subtitulo: 'Descreva o motivo — ficará registrado na auditoria.',
      textoMotivo: '',
      exigeDescricao: true,
    ),
  ];

  static EntregadorMotivoDesbloqueioAdminOpcao? opcaoPorCodigo(String? codigo) {
    if (codigo == null || codigo.isEmpty) return null;
    for (final o in opcoes) {
      if (o.codigo == codigo) return o;
    }
    return null;
  }

  static String textoMotivoParaAuditoria({
    required String codigo,
    String? descricaoOutros,
  }) {
    final op = opcaoPorCodigo(codigo);
    if (op == null) return 'Desbloqueio administrativo';
    if (op.exigeDescricao) return (descricaoOutros ?? '').trim();
    return op.textoMotivo;
  }
}

class EntregadorMotivoDesbloqueioAdminOpcao {
  const EntregadorMotivoDesbloqueioAdminOpcao({
    required this.codigo,
    required this.titulo,
    required this.subtitulo,
    required this.textoMotivo,
    this.exigeDescricao = false,
  });

  final String codigo;
  final String titulo;
  final String subtitulo;
  final String textoMotivo;
  final bool exigeDescricao;
}
